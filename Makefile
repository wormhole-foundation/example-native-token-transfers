all: build

#######################
## BUILD

.PHONY: build
build:
	forge build

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
	@if grep -qr --include \*.json PUSH0 ./out; then echo "Contract uses PUSH0 instruction" 1>&2; exit 1; fi

verify-push0:
	@if grep -qr --include \*.json PUSH0 ./out; then echo "Contract uses PUSH0 instruction" 1>&2; exit 1; fi