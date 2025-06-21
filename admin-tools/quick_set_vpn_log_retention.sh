#!/bin/bash
#
# 快速設定現有 VPN Client Log Groups 保留期間為 30 天
# 這是一個簡化的一次性腳本
#

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

REGION=${AWS_REGION:-"us-east-1"}
RETENTION_DAYS=30

echo -e "${CYAN}=== 快速設定 VPN Log Groups 保留期間 ===${NC}"
echo -e "區域: $REGION"
echo -e "保留期間: $RETENTION_DAYS 天"
echo ""

# 獲取所有 VPN Client Log Groups
echo -e "${BLUE}搜尋 VPN Client Log Groups...${NC}"

# 查找所有以 /aws/clientvpn/ 開頭的 log groups
vpn_log_groups=$(aws logs describe-log-groups \
    --region "$REGION" \
    --log-group-name-prefix "/aws/clientvpn/" \
    --query 'logGroups[].logGroupName' \
    --output text 2>/dev/null)

if [ -z "$vpn_log_groups" ]; then
    echo -e "${YELLOW}未找到任何 VPN Client Log Groups${NC}"
    exit 0
fi

# 顯示找到的 log groups
echo -e "${GREEN}找到以下 VPN Log Groups:${NC}"
for log_group in $vpn_log_groups; do
    echo "  - $log_group"
done
echo ""

# 確認執行
read -p "是否要為這些 Log Groups 設定 30 天保留期間？(y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}操作已取消${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}開始設定保留期間...${NC}"

success_count=0
fail_count=0

# 為每個 log group 設定保留期間
for log_group in $vpn_log_groups; do
    echo -e "${YELLOW}處理: $log_group${NC}"
    
    # 檢查當前保留期間
    current_retention=$(aws logs describe-log-groups \
        --region "$REGION" \
        --log-group-name-prefix "$log_group" \
        --query "logGroups[?logGroupName=='$log_group'].retentionInDays" \
        --output text 2>/dev/null)
    
    if [ -z "$current_retention" ] || [ "$current_retention" = "None" ] || [ "$current_retention" = "null" ]; then
        current_retention="永久"
    else
        current_retention="${current_retention} 天"
    fi
    
    echo "  當前保留期間: $current_retention"
    
    # 設定新的保留期間
    if aws logs put-retention-policy \
        --log-group-name "$log_group" \
        --retention-in-days "$RETENTION_DAYS" \
        --region "$REGION" 2>/dev/null; then
        echo -e "  ${GREEN}✓ 成功設定為 $RETENTION_DAYS 天${NC}"
        ((success_count++))
    else
        echo -e "  ${RED}✗ 設定失敗${NC}"
        ((fail_count++))
    fi
    echo ""
done

# 顯示結果摘要
echo -e "${CYAN}=== 設定完成 ===${NC}"
echo -e "成功: $success_count"
echo -e "失敗: $fail_count"

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}所有 VPN Log Groups 保留期間已成功設定為 30 天！${NC}"
else
    echo -e "${YELLOW}部分 Log Groups 設定失敗，請檢查 AWS 權限${NC}"
fi
