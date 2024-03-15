import { type Idl } from '@coral-xyz/anchor'
import fs from 'fs'

const jsonPath = process.argv[2]
const name = process.argv[3]
if (jsonPath === undefined || name === undefined) {
  console.error(`Usage:\
${process.argv[0]} ${process.argv[1]} <idl.json> <name>`)
  process.exit(1)
}

const idl: Idl = JSON.parse(fs.readFileSync(jsonPath, 'utf8'))

idl.accounts?.forEach((account) => {
  account.name = account.name[0].toLowerCase() + account.name.slice(1)
})

// heredoc
const ts = `\
export type ${name} = ${JSON.stringify(idl, null, 2)}\

export const IDL: ${name} = ${JSON.stringify(idl, null, 2)}
`

console.log(ts)
