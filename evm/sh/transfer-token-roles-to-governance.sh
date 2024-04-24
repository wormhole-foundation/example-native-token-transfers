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
GUARDIAN_ADDRESS=0xbeFA429d57cD18b7F8A4d91A2da9AB4AF05d0FBe
GUARDIAN_SECRET=cfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0

ANVIL_PID=""

function clean_up () {
    ARG=$?
    [ -n "$ANVIL_PID" ] && kill "$ANVIL_PID"
    exit $ARG
}
trap clean_up SIGINT SIGTERM EXIT


#TODO: make RPC an optional argument
USER_ADDRESS=0x42f9d42b0Ad323be203A56618d5053329Cb2fB95
# USER_PK=0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d
# PORT="8545"
# RPC="$HOST:$PORT"

if [[ $run_anvil = true ]]; then
    ./anvil_fork "$chain_name" > $anvil_out &
    ANVIL_PID=$!
    echo "🍴 Forking mainnet..."
    echo "Anvil logs in $anvil_out"
    sleep 5
    ps | grep "$ANVIL_PID"
fi

# ANVIL_RPC=http://localhost:8545

GOV_CONTRACT=""
ACCEPT_ADMIN_VAA=""
TOKEN_CONTRACT="0xB0fFa8000886e57F86dd5264b9582b2Ad87b2b91"
MINTER_AND_BURNER_ADMIN_ROLE=$(cast keccak "MINTER_AND_BURNER_ADMIN")
SET_DELEGATE_ROLE=$(cast keccak "SET_DELEGATE_ROLE")
case "$chain_name" in
    ethereum)
        RPC="https://rpc.ankr.com/eth"
        GOV_CONTRACT=0x23Fea5514DFC9821479fBE18BA1D7e1A61f6FfCf
        ACCEPT_ADMIN_VAA=01000000040d03eeaa775aac556eeed93074732ddc772636eb693a3a3e4d6d6b95ab11f93e19f256312912b4ffa946a6832da4572ea496fd4a34bccdfa7df2689cdb263407b4ee000456ac2cbb395d0d7efcb917aaf43f74fabf7f6e980cd7730aa0dc7eca3fcec325684266c3528c375c9ca5ebad3661ed65d446ed9e700b1356c9ab0ebbf0a23d3e010505c0c824c91b82644232a2d10bacbc66671cf0fc722f8f1c87c46a5174251b7a67def038f011949b9716f01f3def6d29e8e6626fcddc4d90387f701df582a18d01067934e2bb891bd75ff6fb8e082ac3f8d413cea61e85aa3bb7c4e18bdb8bb52114086f8bacc1894fd0611506bc434be3452137b15cdb73acff31415ab5bc64739e010909e21b95c9d4154948efd2e2fa6e69bd78380613be9cd7b21c11bb0bbb5efd542c9716391adbba69c22b9ae087a13571d95d6a0775349c048f4b93bd93c04ef8010adcd90688d0908b387dc1784ebe96bfb6e87f08c8fb2a8cea7ad1098967129bd104dc405624ae2abc80a51c39179f6ee4e7b4267079fff2702eb1623b7728b163000bd91d007fd8b20912a34ddea0b096ee8520cc31b36d483d4248730feebdcfdf7f78d2f1df4cc3e2500ffb1cf2c79ef901eea4c4f622d5ddda34f3e892e6fe6f5f010ded40ec83cd44a59a4bd3ae0f77ea74902aab9f4db8d9d23f79b67d32853aa5634b62d0d348557bddb3050c08f11f4ecad6f902f3f2b434328038a7bfd053e9da000e15d0f58abec3b499a14cb11404e763b9ac11983159a0433cb576b421c56ae7274a138a4b4d496d705e520e3e5426ad1029b1ac5e1d47910f785a33f56128327d010fe7cbede0e14b81d628bb92d6168d1eaa0a61e14e290528a06bcb643ef557eead20c62b885a334af00b57f0a043ec5bad4e27d76573788d3f4eb03d38f776acae01104562101077027a05b8ba700a1699c9df3ae0ac8b9e3a1b535302cd3cddaf32f604ca38d371b7f4997046acc6c20ea70c39b0f7cf974b064044a44b8ddf56aaed0111154d48f78a07eb7c09408121291f8fbdc9a540a9c0da1e7d28dd8284c7f7d43b11d916fdb95d00df9a980b2e85f3109a89e69fad1a457d0419d759c7e4b8496701120d1859e2493ef2690c3a32b7bf6024fa2d15426a1f8653445a9298197d5f927258cceb0eb9cad21967fb9392041b038c80123d171642fd8f2b1966d3dd7f4d690100000000b5f295a500010000000000000000000000000000000000000000000000000000000000000004c71b1582c2e4d62920000000000000000047656e6572616c507572706f7365476f7665726e616e636501000223fea5514dfc9821479fbe18ba1d7e1a61f6ffcfb0ffa8000886e57f86dd5264b9582b2ad87b2b910004cefc1429
        ;;
    arbitrum)
        RPC="https://rpc.ankr.com/arbitrum"
        GOV_CONTRACT=0x36CF4c88FA548c6Ad9fcDc696e1c27Bb3306163F
        ACCEPT_ADMIN_VAA=01000000040d034b96c773dce897724ed8ed4851cfa4f5077c35b7aa397251a3941fc587328a872ce9eac4228c692b2ce2ec9c4a958658fb7e290fdc98eaee1c9c2785c489c2ca010412878b0893d2b98c06490662174c22214417a299ddf6dbd11240fb5781891ff217d023c07cb6d1522d93678269d5dca557d50c2deada2c2126ca5242f96cdcef01051b2a2d7506a6917be3a5fb65b224c77bd7e11c50960d4aed1964ff317afbe7337923f7b656fbf1a88daa2241d73ebdd6e40c6ebad3f9243f93c3c16a9100271f0006e6cbfeadbbed74c30920540c03d35cbece22842371fd87dbc013ae48cf93c4da50bcb57aec8164c2d7ed398a790530a0c76625f440e117b09bb31d9e8f45a77400096ba176d6a0576102261181317d44e28048eaee1ddd76d8a2e4733e47154e524061b1192eedc9c023ceeba3b49f852d9306dada693c211dea0d63545b95139ca9000a5a062b0b5b44ec1f74e1f0548734dae018d70a6c203dc47ca4c7083caa25a81e5420612472b374fbdde1b0401a605f16536d0593faea2d41b82fe5a2895a586d000b929cce6b8a05eb1e57ec34b3728c95c21e9b2915ec61f58e645449fa033815d4158f187ba7080248c3e207debf7492c8096d1a966be4d4de7e6ccbe520b3a983010db8df4588928b1c86ee335666c7034119e2cbea4ae93399a800dca5d7df66d170740ecdacb276ae88f8dab26914bf55eac0043a8917ac21f443508c5a2cf7f5da000e04ab7b872086bf3b333a81fa9630961a1d435d3df12b6c5c4c148c737996d22c2008c11e7f0ec483c4ecd2b55d78f55b40426979230815dce97e552d7917a780000ff8e65d7ce1851a608130cf67f19708d73e655a01e28dee8f6a6a199a27bb93a17ded9c39b018af65ac7f22fcd13de9cb8fba5b60c5fe18f515462a0abc88ec07011070c6a861910be9f680afba830393c7611d0a3ee93b2429a5912157ae9a89428c6bda3dc0d4a31a720e1e290e8d97b133e0b7a3885a658d2d5209ac94789c4f830111aac7526ff88272dadc3d52adf1cc06600a923ae75cfd1359e0922db703b78aea5c10beeec7a85668c3d5a8e4ddc4676eabae5e2a1c86f14da5e22a7d27c1c0bf011231c626e7f23a55a0b1b49296ebac76eee2e7b4e17ddab3d306717ae76ff44fc96f5ac73435e5a63d9e09c84aaabbc07b6fad85b03e7e4013c510af0585ed41e60100000000bf77d51800010000000000000000000000000000000000000000000000000000000000000004d137b2c61b8b0e9c20000000000000000047656e6572616c507572706f7365476f7665726e616e636501001736cf4c88fa548c6ad9fcdc696e1c27bb3306163fb0ffa8000886e57f86dd5264b9582b2ad87b2b910004cefc1429
        ;;
    optimism)
        RPC="https://rpc.ankr.com/optimism"
        GOV_CONTRACT=0x0E09a3081837ff23D2e59B179E0Bc48A349Afbd8
        ACCEPT_ADMIN_VAA=01000000040d03d28251a82cc3ad046b078c60535d6e7597f43943f3cdf8bdbe0eaf46dda6935125f7b3915242f73f7f06628007e1eed0bccd97d8f0cf1a35d03904d895a3167c0004d17f5a9cc5d58eb9cb132d128a0edfae07ca4ae8f4edeeec274381c3b1d74e2b188269726360587bc4ce43479f8f4640226e8b55d46e4bee102b62df20ff815f0105c18d21d285a9951eef9e20c8b51168a94a655cb73b0c7d6546583b5cc6e0129c76b121d416b3d66349cfe643f66feeee2d2dfa1f5a7ed92bb23264a35eb769400006fd20cee22520fd4c3b74a71a250921a3336b45ebfd11a4fe537c635de7fd292b55f98cbfec311caf9b1287acdc417d0a2e047de62b07c1ea6fa679de27b81f530109822234934a66e84894400e65fe33d4e808467b5b25f0aa22537132dfbae9736c38e7d2893851cf1b6788c7b2186f2a5e24ee0d4925397728b486813822b4cc31000aecbeb99f7edc0d0787e15dfd7c12a1e0ec75e90414b69cc76fba97d2217dcacb4597d7206770167e348e620d516972d83852fc83b87c96f83429a779282c2cb3000b7200a05bdb1ac3cfe815703047ca80e1acc4b83d9eaead4afc0cb6a1ef2c415f22fd0acd7a2da448f4a471a1eb77d585ca9ee91fc89a5deb58f79e5dcf2781b0010d38555a865ebcaf3129a79b1d1a0098dd0862773ee07856b21297d171ce5a997e375fe16d8d607977e4311a5592462bc3cd56414d0b4369c6428f18d2eba4f739010e83cab79bdc1171b8511614489a38024ede1358f3f7a46ca881d9b5fa2acf93dd1450a53d198a6563e721bb688537a729bf192c42731068890e410934da0c5f8d010f27d8436366eb17bbd5345f7444c9ba6a9ccfc5e851d0ecaa7ea6d7b4749bd4691e8b81a737573fbd990cdfccba4d12f32bab2b15628a1e53399c4fca9a4b7bdc0010c6ce85b2a6d39c1c5ea479ba31a562e7e8922c446e499340e306d3f510963d89687f8345b0b8f8d394718cb9c75255bc78f05249603c4864a54c941267a6f7b20011a2cc6a0ff60c11879fa1d6ff8afbbf87f1d5305fb237f3ade8050b938f6c1f4109c523f7b41ba5e87182ce4aae86d0be1fa5d9f0771115586997e359dc4fdb2b00127367e99bec7007e12a719d77140faea03831d2c42252396f4957d5e255628be60596a61c449462b66792e51e2f1d67123e3bc605bff2a8f83f0779f94e69e13500000000004079f05300010000000000000000000000000000000000000000000000000000000000000004d7d8ca97c277a64b20000000000000000047656e6572616c507572706f7365476f7665726e616e63650100180e09a3081837ff23d2e59b179e0bc48a349afbd8b0ffa8000886e57f86dd5264b9582b2ad87b2b910004cefc1429
        ;;
    base)
        RPC="https://rpc.ankr.com/base"
        GOV_CONTRACT=0x838a95B6a3E06B6f11C437e22f3C7561a6ec40F1
        ACCEPT_ADMIN_VAA=01000000040d031ab3f03786487a83252fdb1b251245b0fa39b9ced4fc755ba70a6ec78af21e9e6deef754508bebf13c502a8b6c26e0eed82d42a05843d1c5c82ccf75601d4a020104bcf0fedf19a68e2c4d59026a733057efd66428ed60941fac16a7c147d1e5fadf0f9857012c54f16aa160459a29803fd04ffe2558809940512758aea94ff79c9400058267b223f0111d06d8ffd838fc5a5c0b4087ddceb1a5d6b9df97831de684c0961f2215c11768d4aaa9e201836a735285adc6191fbdc12c3ef0d12dbf810d6c4a0006acace3cea0abad185ffc128f09d0e1bba63f798b0bd66268129ad2974587d5b276e3eb3766c85e40cca4075ec6008e2639f9d3b6c0294c38c98ad563addbd9bd01097aac703b53c6c4aa65bfdebdbc5164fe4d419e11e23b3100cbdb7bcc176bb3d60736968e2d1f364235042a7ece072a5d62ecf5d639e44cea6f439198ec759264000a737025bc6ad5d812eb9507f408e7c0f61c46ed83bbfcd9408d57db67d685727936a2609a7b24dddb28c6a2847fd9381f5ca821ab1977054527eb8f190473d5dd010b1f475d0c59c91d8a762596b6ac0f4f5def8c37c8c1a2b59260bac839ccea197923a5745f6bcad0f850e2c02770902aaf6f75c2f108f42fdd08296439f22a1beb000d832f18621f4d1b3d71131b6aa5d1af0681aae4b59731088ca38263ffdde2192f07bb07e1dffe42db07c3ceb48df8c914ca1c08eb08660b9a5ac1bfceff4eadea000e90475805f04fbef4fca2c06dd40a9fabf48d8c3e900fd787097a90d17f277f5040eb991973146bb43cb99b8cc3f5c0091592344a83018c26a7c4fac0f21558bd010f94df5b21bf417f37967cfc812cd1d1aab002e26f9282bb99b98081a8d0d11f5e1f95d250918030093482218acd67dc9b1d0e2b8d952e1b151eaddac9d4db6fcd0110711aceb98e49133d5fb4d4a8edcf9e51a550b331f5abffe279d3c1627bcd8a1f7727f6124a76096612b573c73bddd08f38a2c1becc896a05f39e3c3ae468c6be01116af9ed4590fdb92c4625bd7db9413b33ea8d72a6811dbe76b59cdfc951327bd833d6fc338c7574988e94a5f83d080c0eae91e8b396dccfdc642a95e5e4671bbf01126213e8b501f053b5a18c0ab10ecfdc7162113ae420e1e0d9ec67aa186a14105a4c29df40e161dedfddae990448e2054db9d9ce5723dbfeaed651de1b14f3dabc0100000000aed66b300001000000000000000000000000000000000000000000000000000000000000000432971158f20b77f520000000000000000047656e6572616c507572706f7365476f7665726e616e636501001e838a95b6a3e06b6f11c437e22f3c7561a6ec40f1b0ffa8000886e57f86dd5264b9582b2ad87b2b910004cefc1429
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

# Step 1) Query owner and pauser for the current W token contract (should not be the governance contract)
echo "STEP 1:"
echo "Getting owner and checking admin roles for W token..."
owner=$(cast call "$TOKEN_CONTRACT" "owner()(address)" --rpc-url "$RPC")
minterBurnerAdminRoleUser=$(cast call "$TOKEN_CONTRACT" "hasRole(bytes32,address)(bool)" "$MINTER_AND_BURNER_ADMIN_ROLE" "$USER_ADDRESS" --rpc-url "$RPC")
setDelegateRoleUser=$(cast call "$TOKEN_CONTRACT" "hasRole(bytes32,address)(bool)" "$SET_DELEGATE_ROLE" "$USER_ADDRESS" --rpc-url "$RPC")
if [[ $owner != "$USER_ADDRESS" ]] || [[ $minterBurnerAdminRoleUser != true ]] || [[ $setDelegateRoleUser != true ]]; then
  echo "ERROR! Owner is $owner , minter and burner admin role is $minterBurnerAdminRoleUser , set delegate role is $setDelegateRoleUser which is unexpected! Exiting..."
  clean_up
else
  printf "Verified owner is $owner as expected and has minter and burner admin and set delegate roles as expected\n\n"
fi

# Step 2) Transfer pauser of the W token contract to the Governance contract
echo "STEP 2:"
echo "Transferring pauser to Governance Contract..."
cast send --ledger --mnemonic-derivation-path "m/44'/60'/0'/0/10" "$TOKEN_CONTRACT" "grantRole(bytes32,address)" "$MINTER_AND_BURNER_ADMIN_ROLE" "$GOV_CONTRACT" --rpc-url "$RPC"
sleep 10
cast send --ledger --mnemonic-derivation-path "m/44'/60'/0'/0/10" "$TOKEN_CONTRACT" "renounceRole(bytes32,address)" "$MINTER_AND_BURNER_ADMIN_ROLE" "$USER_ADDRESS" --rpc-url "$RPC"
sleep 10
cast send --ledger --mnemonic-derivation-path "m/44'/60'/0'/0/10" "$TOKEN_CONTRACT" "grantRole(bytes32,address)" "$SET_DELEGATE_ROLE" "$GOV_CONTRACT" --rpc-url "$RPC"
sleep 10
cast send --ledger --mnemonic-derivation-path "m/44'/60'/0'/0/10" "$TOKEN_CONTRACT" "renounceRole(bytes32,address)" "$SET_DELEGATE_ROLE" "$USER_ADDRESS" --rpc-url "$RPC"
sleep 10
cast send --ledger --mnemonic-derivation-path "m/44'/60'/0'/0/10" "$TOKEN_CONTRACT" "beginDefaultAdminTransfer(address)" "$GOV_CONTRACT" --rpc-url "$RPC"
sleep 10
cast send --ledger --mnemonic-derivation-path "m/44'/60'/0'/0/10" "$GOV_CONTRACT" "performGovernance(bytes)" "$ACCEPT_ADMIN_VAA" --rpc-url "$RPC"
printf "Done\n\n"


# # Step 3) Query owner and pauser of the W token contract (should be the governance contract)
echo "STEP 3:"
echo "Getting owner and checking admin roles for W token (should both be granted to "$GOV_CONTRACT")..."
sleep 10
owner=$(cast call "$TOKEN_CONTRACT" "owner()(address)" --rpc-url "$RPC")
minterBurnerAdminRoleUser=$(cast call "$TOKEN_CONTRACT" "hasRole(bytes32,address)(bool)" "$MINTER_AND_BURNER_ADMIN_ROLE" "$USER_ADDRESS" --rpc-url "$RPC")
setDelegateRoleUser=$(cast call "$TOKEN_CONTRACT" "hasRole(bytes32,address)(bool)" "$SET_DELEGATE_ROLE" "$USER_ADDRESS" --rpc-url "$RPC")
minterBurnerAdminRoleGov=$(cast call "$TOKEN_CONTRACT" "hasRole(bytes32,address)(bool)" "$MINTER_AND_BURNER_ADMIN_ROLE" "$GOV_CONTRACT" --rpc-url "$RPC")
setDelegateRoleGov=$(cast call "$TOKEN_CONTRACT" "hasRole(bytes32,address)(bool)" "$SET_DELEGATE_ROLE" "$GOV_CONTRACT" --rpc-url "$RPC")
if [[ $owner != $GOV_CONTRACT ]] || [[ $minterBurnerAdminRoleUser != false ]] || [[ $setDelegateRoleUser != false ]] || [[ $minterBurnerAdminRoleGov != true ]] || [[ $setDelegateRoleGov != true ]]; then
  echo "ERROR! Both owner and admin roles should be granted to governance contract! Exiting..."
  clean_up
else
  printf "Verified owner and admin roles are governance contract $GOV_CONTRACT\n\n"
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

echo "Congratulations! You've verified that the ownership and admin transfer to Governance contract works in a mainnet fork test."

# Anvil can be kept alive by setting the -k flag. This is useful for interacting
# with the contract after it has been upgraded.
if [[ $keepalive_anvil = true ]]; then
    echo "Listening on $RPC"
    # tail -f "$anvil_out"
    wait "$ANVIL_PID"
fi
