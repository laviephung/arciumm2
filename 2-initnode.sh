#!/bin/bash
# ============================================
# ARCIUM CLUSTER OPERATION SCRIPT
# Create cluster and join nodes in pairs
# Usage: ./2_operate_cluster.sh
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

RPC_URL="https://api.devnet.solana.com"
WALLET_BACKUP="wallets-backup.txt"

# Check if offset exists on chain
check_offset_exists() {
    local offset=$1
    if arcium arx-info $offset --rpc-url $RPC_URL 2>&1 | grep -q "Error"; then
        return 1  # Offset does not exist
    else
        return 0  # Offset already exists
    fi
}

# Get offset from node folder
get_node_offset() {
    local node_dir=$1
    if [ -f "$node_dir/node-config.toml" ]; then
        grep "^offset = " "$node_dir/node-config.toml" | awk '{print $3}'
    fi
}

# Init accounts for node
init_arx_accs() {
    local node_dir=$1
    local offset=$2
    local ip_address=$3
    
    echo -e "${CYAN}→${NC} Init accounts for $node_dir (Offset: $offset)..."
    
    cd $node_dir
    arcium init-arx-accs \
        --keypair-path node-keypair.json \
        --callback-keypair-path callback-kp.json \
        --peer-keypair-path identity.pem \
        --bls-keypair-path bls-keypair.json \
        --x25519-keypair-path x25519-keypair.json \
        --node-offset $offset \
        --ip-address $ip_address \
        --rpc-url $RPC_URL > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Init accounts successful"
    else
        echo -e "${RED}✗${NC} Init accounts failed"
        cd ..
        return 1
    fi
    
    cd ..
    return 0
}

# Create cluster
init_cluster() {
    local node_dir=$1
    local offset=$2
    local max_nodes=$3
    
    echo -e "${CYAN}→${NC} Creating cluster with node-offset: $offset, max-nodes: $max_nodes..."
    
    cd $node_dir
    arcium init-cluster \
        --keypair-path node-keypair.json \
        --offset $offset \
        --max-nodes $max_nodes \
        --rpc-url $RPC_URL > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Cluster created successfully"
    else
        echo -e "${RED}✗${NC} Cluster creation failed"
        cd ..
        return 1
    fi
    
    cd ..
    return 0
}

# Propose node join cluster
propose_join_cluster() {
    local node_dir=$1
    local cluster_offset=$2
    local node_offset=$3
    
    echo -e "${CYAN}→${NC} Proposing node (Offset: $node_offset) to join cluster..."
    
    cd $node_dir
    arcium propose-join-cluster \
        --keypair-path node-keypair.json \
        --cluster-offset $cluster_offset \
        --node-offset $node_offset \
        --rpc-url $RPC_URL > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Proposal successful"
    else
        echo -e "${RED}✗${NC} Proposal failed"
        cd ..
        return 1
    fi
    
    cd ..
    return 0
}

# Join cluster (without proposal)
join_cluster() {
    local node_dir=$1
    local node_offset=$2
    local cluster_offset=$3
    
    echo -e "${CYAN}→${NC} Node $node_dir (Offset: $node_offset) joining cluster (Offset: $cluster_offset)..."
    
    cd $node_dir
    
    echo -e "${CYAN}  →${NC} Joining cluster..."
    arcium join-cluster true \
        --keypair-path node-keypair.json \
        --node-offset $node_offset \
        --cluster-offset $cluster_offset \
        --rpc-url $RPC_URL > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}  ✗${NC} Failed to join cluster"
        cd ..
        return 1
    fi
    echo -e "${GREEN}  ✓${NC} Cluster join successful"
    
    cd ..
    return 0
}

# Submit aggregated BLS key
submit_aggregated_bls_key() {
    local node_dir=$1
    local cluster_offset=$2
    local node_offset=$3
    
    echo -e "${CYAN}→${NC} Submitting aggregated BLS key from $node_dir..."
    
    cd $node_dir
    arcium submit-aggregated-bls-key \
        --keypair-path node-keypair.json \
        --cluster-offset $cluster_offset \
        --node-offset $node_offset \
        --rpc-url $RPC_URL > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} BLS key submission successful"
    else
        echo -e "${RED}✗${NC} BLS key submission failed"
        cd ..
        return 1
    fi
    
    cd ..
    return 0
}

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${GREEN}   ARCIUM CLUSTER OPERATION SCRIPT   ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

# Get VPS IP
IP_ADDRESS=$(grep "^IP VPS:" $WALLET_BACKUP | head -1 | awk '{print $NF}')
if [ -z "$IP_ADDRESS" ]; then
    echo -e "${RED}✗ IP VPS not found in $WALLET_BACKUP${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} IP VPS: ${GREEN}$IP_ADDRESS${NC}\n"

# Parse backup file to get node list
NODE_OFFSETS=()
declare -A NODE_INDEX_MAP

NODE_COUNT=0
while IFS= read -r line; do
    if [[ $line =~ ^NODE\ ([0-9]+)\ \(Offset:\ ([0-9]+)\) ]]; then
        NODE_NUM="${BASH_REMATCH[1]}"
        OFFSET="${BASH_REMATCH[2]}"
        NODE_OFFSETS+=("$OFFSET")
        NODE_INDEX_MAP["$OFFSET"]=$NODE_NUM
        NODE_COUNT=$((NODE_COUNT + 1))
    fi
done < "$WALLET_BACKUP"

if [ ${#NODE_OFFSETS[@]} -eq 0 ]; then
    echo -e "${RED}✗ No nodes found in $WALLET_BACKUP${NC}"
    exit 1
fi

echo -e "${YELLOW}Found ${#NODE_OFFSETS[@]} nodes:${NC}"
for i in "${!NODE_OFFSETS[@]}"; do
    echo -e "   Node $((i+1)): Offset ${NODE_OFFSETS[$i]}"
done
echo ""

# Process each cluster of 2 nodes
CLUSTER_NUM=1
for ((i=0; i<${#NODE_OFFSETS[@]}; i+=2)); do
    NODE_1_OFFSET="${NODE_OFFSETS[$i]}"
    NODE_2_OFFSET="${NODE_OFFSETS[$((i+1))]}"
    
    NODE_1_DIR="node-${NODE_INDEX_MAP[$NODE_1_OFFSET]}"
    NODE_2_DIR="node-${NODE_INDEX_MAP[$NODE_2_OFFSET]}"
    
    echo -e "${BLUE}=== CLUSTER $CLUSTER_NUM ===${NC}"
    echo -e "${BLUE}Node-1:${NC} $NODE_1_DIR (Offset: $NODE_1_OFFSET)"
    echo -e "${BLUE}Node-2:${NC} $NODE_2_DIR (Offset: $NODE_2_OFFSET)\n"
    
    # Check if cluster already exists
    echo -e "${CYAN}→${NC} Checking if cluster $NODE_1_OFFSET already exists..."
    if check_offset_exists "$NODE_1_OFFSET"; then
        echo -e "${YELLOW}WARNING:${NC} Cluster $NODE_1_OFFSET already exists, skipping...\n"
        CLUSTER_NUM=$((CLUSTER_NUM + 1))
        continue
    fi
    echo -e "${GREEN}✓${NC} Cluster does not exist, proceeding...\n"
    
    # ===== STEP 1: Init accounts for both nodes =====
    echo -e "${YELLOW}[1/6]${NC} Initializing accounts for both nodes...\n"
    
    if ! init_arx_accs "$NODE_1_DIR" "$NODE_1_OFFSET" "$IP_ADDRESS"; then
        echo -e "${RED}✗ Failed to init node 1, skipping cluster${NC}\n"
        CLUSTER_NUM=$((CLUSTER_NUM + 1))
        continue
    fi
    echo ""
    
    if ! init_arx_accs "$NODE_2_DIR" "$NODE_2_OFFSET" "$IP_ADDRESS"; then
        echo -e "${RED}✗ Failed to init node 2, skipping cluster${NC}\n"
        CLUSTER_NUM=$((CLUSTER_NUM + 1))
        continue
    fi
    echo ""
    
    # ===== STEP 2: Node-1 create cluster =====
    echo -e "${YELLOW}[2/6]${NC} Node-1 creating cluster...\n"
    if ! init_cluster "$NODE_1_DIR" "$NODE_1_OFFSET" 2; then
        echo -e "${RED}✗ Failed to create cluster, skipping${NC}\n"
        CLUSTER_NUM=$((CLUSTER_NUM + 1))
        continue
    fi
    echo ""
    
    # ===== STEP 3: Node-1 join cluster =====
    echo -e "${YELLOW}[3/6]${NC} Node-1 joining cluster...\n"
    if ! propose_join_cluster "$NODE_1_DIR" "$NODE_1_OFFSET" "$NODE_1_OFFSET"; then
        echo -e "${RED}✗ Node-1 proposal to join failed, skipping${NC}\n"
        CLUSTER_NUM=$((CLUSTER_NUM + 1))
        continue
    fi
    if ! join_cluster "$NODE_1_DIR" "$NODE_1_OFFSET" "$NODE_1_OFFSET"; then
        echo -e "${RED}✗ Node-1 failed to join cluster, skipping${NC}\n"
        CLUSTER_NUM=$((CLUSTER_NUM + 1))
        continue
    fi
    echo ""
    
    # ===== STEP 4: Node-1 propose Node-2 join =====
    echo -e "${YELLOW}[4/6]${NC} Node-1 proposing Node-2 to join cluster...\n"
    if ! propose_join_cluster "$NODE_1_DIR" "$NODE_1_OFFSET" "$NODE_2_OFFSET"; then
        echo -e "${RED}✗ Failed to propose Node-2 to join, skipping${NC}\n"
        CLUSTER_NUM=$((CLUSTER_NUM + 1))
        continue
    fi
    echo ""
    
    # ===== STEP 5: Node-2 join cluster =====
    echo -e "${YELLOW}[5/6]${NC} Node-2 joining cluster...\n"
    if ! join_cluster "$NODE_2_DIR" "$NODE_2_OFFSET" "$NODE_1_OFFSET"; then
        echo -e "${RED}✗ Node-2 failed to join cluster, skipping${NC}\n"
        CLUSTER_NUM=$((CLUSTER_NUM + 1))
        continue
    fi
    echo ""
    
    # ===== STEP 6: Node-1 submit BLS key =====
    echo -e "${YELLOW}[6/6]${NC} Node-1 submitting BLS key...\n"
    if ! submit_aggregated_bls_key "$NODE_1_DIR" "$NODE_1_OFFSET" "$NODE_1_OFFSET"; then
        echo -e "${RED}✗ Failed to submit BLS key${NC}\n"
    fi
    echo ""
    
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  CLUSTER $CLUSTER_NUM COMPLETED!        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"
    
    CLUSTER_NUM=$((CLUSTER_NUM + 1))
done

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      ALL CLUSTERS COMPLETED!            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"

echo -e "${CYAN}=== NEXT STEPS ===${NC}"
echo -e "${BLUE}1.${NC} Run docker-compose:"
echo -e "   ${GREEN}docker-compose up -d${NC}"
echo -e "${BLUE}2.${NC} View logs:"
echo -e "   ${GREEN}./view-logs.sh${NC}\n"
