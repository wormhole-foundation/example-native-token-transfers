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
