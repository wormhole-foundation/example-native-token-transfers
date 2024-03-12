import * as anchor from '@coral-xyz/anchor'
import { BN } from '@coral-xyz/anchor'
import * as spl from '@solana/spl-token'
import { PostedMessageData } from '@certusone/wormhole-sdk/lib/cjs/solana/wormhole'
import { expect } from 'chai'
import { toChainId } from '@certusone/wormhole-sdk'
import { MockEmitter, MockGuardians } from '@certusone/wormhole-sdk/lib/cjs/mock'
import * as fs from "fs";

import { encoding } from '@wormhole-foundation/sdk-base'
import { UniversalAddress, serializePayload, deserializePayload } from '@wormhole-foundation/sdk-definitions'
import { NttMessage, postVaa, NTT } from '../ts/sdk'

export const GUARDIAN_KEY = 'cfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0'

describe('example-native-token-transfers', () => {
  const payerSecretKey = Uint8Array.from(JSON.parse(fs.readFileSync(`${__dirname}/../keys/test.json`, { encoding: "utf-8" })));
  const payer = anchor.web3.Keypair.fromSecretKey(payerSecretKey);

  const owner = anchor.web3.Keypair.generate()
  const connection = new anchor.web3.Connection('http://localhost:8899', 'confirmed');
  const ntt = new NTT(connection, {
    nttId: 'NttF2XqV8fc1kb9VinwShysQXPw7JB7hACGvcV1uYFn',
    wormholeId: '3u8hJUVTA4jH1wYAyUur7FFZVQ8H635K3tSHHF4ssjQ5'
  });
  const user = anchor.web3.Keypair.generate()
  let tokenAccount: anchor.web3.PublicKey

  let mint: anchor.web3.PublicKey

  before(async () => {
    // airdrop some tokens to payer
    mint = await spl.createMint(
      connection,
      payer,
      owner.publicKey,
      null,
      9
    )

    // sp
    tokenAccount = await spl.createAssociatedTokenAccount(connection, payer, mint, user.publicKey)
    await spl.mintTo(connection, payer, mint, tokenAccount, owner, BigInt(10000000))
  });

  describe('Locking', () => {
    before(async () => {
      await spl.setAuthority(
        connection,
        payer,
        mint,
        owner,
        0, // mint
        ntt.tokenAuthorityAddress()
      )

      await ntt.initialize({
        payer,
        owner: payer,
        chain: 'solana',
        mint,
        outboundLimit: new BN(1000000),
        mode: 'locking'
      })

      await ntt.registerTransceiver({
        payer,
        owner: payer,
        transceiver: ntt.program.programId
      })

      await ntt.setWormholeTransceiverPeer({
        payer,
        owner: payer,
        chain: 'ethereum',
        address: Buffer.from('transceiver'.padStart(32, '\0')),
      })

      await ntt.setPeer({
        payer,
        owner: payer,
        chain: 'ethereum',
        address: Buffer.from('nttManager'.padStart(32, '\0')),
        limit: new BN(1000000),
        tokenDecimals: 18
      })

    });

    it('Can send tokens', async () => {
      // TODO: factor out this test so it can be reused for burn&mint

      // transfer some tokens

      const amount = new BN(100000)

      const outboxItem = await ntt.transfer({
        payer,
        from: tokenAccount,
        fromAuthority: user,
        amount,
        recipientChain: 'ethereum',
        recipientAddress: Array.from(user.publicKey.toBuffer()), // TODO: dummy
        shouldQueue: false
      })

      const wormholeMessage = ntt.wormholeMessageAccountAddress(outboxItem)

      const wormholeMessageAccount = await connection.getAccountInfo(wormholeMessage)
      if (wormholeMessageAccount === null) {
        throw new Error('wormhole message account not found')
      }

      const messageData = PostedMessageData.deserialize(wormholeMessageAccount.data)
      const transceiverMessage =
        deserializePayload("NTT:WormholeTransfer", messageData.message.payload)

      // assert theat amount is what we expect
      expect(transceiverMessage.nttManagerPayload.payload.trimmedAmount).to.deep.equal({amount: 10000n, decimals: 8})
      // get from balance
      const balance = await connection.getTokenAccountBalance(tokenAccount)
      expect(balance.value.amount).to.equal('9900000')

      // grab logs
      // await connection.confirmTransaction(redeemTx, 'confirmed');
      // const tx = await anchor.getProvider().connection.getParsedTransaction(redeemTx, {
      //   commitment: "confirmed",
      // });
      // console.log(tx);

      // const log = tx.meta.logMessages[1];
      // const message = log.substring(log.indexOf(':') + 1);
      // console.log(message);

      // TODO: assert other stuff in the message
      // console.log(nttManagerMessage);
    });

    it('Can receive tokens', async () => {
      const emitter =
        new MockEmitter(
          Buffer.from('transceiver'.padStart(32, '\0')).toString('hex'),
          toChainId('ethereum'),
          Number(0) // sequence
        )

      const guardians = new MockGuardians(0, [GUARDIAN_KEY])

      const sendingTransceiverMessage = {
        sourceNttManager: new UniversalAddress(encoding.bytes.encode('nttManager'.padStart(32, '\0'))),
        recipientNttManager: new UniversalAddress(ntt.program.programId.toBytes()),
        nttManagerPayload: {
          id: encoding.bytes.encode('sequence1'.padEnd(32, '0')),
          sender: new UniversalAddress('FACE'.padStart(64, '0')),
          payload: {
            trimmedAmount: {
              amount: 10000n,
              decimals: 8
            },
            sourceToken: new UniversalAddress('FAFA'.padStart(64, '0')),
            recipientAddress: new UniversalAddress(user.publicKey.toBytes()),
            recipientChain: 'Solana',
          }
        },
        transceiverPayload: new Uint8Array(0)
      } as const

      const serialized = serializePayload("NTT:WormholeTransfer", sendingTransceiverMessage)

      const published = emitter.publishMessage(
        0, // nonce
        Buffer.from(serialized),
        0 // consistency level
      )

      const vaaBuf = guardians.addSignatures(published, [0])

      await postVaa(connection, payer, vaaBuf, ntt.wormholeId)

      const released = await ntt.redeem({
        payer,
        vaa: vaaBuf,
      })

      expect(released).to.equal(true)

    });
  });

  // describe('Burning', () => {
  //   beforeEach(async () => {
  //     await ntt.initialize({
  //       payer,
  //       owner,
  //       chain: 'solana',
  //       mint,
  //       outboundLimit: new BN(1000000),
  //       mode: 'burning'
  //     })
  //   });
  // });

})
