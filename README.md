# tac-docker

Docker compose for Tac RPC node.

Meant to be used with [central-proxy-docker](https://github.com/CryptoManufaktur-io/central-proxy-docker) for traefik
and Prometheus remote write; use `:ext-network.yml` in `COMPOSE_FILE` inside `.env` in that case.

## Overview

This project provides a production-ready Docker setup for running a Tac RPC node. It supports:
- Full node and archive node configurations
- Snapshot-based fast sync
- EVM JSON-RPC and WebSocket endpoints
- Prometheus metrics
- Traefik integration for HTTPS
- CCIP 1.6 deployment compatibility

## Network Information

- **Chain ID**: `tacchain_239-1`
- **Network**: Tac Mainnet
- **RPC Endpoints**: HTTP (45138), WebSocket (45139)
- **P2P Port**: 58960

### Persistent Peers

The following persistent peers are configured by default:
```
d0a80c43a10a6b60475864728db6d9ba4ead42d2@107.6.113.60:58960
10550a03e4f7fa487c78fbd07e0770e2b0f085c7@64.46.115.78:58960
0efae9d157f0ef60ad7d25507d6939799f832e34@173.244.202.99:58960
78079166d06e345dbf4a5c932ee3c69a04148e92@107.6.91.38:58960
```

## Quick Setup

1. **Clone and configure**:
```bash
cp default.env .env
nano .env
```

Update values like `MONIKER`, `NETWORK`, and optionally `SNAPSHOT` for faster sync.

2. **Expose RPC ports locally** (optional):

If you want the RPC ports exposed locally, add `rpc-shared.yml` to `COMPOSE_FILE` inside `.env`:
```bash
COMPOSE_FILE=tac.yml:rpc-shared.yml
```

3. **Start the node**:
```bash
./tacd up
```

## Syncing Options

### Option 1: Sync from Genesis (Slow - ~3-5 days)

Start without a snapshot. The node will sync from block 0:
```bash
# Leave SNAPSHOT empty in .env
./tacd up
```

### Option 2: Fast Sync with Snapshot (Recommended)

Download and use a snapshot for much faster initial sync:

**Full Node Snapshot**:
```bash
# In .env:
SNAPSHOT=http://snapshot.tac.ankr.com/tac-mainnet-full-latest.tar.lz4
```

**Archive Node Snapshot** (if you need full historical data):
```bash
# In .env:
SNAPSHOT=http://snapshot.tac.ankr.com/tac-mainnet-archive-latest.tar.lz4
```

The snapshot will be automatically downloaded, verified, and extracted on first startup.

## Commands

The `tacd` script provides a convenient CLI for managing your node:

### Basic Operations
- `./tacd up` - Start the Tac node
- `./tacd down` - Stop the Tac node
- `./tacd restart` - Restart the Tac node
- `./tacd logs` - View and follow logs

### Maintenance
- `./tacd update` - Rebuild Docker image (e.g., after changing `TACCHAIND_TAG`)
- `./tacd check-sync` - Check if node is synced with the network
- `./tacd ps` - Show service status

### Advanced
- `./tacd cli <command>` - Run tacchaind CLI commands (e.g., `./tacd cli status`)
- `./tacd exec-node <command>` - Execute command in running container
- `./tacd version` - Show version information

## Upgrading tacd Binary

To upgrade to a new tacchaind version:

1. Update `TACCHAIND_TAG` in `.env` to the desired version tag (e.g., `v1.0.4`)
2. Rebuild the Docker image:
```bash
./tacd update
```

**Note**: Minimum version for mainnet is `v1.0.1`. Latest stable release is `v1.0.4`.

3. Restart the node:
```bash
./tacd restart
```

The tacchaind binary is compiled from source during `docker compose build` in a multi-stage Dockerfile.

## Testing the RPC Endpoint

After the node is synced, test the JSON-RPC endpoint:

```bash
# Get current block number
curl -L http://localhost:45138 -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0","method": "eth_blockNumber","params": [],"id": 1}'

# Get chain ID
curl -L http://localhost:45138 -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0","method": "eth_chainId","params": [],"id": 1}'
```

Expected response format:
```json
{"jsonrpc":"2.0","id":1,"result":"0x..."}
```

## Check Sync Status

Compare your local node height with the network:

```bash
./tacd check-sync
```

The script will sample the sync rate over ~10 seconds and provide an ETA estimate.

Exit codes:
- `0` - Node is synced (height and hash match)
- `1` - Node is syncing (behind public RPC)
- `2` - Node is diverged (hash mismatch, possible fork)
- `3` - Local RPC error
- `4` - Public RPC error
- `5` - Parse error
- `7` - Docker/container error

## Port Configuration

Default ports (configurable in `.env`):

| Service | Port | Description |
|---------|------|-------------|
| JSON-RPC | 45138 | HTTP JSON-RPC endpoint |
| WebSocket | 45139 | WebSocket endpoint |
| P2P | 58960 | Peer-to-peer networking |
| CL RPC | 26657 | Cosmos SDK RPC |
| gRPC | 9090 | gRPC endpoint |
| REST API | 1317 | Cosmos SDK REST API |
| Prometheus | 26660 | Metrics endpoint |

## Data Storage

Node data is stored in a Docker volume named `consensus-data`. To inspect or backup:

```bash
# List volumes
docker volume ls | grep tac

# Inspect volume
docker volume inspect tac-docker_consensus-data

# Backup volume (with node stopped)
./tacd down
docker run --rm -v tac-docker_consensus-data:/data -v $(pwd):/backup \
  ubuntu tar czf /backup/tac-backup.tar.gz /data
```

## Using with CCIP 1.6

This RPC node is designed for use with Chainlink CCIP 1.6 deployments on Tac.

Configure your Chainlink node to use:
- **HTTP RPC**: `http://localhost:45138`
- **WebSocket**: `ws://localhost:45139`
- **Chain ID**: `239` (decimal) or `0xEF` (hex)

## Monitoring

Prometheus metrics are exposed on port 26660. Add to your Prometheus config:

```yaml
scrape_configs:
  - job_name: 'tac-node'
    static_configs:
      - targets: ['localhost:26660']
```

## Troubleshooting

### Node not syncing
```bash
# Check logs
./tacd logs

# Verify peers
./tacd exec-node tacchaind status 2>&1 | jq .
```

### Out of disk space
Tac blockchain data can be large. Ensure you have:
- Full node: ~500GB+ available
- Archive node: ~1TB+ available

### Reset and resync
```bash
./tacd down
docker volume rm tac-docker_consensus-data
# Update SNAPSHOT in .env if desired
./tacd up
```

## Hardware Requirements

**Minimum**:
- 8 CPU cores
- 32 GB RAM
- 1 TB SSD storage
- 100 Mbps network

**Recommended**:
- 16+ CPU cores
- 64 GB RAM
- 2 TB NVMe SSD storage
- 1 Gbps network

## References

- [Tac Network Documentation](https://github.com/TacBuild/tacchain/blob/main/NETWORKS.md)
- [Tac GitHub](https://github.com/TacBuild/tacchain)
- [Tac Snapshots](http://snapshot.tac.ankr.com/)

## Version

This is tac-docker v1.0.0