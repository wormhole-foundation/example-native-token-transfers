# NTT Manager

## Overview

The NttManager contract is responsible for managing the token and the Transceivers. It also handles the rate-limiting and the message attestation logic. Note that each `NttManager` corresponds to a single token. However, a single `NttManager` can control multiple transceivers.

## Message Specification

NttManagers do not directly publish messages. These will be wrapped in a [TransceiverMessage](./Transceiver.md#transceivermessage).

```go
[32]byte id          // a unique message identifier
[32]byte sender      // original message sender address
uint16   payload_len // length of the payload
[]byte   payload
```

### Payloads

#### NativeTokenTransfer

```go
[4]byte  prefix = 0x994E5454 // 0x99'N''T''T'
uint8    decimals            // number of decimals for the amount
uint64   amount              // amount being transferred
[32]byte source_token        // source chain token address
[32]byte recipient_address   // the address of the recipient
uint16   recipient_chain     // the Wormhole Chain ID of the recipient
```
