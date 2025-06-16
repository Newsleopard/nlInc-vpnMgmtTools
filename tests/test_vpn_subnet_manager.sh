#!/bin/bash

# 簡單的 VPN 子網路管理功能測試
# 測試新增的庫函式是否正確載入

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入核心函式和顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}測試 VPN 子網路管理功能...${NC}"

# 測試載入函式庫
echo -e "${BLUE}測試載入函式庫...${NC}"

# 檢查核心函式庫
if [ ! -f "$SCRIPT_DIR/../lib/endpoint_management.sh" ]; then
    echo -e "${RED}錯誤: 找不到 endpoint_management.sh${NC}"
    exit 1
fi

# 定義必需的變數和函式避免依賴錯誤
LOG_FILE_CORE="/tmp/test.log"
validate_aws_region() { return 0; }
validate_endpoint_id() { return 0; }
log_message_core() { return 0; }

# 載入函式庫（處理依賴）
source "$SCRIPT_DIR/../lib/endpoint_management.sh" 2>/dev/null || {
    echo -e "${YELLOW}警告: 載入 endpoint_management.sh 時有警告，但繼續測試${NC}"
}

# 測試函式是否存在
echo -e "${BLUE}檢查新增的函式...${NC}"

if command -v associate_subnet_to_endpoint_lib >/dev/null 2>&1; then
    echo -e "${GREEN}✓ associate_subnet_to_endpoint_lib 函式存在${NC}"
else
    echo -e "${RED}✗ associate_subnet_to_endpoint_lib 函式不存在${NC}"
    exit 1
fi

if command -v disassociate_vpc_lib >/dev/null 2>&1; then
    echo -e "${GREEN}✓ disassociate_vpc_lib 函式存在${NC}"
else
    echo -e "${RED}✗ disassociate_vpc_lib 函式不存在${NC}"
    exit 1
fi

# 測試函式語法（檢查是否有語法錯誤）
echo -e "${BLUE}檢查函式語法...${NC}"

# 測試函式定義不會產生語法錯誤
if bash -n -c "$(declare -f associate_subnet_to_endpoint_lib)" 2>/dev/null; then
    echo -e "${GREEN}✓ associate_subnet_to_endpoint_lib 語法正確${NC}"
else
    echo -e "${RED}✗ associate_subnet_to_endpoint_lib 語法錯誤${NC}"
    exit 1
fi

if bash -n -c "$(declare -f disassociate_vpc_lib)" 2>/dev/null; then
    echo -e "${GREEN}✓ disassociate_vpc_lib 語法正確${NC}"
else
    echo -e "${RED}✗ disassociate_vpc_lib 語法錯誤${NC}"
    exit 1
fi

# 檢查管理腳本是否存在且可執行
echo -e "${BLUE}檢查管理腳本...${NC}"

if [ -f "$SCRIPT_DIR/../admin-tools/vpn_subnet_manager.sh" ]; then
    echo -e "${GREEN}✓ vpn_subnet_manager.sh 存在${NC}"
    
    if [ -x "$SCRIPT_DIR/../admin-tools/vpn_subnet_manager.sh" ]; then
        echo -e "${GREEN}✓ vpn_subnet_manager.sh 可執行${NC}"
    else
        echo -e "${RED}✗ vpn_subnet_manager.sh 不可執行${NC}"
        exit 1
    fi
    
    # 檢查腳本語法
    if bash -n "$SCRIPT_DIR/../admin-tools/vpn_subnet_manager.sh"; then
        echo -e "${GREEN}✓ vpn_subnet_manager.sh 語法正確${NC}"
    else
        echo -e "${RED}✗ vpn_subnet_manager.sh 語法錯誤${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ vpn_subnet_manager.sh 不存在${NC}"
    exit 1
fi

echo -e "${GREEN}所有基本測試通過！${NC}"
echo -e "${BLUE}VPN 子網路管理功能準備就緒${NC}"