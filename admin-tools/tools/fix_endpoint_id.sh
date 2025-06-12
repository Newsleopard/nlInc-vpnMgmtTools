#!/bin/bash

# admin/tools/fix_endpoint_id.sh
# 修復 VPN 端點 ID 配置不匹配問題

# 設定顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 獲取腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 載入環境管理器
if [ -f "$PROJECT_ROOT/lib/env_manager.sh" ]; then
    source "$PROJECT_ROOT/lib/env_manager.sh"
else
    echo -e "${RED}錯誤: 無法找到環境管理器${NC}"
    exit 1
fi

# 載入當前環境並設定配置
load_current_env
if [ -z "$CURRENT_ENVIRONMENT" ]; then
    echo -e "${RED}錯誤: 無法確定當前環境。請先執行 ./vpn_env.sh switch [環境名稱]${NC}"
    exit 1
fi

# 載入環境配置
if ! env_load_config "$CURRENT_ENVIRONMENT"; then
    echo -e "${RED}錯誤: 無法載入環境配置${NC}"
    exit 1
fi

# 設定 CONFIG_FILE 變數指向當前環境的配置檔案
CONFIG_FILE="$PROJECT_ROOT/configs/${CURRENT_ENVIRONMENT}/${CURRENT_ENVIRONMENT}.env"

# 載入核心函式
if [ -f "$PROJECT_ROOT/lib/core_functions.sh" ]; then
    source "$PROJECT_ROOT/lib/core_functions.sh"
else
    echo -e "${RED}錯誤: 無法載入核心函式庫${NC}"
    exit 1
fi

echo -e "${CYAN}=== VPN 端點 ID 修復工具 ===${NC}"
echo -e "${BLUE}此工具將幫您檢查和修復端點 ID 配置問題${NC}"
echo ""

echo -e "${BLUE}當前環境: ${ENV_DISPLAY_NAME:-$CURRENT_ENVIRONMENT}${NC}"
echo -e "${BLUE}配置文件: $CONFIG_FILE${NC}"
echo ""

# 驗證配置檔案存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}錯誤: 配置檔案不存在: $CONFIG_FILE${NC}"
    exit 1
fi

# 載入當前配置
if ! load_config_core "$CONFIG_FILE"; then
    echo -e "${RED}錯誤: 無法載入配置文件${NC}"
    exit 1
fi

echo -e "${YELLOW}步驟 1: 檢查當前配置中的端點 ID${NC}"
echo -e "配置文件中的端點 ID: ${BLUE}${ENDPOINT_ID:-未設定}${NC}"
echo -e "AWS 區域: ${BLUE}${AWS_REGION:-未設定}${NC}"
echo ""

# 檢查 AWS 認證
echo -e "${YELLOW}步驟 2: 檢查 AWS 認證${NC}"
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${RED}錯誤: AWS 認證失敗。請檢查 AWS 憑證配置。${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AWS 認證正常${NC}"
echo ""

# 獲取所有 VPN 端點
echo -e "${YELLOW}步驟 3: 查詢實際的 VPN 端點${NC}"
echo -e "${BLUE}正在查詢 AWS 區域 $AWS_REGION 中的所有 VPN 端點...${NC}"

endpoints_json=$(aws ec2 describe-client-vpn-endpoints --region "$AWS_REGION" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "${RED}錯誤: 無法查詢 VPN 端點。請檢查 AWS 權限和網絡連接。${NC}"
    exit 1
fi

# 解析端點列表
endpoint_count=$(echo "$endpoints_json" | jq '.ClientVpnEndpoints | length' 2>/dev/null || echo "0")

if [ "$endpoint_count" -eq 0 ]; then
    echo -e "${YELLOW}在區域 $AWS_REGION 中沒有找到任何 VPN 端點${NC}"
    echo ""
    echo -e "${BLUE}可能的解決方案:${NC}"
    echo -e "1. 檢查是否在正確的 AWS 區域"
    echo -e "2. 確認是否有權限查看 VPN 端點"
    echo -e "3. 如果端點確實不存在，需要重新創建"
    echo ""
    
    read -p "是否要創建新的 VPN 端點? (y/N): " create_new
    if [[ "$create_new" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}請使用主管理腳本來創建新端點: ./admin/aws_vpn_admin.sh${NC}"
    fi
    exit 0
fi

echo -e "${GREEN}找到 $endpoint_count 個 VPN 端點${NC}"
echo ""

# 顯示所有端點並收集端點列表
echo -e "${BLUE}=== 可用的 VPN 端點列表 ===${NC}"
endpoint_list_file="/tmp/vpn_endpoints_$$"
rm -f "$endpoint_list_file"

counter=1
echo "$endpoints_json" | jq -c '.ClientVpnEndpoints[]' | while read -r endpoint; do
    endpoint_id=$(echo "$endpoint" | jq -r '.ClientVpnEndpointId')
    endpoint_name=$(echo "$endpoint" | jq -r '.Tags[]? | select(.Key=="Name") | .Value // "無名稱"')
    endpoint_status=$(echo "$endpoint" | jq -r '.Status.Code')
    endpoint_cidr=$(echo "$endpoint" | jq -r '.ClientCidrBlock')
    
    echo -e "${CYAN}[$counter]${NC} 端點 ID: ${BLUE}$endpoint_id${NC}"
    echo -e "    名稱: $endpoint_name"
    echo -e "    狀態: $endpoint_status"
    echo -e "    CIDR: $endpoint_cidr"
    echo ""
    
    # 將端點 ID 寫入臨時文件供後續使用
    echo "$endpoint_id" >> "$endpoint_list_file"
    
    counter=$((counter + 1))
done

# 檢查配置中的端點是否存在
if [ -n "$ENDPOINT_ID" ]; then
    echo -e "${YELLOW}步驟 4: 驗證配置中的端點 ID${NC}"
    
    # 檢查當前配置的端點是否存在
    current_endpoint=$(aws ec2 describe-client-vpn-endpoints \
        --client-vpn-endpoint-ids "$ENDPOINT_ID" \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$current_endpoint" ]; then
        echo -e "${GREEN}✓ 配置中的端點 ID 是有效的${NC}"
        
        # 顯示當前端點的詳細信息
        endpoint_status=$(echo "$current_endpoint" | jq -r '.ClientVpnEndpoints[0].Status.Code')
        endpoint_name=$(echo "$current_endpoint" | jq -r '.ClientVpnEndpoints[0].Tags[]? | select(.Key=="Name") | .Value // "無名稱"')
        
        echo -e "端點狀態: $endpoint_status"
        echo -e "端點名稱: $endpoint_name"
        echo ""
        echo -e "${GREEN}配置文件無需修復。${NC}"
        
        # 清理臨時文件
        rm -f "$endpoint_list_file"
        exit 0
    else
        echo -e "${RED}✗ 配置中的端點 ID '$ENDPOINT_ID' 不存在或無法訪問${NC}"
        echo ""
    fi
fi

# 讓用戶選擇正確的端點
echo -e "${YELLOW}步驟 5: 選擇正確的端點 ID${NC}"

# 讀取端點列表（使用兼容性更好的方法）
endpoint_list=()
if [ -f "$endpoint_list_file" ]; then
    while IFS= read -r line; do
        endpoint_list+=("$line")
    done < "$endpoint_list_file"
    rm -f "$endpoint_list_file"
else
    echo -e "${RED}錯誤: 無法獲取端點列表${NC}"
    exit 1
fi

echo -e "${BLUE}請選擇正確的端點 (1-${#endpoint_list[@]}):${NC}"
read -p "選擇編號: " choice

# 驗證選擇
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#endpoint_list[@]}" ]; then
    echo -e "${RED}無效的選擇${NC}"
    exit 1
fi

# 獲取選擇的端點 ID
selected_endpoint="${endpoint_list[$((choice-1))]}"
echo -e "${GREEN}您選擇的端點 ID: $selected_endpoint${NC}"
echo ""

# 確認修復
echo -e "${YELLOW}步驟 6: 確認修復${NC}"
echo -e "${BLUE}即將執行以下修復操作:${NC}"
echo -e "• 備份當前配置文件"
echo -e "• 更新配置文件中的 ENDPOINT_ID"
echo -e "• 從 '$ENDPOINT_ID' 更改為 '$selected_endpoint'"
echo ""

read -p "確認執行修復? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}操作已取消${NC}"
    exit 0
fi

# 執行修復
echo -e "${YELLOW}步驟 7: 執行修復${NC}"

# 備份配置文件
backup_file="${CONFIG_FILE}.backup_$(date +%Y%m%d_%H%M%S)"
cp "$CONFIG_FILE" "$backup_file"
echo -e "${GREEN}✓ 配置文件已備份到: $backup_file${NC}"

# 創建臨時配置文件
temp_config=$(mktemp)

# 更新配置文件
while IFS= read -r line; do
    if [[ "$line" =~ ^ENDPOINT_ID= ]]; then
        echo "ENDPOINT_ID=$selected_endpoint"
    else
        echo "$line"
    fi
done < "$CONFIG_FILE" > "$temp_config"

# 替換原配置文件
mv "$temp_config" "$CONFIG_FILE"

echo -e "${GREEN}✓ 配置文件已更新${NC}"

# 驗證修復結果
echo -e "${YELLOW}步驟 8: 驗證修復結果${NC}"

# 重新載入配置
if ! load_config_core "$CONFIG_FILE"; then
    echo -e "${RED}錯誤: 無法重新載入配置文件${NC}"
    echo -e "${BLUE}正在恢復備份...${NC}"
    cp "$backup_file" "$CONFIG_FILE"
    exit 1
fi

# 檢查新的端點 ID
new_endpoint_check=$(aws ec2 describe-client-vpn-endpoints \
    --client-vpn-endpoint-ids "$ENDPOINT_ID" \
    --region "$AWS_REGION" 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$new_endpoint_check" ]; then
    endpoint_status=$(echo "$new_endpoint_check" | jq -r '.ClientVpnEndpoints[0].Status.Code')
    endpoint_name=$(echo "$new_endpoint_check" | jq -r '.ClientVpnEndpoints[0].Tags[]? | select(.Key=="Name") | .Value // "無名稱"')
    
    echo -e "${GREEN}✓ 修復成功！${NC}"
    echo -e "新的端點 ID: ${BLUE}$ENDPOINT_ID${NC}"
    echo -e "端點狀態: $endpoint_status"
    echo -e "端點名稱: $endpoint_name"
    echo ""
    echo -e "${GREEN}現在您可以正常使用 VPN 管理功能了。${NC}"
else
    echo -e "${RED}✗ 修復失敗，無法驗證新的端點 ID${NC}"
    echo -e "${BLUE}正在恢復備份...${NC}"
    cp "$backup_file" "$CONFIG_FILE"
    exit 1
fi

echo ""
echo -e "${CYAN}=== 修復完成 ===${NC}"
echo -e "${BLUE}建議接下來的操作:${NC}"
echo -e "1. 執行系統健康檢查: ./admin/aws_vpn_admin.sh (選項 8)"
echo -e "2. 檢查 VPN 端點設定是否正確"
echo -e "3. 確認所有功能正常運作"
