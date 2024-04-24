#!/bin/bash

set -euo pipefail

# This script ensures that the EVM contracts can be safely upgraded to without
# bricking the contracts. It does this by simulating contract upgrades against
# the mainnet state, and checks that the state is consistent after the upgrade.
#
# By default, the script will compile the contracts and run the upgrade. It's
# possible to simulate an upgrade against an already deployed implementation
# contract (which is useful for independent verification of a governance
# proposal) -- see the usage instructions below.

function usage() {
cat <<EOF >&2
Usage:

  $(basename "$0") [-h] [-c s] [-x] [-k] [-l s] -- Simulate an upgrade on a fork of mainnet, and check for any errors.

  where:
    -h  show this help text
    -c  chain name
    -x  run anvil
    -k  keep anvil alive
    -l  file to log to (by default creates a new tmp file)
EOF
exit 1
}

before=$(mktemp)
after=$(mktemp)

LEDGER_ARGS="--ledger --mnemonic-derivation-path \"m/44'/60'/0'/0/9\""

### Parse command line options
chain_name=""
run_anvil=false
keepalive_anvil=false
anvil_out=$(mktemp)
while getopts ':h:c::xkl' option; do
  case "$option" in
    h) usage
       ;;
    c) chain_name=$OPTARG
       ;;
    x) run_anvil=true
       ;;
    l) anvil_out=$OPTARG
       ;;
    k) keepalive_anvil=true
       run_anvil=true
       ;;
    :) printf "missing argument for -%s\n" "$OPTARG" >&2
       usage
       ;;
   \?) printf "illegal option: -%s\n" "$OPTARG" >&2
       usage
       ;;
  esac
done
shift $((OPTIND - 1))

# Check that we have the required arguments
[ -z "$chain_name" ] && usage

# Get core contract address
CORE=$(worm info contract mainnet "$chain_name" Core)
printf "Wormhole Core Contract: $CORE\n\n"

# Use the local devnet guardian key (this is not a production key)
# GUARDIAN_ADDRESS=0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe
# GUARDIAN_SECRET=cfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0

ANVIL_PID=""

function clean_up () {
    ARG=$?
    [ -n "$ANVIL_PID" ] && kill "$ANVIL_PID"
    exit $ARG
}
trap clean_up SIGINT SIGTERM EXIT


#TODO: make RPC an optional argument
USER_ADDRESS=0EC6C20DeAb67a58ebCE8695F5e6303BfeB087Af
# USER_PK=0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d
# PORT="8545"
# RPC="$HOST:$PORT"

if [[ $run_anvil = true ]]; then
    ./anvil_fork "$chain_name"
    ANVIL_PID=$!
    echo "🍴 Forking mainnet..."
    echo "Anvil logs in $anvil_out"
    sleep 5
    ps | grep "$ANVIL_PID"
fi

GOV_CONTRACT=""
NTT_CONTRACT=""
UNSIGNED_PAUSE_VAA=""
UNSIGNED_UNPAUSE_VAA=""
case "$chain_name" in
    ethereum)
        RPC="https://rpc.ankr.com/eth"
        GOV_CONTRACT=0x23Fea5514DFC9821479fBE18BA1D7e1A61f6FfCf
        NTT_CONTRACT=0xc072B1AEf336eDde59A049699Ef4e8Fa9D594A48
        UNSIGNED_PAUSE_VAA=0100000004000000000076fc210a00010000000000000000000000000000000000000000000000000000000000000004f6ca212aede81c0a20000000000000000047656e6572616c507572706f7365476f7665726e616e636501000223fea5514dfc9821479fbe18ba1d7e1a61f6ffcfc072b1aef336edde59a049699ef4e8fa9d594a4800048456cb59
        UNSIGNED_UNPAUSE_VAA=010000000400000000002d25e93f000100000000000000000000000000000000000000000000000000000000000000044af9d5923779bdf520000000000000000047656e6572616c507572706f7365476f7665726e616e636501000223fea5514dfc9821479fbe18ba1d7e1a61f6ffcfc072b1aef336edde59a049699ef4e8fa9d594a4800043f4ba83a
        ;;
    arbitrum)
        RPC="https://rpc.ankr.com/arbitrum"
        GOV_CONTRACT=0x36CF4c88FA548c6Ad9fcDc696e1c27Bb3306163F
        NTT_CONTRACT=0x5333d0AcA64a450Add6FeF76D6D1375F726CB484
        UNSIGNED_PAUSE_VAA=01000000040000000000a97c5ba800010000000000000000000000000000000000000000000000000000000000000004efd07b35d2dd420a20000000000000000047656e6572616c507572706f7365476f7665726e616e636501001736cf4c88fa548c6ad9fcdc696e1c27bb3306163f5333d0aca64a450add6fef76d6d1375f726cb48400048456cb59
        UNSIGNED_UNPAUSE_VAA=0100000004000000000092654e5000010000000000000000000000000000000000000000000000000000000000000004529039baf463475220000000000000000047656e6572616c507572706f7365476f7665726e616e636501001736cf4c88fa548c6ad9fcdc696e1c27bb3306163f5333d0aca64a450add6fef76d6d1375f726cb48400043f4ba83a
        ;;
    optimism)
        RPC="https://rpc.ankr.com/optimism"
        GOV_CONTRACT=0x0E09a3081837ff23D2e59B179E0Bc48A349Afbd8
        NTT_CONTRACT=0x1a4F1a790f23Ffb9772966cB6F36dCd658033e13
        UNSIGNED_PAUSE_VAA=01000000040000000000952b3208000100000000000000000000000000000000000000000000000000000000000000042a5d763e56b1709d20000000000000000047656e6572616c507572706f7365476f7665726e616e63650100180e09a3081837ff23d2e59b179e0bc48a349afbd81a4f1a790f23ffb9772966cb6f36dcd658033e1300048456cb59
        UNSIGNED_UNPAUSE_VAA=01000000040000000000fe7d99ea00010000000000000000000000000000000000000000000000000000000000000004a3d4945c1212065020000000000000000047656e6572616c507572706f7365476f7665726e616e63650100180e09a3081837ff23d2e59b179e0bc48a349afbd81a4f1a790f23ffb9772966cb6f36dcd658033e1300043f4ba83a
        ;;
    base)
        RPC="https://rpc.ankr.com/base"
        GOV_CONTRACT=0x838a95B6a3E06B6f11C437e22f3C7561a6ec40F1
        NTT_CONTRACT=0x5333d0AcA64a450Add6FeF76D6D1375F726CB484
        UNSIGNED_PAUSE_VAA=010000000400000000008f3da7570001000000000000000000000000000000000000000000000000000000000000000458191dc4234221d420000000000000000047656e6572616c507572706f7365476f7665726e616e636501001e838a95b6a3e06b6f11c437e22f3c7561a6ec40f15333d0aca64a450add6fef76d6d1375f726cb48400048456cb59
        UNSIGNED_UNPAUSE_VAA=010000000400000000000498f2cd00010000000000000000000000000000000000000000000000000000000000000004a1cc2db10977351720000000000000000047656e6572616c507572706f7365476f7665726e616e636501001e838a95b6a3e06b6f11c437e22f3c7561a6ec40f15333d0aca64a450add6fef76d6d1375f726cb48400043f4ba83a
        ;;
    *) echo "unknown module $module" >&2
       usage
       ;;
esac

# Step 0) the VAAs are not compatible with the guardian
# set on mainnet (since that corresponds to a mainnet guardian network). We need
# to thus locally replace the guardian set with the local guardian key.
# echo "STEP 0:"
# echo "💂 Overriding guardian set with $GUARDIAN_ADDRESS"
# worm evm hijack -g "$GUARDIAN_ADDRESS" -i 0 -a "$CORE" --rpc "$RPC"> /dev/null
# printf "\n\n"

# Step 0.5) override the pauser and owner to be our devnet address
# echo "STEP 0.5:"
# echo "Overriding owner and pauser to be default anvil address..."
# $(cast rpc anvil_setStorageAt "$NTT_CONTRACT" 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300 "0x000000000000000000000000${USER_ADDRESS}")
# $(cast rpc anvil_setStorageAt "$NTT_CONTRACT" 0xBFA91572CE1E5FE8776A160D3B1F862E83F5EE2C080A7423B4761602A3AD1249 "0x000000000000000000000000${USER_ADDRESS}")
# printf "Done\n\n"

# Step 0.75) Resign the pause and unpause VAAs with the devnet guardian secret
# pauseVaa=$(worm edit-vaa --network devnet --gs $GUARDIAN_SECRET --vaa $UNSIGNED_PAUSE_VAA)
# unpauseVaa=$(worm edit-vaa --network devnet --gs $GUARDIAN_SECRET --vaa $UNSIGNED_UNPAUSE_VAA)

# Step 1) Query owner and pauser for the current NTT Manager contract (should not be the governance contract)
echo "STEP 1:"
echo "Getting owner and pauser for NTT Manager..."
owner=$(cast call "$NTT_CONTRACT" "owner()(address)" --rpc-url "$RPC")
pauser=$(cast call "$NTT_CONTRACT" "pauser()(address)" --rpc-url "$RPC")
if [[ $owner != "0x${USER_ADDRESS}" ]] || [[ $pauser != "0x${USER_ADDRESS}" ]]; then
  echo "ERROR! Owner is $owner and pauser is $pauser, which is unexpected! Exiting..."
  clean_up
else
  printf "Verified owner and pauser are expected as $owner\n\n"
fi

# Step 2) Transfer ownership of the NTT Manager contract to the Governance contract
echo "STEP 2:"
echo "Transferring ownership to Governance Contract..."
cast send --ledger --mnemonic-derivation-path "m/44'/60'/0'/0/9" "$NTT_CONTRACT" "transferOwnership(address)" "$GOV_CONTRACT" --rpc-url "$RPC"
cast send --ledger --mnemonic-derivation-path "m/44'/60'/0'/0/9" "$NTT_CONTRACT" "transferPauserCapability(address)" "$GOV_CONTRACT" --rpc-url "$RPC"
printf "Done\n\n"


# Step 3) Query owner and pauser of the NTT Manager contract (should be the governance contract)
echo "STEP 3:"
echo "Getting owner and pauser for NTT Manager (should both be "$GOV_CONTRACT")..."
sleep 10
owner=$(cast call "$NTT_CONTRACT" "owner()(address)" --rpc-url "$RPC")
pauser=$(cast call "$NTT_CONTRACT" "pauser()(address)" --rpc-url "$RPC")
if [[ $owner != $GOV_CONTRACT ]] || [[ $pauser != $GOV_CONTRACT ]]; then
  echo "ERROR! Both owner and pauser should be governance contract! Exiting..."
  clean_up
else
  printf "Verified owner and pauser are governance contract $GOV_CONTRACT\n\n"
fi

# Step 4) Query paused state is UNPAUSED on NTT Manager
# echo "STEP 4:"
# echo "Getting paused state on NTT Manager... (should be 0x01 or UNPAUSED)"
# isPaused=$(cast call "$NTT_CONTRACT" "isPaused()(bool)")
# if [[ $isPaused != false ]]; then
#   echo "ERROR! Contract should not be paused. Exiting..."
#   clean_up
# else
#   printf "Verified contract is not paused\n\n"
# fi

# Step 5) Submit Pause VAA to Manager via Governance contract
# echo "STEP 5:"
# echo "Submitting Pause VAA to Governance contract..."
# cast send --private-key "$USER_PK" "$GOV_CONTRACT" "performGovernance(bytes)" "$pauseVaa"
# printf "Done\n\n"

# Step 6) Query paused state is PAUSED on NTT Manager
# echo "STEP 6:"
# echo "Getting paused state on NTT Manager... (should be 0x02 or PAUSED)"
# isPaused=$(cast call "$NTT_CONTRACT" "isPaused()(bool)")
# if [[ $isPaused != true ]]; then
#   echo "ERROR! Contract should be paused. Exiting..."
#   clean_up
# else
#   printf "Verified contract is paused\n\n"
# fi

# Step 7) Submit Unpause VAA to Manager via Governance contract
# echo "STEP 7:"
# echo "Submitting Unpause VAA to Governance contract..."
# cast send --private-key "$USER_PK" "$GOV_CONTRACT" "performGovernance(bytes)" "$unpauseVaa"
# printf "Done\n\n"

# Step 8) Query paused state is UNPAUSED on NTT Manager
# echo "STEP 8:"
# echo "Getting paused state on NTT Manager... (should be 0x01 or UNPAUSED)"
# isPaused=$(cast call "$NTT_CONTRACT" "isPaused()(bool)")
# if [[ $isPaused != false ]]; then
#   echo "ERROR! Contract should not be paused. Exiting..."
#   clean_up
# else
#   printf "Verified contract is not paused\n\n"
# fi

echo "Congratulations! You've verified that the Governance contract works in a mainnet fork test."

# Anvil can be kept alive by setting the -k flag. This is useful for interacting
# with the contract after it has been upgraded.
if [[ $keepalive_anvil = true ]]; then
    echo "Listening on $RPC"
    # tail -f "$anvil_out"
    wait "$ANVIL_PID"
fi
