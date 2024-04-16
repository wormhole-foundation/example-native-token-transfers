FROM node:20.11.1-alpine@sha256:f4c96a28c0b2d8981664e03f461c2677152cd9a756012ffa8e2c6727427c2bda

WORKDIR /usr/src/sdk/

COPY . ./ 
RUN --mount=type=cache,uid=1000,gid=1000,target=/home/node/.npm \
  npm ci

COPY --from=ntt-evm-contract . ../evm/out
COPY --from=ntt-solana-contract /usr/src/solana/target/idl ../solana/target/idl
COPY --from=ntt-solana-contract /usr/src/solana/target/types ../solana/target/types

RUN npm run build
RUN npm run generate:test