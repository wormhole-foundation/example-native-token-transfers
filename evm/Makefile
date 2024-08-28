.DEFAULT_GOAL = build
.PHONY: build prod-build clean gen-bindings test forge-test push0-test lint fix-lint


#######################
## BUILD

build:
	forge build


prod-build: clean
	docker build --target foundry-export -f Dockerfile -o out .

clean:
	forge clean

gen-bindings: prod-build
	npm ci && cd ts && npm run generate


#######################
## TESTS

test: forge-test push0-test


forge-test:
	forge test -vvv

# Verify that the contracts do not include PUSH0 opcodes
push0-test:
	forge build --extra-output evm.bytecode.opcodes
	@if grep -qr --include \*.json PUSH0 ./evm/out; then echo "Contract uses PUSH0 instruction" 1>&2; exit 1; else echo "PUSH0 Verification Succeeded"; fi


#######################
## LINT

lint:
	forge fmt --check


fix-lint:
	forge fmt