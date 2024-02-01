all: build

#######################
## BUILD

.PHONY: build
build:
	cd evm && forge build

#######################
## TESTS

.PHONY: check-format
check-format:
	forge fmt --check

.PHONY: test
test:
	forge test -vvv

# Verify that the contracts do not include PUSH0 opcodes
test-push0:
	forge build --extra-output evm.bytecode.opcodes
	@if grep -qr --include \*.json PUSH0 ./out; then echo "Contract uses PUSH0 instruction" 1>&2; exit 1; else echo "PUSH0 Verification Succeeded"; fi