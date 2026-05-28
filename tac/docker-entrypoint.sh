#!/usr/bin/env bash
set -euo pipefail

if [ "${FRESH_INIT_WITH_DATA}" = "true" ]; then
  rm -rf /cosmos/.initialized
  SNAPSHOT=""
fi

if [[ ! -f /cosmos/.initialized ]]; then
  echo "Initializing Tac node!"

  echo "Running init..."
  tacchaind init "$MONIKER" --chain-id "$NETWORK" --home /cosmos --overwrite

  echo "Downloading genesis..."
  wget "https://raw.githubusercontent.com/TacBuild/tacchain/refs/heads/main/networks/${NETWORK}/genesis.json" -O /cosmos/config/genesis.json

  if [ -n "$SNAPSHOT" ]; then
    echo "Downloading snapshot..."
    if command -v aria2c &> /dev/null; then
      echo "Using aria2c for faster download (multi-connection)..."
      aria2c -x 16 -s 16 -k 1M --file-allocation=none --allow-overwrite=true -d /tmp -o snapshot.tar.lz4 "$SNAPSHOT" && \
        lz4 -c -d /tmp/snapshot.tar.lz4 | tar --exclude='data/priv_validator_state.json' -x -C /cosmos && \
        rm -f /tmp/snapshot.tar.lz4
    else
      echo "aria2c not found, falling back to curl..."
      curl -o - -L "$SNAPSHOT" | lz4 -c -d - | tar --exclude='data/priv_validator_state.json' -x -C /cosmos
    fi
  else
    echo "No snapshot URL defined. Node will sync from genesis."
  fi

  touch /cosmos/.initialized
else
  echo "Already initialized!"
fi

echo "Updating config..."

# Get public IP address
__public_ip=$(curl -s ifconfig.me/ip || echo "")
if [ -n "$__public_ip" ]; then
  echo "Public IP: ${__public_ip}"
else
  echo "Could not detect public IP, using 0.0.0.0"
  __public_ip="0.0.0.0"
fi

# Always update public IP address, moniker and ports
dasel put -f /cosmos/config/config.toml -v "1s" consensus.timeout_commit
dasel put -f /cosmos/config/config.toml -v "${__public_ip}:${CL_P2P_PORT}" p2p.external_address
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_P2P_PORT}" p2p.laddr
dasel put -f /cosmos/config/config.toml -v "tcp://0.0.0.0:${CL_RPC_PORT}" rpc.laddr
dasel put -f /cosmos/config/config.toml -v "${MONIKER}" moniker
dasel put -f /cosmos/config/config.toml -v true prometheus
dasel put -f /cosmos/config/config.toml -v "${LOG_LEVEL}" log_level

# Set persistent peers
if [ -n "$PERSISTENT_PEERS" ]; then
  echo "Setting persistent peers..."
  dasel put -f /cosmos/config/config.toml -v "$PERSISTENT_PEERS" p2p.persistent_peers
fi

# RPC configuration
dasel put -f /cosmos/config/config.toml -v '["*"]' rpc.cors_allowed_origins
dasel put -f /cosmos/config/config.toml -v '["HEAD","GET","POST"]' rpc.cors_allowed_methods
dasel put -f /cosmos/config/config.toml -v '["Origin","Accept","Content-Type","X-Requested-With","X-Server-Time"]' rpc.cors_allowed_headers

# Configure app.toml for EVM JSON-RPC
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${RPC_PORT}" json-rpc.address
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${WS_PORT}" json-rpc.ws-address
dasel put -f /cosmos/config/app.toml -v true json-rpc.enable
dasel put -f /cosmos/config/app.toml -v "eth,net,web3,txpool,debug" json-rpc.api

# Configure gRPC
dasel put -f /cosmos/config/app.toml -v "0.0.0.0:${CL_GRPC_PORT}" grpc.address
dasel put -f /cosmos/config/app.toml -v true grpc.enable

# Configure REST API
dasel put -f /cosmos/config/app.toml -v "tcp://0.0.0.0:${REST_API_PORT}" api.address
dasel put -f /cosmos/config/app.toml -v true api.enable

# Configure minimum gas prices
dasel put -f /cosmos/config/app.toml -v "25000000000utac" minimum-gas-prices

# Configure pruning
dasel put -f /cosmos/config/app.toml -v "default" pruning

# Configure client
dasel put -f /cosmos/config/client.toml -v "tcp://0.0.0.0:${CL_RPC_PORT}" node

echo "Configuration complete!"
echo "Starting Tac node..."

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${EXTRA_FLAGS}
