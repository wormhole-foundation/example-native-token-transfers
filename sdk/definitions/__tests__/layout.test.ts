import {
  deserializeLayout,
  encoding,
  serializeLayout,
} from "@wormhole-foundation/sdk-base";
import * as path from "path";
import * as fs from "fs";
import {
  nativeTokenTransferLayout,
  nttManagerMessageLayout,
  wormholeTransceiverMessageLayout,
} from "../src/nttLayout.js";

const payloads = {
  transceiver: {
    info: ["transceiver_info_1.txt"],
    message: ["transceiver_message_1.txt"],
    registration: ["transceiver_registration_1.txt"],
  },
};

const filePath = path.join(__dirname, "../../../evm/test/payloads");
describe("Ntt Layout Tests", function () {
  test.each(payloads.transceiver.message)(
    "Test Transceiver %s messages",
    async (filename) => {
      const raw = fs
        .readFileSync(path.join(filePath, filename), "utf-8")
        .trim();
      const data = encoding.hex.decode(raw);
      const deserialized = deserializeLayout(
        wormholeTransceiverMessageLayout(
          nttManagerMessageLayout(nativeTokenTransferLayout)
        ),
        data
      );

      const srcToken =
        deserialized.nttManagerPayload.payload.sourceToken.toString();

      expect(srcToken).toEqual(
        "0xbeefface00000000000000000000000000000000000000000000000000000000"
      );
      expect(deserialized.nttManagerPayload.payload.recipientChain).toEqual(
        "Neon"
      );
      expect(deserialized.transceiverPayload).toBeNull();

      expect(
        serializeLayout(
          wormholeTransceiverMessageLayout(
            nttManagerMessageLayout(nativeTokenTransferLayout)
          ),
          deserialized
        )
      ).toEqual(data);
    }
  );
});
