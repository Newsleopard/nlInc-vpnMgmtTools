#!/bin/bash

# 載入核心函式庫以使用顏色和日誌
source "$(dirname "${BASH_SOURCE[0]}")/core_functions.sh"

# 設定 AWS 配置
# 需要主腳本傳遞 CONFIG_FILE 變數
setup_aws_config() {
    local main_config_file="$1" # 接收主腳本的 CONFIG_FILE 路徑

    echo -e "\n${YELLOW}設定 AWS 配置...${NC}"
    
    if [ ! -f ~/.aws/credentials ] || [ ! -f ~/.aws/config ]; then
        echo -e "${YELLOW}請提供您的 AWS 管理員帳戶資訊：${NC}"
        
        read -p "請輸入 AWS Access Key ID: " aws_access_key
        read -s -p "請輸入 AWS Secret Access Key: " aws_secret_key
        echo
        read -p "請輸入 AWS 區域 (例如 ap-northeast-1): " aws_region
        
        # 創建配置目錄和文件
        mkdir -p ~/.aws
        
        # 寫入認證
        cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = $aws_access_key
aws_secret_access_key = $aws_secret_key
EOF
        
        # 寫入配置
        cat > ~/.aws/config << EOF
[default]
region = $aws_region
output = json
EOF
        
        echo -e "${BLUE}正在驗證 AWS 憑證...${NC}"
        if aws sts get-caller-identity --output text --query 'Arn' > /dev/null 2>&1; then
            echo -e "${GREEN}AWS 憑證驗證成功！${NC}"
            log_message "AWS 憑證驗證成功。"
            echo -e "${GREEN}AWS 配置已完成！${NC}"
        else
            log_message "AWS 憑證驗證失敗。"
            # 使用 core_functions.sh 中的 handle_error
            # 注意：handle_error 預設會退出腳本。如果不想退出，需要傳遞第三個參數 0。
            # 在設定階段，如果憑證無效，退出可能是合理的。
            handle_error "AWS 憑證無效或權限不足。請檢查您輸入的 Access Key ID、Secret Access Key 和區域是否正確，以及帳戶是否具有必要的權限。" "$?" 1
            # 如果 handle_error 終止了腳本，以下程式碼將不會執行
            # 如果選擇不終止，則需要額外的邏輯讓使用者重試或接受風險
            echo -e "${RED}AWS 配置失敗，憑證驗證未通過。${NC}"
            return 1 # 表示設定失敗
        fi
    else
        echo -e "${GREEN}✓ AWS 配置檔案已存在。${NC}"
        # 即使檔案存在，也嘗試獲取當前 region
        # 如果 aws configure get region 失敗，可能表示配置不完整或 aws cli 有問題
        current_region=$(aws configure get region 2>/dev/null)
        if [ -n "$current_region" ]; then
            aws_region="$current_region"
            echo -e "${BLUE}當前 AWS 區域設定為: $aws_region${NC}"
            # 建議：即使檔案存在，也應該提供一個選項來驗證憑證，或至少提示使用者憑證的有效性未在此處驗證
            # 根據第一階段計劃，暫不修改此處邏輯，但標記為未來改進
            # TODO: Offer to validate/update existing AWS credentials
        else
            # 如果無法獲取 region，可能需要重新設定
            log_message "警告：無法從現有 AWS 配置中獲取區域。可能需要重新設定。"
            echo -e "${YELLOW}警告：無法從現有 AWS 配置中獲取區域。建議檢查 ~/.aws/config 或重新執行設定。${NC}"
            # 這裡可以選擇提示使用者重新設定，或者直接使用一個預設值/空值，然後依賴 validate_main_config 捕捉
            # 為了安全起見，如果無法獲取 region，則不應盲目寫入 main_config_file
            # 可以讓使用者手動處理或在主腳本中提示
            echo -e "${RED}無法自動確定 AWS 區域。請手動檢查或重新執行設定。${NC}"
            return 1 # 表示設定不完整
        fi
    fi
    
    # 只有在成功獲取或設定 aws_region 後才保存
    if [ -n "$aws_region" ]; then
        echo "AWS_REGION=$aws_region" > "$main_config_file"
        log_message "AWS 配置已更新，區域: $aws_region"
    else
        log_message "錯誤：AWS 區域未能成功設定或獲取。"
        # 此情況應已被上面的 return 1 處理
    fi
}
