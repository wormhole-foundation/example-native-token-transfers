import { TOKEN_PROGRAM_ID, createSetAuthorityInstruction } from '@solana/spl-token';
import { BN } from '@coral-xyz/anchor'
import { Keypair, PublicKey } from "@solana/web3.js";

import { NTT } from "../sdk";
import { connection, getSigner, getEnv } from './env';
import { ledgerSignAndSend } from './helpers';

type InitConfig = {
  mintAddress: string,
  wormholeProgramId: string,
  nttProgramId: string,
}

(async () => {
  const config: InitConfig = {
    mintAddress: getEnv("MINT_ADDRESS"),
    wormholeProgramId: getEnv("WORMHOLE_PROGRAM_ID"),
    nttProgramId: getEnv("NTT_PROGRAM_ID"),
  };

  const signer = await getSigner();
  const signerPk = new PublicKey(await signer.getAddress());

  const mint = new PublicKey(config.mintAddress);

  const ntt = new NTT(connection, {
    nttId: config.nttProgramId as any,
    wormholeId: config.wormholeProgramId as any,
  });

  const nttManagerPk = ntt.tokenAuthorityAddress();

  // this is needed on testnet, but not on mainnet
  // const setAuthorityInstruction = createSetAuthorityInstruction(
  //   mint,
  //   signerPk,
  //   0,
  //   nttManagerPk,
  //   undefined, // for multi-sig
  //   TOKEN_PROGRAM_ID, // might also be TOKEN_2022_PROGRAM_ID
  // );

  // await ledgerSignAndSend([setAuthorityInstruction], [])

  // console.log(`Authority set to ${nttManagerPk.toBase58()}`);
  
  console.log("Manager Emitter Address:", await ntt.emitterAccountAddress().toBase58());

  const initializeNttIx = await ntt.createInitializeInstruction({
    payer: signerPk,
    owner: signerPk,
    chain: "solana",
    mint,
    // TODO: this two properties should also be configurable
    outboundLimit: new BN(10000000000000),
    mode: "locking",
  });

  await ledgerSignAndSend([initializeNttIx], []);

  console.log("NTT initialized succesfully!");

  await new Promise(resolve => setTimeout(resolve, 5000));

  const wormholeMessageKeys = Keypair.generate();

  const registerTransceiverIxs = await ntt.createRegisterTransceiverInstructions({
    payer: signerPk,
    owner: signerPk,
    wormholeMessage: wormholeMessageKeys.publicKey,
    transceiver: new PublicKey(ntt.program.programId),
  });

  await ledgerSignAndSend(registerTransceiverIxs, [wormholeMessageKeys]);
  
  console.log(`Transceiver program registered: ${ntt.program.programId}`);

  const emitterAddress = await ntt.emitterAccountAddress();
  console.log(`Emitter account address: ${emitterAddress.toBase58()}`);
})();

