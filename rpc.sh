#!/bin/bash
# =========================================================
# ARCIUM RPC SELF-HEAL SCRIPT (SAFE VERSION)
# - Quét log t?ng node
# - Phát hi?n l?i RPC/WSS
# - Ð?i RPC + WSS h?p l?
# - Restart dúng container
# =========================================================

set -euo pipefail

ROOT_DIR="/root/arciumm2"
TOKENS_FILE="$ROOT_DIR/tokens1.txt"

# -------- Các m?u l?i RPC/WSS --------
LOG_KEYWORDS=(
  # Rate limit / network
  "HTTP status client error (429"
  "RPC timeout"
  "unable to connect to server"

  # Pub/Sub / WSS
  "Failed to create new pub/sub"
  "Pub/sub connection closed"

  # Transaction / account
  "Failed to send activation transaction"
  "AccountNotFound"

  # Cluster check / init (R?T QUAN TR?NG)
  "Failed to check cluster status"
  "builder error for url"
  "client.get_version"
)

# -------- Ð?c RPC theo prefix (KHÔNG L?CH) --------
RPC_HTTP=()
RPC_WSS=()

while IFS= read -r line; do
  line=$(echo "$line" | tr -d '\r' | xargs)
  [[ -z "$line" ]] && continue

  if [[ "$line" == http* ]]; then
    RPC_HTTP+=("$line")
  elif [[ "$line" == wss* ]]; then
    RPC_WSS+=("$line")
  fi
done < "$TOKENS_FILE"

TOTAL_HTTP=${#RPC_HTTP[@]}
TOTAL_WSS=${#RPC_WSS[@]}

if [[ $TOTAL_HTTP -eq 0 || $TOTAL_WSS -eq 0 ]]; then
  echo "? Không d?c du?c RPC ho?c WSS t? $TOKENS_FILE"
  exit 1
fi

TOTAL=$(( TOTAL_HTTP < TOTAL_WSS ? TOTAL_HTTP : TOTAL_WSS ))

echo "?? RPC self-heal scan: $(date)"
echo "?? RPC pairs kh? d?ng: $TOTAL"
echo "--------------------------------------------------"

# -------- Duy?t t?ng node --------
for NODE_PATH in "$ROOT_DIR"/node-*; do
  [[ ! -d "$NODE_PATH" ]] && continue

  NODE_NAME=$(basename "$NODE_PATH")
  LOG_DIR="$NODE_PATH/logs"
  CONFIG_FILE="$NODE_PATH/node-config.toml"
  CONTAINER_NAME="dc-arx-$NODE_NAME"

  [[ ! -d "$LOG_DIR" || ! -f "$CONFIG_FILE" ]] && continue

  LOG_FILE=$(ls -t "$LOG_DIR"/arx_log_*.log 2>/dev/null | head -n 1)
  [[ -z "$LOG_FILE" ]] && continue

  ERROR_FOUND=false
  for KEY in "${LOG_KEYWORDS[@]}"; do
    if grep -Fq "$KEY" "$LOG_FILE"; then
      ERROR_FOUND=true
      break
    fi
  done

  if [[ "$ERROR_FOUND" == true ]]; then
    IDX=$((RANDOM % TOTAL))

    NEW_RPC="${RPC_HTTP[$IDX]}"
    NEW_WSS="${RPC_WSS[$IDX]}"

    # -------- VALIDATION C?NG --------
    if [[ -z "$NEW_RPC" || -z "$NEW_WSS" ]]; then
      echo "? [$NODE_NAME] RPC/WSS r?ng – b? qua"
      continue
    fi

    if [[ "$NEW_RPC" == wss* || "$NEW_WSS" == http* ]]; then
      echo "? [$NODE_NAME] RPC/WSS b? d?o – b? qua"
      continue
    fi

    echo "??  [$NODE_NAME] Phát hi?n l?i RPC"
    echo "    ? Ð?i RPC + WSS"
    echo "    endpoint_rpc = $NEW_RPC"
    echo "    endpoint_wss = $NEW_WSS"

    # -------- Ghi config an toàn --------
    sed -i -E 's|endpoint_rpc *= *".*"|endpoint_rpc = "'"$NEW_RPC"'"|' "$CONFIG_FILE"
    sed -i -E 's|endpoint_wss *= *".*"|endpoint_wss = "'"$NEW_WSS"'"|' "$CONFIG_FILE"
    sed -i 's/\r//g; s/[[:space:]]*$//' "$CONFIG_FILE"

    echo "?? Restart container $CONTAINER_NAME"
    if docker restart "$CONTAINER_NAME" >/dev/null 2>&1; then
      echo "    ? Restart thành công"
    else
      echo "    ? Restart th?t b?i"
    fi
  else
    echo "? [$NODE_NAME] OK – không s?a"
  fi
done
