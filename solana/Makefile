.PHONY: build
build: _anchor-build target/idl/example_native_token_transfers.json target/types/example_native_token_transfers.ts

.PHONY: target/idl/example_native_token_transfers.json
target/idl/example_native_token_transfers.json:
	npx ts-node scripts/mangleIdl.ts $@ scripts/ntt_instantiations.json > tmp.json && mv tmp.json $@

target/types/example_native_token_transfers.ts: target/idl/example_native_token_transfers.json
	npx ts-node scripts/idlJsonToTs.ts $< ExampleNativeTokenTransfers > $@

.PHONY: anchor-build
_anchor-build:
	@anchor build --arch sbf

anchor-test: node_modules build target/types/example_native_token_transfers.ts
	anchor test --skip-build

node_modules: package-lock.json
	npm ci

.PHONY: clean
clean:
	anchor clean
	rm -rf .anchor node_modules
