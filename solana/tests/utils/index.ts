import {
  ChainContext,
  Signer,
  signSendWait as ssw,
} from "@wormhole-foundation/sdk";
import path from "path";

const TESTFILE_MATCH_PATTERN = /.test.ts$/;

/**
 * Skips test file execution if the corresponding environment variable is not set.
 *
 * eg:- To run `file-name.test.ts`, `FILE_NAME` environment variable should be set
 */
export const handleTestSkip = (filename: string) => {
  const testName = path.basename(filename).replace(TESTFILE_MATCH_PATTERN, "");
  const envVar = testName.replaceAll("-", "_").toUpperCase();
  const shouldRun = process.env[envVar];
  if (!shouldRun) {
    test.only("Skipping all tests", () => {});
  }
};

export const signSendWait = async (
  chain: ChainContext<any, any, any>,
  txs: AsyncGenerator<any>,
  signer: Signer,
  shouldLog = true,
  shouldThrow = false
) => {
  try {
    await ssw(chain, txs, signer);
  } catch (e) {
    if (shouldLog) {
      console.error(e);
    }
    if (shouldThrow) {
      throw e;
    }
  }
};
