import { type Idl } from '@coral-xyz/anchor'
import { IdlTypeDefined, type IdlAccountDef, type IdlField, type IdlType, type IdlTypeDef, type IdlTypeDefTy, type IdlTypeDefTyStruct } from '@coral-xyz/anchor/dist/cjs/idl'
import fs from 'fs'
import path from 'path'

type FinalType<T> = T extends infer U ? { [K in keyof U]: U[K] } : never
type Override<T, U extends Partial<Record<keyof T, unknown>>> =
  FinalType<Omit<T, keyof U> & U>

const extraIdl: Idl =
  JSON.parse(fs.readFileSync(
    path.join(__dirname, '../target/idl/extra_idl.json'), 'utf8'
  ))

const types = new Map<string, IdlTypeDef>()
extraIdl.types?.forEach((ty) => {
  types.set(ty.name, ty)
})

const idlPath = process.argv[2]
const instantiationsPath = process.argv[3]
if (idlPath === undefined || instantiationsPath === undefined) {
  console.error(`Usage: \
${process.argv[0]} ${process.argv[1]} <idl.json> <instantiations.json>`)
  process.exit(1)
}

const idl: Idl =
  JSON.parse(fs.readFileSync(idlPath, 'utf8'))

const instantiations: Record<string, IdlType[]> =
  JSON.parse(fs.readFileSync(instantiationsPath, 'utf8'))

idl.types?.forEach((ty) => {
  types.set(ty.name, ty)
})

const genericAccounts: IdlAccountDefGeneric[] =
  (idl.accounts?.filter((account: any) =>
    account.generics !== undefined) as IdlAccountDefGeneric[]) ?? []

const genericTypes = new Map<string, any>()
idl.types?.filter((ty: any) => ty.generics !== undefined)
  .forEach((ty: IdlTypeDefGeneric) => {
    genericTypes.set(ty.name, ty)
  })

idl.accounts =
  idl.accounts?.filter((account: any) => account.generics === undefined)

idl.types =
  idl.types?.filter((ty: any) => ty.generics === undefined)

const instantiatedTypes = new Map<string, IdlType[]>()

function instantiatedTypeName(name: string, tys: any[]): string {
  return `${name}${tys.map((ty) => ty.defined ?? ty).join('')}`
}

interface IdlTypeDefinedWithTypeArgs {
  definedWithTypeArgs: {
    name: string
    args: Array<{ type: IdlTypeTyArg }>
  }
}

function isIdlTypeDefinedWithTypeArgs(
  ty: any
): ty is IdlTypeDefinedWithTypeArgs {
  return ty.hasOwnProperty('definedWithTypeArgs')
}

function isIdlTypeDefined(ty: any): ty is IdlTypeDefined {
  return ty.hasOwnProperty('defined')
}

interface IdlTypeTyArg {
  generic: string
}

function isIdlTypeTyArg(ty: any): ty is IdlTypeTyArg {
  return ty.hasOwnProperty('generic')
}

type IdlTypeGeneric = IdlType | IdlTypeTyArg | IdlTypeDefinedWithTypeArgs

type IdlFieldGeneric = Override<IdlField, { type: IdlTypeGeneric }>

type IdlAccountDefGeneric =
  IdlAccountDef & {
    generics: string[] | undefined
    type: Override<IdlTypeDefTyStruct, { fields: IdlField[] }>
  }

type IdlTypeDefTyStructGeneric =
  IdlTypeDefTyStruct & {
    fields: IdlFieldGeneric[]
  }

type IdlTypeDefGeneric =
  IdlTypeDef & {
    generics: string[] | undefined
    type: IdlTypeDefTy | IdlTypeDefTyStructGeneric
  }

function instantiateAccount(
  ty: IdlAccountDefGeneric,
  tys: IdlType[]
): IdlAccountDef {
  ty = structuredClone(ty)

  if (ty.generics === undefined) {
    return ty
  }
  const generics = ty.generics
  delete ty.generics
  if (generics.length !== tys.length) {
    throw new Error(`Expected ${generics.length} generics,\
got ${tys.length} when instantiating ${ty.name}`)
  }
  // map generics to tys
  const map = new Map<string, IdlType>()
  generics.forEach((generic: string, i: number) => {
    map.set(generic, tys[i])
  })

  ty.type = instantiateStruct(ty.type, map)

  return ty
}

function instantiateStruct(
  ty: IdlTypeDefTyStructGeneric,
  map: Map<string, IdlType>
): IdlTypeDefTyStruct {
  ty = structuredClone(ty)

  ty.fields.forEach((field: IdlFieldGeneric) => {
    var v: IdlType | undefined
    if (isIdlTypeTyArg(field.type)) {
      v = map.get(field.type.generic)
      if (v === undefined) {
        throw new Error(`No type arg for ${field.type.generic}`)
      }
      field.type = v
    } else if (isIdlTypeDefinedWithTypeArgs(field.type)) {
      const defined = field.type.definedWithTypeArgs
      if (defined.args.length !== 1) {
        // TODO: we could handle multiple args, but right now there's no need
        throw new Error(`Expected 1 type arg, got ${defined.args.length}`)
      }
      v = map.get(field.type.definedWithTypeArgs.args[0].type.generic)
      if (v === undefined) {
        throw new Error(`No type arg for\
${field.type.definedWithTypeArgs.args[0].type.generic}`)
      }
      field.type = {
        defined: instantiatedTypeName(defined.name, [v])
      }
      // add to instantiatedTypes
      if (!instantiatedTypes.has(defined.name)) {
        instantiatedTypes.set(defined.name, [])
      }
      instantiatedTypes.get(defined.name)?.push(v)
    }

    if (v && isIdlTypeDefined(v) && types.get(v.defined) === undefined) {
      throw new Error(`No type definition for ${v.defined}. Did you forget to\
add it to the extra_idl package?`)
    }
  })

  return ty
}

function instantiateType(ty: IdlTypeDefGeneric, tys: IdlType[]): IdlTypeDef {
  ty = structuredClone(ty)

  if (ty.generics === undefined) {
    return ty
  }
  const generics = ty.generics
  delete ty.generics
  if (generics.length !== tys.length) {
    throw new Error(`Expected ${generics.length} generics, \
got ${tys.length} when instantiating ${ty.name}`)
  }
  // map generics to tys
  const map = new Map<string, IdlType>()
  generics.forEach((generic: string, i: number) => {
    map.set(generic, tys[i])
  })

  if (ty.type.kind === 'struct') {
    ty.type = instantiateStruct(ty.type, map)
  } else {
    throw new Error(`Unsupported type kind: ${ty.type.kind}`)
  }

  ty.name = instantiatedTypeName(ty.name, tys)

  return ty
}

function getInstantiation(name: string): IdlType[] {
  if (instantiations.hasOwnProperty(name)) {
    return instantiations[name]
  }
  throw new Error(`No instantiation for ${name}`)
}

// main logic

idl.accounts?.push(...genericAccounts.map(
  acc => instantiateAccount(acc, getInstantiation(acc.name))))

while (instantiatedTypes.size > 0) {
  const [name, tys]: [string, IdlType[]] =
    instantiatedTypes.entries().next().value
  instantiatedTypes.delete(name)

  tys.forEach((ty) => {
    const tyDef = types.get(name)
    if (tyDef === undefined) {
      throw new Error(`No type definition for ${name}. Did you forget to\
add it to the extra_idl package?`)
    }
    const instantiated =
      instantiateType(types.get(name) as IdlTypeDefGeneric, [ty])
    idl.types?.push(instantiated)
  })
}

extraIdl.types?.forEach((ty) => {
  idl.types?.push(ty)
})

// prune duplicates
idl.types = idl.types?.filter(
  (ty, i, self) => self.findIndex((t) => t.name === ty.name) === i
)

console.log(JSON.stringify(idl, null, 2))
