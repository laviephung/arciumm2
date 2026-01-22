#!/bin/bash

OUTPUT_FILE="docker-compose.yml"

echo "version: '3.8'" > $OUTPUT_FILE
echo "services:" >> $OUTPUT_FILE

echo "Scanning node-* directories..."

for dir in $(find . -maxdepth 1 -type d -name "node-*" | sort -V); do
    folder_name=$(basename "$dir")
    node_id=$(echo "$folder_name" | grep -oE '[0-9]+')

    if [ -z "$node_id" ]; then
        echo "Skipping $folder_name (no numeric ID)"
        continue
    fi

    # ===== PORT LOGIC =====
    # p2p / rpc
    port_p2p=$((8100 + (node_id - 1) * 2 + 1))
    port_rpc=$((8100 + (node_id - 1) * 2 + 2))

    # additional service ports
    port_8012=$((8200 + node_id))
    port_8013=$((8300 + node_id))

    # metrics
    port_metrics=$((9000 + node_id))

    echo "Configuring $folder_name → $port_p2p / $port_rpc / metrics:$port_metrics"

cat <<EOF >> $OUTPUT_FILE
  dc-arx-$folder_name:
    image: arcium/arx-node
    container_name: dc-arx-$folder_name
    restart: unless-stopped

    environment:
      - NODE_IDENTITY_FILE=/usr/arx-node/node-keys/node_identity.pem
      - NODE_KEYPAIR_FILE=/usr/arx-node/node-keys/node_keypair.json
      - CALLBACK_AUTHORITY_KEYPAIR_FILE=/usr/arx-node/node-keys/callback_authority_keypair.json
      - BLS_PRIVATE_KEY_FILE=/usr/arx-node/node-keys/bls_keypair.json
      - X25519_PRIVATE_KEY_FILE=/usr/arx-node/node-keys/x25519_keypair.json
      - ARX_METRICS_HOST=0.0.0.0
      - ARX_METRICS_PORT=9091

    ports:
      - "$port_p2p:8001"
      - "$port_rpc:8002"
      - "$port_8012:8012"
      - "$port_8013:8013"
      - "$port_metrics:9091"

    volumes:
      - ./$folder_name/node-config.toml:/usr/arx-node/arx/node_config.toml
      - ./$folder_name/node-keypair.json:/usr/arx-node/node-keys/node_keypair.json:ro
      - ./$folder_name/callback-kp.json:/usr/arx-node/node-keys/callback_authority_keypair.json:ro
      - ./$folder_name/identity.pem:/usr/arx-node/node-keys/node_identity.pem:ro
      - ./$folder_name/bls-keypair.json:/usr/arx-node/node-keys/bls_keypair.json:ro
      - ./$folder_name/x25519-keypair.json:/usr/arx-node/node-keys/x25519_keypair.json:ro
      - ./$folder_name/logs:/usr/arx-node/logs
      - ./$folder_name/private-shares:/usr/arx-node/private-shares
      - ./$folder_name/public-inputs:/usr/arx-node/public-inputs

EOF
done

echo "----------------------------------"
echo "docker-compose.yml generated OK"
echo "Run: docker compose up -d"
