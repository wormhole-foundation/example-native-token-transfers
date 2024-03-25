<div align="center">
  <img src="images/ntt-logo-black.png", height=100>
</div>

---

# Overview

Wormhole’s Native Token Transfers (NTT) is an open, flexible, and composable framework for transferring tokens across blockchains without liquidity pools. Integrators have full control over how their Natively Transferred Tokens (NTTs) behave on each chain, including the token standard and metadata. For existing token deployments, the framework can be used in “locking” mode which preserves the original token supply on a single chain. Otherwise, the framework can be used in “burning” mode to deploy natively multichain tokens with the supply distributed among multiple chains.

## Design

There are two basic components to NTT:

(1) **Transceiver**: This contract is responsible for sending NTT transfers forwarded through the `NttManager` on the source chain and delivered to a corresponding peer `NttManager` on the recipient chain. Transceivers should follow the `ITransceiver` interface. Transceivers can be defined independently of Wormhole core and can be modified to support any verification backend.

(2) **NttManager**: The NttManager contract is responsible for managing the token and the Transceivers. It also handles the rate-limiting and the message attestation logic. Note that each `NttManager` corresponds to a single token. However, a single `NttManager` can can control multiple transceivers.


<figure>
  <img src="images/ntt_architecture__with_custom_attestation.jpg" alt="NTT Architecture Diagram">
  <figcaption>Figure: NTT Architecture Diagram with Custom Attestations.</figcaption>
</figure>


## Amount trimming

In the payload, amounts are encoded as unsigned 64 bit integers, and capped at the configured `TRIMMED_DECIMALS` (e.g. 8) decimal value.
This means that if on the sending chain, the token has more than than `TRIMMED_DECIMALS`, then the amount is trimmed.
The amount that's removed during trimming is referred to as "dust". The contracts ensure to never destroy dust.
The NTT manager contracts additionally keep track of the token decimals of the other connected chains. When sending to a chain whose token decimals are less than `TRIMMED_DECIMALS`, the amount is instead trimmed to those decimals to ensure that the recipient contract can handle the amount without destroying dust.

The payload includes the trimmed amount, together with the decimals that trimmed amount is expressed in. This number is the minimum of (`TRIMMED_DECIMALS`, source token decimals, destination token decimals).

## Rate-Limiting

NTT supports rate-limiting both on the sending and destination chains. If a transfer is rate-limited on the source chain and queueing is enabled via `shouldQueue = true`, transfers are placed into an outbound queue and can be released after the expiry of the rate limit duration. Transfers that are rate-limited on the destination chain are added to an inbound queue with a similar release delay.

## Cancel-Flows

If users bridge frequently between a given source chain and destination chain, the capacity could be exhausted quickly. This can leave other users rate-limited, potentially delaying their transfers. To mitigate this issue, the outbound transfer cancels the inbound rate-limit on the source chain (refills the inbound rate-limit by an amount equal to that of the outbound transfer amount) and vice-versa, the inbound transfer cancels the outbound rate-limit on the destination chain (refills the outbound rate-limit by an amount equal to the inbound transfer amount).
