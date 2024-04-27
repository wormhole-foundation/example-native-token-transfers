import * as fs from "fs";

// From the persp of `sdk/solana`
//const projectRoot = "../../solana/";
const projectRoot = "./";
const versionFile = "programs/example-native-token-transfers/src/lib.rs";
const versionRegex = /pub const VERSION/;
(function () {
  const contents = fs.readFileSync(projectRoot + versionFile, "utf8");
  for (const line of contents.split("\n")) {
    if (line.match(versionRegex)) {
      const version = line.split('"')[1];
      console.log(version?.replaceAll(".", "_"));
      return;
    }
  }
})();
