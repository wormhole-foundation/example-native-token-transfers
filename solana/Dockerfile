FROM backpackapp/build:v0.29.0 as anchor

WORKDIR /usr/src/anchor-ntt/

COPY Anchor.toml Anchor.toml
COPY Cargo.lock Cargo.lock
COPY Cargo.toml Cargo.toml
COPY modules modules
COPY programs programs
COPY keys/solana-devnet.json solana-devnet.json

ENV RUST_BACKTRACE=1

FROM anchor AS builder

RUN mkdir -p /opt/solana/deps

RUN --mount=type=cache,target=/opt/solana/deps/target,id=build_anchor_ntt_target \
    --mount=type=cache,target=/usr/local/cargo/registry,id=cargo_registry \
    --mount=type=cache,target=.anchor,id=anchor_cache \
    anchor build --arch sbf

RUN cp ./target/sbf-solana-solana/release/example_native_token_transfers.so /opt/solana/deps/example_native_token_transfers.so
RUN cp ./target/sbf-solana-solana/release/wormhole_governance.so /opt/solana/deps/wormhole_governance.so
RUN cp solana-devnet.json /opt/solana/deps/solana-devnet.json

# TODO: Copy compiled files into somewhere accessible for the rest of Tilt.
#       
# FROM scratch AS export-stage
# COPY --from=builder /opt/solana/deps /
