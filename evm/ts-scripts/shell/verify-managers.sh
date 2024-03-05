if test -z "$ENV"; then
  echo "ENV is not set"
  exit 1
fi

scanner_tokens_file="$SCANNER_TOKENS_FILE_PATH"
if test -z $scanner_tokens_file; then
    echo "SCANNER_TOKENS_FILE_PATH is not set"
    exit 1
fi
echo "Using scanner tokens file at $scanner_tokens_file"

chains_file_path="ts-scripts/config/$ENV/chains.json"
if ! test -f "$chains_file_path"; then
  echo "File does not exist at $chains_file_path"
  exit 1
fi

managers_config_file_path="ts-scripts/config/$ENV/managers.json"
if ! test -f "$managers_config_file_path"; then
  echo "Managers file configuration does not exist at $managers_config_file_path"
  exit 1
fi

contracts_file_path="ts-scripts/config/$ENV/contracts.json"
if ! test -f "$contracts_file_path"; then
  echo "Contracts file configuration does not exist at $contracts_file_path"
  exit 1
fi

operating_chains=$(jq -r '.operatingChains' $chains_file_path);

if [ "$operating_chains" = "null" ]; then
  operating_chains=$(jq -r '.chains[] | .chainId' $chains_file_path)
else
  operating_chains=$(jq -r '.operatingChains[]' $chains_file_path)
fi

# export FOUNDRY_PROFILE=production

for chain in $operating_chains; do
  echo "Operating on chain $chain:"
  config=$(jq --raw-output ".[] | select(.chainId == $chain)" $managers_config_file_path)

  export implementation_address=$(jq --raw-output ".NttManagerImplementations[] | select(.chainId == $chain) | .address" $contracts_file_path)
  export proxy_address=$(jq --raw-output ".NttManagerProxies[] | select(.chainId == $chain) | .address" $contracts_file_path)
  export etherscan_api_key=$(jq --raw-output ".[] | select(.chainId == $chain) | .token" $scanner_tokens_file)
  export evm_network_id=$(jq ".chains[] | select(.chainId == $chain) | .evmNetworkId" $chains_file_path)
  export transceiver_structs_address=$(jq --raw-output ".TransceiverStructsLibs[] | select(.chainId == $chain) | .address" $contracts_file_path)
  export trimmed_amount_lib_address=$(jq --raw-output ".TrimmedAmountLibs[] | select(.chainId == $chain) | .address" $contracts_file_path)

  if [ "$implementation_address" = "" ] || 
    [ "$proxy_address" = "" ] ||
    [ "$etherscan_api_key" = "nul" ] ||
    [ "$transceiver_structs_address" = "null" ] ||
    [ "$trimmed_amount_lib_address" = "null" ] ||
    [ "$evm_network_id" = "null" ]; then
      echo "One of the addresses is not set. Skipping...";
      continue
  fi

  token=$(jq --raw-output ".token" <<< $config)
  mode=$(jq --raw-output ".mode" <<< $config)
  rate_limit_duration=$(jq --raw-output ".rateLimitDuration" <<< $config)
  skip_rate_limit=$(jq --raw-output ".skipRateLimit" <<< $config)

  implementation_constructor_args=$(\
    cast abi-encode "constructor(address,uint16,uint16,uint64,bool)" \
    "$token" "$mode" "$chain" "$rate_limit_duration" "$skip_rate_limit" \
  )

  lib_paths="src/libraries/TransceiverStructs.sol:TransceiverStructs:$transceiver_structs_address"
  # a="src/libraries/TrimmedAmount.sol:TrimmedAmountLib:$trimmed_amount_lib_address"

  forge verify-contract --chain "$evm_network_id" \
    --etherscan-api-key "$etherscan_api_key" \
    "$implementation_address" \
    --constructor-args $implementation_constructor_args \
    --libraries $lib_paths \
    src/NttManager/NttManager.sol:NttManager --watch
  
  init_data=$(cast calldata "initialize()")
  forge verify-contract --chain "$evm_network_id" \
    --etherscan-api-key "$etherscan_api_key" \
    "$proxy_address" \
    lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy --watch \
    --constructor-args $(cast abi-encode "constructor(address,bytes)" "$implementation_address" "$init_data")
done
