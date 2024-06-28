import * as fs from "fs";

// From the persp of `sdk/evm`
const projectRoot = "../../";
const versionFile = "evm/src/NttManager/NttManager.sol";
const versionRegex = /string public constant NTT_MANAGER_VERSION/;

// TODO: will we need the transceiver version as well?
// const versionFile = "evm/src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol";
// const versionRegex =  /string public constant WORMHOLE_TRANSCEIVER_VERSION/;

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
