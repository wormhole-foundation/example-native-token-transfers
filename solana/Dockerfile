FROM backpackapp/build:v0.29.0@sha256:9aee169b2d8b89b4a4243419ae35c176773136e78d751b3e439eff692c9c1293 as anchor

WORKDIR /usr/src/solana/

COPY solana/Anchor.toml Anchor.toml
COPY solana/Cargo.lock Cargo.lock
COPY solana/Cargo.toml Cargo.toml
COPY solana/modules modules
COPY solana/programs programs
COPY solana/rust-toolchain rust-toolchain
COPY solana/scripts scripts

ENV RUST_BACKTRACE=1

FROM anchor AS dev-builder

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

COPY solana/Makefile Makefile
RUN make target/idl/example_native_token_transfers.json
COPY solana/ts ts

FROM anchor as mainnet-builder

ARG SOLANA_NETWORK
RUN [ -z "$SOLANA_NETWORK" ] && echo "SOLANA_NETWORK is required" && exit 1 || echo "SOLANA_NETWORK=$SOLANA_NETWORK"

RUN --mount=type=cache,target=/opt/solana/deps/target,id=build_anchor_ntt_target \
    --mount=type=cache,target=/usr/local/cargo/registry,id=cargo_registry \
    --mount=type=cache,target=.anchor,id=anchor_cache \
    anchor build --arch sbf -- --no-default-features --features $SOLANA_NETWORK

FROM scratch as export
COPY --from=mainnet-builder /usr/src/solana/target/deploy /
