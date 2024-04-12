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

# Run anchor's linter on all Rust files in the current directory via `anchor idl parse`
# Results written to /dev/null because we're just calling parse for the linting capabilities and we don't care about
# the JSON output.
# anchor-cli v0.29.0 doesn't seem to do linting on the command-line during the build process so this is a workaround

.PHONY: anchor-lint
anchor-lint:
	bash scripts/anchor-lint.sh

node_modules: package-lock.json
	npm ci

.PHONY: clean
clean:
	anchor clean
	rm -rf .anchor node_modules

