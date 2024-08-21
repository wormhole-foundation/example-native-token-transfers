#######################
## BUILD

.PHONY: build-evm
build-evm:
	cd evm && forge build

.PHONY: clean-evm
clean-evm:
	cd evm && forge clean

.PHONY: build-evm-prod
build-evm-prod: clean-evm
	cd evm && docker build --target foundry-export -f Dockerfile -o out .

.PHONY: gen-evm-bindings
gen-evm-bindings: build-evm-prod
	npm ci && cd evm/ts && npm run generate

.PHONY: build-solana
build-solana:
	cd solana; BPF_OUT_DIR="$(pwd)/target/deploy" cargo build-sbf

.PHONY: build-anchor
build-anchor:
	cd solana; make build

#######################
## TESTS

.PHONY: check-format
check-format:
	cd evm && forge fmt --check

.PHONY: fix-format
fix-format:
	cd evm && forge fmt

.PHONY: test-evm
test-evm:
	cd evm && forge test -vvv


# Verify that the contracts do not include PUSH0 opcodes
.PHONY: test-push0
test-push0:
	cd evm && forge build --extra-output evm.bytecode.opcodes
	@if grep -qr --include \*.json PUSH0 ./evm/out; then echo "Contract uses PUSH0 instruction" 1>&2; exit 1; else echo "PUSH0 Verification Succeeded"; fi

.PHONY: test-solana-unit
test-solana-unit:
	cd solana; cargo build-sbf --features "mainnet"
	cd solana; cargo test-sbf --features "mainnet"
	cd solana; cargo test

.PHONY: test-anchor
test-anchor:
	cd solana; make test

.PHONY: test-solana
test-solana: build-solana test-solana-unit build-anchor test-anchor


.PHONY: lint-solana
lint-solana:
	cargo fmt --check --all --manifest-path solana/Cargo.toml
	cargo check --workspace --tests --manifest-path solana/Cargo.toml
	cargo clippy --workspace --tests --manifest-path solana/Cargo.toml -- -Dclippy::cast_possible_truncation
