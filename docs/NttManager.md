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

> Note: Integrators who need to send different types of payloads should also use a unique 4-byte prefix to distinguish them from `NativeTokenTransfer` and one another.

#### NativeTokenTransfer

```go
[4]byte   prefix = 0x994E5454 // 0x99'N''T''T'
uint8     decimals            // number of decimals for the amount
uint64    amount              // amount being transferred
[32]byte  source_token        // source chain token address
[32]byte  recipient_address   // the address of the recipient
uint16    recipient_chain     // the Wormhole Chain ID of the recipient
```

To support integrators who may want to send additional, custom data with their transfers, this format may be extended to also include these additional, optional fields. Customizing transfers in this way ensures compatibility of the canonical portion of the payload across the ecosystem (Connect, explorers, NTT Global Accountant, etc).

In order to aid parsers in identifying your additional payload, it is recommended to start it with a unique 4-byte prefix.

```go
uint16 additional_payload_len // length of the custom payload
[]byte additional_payload     // custom payload - recommended that the first 4 bytes are a unique prefix
```
