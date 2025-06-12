#!/bin/bash

# admin/tools/validate_config.sh
# 驗證和自動修復配置檔案中的端點 ID

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

# 載入核心函式
if [ -f "$PROJECT_ROOT/lib/core_functions.sh" ]; then
    source "$PROJECT_ROOT/lib/core_functions.sh"
else
    echo -e "${RED}錯誤: 無法載入核心函式庫${NC}"
    exit 1
fi

echo -e "${CYAN}=== VPN 配置驗證工具 ===${NC}"
echo -e "${BLUE}此工具將驗證所有環境的配置正確性${NC}"
echo ""

# 驗證函數
validate_endpoint_id() {
    local env_name="$1"
    local config_file="$2"
    local endpoint_id="$3"
    local aws_region="$4"
    
    echo -e "${YELLOW}驗證 $env_name 環境的端點 ID...${NC}"
    
    # 如果端點 ID 為空或看起來像假 ID
    if [ -z "$endpoint_id" ] || [[ "$endpoint_id" =~ -staging123$|template123$ ]]; then
        echo -e "${YELLOW}⚠️  $env_name: 端點 ID 未設定或為測試 ID${NC}"
        return 1
    fi
    
    # 檢查端點是否真實存在
    if aws ec2 describe-client-vpn-endpoints \
        --client-vpn-endpoint-ids "$endpoint_id" \
        --region "$aws_region" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ $env_name: 端點 ID 有效 ($endpoint_id)${NC}"
        return 0
    else
        echo -e "${RED}✗ $env_name: 端點 ID 無效或不存在 ($endpoint_id)${NC}"
        return 1
    fi
}

# 自動修復函數
auto_fix_endpoint_id() {
    local env_name="$1"
    local config_file="$2"
    local aws_region="$3"
    
    echo -e "${YELLOW}正在為 $env_name 環境自動修復端點 ID...${NC}"
    
    # 查詢該區域的所有端點
    local endpoints_json=$(aws ec2 describe-client-vpn-endpoints --region "$aws_region" 2>/dev/null)
    local endpoint_count=$(echo "$endpoints_json" | jq '.ClientVpnEndpoints | length' 2>/dev/null || echo "0")
    
    if [ "$endpoint_count" -eq 0 ]; then
        echo -e "${YELLOW}在區域 $aws_region 中沒有找到任何 VPN 端點${NC}"
        echo -e "${BLUE}建議: 使用 ./admin/aws_vpn_admin.sh 創建新的 VPN 端點${NC}"
        return 1
    fi
    
    if [ "$endpoint_count" -eq 1 ]; then
        # 只有一個端點，自動使用它
        local real_endpoint_id=$(echo "$endpoints_json" | jq -r '.ClientVpnEndpoints[0].ClientVpnEndpointId')
        local endpoint_name=$(echo "$endpoints_json" | jq -r '.ClientVpnEndpoints[0].Tags[]? | select(.Key=="Name") | .Value // "無名稱"')
        
        echo -e "${GREEN}找到唯一端點: $real_endpoint_id ($endpoint_name)${NC}"
        
        # 備份配置文件
        local backup_file="${config_file}.backup_$(date +%Y%m%d_%H%M%S)"
        cp "$config_file" "$backup_file"
        echo -e "${BLUE}配置文件已備份到: $backup_file${NC}"
        
        # 更新配置文件
        local temp_config=$(mktemp)
        while IFS= read -r line; do
            if [[ "$line" =~ ^ENDPOINT_ID=|^#.*ENDPOINT_ID ]]; then
                echo "ENDPOINT_ID=$real_endpoint_id"
            else
                echo "$line"
            fi
        done < "$config_file" > "$temp_config"
        
        mv "$temp_config" "$config_file"
        echo -e "${GREEN}✓ $env_name 環境的端點 ID 已自動修復為: $real_endpoint_id${NC}"
        return 0
    else
        # 多個端點，需要手動選擇
        echo -e "${YELLOW}找到 $endpoint_count 個端點，需要手動選擇${NC}"
        echo -e "${BLUE}請執行: ./admin/tools/fix_endpoint_id.sh${NC}"
        return 1
    fi
}

# 主要邏輯
validation_passed=true

# 驗證所有環境
for env_dir in "$PROJECT_ROOT/configs"/*; do
    if [[ -d "$env_dir" && ! "$env_dir" =~ template ]]; then
        env_name=$(basename "$env_dir")
        config_file="$env_dir/${env_name}.env"
        
        if [[ -f "$config_file" ]]; then
            echo -e "${BLUE}檢查 $env_name 環境...${NC}"
            
            # 載入配置
            source "$config_file"
            
            # 驗證端點 ID
            if ! validate_endpoint_id "$env_name" "$config_file" "$ENDPOINT_ID" "$AWS_REGION"; then
                validation_passed=false
                
                echo -e "${YELLOW}嘗試自動修復...${NC}"
                if auto_fix_endpoint_id "$env_name" "$config_file" "$AWS_REGION"; then
                    echo -e "${GREEN}$env_name 環境已自動修復${NC}"
                else
                    echo -e "${RED}$env_name 環境需要手動修復${NC}"
                fi
            fi
            echo ""
        fi
    fi
done

# 總結
echo -e "${CYAN}=== 驗證完成 ===${NC}"
if [ "$validation_passed" = true ]; then
    echo -e "${GREEN}所有環境配置都是有效的！${NC}"
    exit 0
else
    echo -e "${YELLOW}部分環境配置需要注意或已自動修復${NC}"
    echo -e "${BLUE}建議執行系統健康檢查: ./admin/aws_vpn_admin.sh (選項 8)${NC}"
    exit 1
fi
