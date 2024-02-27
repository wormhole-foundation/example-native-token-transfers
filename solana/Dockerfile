FROM backpackapp/build:v0.29.0

COPY . /usr/src/anchor-ntt
WORKDIR /usr/src/anchor-ntt/

RUN mkdir -p /opt/solana/deps

# Build NTT Solana programs
RUN anchor build --arch sbf
# RUN anchor build --arch sbf && \
#     cp target/sbf-solana-solana/release/example_native_token_transfers.so /opt/solana/deps/example_native_token_transfers.so && \
#     cp target/sbf-solana-solana/release/wormhole-governance.so /opt/solana/deps/wormhole-governance.so
#
# # FROM scratch AS export-stage
# # COPY --from=builder /opt/solana/deps /
