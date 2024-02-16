all: build

#######################
## BUILD

.PHONY: forge_dependencies
forge_dependencies: lib/forge-std lib/wormhole-solidity-sdk lib/openzeppelin-contracts

lib/wormhole-solidity-sdk:
	forge install wormhole-foundation/wormhole-solidity-sdk@2b7db51f99b49eda99b44f4a044e751cb0b2e8ea --no-git --no-commit

lib/openzeppelin-contracts:
	forge install openzeppelin/openzeppelin-contracts@0457042d93d9dfd760dbaa06a4d2f1216fdbe297 --no-git --no-commit

lib/forge-std:
	forge install foundry-rs/forge-std@v1.7.5 --no-git --no-commit

.PHONY: build
build: forge_dependencies
	forge build

.PHONY: clean
clean:
	rm -rf lib
	forge clean

#######################
## TESTS

.PHONY: check-format
check-format:
	forge fmt --check

.PHONY: test
test: forge_dependencies
	forge test -vvv

# Verify that the contracts do not include PUSH0 opcodes
test-push0: forge_dependencies
	forge build --extra-output evm.bytecode.opcodes
	@if grep -qr --include \*.json PUSH0 ./out; then echo "Contract uses PUSH0 instruction" 1>&2; exit 1; else echo "PUSH0 Verification Succeeded"; fi