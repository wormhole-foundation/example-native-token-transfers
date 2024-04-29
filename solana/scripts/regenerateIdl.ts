import { type Idl } from "@coral-xyz/anchor";
import fs from "fs";

const jsonPath = process.argv[2];
if (jsonPath === undefined) {
  console.error(`Usage:\
${process.argv[0]} ${process.argv[1]} <idl.json>`);
  process.exit(1);
}

// snake to title case
const titleCase = (str: string) =>
  str
    .split("_")
    .map((word) => word[0].toUpperCase() + word.slice(1).toLowerCase())
    .join("");

const idl: Idl = JSON.parse(fs.readFileSync(jsonPath, "utf8"));

const name = titleCase(idl["name"]);

idl.accounts?.forEach((account) => {
  account.name = account.name.replace(/^[A-Z]+/, (match) =>
    match.toLowerCase()
  );
});

// heredoc
const ts = `\
export type ${name} = ${JSON.stringify(idl, null, 2)}\

export const IDL: ${name} = ${JSON.stringify(idl, null, 2)}
`;

console.log(ts);
