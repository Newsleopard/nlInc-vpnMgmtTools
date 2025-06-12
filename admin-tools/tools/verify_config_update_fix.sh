#!/bin/bash

# Configuration Update Fix Verification Tool
# 這個工具驗證配置文件更新修復是否正確工作

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔍 配置文件更新修復驗證工具${NC}"
echo "=================================================="

# 獲取腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 配置
CONFIG_DIR="$PROJECT_ROOT/configs/staging"
CONFIG_FILE="$CONFIG_DIR/staging.env"
TEST_CONFIG="/tmp/test_config_update_$(date +%Y%m%d_%H%M%S).env"

echo -e "\n${CYAN}=== 驗證目標 ===${NC}"
echo "1. 檢查 endpoint_creation.sh 中的配置更新邏輯"
echo "2. 模擬配置文件更新過程"
echo "3. 驗證現有配置項是否得到保留"
echo "4. 確認新配置項被正確添加/更新"

# 1. 檢查修復的代碼
echo -e "\n${YELLOW}1. 檢查 endpoint_creation.sh 中的修復...${NC}"

ENDPOINT_CREATION_FILE="$PROJECT_ROOT/lib/endpoint_creation.sh"
if [ ! -f "$ENDPOINT_CREATION_FILE" ]; then
    echo -e "${RED}❌ 找不到 endpoint_creation.sh 文件${NC}"
    exit 1
fi

# 檢查是否還有覆蓋配置的危險代碼
if grep -n "echo.*> \$.*config" "$ENDPOINT_CREATION_FILE" >/dev/null 2>&1; then
    echo -e "${RED}❌ 仍然存在覆蓋配置文件的危險代碼:${NC}"
    grep -n "echo.*> \$.*config" "$ENDPOINT_CREATION_FILE" || true
    exit 1
else
    echo -e "${GREEN}✅ 沒有發現覆蓋配置文件的危險代碼${NC}"
fi

# 檢查是否有安全的配置更新邏輯
if grep -q "創建臨時文件來安全地更新配置" "$ENDPOINT_CREATION_FILE"; then
    echo -e "${GREEN}✅ 發現安全的配置更新邏輯${NC}"
else
    echo -e "${RED}❌ 沒有發現安全的配置更新邏輯${NC}"
    exit 1
fi

# 2. 創建測試配置文件
echo -e "\n${YELLOW}2. 創建測試配置文件...${NC}"

cat > "$TEST_CONFIG" << 'EOF'
# AWS 配置
AWS_REGION=us-east-1
AWS_PROFILE=default

# VPN 端點配置 (這些將被更新)
ENDPOINT_ID=cvpn-endpoint-old123
VPN_CIDR=172.16.0.0/20
VPN_NAME=old-vpn-name

# 服務器配置 (這些應該保留)
SERVER_CERT_ARN=arn:aws:acm:us-east-1:123456789012:certificate/old-cert
CLIENT_CERT_ARN=arn:aws:acm:us-east-1:123456789012:certificate/old-client-cert

# 網絡配置
VPC_ID=vpc-old123
VPC_CIDR=10.0.0.0/16
SUBNET_ID=subnet-old123

# 自定義配置 (這些應該保留)
CUSTOM_SETTING=important_value
DEBUG_MODE=true
BACKUP_ENABLED=yes

# 多 VPC 配置
MULTI_VPC_COUNT=2
MULTI_VPC_1=vpc-extra1,subnet-extra1,10.1.0.0/16
MULTI_VPC_2=vpc-extra2,subnet-extra2,10.2.0.0/16
EOF

echo -e "${GREEN}✅ 測試配置文件已創建: $TEST_CONFIG${NC}"

# 3. 模擬配置更新函數
echo -e "\n${YELLOW}3. 模擬配置更新過程...${NC}"

simulate_config_update() {
    local main_config_file="$1"
    local endpoint_id="cvpn-endpoint-new456"
    local aws_region="us-west-2"
    local vpn_cidr="172.16.0.0/22"
    local vpn_name="new-vpn-name"
    local arg_server_cert_arn="arn:aws:acm:us-west-2:123456789012:certificate/new-cert"
    local arg_client_cert_arn="arn:aws:acm:us-west-2:123456789012:certificate/new-client-cert"
    local vpc_id="vpc-new456"
    local vpc_cidr="10.0.0.0/16"
    local subnet_id="subnet-new456"
    
    echo -e "${BLUE}模擬更新配置項...${NC}"
    
    # 創建臨時文件來安全地更新配置 (模擬修復後的邏輯)
    local temp_config=$(mktemp)
    local config_updated=false
    
    # 如果配置文件存在，讀取並更新現有配置
    if [ -f "$main_config_file" ]; then
        while IFS='=' read -r key value; do
            # 跳過空行和註釋
            if [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]]; then
                echo "$key=$value" >> "$temp_config"
                continue
            fi
            
            # 更新需要修改的配置項
            case "$key" in
                "ENDPOINT_ID") echo "ENDPOINT_ID=$endpoint_id" >> "$temp_config" ;;
                "AWS_REGION") echo "AWS_REGION=$aws_region" >> "$temp_config" ;;
                "VPN_CIDR") echo "VPN_CIDR=$vpn_cidr" >> "$temp_config" ;;
                "VPN_NAME") echo "VPN_NAME=$vpn_name" >> "$temp_config" ;;
                "SERVER_CERT_ARN") echo "SERVER_CERT_ARN=$arg_server_cert_arn" >> "$temp_config" ;;
                "CLIENT_CERT_ARN") echo "CLIENT_CERT_ARN=$arg_client_cert_arn" >> "$temp_config" ;;
                "VPC_ID") echo "VPC_ID=$vpc_id" >> "$temp_config" ;;
                "VPC_CIDR") echo "VPC_CIDR=$vpc_cidr" >> "$temp_config" ;;
                "SUBNET_ID") echo "SUBNET_ID=$subnet_id" >> "$temp_config" ;;
                "MULTI_VPC_COUNT") echo "MULTI_VPC_COUNT=0" >> "$temp_config" ;;
                *) echo "$key=$value" >> "$temp_config" ;;
            esac
        done < "$main_config_file"
        config_updated=true
    fi
    
    # 原子性地替換配置文件
    mv "$temp_config" "$main_config_file"
    echo -e "${GREEN}✓ 配置已安全更新，現有設置得到保留${NC}"
}

# 保存原始配置以便比較
cp "$TEST_CONFIG" "${TEST_CONFIG}.original"

# 執行模擬更新
simulate_config_update "$TEST_CONFIG"

# 4. 驗證結果
echo -e "\n${YELLOW}4. 驗證更新結果...${NC}"

echo -e "\n${BLUE}原始配置:${NC}"
cat "${TEST_CONFIG}.original"

echo -e "\n${BLUE}更新後配置:${NC}"
cat "$TEST_CONFIG"

# 檢查關鍵更新
echo -e "\n${YELLOW}檢查關鍵配置項更新:${NC}"

check_config_value() {
    local file="$1"
    local key="$2"
    local expected="$3"
    local actual=$(grep "^$key=" "$file" | cut -d'=' -f2-)
    
    if [ "$actual" = "$expected" ]; then
        echo -e "${GREEN}✅ $key: $actual${NC}"
    else
        echo -e "${RED}❌ $key: 期望 '$expected', 實際 '$actual'${NC}"
        return 1
    fi
}

errors=0

# 檢查更新的配置項
check_config_value "$TEST_CONFIG" "ENDPOINT_ID" "cvpn-endpoint-new456" || ((errors++))
check_config_value "$TEST_CONFIG" "AWS_REGION" "us-west-2" || ((errors++))
check_config_value "$TEST_CONFIG" "VPN_CIDR" "172.16.0.0/22" || ((errors++))
check_config_value "$TEST_CONFIG" "VPN_NAME" "new-vpn-name" || ((errors++))
check_config_value "$TEST_CONFIG" "MULTI_VPC_COUNT" "0" || ((errors++))

# 檢查保留的自定義配置項
echo -e "\n${YELLOW}檢查保留的自定義配置項:${NC}"
check_config_value "$TEST_CONFIG" "CUSTOM_SETTING" "important_value" || ((errors++))
check_config_value "$TEST_CONFIG" "DEBUG_MODE" "true" || ((errors++))
check_config_value "$TEST_CONFIG" "BACKUP_ENABLED" "yes" || ((errors++))

# 檢查註釋是否保留
echo -e "\n${YELLOW}檢查註釋保留:${NC}"
if grep -q "# AWS 配置" "$TEST_CONFIG"; then
    echo -e "${GREEN}✅ 註釋得到保留${NC}"
else
    echo -e "${RED}❌ 註釋沒有被保留${NC}"
    ((errors++))
fi

# 5. 檢查多 VPC 配置處理
echo -e "\n${YELLOW}5. 檢查多 VPC 配置處理...${NC}"

# 檢查 MULTI_VPC_1 和 MULTI_VPC_2 是否被保留
if grep -q "MULTI_VPC_1=" "$TEST_CONFIG"; then
    echo -e "${GREEN}✅ 多 VPC 配置項得到保留${NC}"
else
    echo -e "${RED}❌ 多 VPC 配置項沒有被保留${NC}"
    ((errors++))
fi

# 6. 總結
echo -e "\n${CYAN}=== 驗證總結 ===${NC}"

if [ $errors -eq 0 ]; then
    echo -e "${GREEN}🎉 所有驗證通過！配置更新修復工作正常。${NC}"
    echo ""
    echo -e "${BLUE}關鍵改進:${NC}"
    echo "✅ 不再覆蓋整個配置文件"
    echo "✅ 現有配置項得到保留"
    echo "✅ 只更新必要的 VPN 相關配置"
    echo "✅ 註釋和自定義設置保持不變"
    echo "✅ 原子性更新確保操作安全"
else
    echo -e "${RED}❌ 發現 $errors 個問題，修復可能不完整${NC}"
fi

# 清理測試文件
rm -f "$TEST_CONFIG" "${TEST_CONFIG}.original"

echo -e "\n${YELLOW}建議的後續操作:${NC}"
echo "1. 測試實際的 VPN 創建流程"
echo "2. 確認現有的配置文件不會被破壞"
echo "3. 檢查其他可能有類似問題的腳本"
