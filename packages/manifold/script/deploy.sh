#!/usr/bin/env bash
# Deploy a shared extension (for example a new Lazy Claim version) through the standard CREATE2
# deployer, on any network, and optionally hand its ownership over.
#
#   PRIVATE_KEY=0x... RPC_URL=<rpc> script/deploy.sh <Contract>
#
# <Contract> needs a Foundry script at script/<Contract>.s.sol. That script stays the source of
# truth for the salt and the constructor arguments. This wrapper runs it locally to get the
# deploy bytes, then adds the checks around sending them:
#   - works out the address before anything is sent, and stops if it is not EXPECTED_ADDRESS
#   - if the address already has code (a CREATE2 collision), reports it and deploys nothing
#   - asks before every transaction
#   - checks the code after deploying and the owner after a transfer
# It is safe to run again: steps that are already done are skipped.
#
# Environment
#   RPC_URL            Network to deploy on. Any chain that has the CREATE2 deployer.
#   PRIVATE_KEY        Deployer key. Leave it unset to preview: the script prints the address
#                      and what is on chain, and sends nothing.
#   INITIAL_OWNER      Owner set by the constructor. Default: the PRIVATE_KEY wallet.
#   OPTIMIZER_RUNS     Optimizer runs for the build. Default: foundry.toml.
#   EXPECTED_ADDRESS   Stop unless the contract lands on this address. Set it on every chain
#                      after the first one, so all chains get identical bytes.
#   NEW_OWNER          After deploying, transfer ownership to this address.
#   NEW_OWNER_FROM     Same, but take the address from owner() of this contract on the target
#                      chain. Point it at the previous version to reuse that chain's Safe.
#   COPY_FROM_TX       Skip the build and reuse the exact bytes of an earlier deployment:
#   COPY_FROM_RPC_URL  its deploy transaction hash, and the rpc of the chain it is on.
#   YES=1              Do not ask before sending.
#
# Examples
#   First deploy of a new version, on a testnet:
#     RPC_URL=$SEPOLIA_RPC script/deploy.sh ERC721LazyPayableClaim
#   The same bytes on another chain, handing ownership to the owner of the previous version:
#     RPC_URL=$BASE_RPC COPY_FROM_TX=0x... COPY_FROM_RPC_URL=$SEPOLIA_RPC \
#       EXPECTED_ADDRESS=0x... NEW_OWNER_FROM=0x... script/deploy.sh ERC721LazyPayableClaim
#   Preview or collision test, without a key:
#     RPC_URL=$SEPOLIA_RPC INITIAL_OWNER=0x... script/deploy.sh ERC721LazyPayableClaim
set -euo pipefail

CREATE2=0x4e59b44847b379578588920ca78fbf26c0b4956c
ZERO=0x0000000000000000000000000000000000000000
# Only used to run the Foundry script locally when no PRIVATE_KEY is set. Never sends anything.
PREVIEW_KEY=0x0000000000000000000000000000000000000000000000000000000000000001

usage() { sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
lc() { printf '%s' "$1" | tr 'A-F' 'a-f'; }
die() { echo "STOP: $*" >&2; exit 1; }
same() { [ "$(lc "$1")" = "$(lc "$2")" ]; }
confirm() {
  if [ "${YES:-}" = "1" ]; then return 0; fi
  printf '%s Type yes to send: ' "$1"
  read -r answer || answer=
  [ "$answer" = "yes" ] || die "not confirmed, nothing sent"
}
# send <to> <data or signature> [args...]: sends one transaction, prints its hash
send() {
  local out hash status
  out=$(cast send "$@" --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" --json) || die "the transaction was not sent"
  out=$(printf '%s' "$out" | tr -d ' \n')
  hash=$(printf '%s' "$out" | sed -n 's/.*"transactionHash":"\(0x[0-9a-fA-F]*\)".*/\1/p')
  status=$(printf '%s' "$out" | sed -n 's/.*"status":"\(0x[0-9a-fA-F]*\)".*/\1/p')
  [ "$status" = "0x1" ] || die "transaction $hash failed on chain"
  echo "$hash"
}
code_at() { cast code "$1" --rpc-url "$RPC_URL"; }
owner_of() { cast call "$1" "owner()(address)" --rpc-url "$RPC_URL" 2>/dev/null || true; }

[ $# -eq 1 ] || usage 1
case "$1" in -h | --help) usage 0 ;; esac
CONTRACT=$1
command -v cast >/dev/null || die "cast not found, install Foundry first"
: "${RPC_URL:?set RPC_URL to the rpc of the network to deploy on}"
cd "$(dirname "$0")/.."

CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
[ "$(code_at $CREATE2)" != "0x" ] || die "chain $CHAIN_ID has no CREATE2 deployer at $CREATE2"

SIGNER=
if [ -n "${PRIVATE_KEY:-}" ]; then SIGNER=$(cast wallet address --private-key "$PRIVATE_KEY"); fi

# ---- the deploy bytes: salt followed by the creation code and constructor arguments ----
if [ -n "${COPY_FROM_TX:-}" ]; then
  : "${COPY_FROM_RPC_URL:?set COPY_FROM_RPC_URL to the rpc of the chain COPY_FROM_TX is on}"
  to=$(cast tx "$COPY_FROM_TX" to --rpc-url "$COPY_FROM_RPC_URL")
  same "$to" $CREATE2 || die "$COPY_FROM_TX was sent to $to, not to the CREATE2 deployer"
  DATA=$(cast tx "$COPY_FROM_TX" input --rpc-url "$COPY_FROM_RPC_URL")
  SOURCE="bytes copied from $COPY_FROM_TX"
else
  [ -f "script/$CONTRACT.s.sol" ] || die "no script/$CONTRACT.s.sol for this contract"
  command -v forge >/dev/null || die "forge not found, install Foundry first"
  command -v jq >/dev/null || die "jq not found, install it (or use COPY_FROM_TX, which needs no build)"
  OWNER_FOR_BUILD=${INITIAL_OWNER:-$SIGNER}
  [ -n "$OWNER_FOR_BUILD" ] || die "set INITIAL_OWNER, or PRIVATE_KEY whose wallet is the default initial owner"
  errors=$(mktemp)
  trap 'rm -f "$errors"' EXIT
  echo "building $CONTRACT${OPTIMIZER_RUNS:+ with $OPTIMIZER_RUNS optimizer runs} ..."
  # A local run, with no rpc and no broadcast: it only tells us what the script would send.
  if ! build=$(PRIVATE_KEY=${PRIVATE_KEY:-$PREVIEW_KEY} INITIAL_OWNER=$OWNER_FOR_BUILD \
    forge script "script/$CONTRACT.s.sol" ${OPTIMIZER_RUNS:+--optimizer-runs "$OPTIMIZER_RUNS"} --json 2>"$errors"); then
    tail -n 20 "$errors" >&2
    die "forge script script/$CONTRACT.s.sol failed"
  fi
  DATA=$(printf '%s\n' "$build" | grep '^{' | jq -r --arg deployer $CREATE2 '
    [.. | objects
        | select(has("address") and has("data") and (.address | type) == "string")
        | select((.address | ascii_downcase) == $deployer)
        | .data] | unique | .[]')
  [ "$(printf '%s\n' "$DATA" | grep -c '^0x')" = "1" ] ||
    die "expected script/$CONTRACT.s.sol to make exactly one CREATE2 deployment (new X{salt: ...})"
  SOURCE="built from this checkout, initial owner $OWNER_FOR_BUILD"
fi
[ ${#DATA} -gt 130 ] || die "the deploy bytes are too short to hold a salt and a contract"

SALT=${DATA:2:64}
INIT_HASH=$(cast keccak "0x${DATA:66}")
ADDRESS=$(cast to-check-sum-address "0x$(cast keccak "0xff${CREATE2#0x}${SALT}${INIT_HASH#0x}" | cut -c27-66)")

echo "contract  $CONTRACT ($SOURCE)"
echo "chain id  $CHAIN_ID"
echo "address   $ADDRESS"
if [ -n "${EXPECTED_ADDRESS:-}" ]; then
  same "$ADDRESS" "$EXPECTED_ADDRESS" ||
    die "this would deploy to $ADDRESS, not EXPECTED_ADDRESS $EXPECTED_ADDRESS. Nothing sent. The bytes differ from the expected deployment (optimizer runs, initial owner, salt or source)."
fi
if [ -n "$SIGNER" ]; then echo "signer    $SIGNER, balance $(cast balance "$SIGNER" --ether --rpc-url "$RPC_URL")"; fi

# ---- deploy ----
if [ "$(code_at "$ADDRESS")" != "0x" ]; then
  echo "already deployed: $ADDRESS has code on chain $CHAIN_ID. CREATE2 only gives this address to these exact bytes, so there is nothing to deploy."
elif [ -z "$SIGNER" ]; then
  echo "not deployed on chain $CHAIN_ID yet. Preview only: set PRIVATE_KEY to deploy."
  exit 0
else
  predicted=$(cast call $CREATE2 "$DATA" --from "$SIGNER" --rpc-url "$RPC_URL") || die "the deploy simulation failed"
  same "$predicted" "$ADDRESS" || die "the simulation returned $predicted, expected $ADDRESS"
  confirm "Deploy $CONTRACT on chain $CHAIN_ID to $ADDRESS."
  hash=$(send $CREATE2 "$DATA")
  echo "deployed in $hash"
  tries=0
  until [ "$(code_at "$ADDRESS")" != "0x" ]; do
    tries=$((tries + 1))
    [ $tries -lt 15 ] || die "$hash succeeded but $ADDRESS has no code yet, check the transaction"
    sleep 2
  done
fi
if [ -n "${COPY_FROM_TX:-}" ]; then
  [ "$(code_at "$ADDRESS")" = "$(cast code "$ADDRESS" --rpc-url "$COPY_FROM_RPC_URL")" ] ||
    die "the code at $ADDRESS differs from the chain it was copied from"
  echo "code is identical to the chain it was copied from"
fi

# ---- ownership ----
OWNER=$(owner_of "$ADDRESS")
if [ -z "$OWNER" ]; then
  [ -z "${NEW_OWNER:-}${NEW_OWNER_FROM:-}" ] || die "$ADDRESS has no owner(), cannot transfer ownership"
  echo "done: $CONTRACT is at $ADDRESS on chain $CHAIN_ID"
  exit 0
fi
TARGET=${NEW_OWNER:-}
if [ -n "${NEW_OWNER_FROM:-}" ]; then
  from_owner=$(owner_of "$NEW_OWNER_FROM")
  [ -n "$from_owner" ] || die "could not read owner() of NEW_OWNER_FROM $NEW_OWNER_FROM on chain $CHAIN_ID"
  [ -z "$TARGET" ] || same "$TARGET" "$from_owner" || die "NEW_OWNER $TARGET is not the owner of $NEW_OWNER_FROM ($from_owner)"
  TARGET=$from_owner
fi
if [ -z "$TARGET" ]; then
  echo "done: $CONTRACT is at $ADDRESS on chain $CHAIN_ID, owner $OWNER (no NEW_OWNER given, ownership left as is)"
  exit 0
fi
same "$TARGET" $ZERO && die "the new owner is the zero address"
if [ "$(code_at "$TARGET")" != "0x" ]; then kind="a contract"; else kind="a plain wallet"; fi
if same "$OWNER" "$TARGET"; then
  echo "owner is already $OWNER"
elif [ -z "$SIGNER" ]; then
  echo "owner is $OWNER. Preview only: with PRIVATE_KEY set, ownership would go to $TARGET ($kind)."
  exit 0
else
  same "$OWNER" "$SIGNER" || die "the owner is $OWNER. Only that wallet can transfer ownership, and the signer is $SIGNER."
  confirm "Transfer ownership of $CONTRACT on chain $CHAIN_ID to $TARGET ($kind)."
  hash=$(send "$ADDRESS" "transferOwnership(address)" "$TARGET")
  echo "ownership transferred in $hash"
  OWNER=$(owner_of "$ADDRESS")
  same "$OWNER" "$TARGET" || die "the owner is $OWNER after the transfer, expected $TARGET"
fi
echo "done: $CONTRACT is at $ADDRESS on chain $CHAIN_ID, owner $OWNER"
