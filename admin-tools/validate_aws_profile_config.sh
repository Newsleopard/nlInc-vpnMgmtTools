#!/bin/bash

# AWS Profile 與環境設定驗證腳本
# 用於驗證環境設置檔與 AWS Profile 關聯是否正確設定

# 設定腳本路徑
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# 載入環境管理器
if [[ -f "$PROJECT_ROOT/lib/env_manager.sh" ]]; then
    source "$PROJECT_ROOT/lib/env_manager.sh"
else
    echo "錯誤: 找不到環境管理器 lib/env_manager.sh"
    exit 1
fi

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 顯示標題
show_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}AWS Profile 與環境設定關聯驗證${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

# 驗證環境設置檔
validate_environment_config() {
    local env_name="$1"
    local env_file="$PROJECT_ROOT/configs/${env_name}/${env_name}.env"
    
    echo -e "${CYAN}檢查 ${env_name} 環境設置檔...${NC}"
    
    if [[ ! -f "$env_file" ]]; then
        echo -e "  ${RED}✗ 設置檔不存在: $env_file${NC}"
        return 1
    fi
    
    echo -e "  ${GREEN}✓ 設置檔存在: $env_file${NC}"
    
    # 檢查關鍵變數
    local aws_profile
    aws_profile=$(grep "^AWS_PROFILE=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    
    if [[ -n "$aws_profile" ]]; then
        echo -e "  ${GREEN}✓ AWS_PROFILE 已設定: $aws_profile${NC}"
    else
        echo -e "  ${YELLOW}⚠ AWS_PROFILE 未設定${NC}"
    fi
    
    # 檢查其他重要變數
    local env_vars=("ENV_NAME" "ENV_DISPLAY_NAME" "AWS_REGION" "VPN_CIDR" "VPN_NAME")
    for var in "${env_vars[@]}"; do
        if grep -q "^${var}=" "$env_file"; then
            local value=$(grep "^${var}=" "$env_file" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
            echo -e "  ${GREEN}✓ $var: $value${NC}"
        else
            echo -e "  ${YELLOW}⚠ $var 未設定${NC}"
        fi
    done
    
    echo ""
    return 0
}

# 驗證 AWS Profile 可用性
validate_aws_profile_availability() {
    local env_name="$1"
    
    echo -e "${CYAN}檢查 ${env_name} 環境的 AWS Profile 可用性...${NC}"
    
    # 載入環境配置
    local env_file="$PROJECT_ROOT/configs/${env_name}/${env_name}.env"
    if [[ -f "$env_file" ]]; then
        source "$env_file"
    fi
    
    # 獲取 Profile
    local profile
    if [[ -f "$PROJECT_ROOT/lib/env_core.sh" ]]; then
        source "$PROJECT_ROOT/lib/env_core.sh"
        profile=$(get_env_profile "$env_name")
    fi
    
    if [[ -z "$profile" ]]; then
        echo -e "  ${RED}✗ 無法確定 AWS Profile${NC}"
        return 1
    fi
    
    echo -e "  ${BLUE}目標 Profile: $profile${NC}"
    
    # 檢查 AWS CLI 是否可用
    if ! command -v aws &> /dev/null; then
        echo -e "  ${YELLOW}⚠ AWS CLI 未安裝，無法驗證 Profile${NC}"
        return 0
    fi
    
    # 檢查 Profile 是否存在
    if ! aws configure list-profiles | grep -q "^$profile$"; then
        echo -e "  ${RED}✗ AWS Profile '$profile' 不存在${NC}"
        echo -e "  ${YELLOW}建議執行: aws configure --profile $profile${NC}"
        return 1
    fi
    
    echo -e "  ${GREEN}✓ AWS Profile '$profile' 存在${NC}"
    
    # 檢查 Profile 是否可以驗證身份
    if aws sts get-caller-identity --profile "$profile" &>/dev/null; then
        local account_id region
        account_id=$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null)
        region=$(aws configure get region --profile "$profile" 2>/dev/null)
        
        echo -e "  ${GREEN}✓ Profile 身份驗證成功${NC}"
        [[ -n "$account_id" ]] && echo -e "  ${BLUE}  帳戶 ID: $account_id${NC}"
        [[ -n "$region" ]] && echo -e "  ${BLUE}  區域: $region${NC}"
    else
        echo -e "  ${RED}✗ Profile 身份驗證失敗${NC}"
        echo -e "  ${YELLOW}請檢查 AWS credentials 是否正確設定${NC}"
        return 1
    fi
    
    echo ""
    return 0
}

# 測試環境切換和 Profile 載入
test_environment_switching() {
    echo -e "${CYAN}測試環境切換和 Profile 載入...${NC}"
    
    # 保存當前環境
    load_current_env
    local original_env="$CURRENT_ENVIRONMENT"
    
    # 測試環境
    local test_envs=("staging" "production")
    
    for env in "${test_envs[@]}"; do
        echo -e "  ${BLUE}測試切換到 $env 環境...${NC}"
        
        # 嘗試載入環境配置
        if env_load_config "$env" &>/dev/null; then
            echo -e "    ${GREEN}✓ 環境配置載入成功${NC}"
            
            # 檢查 AWS_PROFILE 是否正確設定
            if [[ -n "$AWS_PROFILE" ]]; then
                echo -e "    ${GREEN}✓ AWS_PROFILE 已設定: $AWS_PROFILE${NC}"
            else
                echo -e "    ${YELLOW}⚠ AWS_PROFILE 未設定${NC}"
            fi
        else
            echo -e "    ${RED}✗ 環境配置載入失敗${NC}"
        fi
    done
    
    # 恢復原始環境
    if [[ -n "$original_env" ]]; then
        env_load_config "$original_env" &>/dev/null
    fi
    
    echo ""
}

# 顯示建議和最佳實踐
show_recommendations() {
    echo -e "${CYAN}建議和最佳實踐:${NC}"
    echo -e "  ${BLUE}1.${NC} 確保每個環境都有對應的 AWS Profile"
    echo -e "  ${BLUE}2.${NC} Staging 和 Production 應使用不同的 AWS 帳戶"
    echo -e "  ${BLUE}3.${NC} 定期驗證 AWS Profile 的有效性"
    echo -e "  ${BLUE}4.${NC} 使用 MFA 增強 Production 環境安全性"
    echo -e "  ${BLUE}5.${NC} 定期檢查和更新環境設置檔"
    echo ""
}

# 主執行函數
main() {
    show_header
    
    # 檢查基本環境
    local environments=("staging" "production")
    local overall_status=0
    
    for env in "${environments[@]}"; do
        echo -e "${YELLOW}=== 驗證 $env 環境 ===${NC}"
        
        if ! validate_environment_config "$env"; then
            overall_status=1
        fi
        
        if ! validate_aws_profile_availability "$env"; then
            overall_status=1
        fi
    done
    
    # 測試環境切換
    test_environment_switching
    
    # 顯示總結
    echo -e "${YELLOW}=== 驗證總結 ===${NC}"
    if [[ $overall_status -eq 0 ]]; then
        echo -e "${GREEN}✅ 所有檢查通過，AWS Profile 與環境設定關聯正確${NC}"
    else
        echo -e "${RED}❌ 發現問題，請根據上述建議進行修正${NC}"
    fi
    
    echo ""
    show_recommendations
    
    return $overall_status
}

# 執行主程式
main "$@"