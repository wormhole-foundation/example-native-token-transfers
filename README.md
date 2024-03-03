## NTT: Native Token Transfers

### Overview

Wormhole’s Native Token Transfers (NTT) is an open, flexible, and composable framework for transferring tokens across blockchains without liquidity pools. Integrators have full control over how their Natively Transferred Tokens (NTTs) behave on each chain, including the token standard and metadata. For existing token deployments, the framework can be used in “locking” mode which preserves the original token supply on a single chain. Otherwise, the framework can be used in “burning” mode to deploy natively multichain tokens with supply distributed among multiple chains.

### Design

- Transceiver - This contract module is responsible for sending Ntt transfers forwarded through the NTTManager on the source chain and delivered to a corresponding peer NTTManager on the recipient chain. Transceivers should follow the ITransceiver interface. Transceivers can be instantiated without use of the Wormhole core contracts for message authentication.

- NttManager: The NttManager contract is responsible for managing the token and the transceivers. It also handles the rate limiting and the message attestation logic. Note that each NTTManager corresponds to a single token. However, a single NTTManager can manager can control multiple transceivers.

### Amount trimming

In the payload, amounts are encoded as unsigned 64 bit integers, and capped at 8 decimals.
This means that if on the sending chain, the token has more than 8 decimals, then the amount is trimmed.
The amount that's removed during trimming is referred to as "dust". The contracts make sure to never destroy dust.
The NTT manager contracts additionally keep track of the token decimals of the other connected chains. When sending to a chain whose token decimals are less than 8, the amount is instead truncated to those decimals, in order to ensure that the recipient contract can handle the amount without destroying dust.

The payload includes the trimmed amount, together with the decimals that trimmed amount is expressed in. This number is the minimum of (8, source token decimals, destination token decimals).

### NTT Message Lifecycle

### EVM

1. **Sending**: A client calls on [`transfer`] to initiate an NTT transfer. The client must specify at minimum, the amount of the transfer, the recipient chain, and the recipient address on the recipient chain. [`transfer`] also supports a flag to specify whether the NTTManager should queue transfers if they are rate-limited. Clients can also include additional instructions to forward along to its peer NTT Manager on the recipient chain to execute. Depending on the mode, transfers are either "locked" or "burned". Once the transfer has been forwarded to the Transceiver, the NTTManager emits the following event:

```solidity
emit TransferSent(recipient, _nttDenormalize(amount), recipientChain, seq);
```

2. **Rate Limiting**: NTT supports rate-limiting of tranfers based on a 24-hr sliding window. This is intended to be a defense-in-depth security measure to mitigate and localize risk. This is a security feature intended to protect large unintended transfers. If a transfer sent from the source chain is rate-limited, it is added to a queue of transfers. The following event is emitted:

```solidity
emit OutboundTransferRateLimited(msg.sender, sequence, amount, getCurrentOutboundCapacity());
```

A transfer can be released from the queue in 2 ways: (1) the capacity available exceeds the transfer amount; (2) the 24 hr period is up. In both cases, the client can call the [`completeOutboundQueuedTransfer`] function to release the transfer from the queue. The client should specify the gas amount here again to ensure that the delivery does not revert.

3. Transmit

Once the NttManager forwards the message to the Transceiver the message is transmitted via the [`sendMessage`] method. The method signature if enforced by the [`Transceiver`] but transceivers are free to determine their own implementation for transmitting messages.
(e.g A message routed through the Wormhole Transceiver can be sent via automatic relaying (AR), via a specialized or custom relayer, or via the core bridge).The following event is emitted once the message has been transmitted.

```solidity
emit SendTransceiverMessage(recipientChain, endpointMessage);
```

4. Receive

Once a message has been transmitted across the wire, an off-chain process (e.g. a relayer) will forward the message to the corresponding Transceiver on the recipient chain. The relayer interacts with the transceiver via an entrypoint for receiving messages (e.g. Wormhole messages are received through the [`receiveWormholeMessages`] method, which performs the messages verification along with replay protection)
The following event is emitted during this process:

```solidity
emit ReceivedRelayedMessage(deliveryHash, sourceChain, sourceAddress);
```

This method should also forward the message to the NttManager on the recipient chain.
NOTE: The Transceiver interface does not enforce the method signature abstractly because receiving messages may be specific to the way in which a transceiver consumes messages.

```solidity
emit ReceivedMessage(vm.hash, vm.emitterChainId, vm.emitterAddress, vm.sequence);
```

5. Attestation

```solidity
emit MessageAttestedTo(digest, endpoint, _getEndpointInfosStorage()[endpoint].index);
emit MessageAlreadyExecuted(sourceManagerAddress, digest);
```

6. Mint or Unlock

```solidity
emit TransferRedeemed(digest);
```

### Solana

1. Sending

A client calls the [transfer_lock] or [transfer_burn] instruction based on whether the program is in "locking" or "burning" mode. The program mode is set during initialization. When transferring, the client must specify the amount of the transfer, the recipient chain, the recipient address on the recipient chain, and the boolean flag `should_queue` to specify whether the transfer should be queued if it hits the outbound rate limit. If `should_queue` is set to false, the transfer reverts instead of queuing if the rate limit were to be hit.

> Using the wrong transfer instruction, i.e. [`transfer_lock`] for a program that is in "burning" mode, will result in `InvalidMode` error.

Depending on the mode and instruction, the following will be produced in the program logs:

```
Program log: Instruction: TransferLock
Program log: Instruction: TransferBurn
```

Outbound transfers are always added into an Outbox via the `insert_into_outbox` method. This method checks the transfer against the configured outbound rate limit amount to determine whether the transfer should be rate limited. An `OutboxItem` is a Solana Account which holds details of the outbound transfer. If no rate limit is hit, the transfer can be released from the Outbox immediately. If a rate limit is hit, the transfer can only be released from the Outbox after the rate limit delay duration has expired.

2. Rate Limiting

The program checks rate limits via the `consume_or_delay` function during the transfer process. The Solana rate limiting logic is equivalent to the EVM rate limiting logic.

If the transfer amount fits within the current capacity:

- Reduce the current capacity
- Refill the inbound capacity for the destination chain
- Add the transfer to the outbox with `release_timestamp` set to the current timestamp, so it can be released immediately.

If the transfer amount does not fit within the current capacity:

- If `shouldQueue = true`, add the transfer to the outbox with `release_timestamp` set to the current timestamp plus the configured `RATE_LIMIT_DURATION`.
- If `shouldQueue = false`, revert with a `TransferExceedsRateLimit` error

3. Transmit

The caller then needs to request each Transceiver to send messages via the [`release_outbound`] instruction. To execute this instruction, the caller needs to pass the account of the Outbox item to be released. The instruction will then verify that the Transceiver is one of the specified senders for the message. Transceivers then send the messages based on the verification backend they are using.

For example, the Wormhole Transceiver will send by calling [`post_message`] on the Wormhole program, so that the Wormhole Guardians can observe and verify the message.

> When `revert_on_delay` is true, the transaction will revert if the release timestamp has not been reached. When `revert_on_delay` is false, the transaction succeeds, but the outbound release is not performed.

The following will be produced in the program logs:

```
Program log: Instruction: ReleaseOutbound
```

4. Receive

Similar to EVM, Transceivers vary in how they receive messages, since message relaying and verification methods may differ between implementations.

The Wormhole Transceiver receives a verified Wormhole message on Solana via the [`receive_message`] entrypoint instruction. Callers can use the [`receive_wormhole_message`] Anchor library function to execute this instruction. The instruction verifies the Wormhole VAA and stores it in a `VerifiedTransceiverMessage` account.

The following will be produced in the program logs:

```
Program log: Instruction: ReceiveMessage
```

[`redeem`] checks the inbound rate limit and places the message in an Inbox. Logic works the same as the outbound rate limit we mentioned previously.

The following will be produced in the program logs:

```
Program log: Instruction: Redeem
```

5. Mint or Unlock

The inbound transfer is released and the tokens are unlocked or minted to the recipient (depending on the mode) through either [`release_inbound_mint`] (if the mode is `burning`) or [`release_inbound_unlock`] (if the mode is `locking`). Similar to transfer, using the wrong transfer instruction, i.e. [`release_inbound_mint`] for a program that is in "locking" mode, will result in `InvalidMode` error.

> When `revert_on_delay` is true, the transaction will revert if the release timestamp has not been reached. When `revert_on_delay` is false, the transaction succeeds, but the minting/unlocking is not performed.

Depending on the mode and instruction, the following will be produced in the program logs:

```
Program log: Instruction: ReleaseInboundMint
Program log: Instruction: ReleaseInboundUnlock
```

#### Installation

Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
[Foundry]: https://book.getfoundry.sh/getting-started/installation#using-foundryup

TODO: add installation instructions for solana

Install [rust](https://doc.rust-lang.org/book/ch01-01-installation.html)

```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

#### Developer Commands

_Build_

```
$ forge build
```

_Test_

```
$ forge test
```

#### Submitting a PR

Before submitting a PR, please run the following commands:

_Test_
EVM Tests:

```
$ make test-evm
```
