.PHONY: build
build: _anchor-build target/idl/example_native_token_transfers.json

# remove the generics from the idl file. This is necessary as of anchor 0.29.0, because
# the javascript library does not support generics yet, and just panics
.PHONY: target/idl/example_native_token_transfers.json
target/idl/example_native_token_transfers.json: _anchor-build
	@echo "Removing generics from $@"
	@ ./scripts/patch-idl $@

.PHONY: anchor-build
_anchor-build:
	@anchor build --arch sbf

anchor-test: build idl sdk
	anchor test --skip-build

.PHONY: idl
idl: target/idl/example_native_token_transfers.json
	$(eval VERSION=$(shell grep "const VERSION" programs/example-native-token-transfers/src/lib.rs | cut -d'"' -f2 | sed 's/\./_/g'))
	@echo "IDL Version: $(VERSION)"
	@ mkdir -p ts/idl/$(VERSION)/json
	@ mkdir -p ts/idl/$(VERSION)/ts
	@ cp -r target/idl/* ts/idl/$(VERSION)/json/
	@for jsonfile in ts/idl/$(VERSION)/json/*.json; do \
	    tsfile=$$(echo $$jsonfile | sed 's/json\/\(.*\)\.json/ts\/\1.ts/'); \
	    tsx scripts/regenerateIdl.ts $$jsonfile > $$tsfile; \
	done

sdk: build
	@echo "Building SDK"
	cd .. && npm ci && npm run build:solana

.PHONY: clean
clean:
	anchor clean
	rm -rf .anchor node_modules
