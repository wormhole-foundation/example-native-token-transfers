.PHONY: build
build: _anchor-build target/idl/example_native_token_transfers.json

# remove the generics from the idl file. This is necessary as of anchor 0.29.0, because
# the javascript library does not support generics yet, and just panics
.PHONY: target/idl/example_native_token_transfers.json
target/idl/example_native_token_transfers.json:
	@echo "Removing generics from $@"
	@ ./scripts/patch-idl $@

.PHONY: anchor-build
_anchor-build:
	@anchor build --arch sbf

anchor-test:
	anchor test

node_modules: package-lock.json
	npm ci

.PHONY: artifacts-mainnet
artifacts-mainnet:
	rm -rf $@
	DOCKER_BUILDKIT=1 docker build -t export -o $@ .
	@cd $@ && ls | xargs sha256sum > checksums.txt
	@cat $@/checksums.txt

.PHONY: clean
clean:
	anchor clean
	rm -rf .anchor node_modules
