.PHONY: build
build: _anchor-build target/idl/example_native_token_transfers.json idl

# remove the generics from the idl file. This is necessary as of anchor 0.29.0, because
# the javascript library does not support generics yet, and just panics
.PHONY: target/idl/example_native_token_transfers.json
target/idl/example_native_token_transfers.json: _anchor-build
	@echo "Removing generics from $@"
	@ ./scripts/patch-idl $@

.PHONY: anchor-build
_anchor-build:
	@anchor build --arch sbf

anchor-test: node_modules build target/idl/example_native_token_transfers.json sdk
	anchor test --skip-build

sdk: build
	@echo "Building SDK"
	cd ../sdk && npm ci && npm run build:solana

.PHONY: idl
idl: target/idl/example_native_token_transfers.json
	@ mkdir -p $@/json
	@ mkdir -p $@/ts
	@ cp -r target/idl/* $@/json/
	@ cp -r target/types/* $@/ts/

node_modules: package-lock.json
	npm ci

.PHONY: artifacts-mainnet
artifacts-mainnet: NETWORK=mainnet
artifacts-mainnet: _artifacts
	mv _artifacts $@

.PHONY: artifacts-solana-devnet
artifacts-solana-devnet: NETWORK=solana-devnet
artifacts-solana-devnet: _artifacts
	mv _artifacts $@

.PHONY: artifacts-tilt-devnet
artifacts-tilt-devnet: NETWORK=tilt-devnet
artifacts-tilt-devnet: _artifacts
	mv _artifacts $@

.PHONY: _artifacts
_artifacts:
	rm -rf $@
	DOCKER_BUILDKIT=1 cd .. && docker build -f solana/Dockerfile --build-arg="SOLANA_NETWORK=$(NETWORK)" -t export -o solana/$@ .
	@cd $@ && ls | xargs sha256sum > checksums.txt
	@cat $@/checksums.txt

.PHONY: clean
clean:
	anchor clean
	rm -rf .anchor node_modules
