.PHONY: build
build: _anchor-build target/idl/example_native_token_transfers.json

# remove the generics from the idl file. This is necessary as of anchor 0.29.0, because
# the javascript library does not support generics yet, and just panics
.PHONY: target/idl/example_native_token_transfers.json
target/idl/example_native_token_transfers.json:
	@echo "Removing generics from $@"
	@ cat $@ | jq '(.accounts, .types) |= map(select(has("generics") | not))' > temp.json && mv temp.json $@

.PHONY: anchor-build
_anchor-build:
	@anchor build

anchor-test: build target/idl/example_native_token_transfers.json
	anchor test --skip-build
