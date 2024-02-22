import { PublicKey } from "@solana/web3.js";

export const BPF_LOADER_UPGRADEABLE_PROGRAM_ID = new PublicKey(
    "BPFLoaderUpgradeab1e11111111111111111111111",
);

export function programDataAddress(programId: PublicKey) {
    return PublicKey.findProgramAddressSync(
        [programId.toBuffer()],
        BPF_LOADER_UPGRADEABLE_PROGRAM_ID,
    )[0];
}