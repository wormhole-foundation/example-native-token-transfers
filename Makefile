all: build

#######################
## BUILD

.PHONY: build
build: forge_dependencies
	forge build

#######################
## INSTALL DEPENDENCIES

.PHONY: forge_dependencies
forge_dependencies: lib/forge-std lib/openzeppelin-contracts lib/wormhole-solidity-sdk

lib/forge-std:
	forge install foundry-rs/forge-std@v1.5.5 --no-git --no-commit

lib/openzeppelin-contracts:
	forge install openzeppelin/openzeppelin-contracts@0457042d93d9dfd760dbaa06a4d2f1216fdbe297 --no-git --no-commit

lib/wormhole-solidity-sdk:
	forge install wormhole-foundation/wormhole-solidity-sdk@374a016685715f6aa8cb05f079f22f471e5f48fc --no-git --no-commit

#######################
## TESTS

.PHONY: check-format
check-format:
	forge fmt --check

.PHONY: test
test: forge_dependencies
	forge test -vvv
