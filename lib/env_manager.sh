#!/bin/bash

# Environment Manager for nlInc-vpnMgmtTools
# 環境管理器 - 提供雙環境支援的核心功能
# Version: 1.0
# Date: 2025-05-24

# 設定腳本路徑
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CURRENT_ENV_FILE="$PROJECT_ROOT/.current_env"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 載入當前環境設定
load_current_env() {
    if [[ -f "$CURRENT_ENV_FILE" ]]; then
        source "$CURRENT_ENV_FILE"
    else
        CURRENT_ENVIRONMENT="staging"
        echo "CURRENT_ENVIRONMENT=staging" > "$CURRENT_ENV_FILE"
        echo "LAST_SWITCHED_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CURRENT_ENV_FILE"
        echo "SWITCHED_BY=system" >> "$CURRENT_ENV_FILE"
    fi
}

# 顯示當前環境狀態
env_current() {
    load_current_env
    
    # 載入環境配置以獲取顯示資訊
    local env_file="$PROJECT_ROOT/${CURRENT_ENVIRONMENT}.env"
    if [[ -f "$env_file" ]]; then
        source "$env_file"
        local icon="${ENV_ICON:-⚪}"
        local display_name="${ENV_DISPLAY_NAME:-$CURRENT_ENVIRONMENT}"
        
        echo -e "\n=== 當前 VPN 環境狀態 ==="
        echo -e "環境: ${icon} ${display_name}"
        echo -e "名稱: ${CURRENT_ENVIRONMENT}"
        echo -e "最後切換: ${LAST_SWITCHED_TIME:-未知}"
        echo -e "切換者: ${SWITCHED_BY:-未知}"
        
        # 檢查環境健康狀態
        if env_health_check "${CURRENT_ENVIRONMENT}"; then
            echo -e "狀態: ${GREEN}🟢 健康${NC}"
        else
            echo -e "狀態: ${YELLOW}🟡 警告${NC}"
        fi
        echo "========================"
    else
        echo -e "${RED}錯誤: 找不到環境配置檔案 $env_file${NC}"
        return 1
    fi
}

# 切換環境
env_switch() {
    local target_env="$1"
    
    if [[ -z "$target_env" ]]; then
        echo -e "${RED}錯誤: 請指定目標環境 (staging 或 production)${NC}"
        return 1
    fi
    
    # 驗證目標環境是否存在
    local target_env_file="$PROJECT_ROOT/${target_env}.env"
    if [[ ! -f "$target_env_file" ]]; then
        echo -e "${RED}錯誤: 環境 '$target_env' 不存在${NC}"
        echo "可用環境: staging, production"
        return 1
    fi
    
    load_current_env
    
    # 如果已經是目標環境，直接返回
    if [[ "$CURRENT_ENVIRONMENT" == "$target_env" ]]; then
        echo -e "${YELLOW}已經在 $target_env 環境中${NC}"
        env_current
        return 0
    fi
    
    # 載入目標環境資訊以顯示切換確認
    source "$target_env_file"
    local target_icon="${ENV_ICON:-⚪}"
    local target_display_name="${ENV_DISPLAY_NAME:-$target_env}"
    
    # 顯示切換確認
    echo -e "\n🔄 ${BLUE}環境切換確認${NC}"
    echo -e "從: $(get_env_display_info "$CURRENT_ENVIRONMENT")"
    echo -e "到: ${target_icon} ${target_display_name}"
    echo ""
    echo "此操作將："
    echo "• 切換所有後續操作到 $target_env 環境"
    echo "• 載入 $target_env 環境配置"
    echo "• 記錄環境切換歷史"
    echo ""
    
    # 如果是 production 環境，需要額外確認
    if [[ "$target_env" == "production" ]]; then
        echo -e "${RED}⚠️  警告: 您即將切換到 Production 環境${NC}"
        echo -e "${RED}   請確保您了解此操作的影響${NC}"
        echo ""
    fi
    
    read -p "確認切換？ [yes/NO]: " confirm
    if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${YELLOW}環境切換已取消${NC}"
        return 1
    fi
    
    # 執行環境切換
    if perform_env_switch "$target_env"; then
        echo -e "${GREEN}✅ 環境切換成功${NC}"
        env_current
    else
        echo -e "${RED}❌ 環境切換失敗${NC}"
        return 1
    fi
}

# 載入環境配置
env_load_config() {
    local env_name="${1:-$CURRENT_ENVIRONMENT}"
    
    if [[ -z "$env_name" ]]; then
        load_current_env
        env_name="$CURRENT_ENVIRONMENT"
    fi
    
    local env_file="$PROJECT_ROOT/${env_name}.env"
    if [[ -f "$env_file" ]]; then
        source "$env_file"
        
        # 設定環境特定的目錄路徑
        export VPN_CERT_DIR="$PROJECT_ROOT/$CERT_DIR"
        export VPN_CONFIG_DIR="$PROJECT_ROOT/$CONFIG_DIR"
        export VPN_LOG_DIR="$PROJECT_ROOT/$LOG_DIR"
        
        # 建立必要的目錄
        mkdir -p "$VPN_CERT_DIR" "$VPN_CONFIG_DIR" "$VPN_LOG_DIR"
        
        echo -e "${GREEN}✅ 已載入 $env_name 環境配置${NC}"
        return 0
    else
        echo -e "${RED}錯誤: 找不到環境配置檔案 $env_file${NC}"
        return 1
    fi
}

# 執行環境切換的內部函式
perform_env_switch() {
    local target_env="$1"
    local current_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local current_user="${USER:-unknown}"
    
    # 更新當前環境檔案
    cat > "$CURRENT_ENV_FILE" << EOF
CURRENT_ENVIRONMENT=$target_env
LAST_SWITCHED_TIME=$current_time
SWITCHED_BY=$current_user
EOF
    
    # 驗證切換是否成功
    if [[ -f "$CURRENT_ENV_FILE" ]]; then
        # 載入新環境配置
        env_load_config "$target_env"
        return 0
    else
        return 1
    fi
}

# 獲取環境顯示資訊
get_env_display_info() {
    local env_name="$1"
    local env_file="$PROJECT_ROOT/${env_name}.env"
    
    if [[ -f "$env_file" ]]; then
        local ENV_ICON ENV_DISPLAY_NAME
        source "$env_file"
        echo "${ENV_ICON:-⚪} ${ENV_DISPLAY_NAME:-$env_name}"
    else
        echo "⚪ $env_name"
    fi
}

# 環境健康檢查
env_health_check() {
    local env_name="$1"
    local env_file="$PROJECT_ROOT/${env_name}.env"
    
    # 基本檢查：配置檔案存在
    if [[ ! -f "$env_file" ]]; then
        return 1
    fi
    
    # 載入配置並檢查必要目錄
    source "$env_file"
    local cert_dir="$PROJECT_ROOT/$CERT_DIR"
    local config_dir="$PROJECT_ROOT/$CONFIG_DIR"
    
    # 檢查目錄是否存在且可寫入
    if [[ ! -d "$cert_dir" ]] || [[ ! -w "$cert_dir" ]]; then
        return 1
    fi
    
    if [[ ! -d "$config_dir" ]] || [[ ! -w "$config_dir" ]]; then
        return 1
    fi
    
    return 0
}

# 列出所有可用環境
env_list() {
    echo -e "\n=== 可用的 VPN 環境 ==="
    
    local current_env
    load_current_env
    current_env="$CURRENT_ENVIRONMENT"
    
    for env_file in "$PROJECT_ROOT"/*.env; do
        if [[ -f "$env_file" ]]; then
            local env_name=$(basename "$env_file" .env)
            source "$env_file"
            
            local icon="${ENV_ICON:-⚪}"
            local display_name="${ENV_DISPLAY_NAME:-$env_name}"
            local status=""
            
            if [[ "$env_name" == "$current_env" ]]; then
                status="${GREEN}(當前)${NC}"
            fi
            
            echo -e "  ${icon} ${display_name} ${status}"
        fi
    done
    echo "========================"
}

# 環境選擇器介面
env_selector() {
    while true; do
        clear
        echo -e "=== ${BLUE}AWS Client VPN 多環境管理控制台${NC} ==="
        echo ""
        
        # 顯示當前環境
        load_current_env
        local current_display=$(get_env_display_info "$CURRENT_ENVIRONMENT")
        echo -e "當前環境: ${current_display} ${GREEN}(活躍)${NC}"
        echo ""
        
        # 顯示可用環境
        echo "可用環境:"
        local counter=1
        for env_file in "$PROJECT_ROOT"/*.env; do
            if [[ -f "$env_file" ]]; then
                local env_name=$(basename "$env_file" .env)
                source "$env_file"
                
                local icon="${ENV_ICON:-⚪}"
                local display_name="${ENV_DISPLAY_NAME:-$env_name}"
                local description=""
                
                case "$env_name" in
                    staging)
                        description="開發測試環境"
                        ;;
                    production)
                        description="生產營運環境"
                        ;;
                esac
                
                echo "  ${counter}. ${icon} ${env_name} - ${description}"
                counter=$((counter + 1))
            fi
        done
        
        echo ""
        echo "快速操作:"
        echo "  [S] 環境狀態    [H] 健康檢查    [Q] 退出"
        echo ""
        
        read -p "請選擇環境或操作 [1-2/S/H/Q]: " choice
        
        case "$choice" in
            1)
                env_switch "staging"
                read -p "按 Enter 繼續..."
                ;;
            2)
                env_switch "production"
                read -p "按 Enter 繼續..."
                ;;
            [Ss])
                env_current
                read -p "按 Enter 繼續..."
                ;;
            [Hh])
                echo "檢查環境健康狀態..."
                for env_file in "$PROJECT_ROOT"/*.env; do
                    if [[ -f "$env_file" ]]; then
                        local env_name=$(basename "$env_file" .env)
                        if env_health_check "$env_name"; then
                            echo -e "${env_name}: ${GREEN}🟢 健康${NC}"
                        else
                            echo -e "${env_name}: ${YELLOW}🟡 警告${NC}"
                        fi
                    fi
                done
                read -p "按 Enter 繼續..."
                ;;
            [Qq])
                echo -e "${BLUE}感謝使用 AWS Client VPN 管理工具${NC}"
                break
                ;;
            *)
                echo -e "${RED}無效的選擇，請重新輸入${NC}"
                sleep 1
                ;;
        esac
    done
}

# 初始化環境管理器
env_init() {
    # 建立必要的目錄結構
    mkdir -p "$PROJECT_ROOT/certs/staging" \
             "$PROJECT_ROOT/certs/production" \
             "$PROJECT_ROOT/configs/staging" \
             "$PROJECT_ROOT/configs/production" \
             "$PROJECT_ROOT/logs/staging" \
             "$PROJECT_ROOT/logs/production"
    
    # 初始化當前環境檔案
    if [[ ! -f "$CURRENT_ENV_FILE" ]]; then
        echo "CURRENT_ENVIRONMENT=staging" > "$CURRENT_ENV_FILE"
        echo "LAST_SWITCHED_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CURRENT_ENV_FILE"
        echo "SWITCHED_BY=system" >> "$CURRENT_ENV_FILE"
    fi
    
    echo -e "${GREEN}✅ 環境管理器初始化完成${NC}"
}

# 主程式入口點
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        current)
            env_current
            ;;
        switch)
            env_switch "$2"
            ;;
        load)
            env_load_config "$2"
            ;;
        list)
            env_list
            ;;
        selector)
            env_selector
            ;;
        init)
            env_init
            ;;
        health)
            env_health_check "$2"
            ;;
        *)
            echo "使用方式: $0 {current|switch <env>|load <env>|list|selector|init|health <env>}"
            echo ""
            echo "命令說明:"
            echo "  current          顯示當前環境狀態"
            echo "  switch <env>     切換到指定環境"
            echo "  load <env>       載入環境配置"
            echo "  list             列出所有可用環境"
            echo "  selector         啟動互動式環境選擇器"
            echo "  init             初始化環境管理器"
            echo "  health <env>     檢查環境健康狀態"
            exit 1
            ;;
    esac
fi
