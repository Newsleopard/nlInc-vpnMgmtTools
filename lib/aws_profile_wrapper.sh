#!/bin/bash

# AWS 命令增強封裝
# 確保所有 AWS CLI 命令都使用正確的 Profile
# 這個腳本提供統一的 AWS CLI 命令包裝器

# 獲取當前環境的 AWS Profile
get_current_aws_profile() {
    # 優先順序:
    # 1. ENV_AWS_PROFILE (環境特定設定)
    # 2. AWS_PROFILE (標準設定)
    # 3. 從環境配置檔讀取
    
    if [[ -n "$ENV_AWS_PROFILE" ]]; then
        echo "$ENV_AWS_PROFILE"
        return 0
    fi
    
    if [[ -n "$AWS_PROFILE" ]]; then
        echo "$AWS_PROFILE"
        return 0
    fi
    
    # 嘗試從當前環境配置讀取
    if [[ -f "$(dirname "${BASH_SOURCE[0]}")/env_core.sh" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/env_core.sh"
        if command -v get_env_profile &>/dev/null; then
            local current_env="${CURRENT_ENVIRONMENT:-staging}"
            local profile
            profile=$(get_env_profile "$current_env" 2>/dev/null)
            if [[ -n "$profile" ]]; then
                echo "$profile"
                return 0
            fi
        fi
    fi
    
    # 回退到預設
    echo "default"
}

# 安全的 AWS CLI 命令執行
# 自動添加 --profile 參數（如果尚未指定）
aws_safe() {
    local profile
    profile=$(get_current_aws_profile)
    
    # 檢查命令是否已經包含 --profile 參數
    local has_profile=false
    local args=("$@")
    for ((i=0; i<${#args[@]}; i++)); do
        if [[ "${args[i]}" == "--profile" ]]; then
            has_profile=true
            break
        fi
    done
    
    # 如果沒有 --profile 參數，添加它
    if [[ "$has_profile" == "false" ]]; then
        # 在 AWS 子命令之前插入 --profile
        # 例如: aws ec2 describe-vpcs -> aws --profile xxx ec2 describe-vpcs
        if [[ ${#args[@]} -gt 0 ]]; then
            aws --profile "$profile" "${args[@]}"
        else
            aws --profile "$profile"
        fi
    else
        # 已有 --profile 參數，直接執行
        aws "${args[@]}"
    fi
}

# 顯示當前 AWS Profile 資訊
show_aws_profile_info() {
    local profile
    profile=$(get_current_aws_profile)
    
    echo "當前 AWS Profile: $profile"
    
    if command -v aws &>/dev/null; then
        if aws configure list-profiles | grep -q "^$profile$"; then
            echo "Profile 狀態: 存在"
            if aws sts get-caller-identity --profile "$profile" &>/dev/null; then
                echo "認證狀態: 有效"
                local account_id region
                account_id=$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null)
                region=$(aws configure get region --profile "$profile" 2>/dev/null)
                [[ -n "$account_id" ]] && echo "帳戶 ID: $account_id"
                [[ -n "$region" ]] && echo "區域: $region"
            else
                echo "認證狀態: 無效"
            fi
        else
            echo "Profile 狀態: 不存在"
        fi
    else
        echo "AWS CLI: 未安裝"
    fi
}

# 如果直接執行此腳本，顯示 Profile 資訊
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_aws_profile_info
fi