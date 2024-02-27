# This file is based on: https://github.com/wormhole-foundation/wormhole/blob/wen/solana-rewrite/solana/Dockerfile.ci
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

ARG SOLANA_CLI
RUN if [ -z "$SOLANA_CLI" ]; then echo 'Environment variable SOLANA_CLI must be specified. Exiting.'; exit 1; fi

ARG ANCHOR_CLI
RUN if [ -z "$ANCHOR_CLI" ]; then echo 'Environment variable ANCHOR_CLI must be specified. Exiting.'; exit 1; fi

# Compare with EVM Dockerfile
ARG NODE_VERSION="v20.11.1"

ENV HOME="/root"
ENV PATH="${HOME}/.cargo/bin:${PATH}"
ENV PATH="${HOME}/.local/share/solana/install/active_release/bin:${PATH}"
ENV PATH="${HOME}/.nvm/versions/node/${NODE_VERSION}/bin:${PATH}"

# Install base utilities.
RUN mkdir -p /workdir && \
    apt-get update -qq && apt-get upgrade -qq && apt-get install -qq \
    build-essential git curl wget jq pkg-config python3-pip \
    libssl-dev libudev-dev

# Install rust.
# TODO: we can consider removing rustfmt and clippy here. this container does integration tests, not linting
RUN curl "https://sh.rustup.rs" -sfo rustup.sh && \
    sh rustup.sh -y 

# Install node / npm / yarn.
RUN curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.11/install.sh | bash
ENV NVM_DIR="${HOME}/.nvm"
RUN . $NVM_DIR/nvm.sh && \
    nvm install ${NODE_VERSION} && \
    nvm use ${NODE_VERSION} && \
    nvm alias default node

RUN npm install -g yarn

# Install Solana tools.
RUN sh -c "$(curl -sSfL https://release.solana.com/${SOLANA_CLI}/install)"

# Install anchor.
RUN cargo install --git https://github.com/coral-xyz/anchor --tag ${ANCHOR_CLI} anchor-cli --locked

COPY . /ci_tests_solana

COPY package.json package-lock.json ./ci_tests_solana

WORKDIR /ci_tests_solana

# the anchor build target has an underscore
RUN make _anchor-build

RUN make anchor-test
