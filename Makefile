all: build

#######################
## BUILD

.PHONY: build
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
	cd ci_tests && rm -rf evm_binding && npm ci && npm run gen-evm-bindings && cd -
	cd sdk/evm && rm -rf src/ethers-contracts && npm ci && npm run genenerate && cd -

#######################
## TESTS

.PHONY: check-format
check-format:
	cd evm && forge fmt --check

.PHONY: fix-format
fix-format:
	cd evm && forge fmt

.PHONY: test
test-evm:
	cd evm && forge test -vvv

# Verify that the contracts do not include PUSH0 opcodes
test-push0:
	forge build --extra-output evm.bytecode.opcodes
	@if grep -qr --include \*.json PUSH0 ./out; then echo "Contract uses PUSH0 instruction" 1>&2; exit 1; else echo "PUSH0 Verification Succeeded"; fi
