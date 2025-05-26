#!/bin/bash

# admin/tools/simple_endpoint_fix.sh
# 簡化的端點 ID 修復工具

echo "=== VPN 端點 ID 診斷和修復工具 ==="
echo ""

# 檢查當前環境
current_dir=$(pwd)
echo "當前目錄: $current_dir"

# 檢查配置文件
config_file="./configs/staging/staging.env"
if [ -f "$config_file" ]; then
    echo "找到配置文件: $config_file"
    echo ""
    echo "當前配置中的端點 ID:"
    grep "ENDPOINT_ID=" "$config_file"
    echo ""
else
    echo "錯誤: 找不到配置文件 $config_file"
    exit 1
fi

echo "=== 手動修復步驟 ==="
echo ""
echo "1. 首先檢查 AWS 認證:"
echo "   aws sts get-caller-identity"
echo ""
echo "2. 查看實際的 VPN 端點:"
echo "   aws ec2 describe-client-vpn-endpoints --region us-east-1 --query 'ClientVpnEndpoints[*].{ID:ClientVpnEndpointId,Name:Tags[?Key==\`Name\`].Value|[0],Status:Status.Code}' --output table"
echo ""
echo "3. 如果找到正確的端點 ID，請手動編輯配置文件:"
echo "   nano $config_file"
echo "   或"
echo "   vim $config_file"
echo ""
echo "4. 將 ENDPOINT_ID 行修改為正確的值，例如:"
echo "   ENDPOINT_ID=cvpn-endpoint-實際的ID"
echo ""
echo "5. 保存文件後，重新測試 VPN 管理功能"
echo ""

# 備份當前配置
backup_file="${config_file}.backup_$(date +%Y%m%d_%H%M%S)"
cp "$config_file" "$backup_file"
echo "已建立配置文件備份: $backup_file"
echo ""

echo "=== 如果沒有找到任何端點 ==="
echo ""
echo "可能的原因:"
echo "1. 端點確實不存在（已被刪除）"
echo "2. AWS 區域設定錯誤"
echo "3. AWS 權限不足"
echo "4. 網絡連接問題"
echo ""
echo "解決方案:"
echo "1. 確認 AWS 區域設定正確（當前設定: us-east-1）"
echo "2. 檢查 AWS 權限是否包含 ec2:DescribeClientVpnEndpoints"
echo "3. 如果端點不存在，請使用主管理腳本創建新端點:"
echo "   ./admin/aws_vpn_admin.sh"
echo "   選擇選項 1: 建立新的 VPN 端點"

echo ""
echo "=== 快速測試命令 ==="
echo ""
echo "# 測試 AWS 連接:"
echo "aws sts get-caller-identity"
echo ""
echo "# 列出所有 VPN 端點:"
echo "aws ec2 describe-client-vpn-endpoints --region us-east-1"
echo ""
echo "# 檢查特定端點:"
echo "aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids cvpn-endpoint-staging123 --region us-east-1"
