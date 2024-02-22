import * as anchor from '@coral-xyz/anchor'
import { BN, type Program } from '@coral-xyz/anchor'
import * as spl from '@solana/spl-token'
import { type ExampleNativeTokenTransfers } from '../ts/sdk'
import { PostedMessageData } from '@certusone/wormhole-sdk/lib/cjs/solana/wormhole'
import { expect } from 'chai'
import { toChainId } from '@certusone/wormhole-sdk'
import { MockEmitter, MockGuardians } from '@certusone/wormhole-sdk/lib/cjs/mock'
import * as fs from "fs";

import { type EndpointMessage, ManagerMessage, NativeTokenTransfer, NormalizedAmount, postVaa, WormholeEndpointMessage, NTT } from '../ts/sdk'

export const GUARDIAN_KEY = 'cfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0'

describe('example-native-token-transfers', () => {
  // Configure the client to use the local cluster.
  anchor.setProvider(anchor.AnchorProvider.env())

  const payerSecretKey = Uint8Array.from(JSON.parse(fs.readFileSync(`${__dirname}/../keys/test.json`, { encoding: "utf-8" })));
  const payer = anchor.web3.Keypair.fromSecretKey(payerSecretKey);

  const program = anchor.workspace.ExampleNativeTokenTransfers as Program<ExampleNativeTokenTransfers>
  const owner = anchor.web3.Keypair.generate()
  const ntt = new NTT({
    program,
    wormholeId: 'worm2ZoG2kUd4vFXhvjh93UUH596ayRfgQ2MgjNMTth'
  })
  const user = anchor.web3.Keypair.generate()
  let tokenAccount: anchor.web3.PublicKey


  let mint: anchor.web3.PublicKey

  before(async () => {
    // airdrop some tokens to payer
    mint = await spl.createMint(
      program.provider.connection,
      payer,
      owner.publicKey,
      null,
      9
    )

    tokenAccount = await spl.createAssociatedTokenAccount(program.provider.connection, payer, mint, user.publicKey)
    await spl.mintTo(program.provider.connection, payer, mint, tokenAccount, owner, BigInt(10000000))
  });

  describe('Locking', () => {
    before(async () => {
      await spl.setAuthority(
        program.provider.connection,
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

      await ntt.registerEndpoint({
        payer,
        owner: payer,
        endpoint: ntt.program.programId
      })

      await ntt.setWormholeEndpointSibling({
        payer,
        owner: payer,
        chain: 'ethereum',
        address: Buffer.from('endpoint'.padStart(32, '\0')),
      })

      await ntt.setSibling({
        payer,
        owner: payer,
        chain: 'ethereum',
        address: Buffer.from('manager'.padStart(32, '\0')),
        limit: new BN(1000000)
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

      const wormholeMessageAccount = await program.provider.connection.getAccountInfo(wormholeMessage)
      if (wormholeMessageAccount === null) {
        throw new Error('wormhole message account not found')
      }

      const messageData = PostedMessageData.deserialize(wormholeMessageAccount.data)
      const endpointMessage = WormholeEndpointMessage.deserialize(
        messageData.message.payload,
        a => ManagerMessage.deserialize(a, NativeTokenTransfer.deserialize)
      )

      // assert theat amount is what we expect
      expect(endpointMessage.managerPayload.payload.normalizedAmount).to.deep.equal(new NormalizedAmount(BigInt(10000), 8))
      // get from balance
      const balance = await program.provider.connection.getTokenAccountBalance(tokenAccount)
      expect(balance.value.amount).to.equal('9900000')

      // grab logs
      // await program.provider.connection.confirmTransaction(redeemTx, 'confirmed');
      // const tx = await anchor.getProvider().connection.getParsedTransaction(redeemTx, {
      //   commitment: "confirmed",
      // });
      // console.log(tx);

      // const log = tx.meta.logMessages[1];
      // const message = log.substring(log.indexOf(':') + 1);
      // console.log(message);

      // TODO: assert other stuff in the message
      // console.log(managerMessage);
    });

    it('Can receive tokens', async () => {
      const emitter =
        new MockEmitter(
          Buffer.from('endpoint'.padStart(32, '\0')).toString('hex'),
          toChainId('ethereum'),
          Number(0) // sequence
        )

      const guardians = new MockGuardians(0, [GUARDIAN_KEY])

      const sendingEndpointMessage: EndpointMessage<NativeTokenTransfer> = {
        sourceManager: Buffer.from('manager'.padStart(32, '\0')),
        managerPayload: new ManagerMessage(
          BigInt(0),
          Buffer.from('FACE'.padStart(64, '0'), 'hex'),
          new NativeTokenTransfer(
            Buffer.from('FAFA'.padStart(64, '0'), 'hex'),
            new NormalizedAmount(BigInt(10000), 8),
            toChainId('solana'),
            user.publicKey.toBuffer()
          ),
        ),
        endpointPayload: Buffer.alloc(0)
      }

      const serialized = WormholeEndpointMessage.serialize(sendingEndpointMessage, a => ManagerMessage.serialize(a, NativeTokenTransfer.serialize))

      const published = emitter.publishMessage(
        0, // nonce
        serialized,
        0 // consistency level
      )

      const vaaBuf = guardians.addSignatures(published, [0])

      await postVaa(program.provider.connection, payer, vaaBuf, ntt.wormholeId)

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
