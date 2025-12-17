#!/bin/bash

# Output filename
OUTPUT_FILE="docker-compose.yml"

# Start writing header for docker-compose file
echo "version: '3.8'" > $OUTPUT_FILE
echo "services:" >> $OUTPUT_FILE

echo "Scanning node-* directories..."

# Find all directories starting with node-, sort numerically to order node-2 before node-10
for dir in $(find . -maxdepth 1 -type d -name "node-*" | sort -V); do
    # Get directory name (e.g.: node-1)
    folder_name=$(basename "$dir")
    
    # Get node ID from directory name (e.g.: 1 from node-1)
    node_id=$(echo "$folder_name" | grep -oE '[0-9]+')
    
    if [ -z "$node_id" ]; then
        echo "Skipping directory $folder_name - no numeric ID found."
        continue
    fi

    # Calculate ports based on logic:
    # Node 1: 8101, 8102
    # Node 2: 8103, 8104
    # Formula: Base 8100 + (ID-1)*2 + offset
    port_p2p=$((8100 + (node_id - 1) * 2 + 1))
    port_rpc=$((8100 + (node_id - 1) * 2 + 2))

    echo "  - Configuring $folder_name (Port: $port_p2p, $port_rpc)"

    # Write service configuration to docker-compose.yml
    # Use cat <<EOF to maintain proper YAML format
cat <<EOF >> $OUTPUT_FILE
  dc-arx-$folder_name:
    image: arcium/arx-node
    container_name: dc-arx-$folder_name
    restart: unless-stopped
    ports:
      - "$port_p2p:8001"
      - "$port_rpc:8002"
    environment:
      - NODE_IDENTITY_FILE=/usr/arx-node/node-keys/node_identity.pem
      - NODE_KEYPAIR_FILE=/usr/arx-node/node-keys/node_keypair.json
      - CALLBACK_AUTHORITY_KEYPAIR_FILE=/usr/arx-node/node-keys/callback_authority_keypair.json
      - BLS_PRIVATE_KEY_FILE=/usr/arx-node/node-keys/bls_keypair.json
    volumes:
      - ./$folder_name/node-config.toml:/usr/arx-node/arx/node_config.toml
      - ./$folder_name/node-keypair.json:/usr/arx-node/node-keys/node_keypair.json:ro
      - ./$folder_name/callback-kp.json:/usr/arx-node/node-keys/callback_authority_keypair.json:ro
      - ./$folder_name/identity.pem:/usr/arx-node/node-keys/node_identity.pem:ro
      - ./$folder_name/bls-keypair.json:/usr/arx-node/node-keys/bls_keypair.json:ro
      - ./$folder_name/logs:/usr/arx-node/logs

EOF
done

echo "---"
echo "Completed! Successfully created $OUTPUT_FILE."
echo "Run the following command to start: docker-compose up -d"
