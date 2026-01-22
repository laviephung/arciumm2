#!/bin/bash
# ============================================
# SCRIPT XEM LOGS ARCIUM NODES
# Sử dụng:
#   ./view-logs.sh              -> Menu chọn
#   ./view-logs.sh 5            -> Xem logs node 5
#   ./view-logs.sh all          -> Xem logs tất cả
#   ./view-logs.sh active       -> Xem nodes đang active
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_menu() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${GREEN}      ARCIUM LOGS VIEWER            ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"
    
    echo -e "${YELLOW}Chọn cách xem logs:${NC}"
    echo -e "${CYAN}1.${NC} Xem logs 1 node cụ thể"
    echo -e "${CYAN}2.${NC} Xem logs tất cả nodes (docker logs)"
    echo -e "${CYAN}3.${NC} Xem logs file của 1 node"
    echo -e "${CYAN}4.${NC} Xem logs file của tất cả nodes"
    echo -e "${CYAN}5.${NC} Tìm kiếm trong logs"
    echo -e "${CYAN}6.${NC} Xem nodes đang active"
    echo -e "${CYAN}0.${NC} Thoát"
    echo ""
}

view_docker_log() {
    local node_num=$1
    echo -e "${GREEN}Xem logs node-$node_num (Docker)...${NC}"
    echo -e "${YELLOW}Nhấn Ctrl+C để thoát${NC}\n"
    docker logs -f arx-node-$node_num
}

view_file_log() {
    local node_num=$1
    local log_dir="node-$node_num/logs"
    
    if [ ! -d "$log_dir" ]; then
        echo -e "${RED}✗ Thư mục logs không tồn tại: $log_dir${NC}"
        return
    fi
    
    local log_file=$(ls -t $log_dir/arx_log_*.log 2>/dev/null | head -1)
    
    if [ -z "$log_file" ]; then
        echo -e "${RED}✗ Không tìm thấy file log trong $log_dir${NC}"
        return
    fi
    
    echo -e "${GREEN}Xem log file: $log_file${NC}"
    echo -e "${YELLOW}Nhấn Ctrl+C để thoát${NC}\n"
    tail -f "$log_file"
}

view_all_docker_logs() {
    echo -e "${GREEN}Xem logs tất cả nodes (Docker)...${NC}"
    echo -e "${YELLOW}Nhấn Ctrl+C để thoát${NC}\n"
    docker-compose logs -f
}

view_all_file_logs() {
    echo -e "${GREEN}Logs file của tất cả nodes:${NC}\n"
    
    for dir in node-*/logs; do
        if [ -d "$dir" ]; then
            node_num=$(echo $dir | grep -o '[0-9]*' | head -1)
            log_file=$(ls -t $dir/arx_log_*.log 2>/dev/null | head -1)
            
            if [ -n "$log_file" ]; then
                echo -e "${CYAN}═══ Node $node_num ═══${NC}"
                tail -20 "$log_file"
                echo ""
            fi
        fi
    done
    
    echo -e "${YELLOW}Để follow logs 1 node: ./view-logs.sh <số_node>${NC}"
}

search_logs() {
    read -p "Nhập từ khóa tìm kiếm: " keyword
    echo -e "\n${GREEN}Tìm kiếm '$keyword' trong logs...${NC}\n"
    
    for dir in node-*/logs; do
        if [ -d "$dir" ]; then
            node_num=$(echo $dir | grep -o '[0-9]*' | head -1)
            log_file=$(ls -t $dir/arx_log_*.log 2>/dev/null | head -1)
            
            if [ -n "$log_file" ]; then
                results=$(grep -i "$keyword" "$log_file" 2>/dev/null)
                if [ -n "$results" ]; then
                    echo -e "${CYAN}═══ Node $node_num ═══${NC}"
                    echo "$results" | tail -5
                    echo ""
                fi
            fi
        fi
    done
}

check_active_nodes() {
    echo -e "${GREEN}Kiểm tra nodes đang active...${NC}\n"
    
    for dir in node-*/; do
        [ ! -d "$dir" ] && continue
        node_num=$(echo $dir | grep -o '[0-9]*')
        log_dir="$dir/logs"
        log_file=$(ls -t $log_dir/arx_log_*.log 2>/dev/null | head -1)
        
        if [ -n "$log_file" ]; then
            if grep -q "Node activated" "$log_file" 2>/dev/null; then
                echo -e "${GREEN}✓ Node $node_num: ACTIVE${NC}"
            elif grep -q "Error\|Failed" "$log_file" 2>/dev/null; then
                echo -e "${RED}✗ Node $node_num: ERROR${NC}"
            else
                echo -e "${YELLOW}○ Node $node_num: STARTING${NC}"
            fi
        else
            echo -e "${YELLOW}? Node $node_num: NO LOGS${NC}"
        fi
    done
}

# Main
case "$1" in
    "")
        while true; do
            show_menu
            read -p "Chọn (0-6): " choice
            echo ""
            
            case $choice in
                1)
                    read -p "Nhập số node: " node_num
                    view_docker_log $node_num
                    ;;
                2)
                    view_all_docker_logs
                    ;;
                3)
                    read -p "Nhập số node: " node_num
                    view_file_log $node_num
                    ;;
                4)
                    view_all_file_logs
                    read -p "Nhấn Enter để tiếp tục..."
                    ;;
                5)
                    search_logs
                    read -p "Nhấn Enter để tiếp tục..."
                    ;;
                6)
                    check_active_nodes
                    read -p "Nhấn Enter để tiếp tục..."
                    ;;
                0)
                    exit 0
                    ;;
                *)
                    echo -e "${RED}Lựa chọn không hợp lệ${NC}"
                    ;;
            esac
            echo ""
        done
        ;;
    "all")
        view_all_docker_logs
        ;;
    "active")
        check_active_nodes
        ;;
    *)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
            view_file_log $1
        else
            echo -e "${RED}Sử dụng:${NC}"
            echo -e "  ./view-logs.sh              ${YELLOW}# Menu${NC}"
            echo -e "  ./view-logs.sh 5            ${YELLOW}# Xem node 5${NC}"
            echo -e "  ./view-logs.sh all          ${YELLOW}# Xem tất cả${NC}"
            echo -e "  ./view-logs.sh active       ${YELLOW}# Check active${NC}"
        fi
        ;;
esac
