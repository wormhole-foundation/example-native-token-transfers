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

config_file_path="ts-scripts/config/$ENV/transceivers.json"
if ! test -f "$config_file_path"; then
  echo "Managers file configuration does not exist at $config_file_path"
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

export FOUNDRY_PROFILE=production

for chain in $operating_chains; do
  echo "Operating on chain $chain:"
  config=$(jq --raw-output ".[] | select(.chainId == $chain)" $config_file_path)

  export implementation_address=$(jq --raw-output ".NttTransceiverImplementations[] | select(.chainId == $chain) | .address" $contracts_file_path)
  export proxy_address=$(jq --raw-output ".NttTransceiverProxies[] | select(.chainId == $chain) | .address" $contracts_file_path)

  export manager_address=$(jq --raw-output ".NttManagerProxies[] | select(.chainId == $chain) | .address" $contracts_file_path)
  export wormhole_core_address=$(jq --raw-output ".WormholeCoreContracts[] | select(.chainId == $chain) | .address" $contracts_file_path)
  export wormhole_relayer_address=$(jq --raw-output ".WormholeRelayers[] | select(.chainId == $chain) | .address" $contracts_file_path)
  export specialized_relayer_address=$(jq --raw-output ".SpecializedRelayers[] | select(.chainId == $chain) | .address" $contracts_file_path)
  export transceiver_structs_address=$(jq --raw-output ".TransceiverStructsLibs[] | select(.chainId == $chain) | .address" $contracts_file_path)

  export etherscan_api_key=$(jq --raw-output ".[] | select(.chainId == $chain) | .token" $scanner_tokens_file)
  export evm_network_id=$(jq ".chains[] | select(.chainId == $chain) | .evmNetworkId" $chains_file_path)

  # echo "implementation_address $implementation_address"
  # echo "proxy_address $proxy_address"
  # echo "etherscan_api_key $etherscan_api_key"
  # echo "manager_address $manager_address"
  # echo "wormhole_core_address $wormhole_core_address"
  # echo "wormhole_relayer_address $wormhole_relayer_address"
  # echo "specialized_relayer_address $specialized_relayer_address"
  # echo "transceiver_structs_address $transceiver_structs_address"
  # echo "evm_network_id $evm_network_id"

  if [ "$implementation_address" = "" ] || 
    [ "$proxy_address" = "" ] ||
    [ "$etherscan_api_key" = "nul" ] ||
    [ "$manager_address" = "null" ] ||
    [ "$wormhole_core_address" = "null" ] ||
    [ "$wormhole_relayer_address" = "null" ] ||
    [ "$specialized_relayer_address" = "null" ] ||
    [ "$transceiver_structs_address" = "null" ] ||
    [ "$evm_network_id" = "null" ]; then
      echo "One of the addresses is not set. Skipping...";
      continue
  fi

  consistency_level=$(jq --raw-output ".consistencyLevel" <<< $config)
  gas_limit=$(jq --raw-output ".gasLimit" <<< $config)

  implementation_constructor_args=$(\
    cast abi-encode "constructor(address,address,address,address,uint8,uint256)" \
    "$manager_address" "$wormhole_core_address" "$wormhole_relayer_address" \
    "$specialized_relayer_address" "$consistency_level" "$gas_limit" \
  )

  lib_paths="src/libraries/TransceiverStructs.sol:TransceiverStructs:$transceiver_structs_address"

  # echo "lib_paths: $lib_paths"

  echo "constructor args: $implementation_constructor_args"

  forge verify-contract --chain "$evm_network_id" \
    --etherscan-api-key "$etherscan_api_key" \
    "$implementation_address" \
    --constructor-args $implementation_constructor_args \
    --libraries "$lib_paths" \
    src/Transceiver/WormholeTransceiver/WormholeTransceiver.sol:WormholeTransceiver --watch
  
  init_data=$(cast calldata "initialize()")
  forge verify-contract --chain "$evm_network_id" \
    --etherscan-api-key "$etherscan_api_key" \
    "$proxy_address" \
    lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy --watch \
    --constructor-args $(cast abi-encode "constructor(address,bytes)" "$implementation_address" "$init_data")
done
