#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: check_sync.sh [options]

Options:
  --container NAME         Docker container name or ID to run curl/jq within
  --compose-service NAME   Docker Compose service name to resolve to a container
  --local-rpc URL          Local RPC URL (default: http://127.0.0.1:${CL_RPC_PORT:-26657})
  --public-rpc URL         Public/reference RPC URL (default: https://tendermint.rpc.tac.build)
  --block-lag N            Acceptable lag in blocks (default: 2)
  --sample-secs N          ETA sampling window in seconds (default: 10)
  --no-install             Do not install curl/jq inside the container
  --env-file PATH          Path to env file to load
  -h, --help               Show this help

Examples:
  ./check_sync.sh --public-rpc https://tendermint.rpc.tac.build
  ./check_sync.sh --compose-service tac --public-rpc https://tendermint.rpc.tac.build
  CONTAINER=tac-1 PUBLIC_RPC=https://tendermint.rpc.tac.build ./check_sync.sh
EOF
}

ENV_FILE="${ENV_FILE:-}"
CONTAINER="${CONTAINER:-}"
DOCKER_SERVICE="${DOCKER_SERVICE:-}"
LOCAL_RPC="${LOCAL_RPC:-}"
PUBLIC_RPC="${PUBLIC_RPC:-}"
BLOCK_LAG_THRESHOLD="${BLOCK_LAG_THRESHOLD:-2}"
SAMPLE_SECS="${SAMPLE_SECS:-10}"
INSTALL_TOOLS="${INSTALL_TOOLS:-1}"

load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line#export }"
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      local key="${line%%=*}"
      local val="${line#*=}"
      val="${val#"${val%%[![:space:]]*}"}"
      if [[ "$val" =~ ^\".*\"$ ]]; then
        val="${val:1:-1}"
      elif [[ "$val" =~ ^\'.*\'$ ]]; then
        val="${val:1:-1}"
      fi
      printf -v "$key" '%s' "$val"
      export "${key?}"
    fi
  done < "$file"
}

args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "--env-file" ]]; then
    ENV_FILE="${args[$((i+1))]:-}"
  fi
done

if [[ -n "${ENV_FILE:-}" ]]; then
  load_env_file "$ENV_FILE"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container) CONTAINER="$2"; shift 2 ;;
    --compose-service) DOCKER_SERVICE="$2"; shift 2 ;;
    --local-rpc) LOCAL_RPC="$2"; shift 2 ;;
    --public-rpc) PUBLIC_RPC="$2"; shift 2 ;;
    --block-lag) BLOCK_LAG_THRESHOLD="$2"; shift 2 ;;
    --sample-secs) SAMPLE_SECS="$2"; shift 2 ;;
    --no-install) INSTALL_TOOLS="0"; shift ;;
    --env-file) ENV_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 2 ;;
  esac
done

LOCAL_RPC="${LOCAL_RPC:-http://127.0.0.1:${CL_RPC_PORT:-26657}}"
PUBLIC_RPC="${PUBLIC_RPC:-https://tendermint.rpc.tac.build}"

resolve_container() {
  if [[ -n "$CONTAINER" || -z "$DOCKER_SERVICE" ]]; then
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "❌ docker not found; cannot resolve --compose-service $DOCKER_SERVICE"
    exit 2
  fi
  if docker compose version >/dev/null 2>&1; then
    CONTAINER="$(docker compose ps -q "$DOCKER_SERVICE" | head -n 1)"
  elif command -v docker-compose >/dev/null 2>&1; then
    CONTAINER="$(docker-compose ps -q "$DOCKER_SERVICE" | head -n 1)"
  else
    echo "❌ docker compose not available; cannot resolve --compose-service $DOCKER_SERVICE"
    exit 2
  fi
}

rpc_get() {
  # args: rpc_url_path
  local rpc="$1"
  if [[ -n "$CONTAINER" ]]; then
    docker exec "$CONTAINER" sh -c "curl -sS '$rpc'"
  else
    curl -sS "$rpc"
  fi
}

jq_eval() {
  if [[ -n "$CONTAINER" ]]; then
    docker exec -i "$CONTAINER" jq -r "$1"
  else
    jq -r "$1"
  fi
}

resolve_container

if [[ -z "$PUBLIC_RPC" ]]; then
  echo "❌ PUBLIC_RPC is required. Use --public-rpc or set PUBLIC_RPC."
  exit 2
fi

if [[ -n "$CONTAINER" ]]; then
  if [[ "$INSTALL_TOOLS" == "1" ]]; then
    echo "==> Ensuring curl and jq are installed inside container"

    docker exec -u root "$CONTAINER" sh -c '
    set -e
    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      exit 0
    fi

    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y
      apt-get install -y curl jq ca-certificates
    elif command -v apk >/dev/null 2>&1; then
      apk add --no-cache curl jq ca-certificates
    else
      echo "Unsupported base image. No apt-get or apk found."
      exit 1
    fi
    '
  fi
else
  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "❌ curl and jq are required on the host when no --container is set."
    exit 2
  fi
fi

echo "==> Checking local tacchaind sync status"

local_status="$(rpc_get "${LOCAL_RPC}/status")"
local_catching_up="$(echo "$local_status" | jq_eval '.result.sync_info.catching_up // .sync_info.catching_up')"
local_height="$(echo "$local_status" | jq_eval '.result.sync_info.latest_block_height // .sync_info.latest_block_height')"

if [[ -z "$local_height" || "$local_height" == "null" ]]; then
  echo "❌ Could not parse local status response. Raw response:"
  echo "$local_status"
  exit 5
fi

if [[ "$local_catching_up" == "true" ]]; then
  echo "catching_up: true (actively syncing)"
else
  echo "catching_up: false (not actively syncing)"
fi

echo
echo "==> Querying local and public heights and estimating ETA"

public_status="$(rpc_get "${PUBLIC_RPC}/status")"
public_height="$(echo "$public_status" | jq_eval '.result.sync_info.latest_block_height // .sync_info.latest_block_height')"

if [[ "$public_height" == "null" || -z "$public_height" ]]; then
  echo "❌ Public RPC returned no height. Raw response:"
  echo "$public_status"
  exit 7
fi

remaining="$((public_height - local_height))"

echo "Local  head:    $local_height"
echo "Public head:    $public_height"
echo "Remaining:      $remaining blocks"

echo "==> Sampling local head rate for ~${SAMPLE_SECS}s"
sleep "$SAMPLE_SECS"

local_status_2="$(rpc_get "${LOCAL_RPC}/status")"
local_height_2="$(echo "$local_status_2" | jq_eval '.result.sync_info.latest_block_height // .sync_info.latest_block_height')"

delta="$((local_height_2 - local_height))"
echo "Advanced:       $delta blocks in ${SAMPLE_SECS}s"

if (( delta <= 0 )); then
  echo "ETA:            unknown (local head not advancing yet)"
else
  bps="$((delta / SAMPLE_SECS))"
  if (( bps <= 0 )); then
    echo "ETA:            unknown (rate < 1 block/sec over sample window)"
  else
    eta_secs="$((remaining / bps))"
    eta_mins="$((eta_secs / 60))"
    echo "Rate:           ~${bps} blocks/sec"
    echo "ETA to head:    ~${eta_mins} minutes (very rough)"
  fi
fi

echo
echo "==> Querying local and public latest blocks (height + hash)"

local_height_final="$(echo "$local_status_2" | jq_eval '.result.sync_info.latest_block_height // .sync_info.latest_block_height')"
local_hash="$(echo "$local_status_2" | jq_eval '.result.sync_info.latest_block_hash // .sync_info.latest_block_hash')"

public_status_final="$(rpc_get "${PUBLIC_RPC}/status")"
public_height_final="$(echo "$public_status_final" | jq_eval '.result.sync_info.latest_block_height // .sync_info.latest_block_height')"
public_hash="$(echo "$public_status_final" | jq_eval '.result.sync_info.latest_block_hash // .sync_info.latest_block_hash')"

if [[ "$local_height_final" == "null" || "$local_hash" == "null" || -z "$local_height_final" || -z "$local_hash" ]]; then
  echo "❌ Local RPC returned no block data (height/hash null). Raw response:"
  echo "$local_status_2"
  exit 3
fi

if [[ "$public_height_final" == "null" || "$public_hash" == "null" || -z "$public_height_final" || -z "$public_hash" ]]; then
  echo "❌ Public RPC returned no block data (height/hash null). Raw response:"
  echo "$public_status_final"
  exit 4
fi

lag="$((public_height_final - local_height_final))"

echo
echo "Local   block: $local_height_final  $local_hash"
echo "Public  block: $public_height_final $public_hash"
echo "Lag:          $lag blocks (threshold: $BLOCK_LAG_THRESHOLD)"
echo

if [[ "$local_height_final" == "$public_height_final" && "$local_hash" == "$public_hash" ]]; then
  echo "✅ Node is in sync (height and hash match)"
  exit 0
fi

if (( lag > BLOCK_LAG_THRESHOLD )); then
  echo "⚠️  Heights differ beyond threshold. Still syncing."
  exit 1
fi

if [[ "$local_height_final" == "$public_height_final" && "$local_hash" != "$public_hash" ]]; then
  echo "❌ Heights match but hashes differ. Possible reorg or divergence."
  exit 2
fi

echo "⚠️  Heights differ but within threshold. Likely normal propagation lag."
exit 0
