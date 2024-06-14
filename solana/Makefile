.DEFAULT_GOAL = build
.PHONY: build test idl sdk clean

#find and convert version line:
#  turn `const VERSION: &str = "major.minor.patch";` into `major_minor_patch`
#use make functions to minimize dependence on shell
VERSION = $(subst .,_,$(subst ;,,$(subst ",,$(lastword \
  $(shell grep "const VERSION" programs/example-native-token-transfers/src/lib.rs) \
))))

# after building, remove the generics from the idl file. This is necessary as of anchor 0.29.0,
# because the javascript library does not support generics yet, and just panics
build:
	anchor build --arch sbf
	@echo "Removing generics from target/idl/example_native_token_transfers.json"
	./scripts/patch-idl target/idl/example_native_token_transfers.json


test: idl sdk node_modules
	anchor test --skip-build

idl: build
	@echo "IDL Version: $(VERSION)"
	mkdir -p ts/idl/$(VERSION)/json
	mkdir -p ts/idl/$(VERSION)/ts
	cp -r target/idl/* ts/idl/$(VERSION)/json/
	for jsonfile in ts/idl/$(VERSION)/json/*.json; do \
	  tsfile=$$(echo $$jsonfile | sed 's/json\/\(.*\)\.json/ts\/\1.ts/'); \
	  tsx scripts/regenerateIdl.ts $$jsonfile > $$tsfile; \
	done

sdk: build
	@echo "Building SDK"
	cd .. && npm ci && npm run build:solana

clean:
	anchor clean
	rm -rf .anchor node_modules

node_modules:
	npm install