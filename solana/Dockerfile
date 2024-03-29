FROM backpackapp/build:v0.29.0@sha256:9aee169b2d8b89b4a4243419ae35c176773136e78d751b3e439eff692c9c1293 as anchor

WORKDIR /usr/src/anchor-ntt/

COPY Anchor.toml Anchor.toml
COPY Cargo.lock Cargo.lock
COPY Cargo.toml Cargo.toml
COPY modules modules
COPY programs programs

ENV RUST_BACKTRACE=1

FROM anchor AS builder

RUN mkdir -p /opt/solana/deps

RUN --mount=type=cache,target=/opt/solana/deps/target,id=build_anchor_ntt_target \
    --mount=type=cache,target=/usr/local/cargo/registry,id=cargo_registry \
    --mount=type=cache,target=.anchor,id=anchor_cache \
    anchor build --arch sbf -- --no-default-features --features tilt-devnet

RUN cp ./target/sbf-solana-solana/release/example_native_token_transfers.so /opt/solana/deps/example_native_token_transfers.so
RUN cp ./target/sbf-solana-solana/release/wormhole_governance.so /opt/solana/deps/wormhole_governance.so

RUN --mount=type=cache,target=/opt/solana/deps/target,id=build_anchor_ntt_target \
    --mount=type=cache,target=/usr/local/cargo/registry,id=cargo_registry \
    --mount=type=cache,target=.anchor,id=anchor_cache \
    anchor build --arch sbf -- --no-default-features --features tilt-devnet2

RUN cp ./target/sbf-solana-solana/release/example_native_token_transfers.so /opt/solana/deps/example_native_token_transfers_2.so

COPY --from=solana-contract /opt/solana/deps/bridge.so /opt/solana/deps/bridge.so
COPY --from=solana-contract /opt/solana/deps/token_bridge.so /opt/solana/deps/token_bridge.so
COPY --from=solana-contract /opt/solana/deps/nft_bridge.so /opt/solana/deps/nft_bridge.so
COPY --from=solana-contract /opt/solana/deps/cpi_poster.so /opt/solana/deps/cpi_poster.so
COPY --from=solana-contract /opt/solana/deps/mpl_token_metadata.so /opt/solana/deps/mpl_token_metadata.so
COPY --from=solana-contract /opt/solana/deps/wormhole_migration.so /opt/solana/deps/wormhole_migration.so

COPY Makefile Makefile
RUN make target/idl/example_native_token_transfers.json
COPY ts ts
