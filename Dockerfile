FROM node:20.11.1-alpine@sha256:f4c96a28c0b2d8981664e03f461c2677152cd9a756012ffa8e2c6727427c2bda

COPY ci_tests/package.json ci_tests/package-lock.json  ./ci_tests/
RUN --mount=type=cache,uid=1000,gid=1000,target=/home/node/.npm \
  npm ci --prefix ci_tests
COPY ci_tests ./ci_tests
