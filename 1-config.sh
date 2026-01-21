#!/bin/bash
# ============================================
# ARCIUM MULTI-NODE SETUP SCRIPT
# Create keypairs and config for multiple nodes
# Usage: ./1_config-nodes.sh <num_nodes>
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

NUM_NODES=${1:-5}
RPC_URL="https://api.devnet.solana.com"
OFFSET_FILE="offsets-used.txt"

# Generate random unique offset
generate_unique_offset() {
    local offset
    local max_attempts=100
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        offset=$((RANDOM % 90000 + 10000))$((RANDOM % 90000 + 10000))
        
        if [ -f "$OFFSET_FILE" ] && grep -q "^$offset$" "$OFFSET_FILE"; then
            attempt=$((attempt + 1))
            continue
        fi
        
        echo -e "    ${CYAN}→${NC} Checking offset $offset on chain..." >&2
        
        if arcium arx-info $offset --rpc-url $RPC_URL 2>&1 | grep -q "Error"; then
            echo "$offset" >> "$OFFSET_FILE"
            echo "$offset"
            return 0
        else
            echo -e "    ${YELLOW}→${NC} Offset $offset already used, retrying..." >&2
            attempt=$((attempt + 1))
        fi
    done
    
    echo -e "${RED}✗ Cannot generate offset after $max_attempts attempts!${NC}" >&2
    exit 1
}

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${GREEN}   ARCIUM MULTI-NODE SETUP SCRIPT   ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}Num nodes: $NUM_NODES${NC}\n"

# Get IP
echo -e "${BLUE}[1/5]${NC} Getting IP address..."
IP_ADDRESS=$(curl -4 -s https://api.ipify.org)
echo -e "${GREEN}✓${NC} IP: ${GREEN}$IP_ADDRESS${NC}\n"

touch $OFFSET_FILE

EXISTING_NODES=0
for dir in node-*/; do
    [ -d "$dir" ] && EXISTING_NODES=$((EXISTING_NODES + 1))
done

# Create backup file
echo -e "${BLUE}[2/5]${NC} Creating backup file..."
WALLET_BACKUP="wallets-backup.txt"

if [ $EXISTING_NODES -gt 0 ]; then
    echo -e "${YELLOW}Detected $EXISTING_NODES existing nodes${NC}"
    echo -e "${YELLOW}Will create $((NUM_NODES - EXISTING_NODES)) new nodes${NC}\n"
    START_INDEX=$((EXISTING_NODES + 1))
    # If old nodes exist, append to existing backup file
    echo "" >> $WALLET_BACKUP
    echo "=== $(date) ===" >> $WALLET_BACKUP
    echo "" >> $WALLET_BACKUP
else
    START_INDEX=1
    # If first time, create new backup file
    cat > $WALLET_BACKUP << EOF
╔════════════════════════════════════════╗
║     ARCIUM NODES WALLET BACKUP         ║
╚════════════════════════════════════════╝
IP VPS: $IP_ADDRESS
Date: $(date)
Total Nodes: $NUM_NODES

EOF
fi

# Create nodes
echo -e "${BLUE}[3/5]${NC} Creating nodes...\n"

for i in $(seq $START_INDEX $NUM_NODES); do
    NODE_DIR="node-$i"
    
    if [ -d "$NODE_DIR" ]; then
        echo -e "${YELLOW}Node $i already exists, skipping...${NC}\n"
        continue
    fi
    
    echo -e "${CYAN}╔══ NODE $i ══╗${NC}"
    
    NODE_OFFSET=$(generate_unique_offset)
    echo -e "${GREEN}✓${NC} Offset: ${GREEN}$NODE_OFFSET${NC}"
    
    mkdir -p $NODE_DIR/logs
    cd $NODE_DIR
    
    echo -e "${CYAN}→${NC} Creating keypairs..."
    NODE_KEYPAIR_OUTPUT=$(solana-keygen new --outfile node-keypair.json --no-bip39-passphrase 2>&1)
    NODE_SEED=$(echo "$NODE_KEYPAIR_OUTPUT" | grep -A 1 "Save this seed phrase" | tail -1)
    
    CALLBACK_KEYPAIR_OUTPUT=$(solana-keygen new --outfile callback-kp.json --no-bip39-passphrase 2>&1)
    CALLBACK_SEED=$(echo "$CALLBACK_KEYPAIR_OUTPUT" | grep -A 1 "Save this seed phrase" | tail -1)
    
    openssl genpkey -algorithm Ed25519 -out identity.pem 2>/dev/null
    arcium gen-bls-key bls-keypair.json 2>/dev/null
    arcium generate-x25519 -o x25519-keypair.json 2>/dev/null
    echo -e "${GREEN}✓${NC} Keypairs created"
    
    NODE_ADDR=$(solana address --keypair node-keypair.json)
    CALLBACK_ADDR=$(solana address --keypair callback-kp.json)
    
    cat >> ../$WALLET_BACKUP << EOF
────────────────────────────────────────
NODE $i (Offset: $NODE_OFFSET)
────────────────────────────────────────
Node Wallet:     $NODE_ADDR
Node Seed:       $NODE_SEED
Callback Wallet: $CALLBACK_ADDR
Callback Seed:   $CALLBACK_SEED
Faucet: https://faucet.solana.com

EOF
    
    echo -e "${GREEN}✓${NC} Node:     ${YELLOW}$NODE_ADDR${NC}"
    echo -e "${GREEN}✓${NC} Callback: ${YELLOW}$CALLBACK_ADDR${NC}"
    
    cat > node-config.toml <<EOF
[node]
offset = $NODE_OFFSET
hardware_claim = 0
starting_epoch = 0
ending_epoch = 9223372036854775807

[network]
address = "0.0.0.0"

[solana]
endpoint_rpc = "$RPC_URL"
endpoint_wss = "wss://api.devnet.solana.com"
cluster = "Devnet"
commitment.commitment = "confirmed"
EOF
    
    echo -e "${GREEN}✓${NC} Config created\n"
    cd ..
done

# Create check-balance script
echo -e "${BLUE}[5/5]${NC} Creating utility scripts..."
cat > check-balance.sh << 'EOFCHECK'
#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════ CHECK BALANCE ════════${NC}\n"

TOTAL_OK=0
TOTAL_LOW=0

for dir in node-*/; do
    [ ! -d "$dir" ] && continue
    i=$(echo $dir | grep -o '[0-9]*')
    
    node_bal=$(solana balance --keypair $dir/node-keypair.json 2>/dev/null | awk '{print $1}')
    callback_bal=$(solana balance --keypair $dir/callback-kp.json 2>/dev/null | awk '{print $1}')
    
    echo -e "${YELLOW}Node $i:${NC}"
    
    if (( $(echo "$node_bal >= 0.5" | bc -l) )); then
        echo -e "  Node:     ${GREEN}$node_bal SOL ✓${NC}"
        TOTAL_OK=$((TOTAL_OK + 1))
    else
        echo -e "  Node:     ${RED}$node_bal SOL ✗ NEED AIRDROP!${NC}"
        TOTAL_LOW=$((TOTAL_LOW + 1))
    fi
    
    if (( $(echo "$callback_bal >= 0.5" | bc -l) )); then
        echo -e "  Callback: ${GREEN}$callback_bal SOL ✓${NC}"
        TOTAL_OK=$((TOTAL_OK + 1))
    else
        echo -e "  Callback: ${RED}$callback_bal SOL ✗ NEED AIRDROP!${NC}"
        TOTAL_LOW=$((TOTAL_LOW + 1))
    fi
    echo ""
done

echo -e "${BLUE}════════════════════════════════════${NC}"
echo -e "${GREEN}OK: $TOTAL_OK${NC} | ${RED}Need airdrop: $TOTAL_LOW${NC}"
EOFCHECK

chmod +x check-balance.sh
echo -e "${GREEN}✓${NC} check-balance.sh created\n"

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          SETUP COMPLETED!              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"

echo -e "${YELLOW}Offset list:${NC}"
cat $OFFSET_FILE | nl
echo ""

echo -e "${CYAN}=== NEXT STEPS ====${NC}"
echo -e "${BLUE}1.${NC} View wallets that need airdrop:"
echo -e "   ${GREEN}cat wallets-backup.txt${NC}"
echo -e "${BLUE}2.${NC} Airdrop SOL at:"
echo -e "   ${GREEN}https://faucet.solana.com${NC}"
echo -e "${BLUE}3.${NC} Check balance:"
echo -e "   ${GREEN}./check-balance.sh${NC}"
echo -e "${BLUE}4.${NC} Operate cluster:"
echo -e "   ${GREEN}./2_operate_cluster.sh${NC}"
echo -e "${BLUE}5.${NC} Generate compose:"
echo -e "   ${GREEN}./3_gen_compose.sh${NC}\n"
echo -e "${BLUE}6.${NC} Run nodes:"
echo -e "   ${GREEN}docker-compose up -d --no-recreate${NC}\n"

echo -e "${RED}IMPORTANT:${NC} Backup files ${GREEN}$WALLET_BACKUP${NC} and ${GREEN}$OFFSET_FILE${NC}!"
