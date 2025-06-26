#!/bin/bash

# Post-deployment checklist and validation script

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}🔍 $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

check_deployment_status() {
    print_header "部署狀態檢查"
    
    # Check if CDK outputs exist
    if [ -f "cdk-outputs-production.json" ]; then
        print_success "生產環境 CDK 輸出文件存在"
    else
        print_error "生產環境 CDK 輸出文件不存在"
    fi
    
    if [ -f "cdk-outputs-staging.json" ]; then
        print_success "測試環境 CDK 輸出文件存在"
    else
        print_error "測試環境 CDK 輸出文件不存在"
    fi
}

check_parameters_status() {
    print_header "參數配置狀態"
    
    print_warning "以下參數需要手動配置："
    echo "  1. Slack Webhook URL"
    echo "  2. Slack 簽名密鑰"
    echo "  3. Slack Bot Token"
    echo ""
    print_info "使用以下命令配置參數："
    echo "  scripts/setup-parameters.sh --all --auto-read --secure \\"
    echo "    --slack-webhook 'https://hooks.slack.com/services/...' \\"
    echo "    --slack-secret 'your-signing-secret' \\"
    echo "    --slack-bot-token 'xoxb-your-bot-token'"
}

check_lambda_functions() {
    print_header "Lambda 函數檢查"
    
    local functions=("slack-webhook" "query-vpn-status" "delete-vpn-connection")
    
    for func in "${functions[@]}"; do
        if [ -d "lambda/functions/$func/dist" ]; then
            print_success "Lambda 函數 $func 已構建"
        else
            print_warning "Lambda 函數 $func 構建目錄不存在"
        fi
    done
}

print_next_steps() {
    print_header "後續步驟"
    
    echo "1. 配置 Slack 參數（必需）："
    echo "   scripts/setup-parameters.sh --all --auto-read --secure \\"
    echo "     --slack-webhook 'YOUR_WEBHOOK_URL' \\"
    echo "     --slack-secret 'YOUR_SIGNING_SECRET' \\"
    echo "     --slack-bot-token 'YOUR_BOT_TOKEN'"
    echo ""
    echo "2. 測試 API 端點："
    echo "   curl -X POST [API_GATEWAY_URL]/webhook"
    echo ""
    echo "3. 驗證 Slack 整合："
    echo "   在 Slack 中使用斜線命令測試"
    echo ""
    echo "4. 監控 CloudWatch 日誌："
    echo "   檢查 Lambda 函數執行日誌"
}

main() {
    print_header "VPN 管理工具 - 部署後檢查"
    
    check_deployment_status
    check_lambda_functions
    check_parameters_status
    print_next_steps
    
    print_header "檢查完成"
    print_info "系統已部署但需要配置參數才能正常運作"
}

main "$@"
