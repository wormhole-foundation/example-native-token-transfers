## NTT: Native Token Transfers

### Overview

Wormhole’s Native Token Transfers (NTT) is an open, flexible, and composable framework for transferring tokens across blockchains without liquidity pools. Integrators have full control over how their Natively Transferred Tokens (NTTs) behave on each chain, including the token standard and metadata. For existing token deployments, the framework can be used in “locking” mode which preserves the original token supply on a single chain. Otherwise, the framework can be used in “burning” mode to deploy natively multichain tokens with supply distributed among multiple chains.

### Design
 - Transceiver - This contract module is responsible for sending Ntt transfers forwarded through the NTTManager on the source chain and delivered to a corresponding peer NTTManager on the recipient chain. Transceivers should follow the ITransceiver interface. Transceivers can be instantiated without use of the Wormhole core contracts for message authentication.

 - NttManager: The NttManager contract is responsible for managing the token and the transceivers. It also handles the rate limiting and the message attestation logic. Note that each NTTManager corresponds to a single token. However, a single NTTManager can manager can control multiple transceivers.

### NTT Message Lifecycle

### EVM
1. **Sending**: A client calls on [`transfer`] to initiate an NTT transfer. The client must specify at minimum, the amount of the transfer, the recipient chain, and the recipient address on the recipient chain. [`transfer`] also supports a flag to specify whether the NTTManager should queue transfers if they are rate-limited. Clients can also include additional instructions to forward along to its peer NTT Manager on the recipient chain to execute. Depending on the mode, transfers are either "locked" or "burned". Once the transfer has been forwarded to the Transceiver, the NTTManager emits the following event:

``` solidity
emit TransferSent(recipient, _nttDenormalize(amount), recipientChain, seq);
```
2. **Rate Limiting**: NTT supports rate-limiting of tranfers based on a 24-hr sliding window. This is intended to be a defense-in-depth security measure to mitigate and localize risk. This is a security feature intended to protect large unintended transfers. If a transfer sent from the source chain is rate-limited, it is added to a queue of transfers. The following event is emitted:
``` solidity
emit OutboundTransferRateLimited(msg.sender, sequence, amount, getCurrentOutboundCapacity());
```
A transfer can be released from the queue in 2 ways: (1) the capacity available exceeds the transfer amount; (2) the 24 hr period is up. In both cases, the client can call the [`completeOutboundQueuedTransfer`] function to release the transfer from the queue. The client should specify the gas amount here again to ensure that the delivery does not revert.

3. Transmit

Once the NttManager forwards the message to the Transceiver the message is transmitted via the [`sendMessage`] method. The method signature if enforced by the [`Transceiver`] but transceivers are free to determine their own implementation for transmitting messages.
(e.g A message routed through the Wormhole Transceiver can be sent via automatic relaying (AR), via a specialized or custom relayer, or via the core bridge).The following event is emitted once the message has been transmitted.
``` solidity
emit SendTransceiverMessage(recipientChain, endpointMessage);
```
4. Receive

Once a message has been transmitted across the wire, an off-chain process (e.g. a relayer) will forward the message to the corresponding Transceiver on the recipient chain. The relayer interacts with the transceiver via an entrypoint for receiving messages (e.g. Wormhole messages are received through the [`receiveWormholeMessages`] method, which performs the messages verification along with replay protection)
The following event is emitted during this process:
``` solidity
emit ReceivedRelayedMessage(deliveryHash, sourceChain, sourceAddress);
```
This method should also forward the message to the NttManager on the recipient chain.
NOTE: The Transceiver interface does not enforce the method signature abstractly because receiving messages may be specific to the way in which a transceiver consumes messages.

``` solidity
emit ReceivedMessage(vm.hash, vm.emitterChainId, vm.emitterAddress, vm.sequence);
```

5. Attestation

``` solidity
emit MessageAttestedTo(digest, endpoint, _getEndpointInfosStorage()[endpoint].index);
emit MessageAlreadyExecuted(sourceManagerAddress, digest);
```

6. Mint or Unlock
``` solidity
emit TransferRedeemed(digest);
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
