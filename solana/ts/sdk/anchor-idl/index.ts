export * from "./1_0_0.js";

// This is a workaround for the fact that the anchor idl doesn't support generics
// yet. This type is used to remove the generics from the idl types.
export type OmitGenerics<T> = {
  [P in keyof T]: T[P] extends Record<"generics", any>
    ? never
    : T[P] extends object
    ? OmitGenerics<T[P]>
    : T[P];
};
