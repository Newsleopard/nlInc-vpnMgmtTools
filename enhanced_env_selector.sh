#!/bin/bash

# Enhanced Environment Selector for AWS VPN Management
# 增強版環境選擇器 - 階段三實施
# Version: 2.0
# Date: 2025-05-24

# 設定腳本路徑
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
ENV_MANAGER="$SCRIPT_DIR/lib/env_manager.sh"

# 檢查環境管理器是否存在
if [[ ! -f "$ENV_MANAGER" ]]; then
    echo "錯誤: 找不到環境管理器 $ENV_MANAGER"
    exit 1
fi

# 載入環境管理器
source "$ENV_MANAGER"

# 載入增強確認模組
source "$PROJECT_ROOT/lib/enhanced_confirmation.sh"

# 增強顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
NC='\033[0m' # No Color

# 狀態圖示定義
STATUS_HEALTHY="🟢"
STATUS_WARNING="🟡"
STATUS_ERROR="🔴"
STATUS_UNKNOWN="⚪"
STATUS_CHECKING="🔄"

# 獲取環境連線數 (模擬)
get_env_connection_count() {
    local env_name="$1"
    
    # 這裡應該實際查詢 AWS Client VPN 的連線數
    # 暫時使用模擬數據
    case "$env_name" in
        staging)
            echo "3"
            ;;
        production)
            echo "8"
            ;;
        *)
            echo "0"
            ;;
    esac
}

# 獲取環境資源使用狀態 (模擬)
get_env_resource_usage() {
    local env_name="$1"
    
    # 這裡應該實際查詢 AWS 資源使用情況
    # 暫時使用模擬數據
    case "$env_name" in
        staging)
            echo "CPU: 15% | MEM: 32% | NET: 2.3MB/s"
            ;;
        production)
            echo "CPU: 45% | MEM: 67% | NET: 8.1MB/s"
            ;;
        *)
            echo "CPU: --% | MEM: --% | NET: --MB/s"
            ;;
    esac
}

# 檢查證書有效性
check_certificate_validity() {
    local env_name="$1"
    local env_file="$PROJECT_ROOT/configs/${env_name}/${env_name}.env"
    
    if [[ ! -f "$env_file" ]]; then
        return 1
    fi
    
    source "$env_file"
    local cert_dir="$PROJECT_ROOT/$CERT_DIR"
    local ca_cert="$cert_dir/ca.crt"
    
    # 檢查證書檔案是否存在
    if [[ ! -f "$ca_cert" ]]; then
        return 1
    fi
    
    # 檢查證書是否即將到期 (模擬檢查，實際應使用 openssl)
    # 這裡假設證書都是有效的
    return 0
}

# 檢查 VPN 端點狀態
check_vpn_endpoint_status() {
    local env_name="$1"
    local env_file="$PROJECT_ROOT/configs/${env_name}/${env_name}.env"
    
    if [[ ! -f "$env_file" ]]; then
        return 1
    fi
    
    source "$env_file"
    
    # 這裡應該實際使用 AWS CLI 查詢端點狀態
    # aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids $ENDPOINT_ID
    # 暫時使用模擬檢查
    
    # 檢查環境變數是否設定
    if [[ -n "$ENDPOINT_ID" && -n "$AWS_REGION" ]]; then
        return 0
    else
        return 1
    fi
}

# 綜合環境健康檢查
enhanced_env_health_check() {
    local env_name="$1"
    local health_score=0
    local status_icon="$STATUS_UNKNOWN"
    local status_text="未知"
    
    # 基本健康檢查
    if env_health_check "$env_name"; then
        health_score=$((health_score + 25))
    fi
    
    # 證書有效性檢查
    if check_certificate_validity "$env_name"; then
        health_score=$((health_score + 25))
    fi
    
    # VPN 端點狀態檢查
    if check_vpn_endpoint_status "$env_name"; then
        health_score=$((health_score + 25))
    fi
    
    # 配置完整性檢查
    local env_file="$PROJECT_ROOT/configs/${env_name}/${env_name}.env"
    if [[ -f "$env_file" ]]; then
        source "$env_file"
        if [[ -n "$AWS_REGION" && -n "$VPN_CIDR" && -n "$PRIMARY_VPC_ID" ]]; then
            health_score=$((health_score + 25))
        fi
    fi
    
    # 根據分數確定狀態
    if [[ $health_score -ge 90 ]]; then
        status_icon="$STATUS_HEALTHY"
        status_text="健康"
    elif [[ $health_score -ge 70 ]]; then
        status_icon="$STATUS_WARNING"
        status_text="警告"
    elif [[ $health_score -ge 50 ]]; then
        status_icon="$STATUS_ERROR"
        status_text="錯誤"
    else
        status_icon="$STATUS_UNKNOWN"
        status_text="未知"
    fi
    
    echo "$status_icon $status_text (${health_score}%)"
}

# 顯示環境詳細資訊
show_env_details() {
    local env_name="$1"
    local env_file="$PROJECT_ROOT/configs/${env_name}/${env_name}.env"
    
    if [[ ! -f "$env_file" ]]; then
        echo -e "${RED}環境配置檔案不存在${NC}"
        return 1
    fi
    
    source "$env_file"
    
    echo -e "${CYAN}${BOLD}=== 環境詳細資訊: $env_name ===${NC}"
    echo -e "${BLUE}基本資訊:${NC}"
    echo -e "  名稱: ${ENV_DISPLAY_NAME:-$env_name}"
    echo -e "  圖示: ${ENV_ICON:-⚪}"
    echo -e "  AWS 區域: ${AWS_REGION:-未設定}"
    echo -e "  VPN CIDR: ${VPN_CIDR:-未設定}"
    echo ""
    
    echo -e "${BLUE}連線資訊:${NC}"
    echo -e "  活躍連線: $(get_env_connection_count "$env_name") 個"
    echo -e "  端點 ID: ${ENDPOINT_ID:-未設定}"
    echo -e "  主要 VPC: ${PRIMARY_VPC_ID:-未設定}"
    echo ""
    
    echo -e "${BLUE}資源使用:${NC}"
    echo -e "  $(get_env_resource_usage "$env_name")"
    echo ""
    
    echo -e "${BLUE}健康狀態:${NC}"
    echo -e "  $(enhanced_env_health_check "$env_name")"
    echo -e "  最後檢查: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    echo -e "${BLUE}安全設定:${NC}"
    echo -e "  MFA 要求: ${REQUIRE_MFA_FOR_ADMIN:-false}"
    echo -e "  操作確認: ${REQUIRE_OPERATION_CONFIRMATION:-false}"
    echo -e "  審計日誌: ${ENABLE_AUDIT_LOGGING:-true}"
    echo ""
    
    echo -e "${BLUE}目錄路徑:${NC}"
    echo -e "  證書目錄: $CERT_DIR"
    echo -e "  配置目錄: $CONFIG_DIR"
    echo -e "  日誌目錄: $LOG_DIR"
    echo ""
}

# 環境比較功能
compare_environments() {
    echo -e "${CYAN}${BOLD}=== 環境比較 ===${NC}"
    echo ""
    
    # 獲取所有環境
    local envs=()
    for env_dir in "$PROJECT_ROOT/configs"/*; do
        if [[ -d "$env_dir" ]]; then
            local env_name=$(basename "$env_dir")
            local env_file="$env_dir/${env_name}.env"
            if [[ -f "$env_file" ]]; then
                envs+=("$env_name")
            fi
        fi
    done
    
    if [[ ${#envs[@]} -eq 0 ]]; then
        echo -e "${RED}未找到任何環境配置${NC}"
        return 1
    fi
    
    # 表格標題
    printf "%-15s %-20s %-10s %-15s %-15s\n" "環境" "顯示名稱" "連線數" "健康狀態" "最後檢查"
    echo "─────────────────────────────────────────────────────────────────────────────"
    
    # 顯示每個環境的資訊
    for env_name in "${envs[@]}"; do
        local env_file="$PROJECT_ROOT/configs/${env_name}/${env_name}.env"
        source "$env_file"
        
        local display_name="${ENV_DISPLAY_NAME:-$env_name}"
        local connection_count=$(get_env_connection_count "$env_name")
        local health_status=$(enhanced_env_health_check "$env_name")
        local last_check=$(date '+%H:%M:%S')
        
        printf "%-15s %-20s %-10s %-25s %-15s\n" \
            "${ENV_ICON:-⚪} $env_name" \
            "$display_name" \
            "$connection_count" \
            "$health_status" \
            "$last_check"
    done
    echo ""
}

# 快速操作選單
show_quick_operations() {
    echo -e "${PURPLE}${BOLD}快速操作:${NC}"
    echo -e "  ${BOLD}[E]${NC} 切換環境    ${BOLD}[S]${NC} 環境狀態    ${BOLD}[H]${NC} 健康檢查"
    echo -e "  ${BOLD}[D]${NC} 詳細資訊    ${BOLD}[C]${NC} 環境比較    ${BOLD}[R]${NC} 重新整理"
    echo -e "  ${BOLD}[Q]${NC} 退出"
    echo ""
}

# 增強版環境選擇器主介面
enhanced_env_selector() {
    while true; do
        clear
        
        # 標題
        echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}${BOLD}║               AWS Client VPN 多環境管理控制台 v2.0               ║${NC}"
        echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # 顯示當前環境
        load_current_env
        local current_display=$(get_env_display_info "$CURRENT_ENVIRONMENT")
        local current_health=$(enhanced_env_health_check "$CURRENT_ENVIRONMENT")
        echo -e "${BOLD}當前環境:${NC} ${GREEN}${current_display} (活躍)${NC}"
        echo -e "${BOLD}健康狀態:${NC} ${current_health}"
        echo -e "${BOLD}連線數量:${NC} $(get_env_connection_count "$CURRENT_ENVIRONMENT") 個活躍連線"
        echo -e "${BOLD}最後更新:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        
        # 顯示所有可用環境
        echo -e "${BLUE}${BOLD}可用環境:${NC}"
        local counter=1
        for env_dir in "$PROJECT_ROOT/configs"/*; do
            if [[ -d "$env_dir" ]]; then
                local env_name=$(basename "$env_dir")
                local env_file="$env_dir/${env_name}.env"
                if [[ -f "$env_file" ]]; then
                    source "$env_file"
                    
                    local icon="${ENV_ICON:-⚪}"
                    local display_name="${ENV_DISPLAY_NAME:-$env_name}"
                    local description=""
                    local connection_count=$(get_env_connection_count "$env_name")
                    local health_status=$(enhanced_env_health_check "$env_name")
                    
                    case "$env_name" in
                        staging)
                            description="開發測試環境"
                            ;;
                        production)
                            description="生產營運環境"
                            ;;
                        *)
                            description="自訂環境"
                            ;;
                    esac
                    
                    # 標示當前環境
                    local current_marker=""
                    if [[ "$env_name" == "$CURRENT_ENVIRONMENT" ]]; then
                        current_marker="${GREEN} ← 當前${NC}"
                    fi
                    
                    echo -e "  ${BOLD}${counter}.${NC} ${icon} ${BOLD}${display_name}${NC} - ${description}${current_marker}"
                    echo -e "      連線: ${connection_count} 個 | 狀態: ${health_status}"
                    echo ""
                    counter=$((counter + 1))
                fi
            fi
        done
        
        # 快速操作選單
        show_quick_operations
        
        # 讀取用戶輸入
        read -p "請選擇環境或操作 [1-2/E/S/H/D/C/R/Q]: " choice
        
        case "$choice" in
            1)
                env_switch "staging"
                read -p "按 Enter 繼續..."
                ;;
            2)
                env_switch "production"
                read -p "按 Enter 繼續..."
                ;;
            [Ee])
                echo ""
                echo "可用環境:"
                env_list
                echo ""
                read -p "請輸入環境名稱: " target_env
                if [[ -n "$target_env" ]]; then
                    env_switch "$target_env"
                fi
                read -p "按 Enter 繼續..."
                ;;
            [Ss])
                clear
                env_current
                echo ""
                show_env_details "$CURRENT_ENVIRONMENT"
                read -p "按 Enter 繼續..."
                ;;
            [Hh])
                clear
                echo -e "${YELLOW}${STATUS_CHECKING} 正在檢查所有環境健康狀態...${NC}"
                echo ""
                
                for env_dir in "$PROJECT_ROOT/configs"/*; do
                    if [[ -d "$env_dir" ]]; then
                        local env_name=$(basename "$env_dir")
                        local health_result=$(enhanced_env_health_check "$env_name")
                        echo -e "${env_name}: ${health_result}"
                    fi
                done
                echo ""
                read -p "按 Enter 繼續..."
                ;;
            [Dd])
                echo ""
                read -p "請輸入要查看詳細資訊的環境名稱 [${CURRENT_ENVIRONMENT}]: " target_env
                target_env="${target_env:-$CURRENT_ENVIRONMENT}"
                clear
                show_env_details "$target_env"
                read -p "按 Enter 繼續..."
                ;;
            [Cc])
                clear
                compare_environments
                read -p "按 Enter 繼續..."
                ;;
            [Rr])
                echo -e "${YELLOW}${STATUS_CHECKING} 重新整理環境資訊...${NC}"
                sleep 1
                ;;
            [Qq])
                echo -e "${BLUE}${BOLD}感謝使用 AWS Client VPN 管理工具${NC}"
                echo -e "${DIM}再見！${NC}"
                break
                ;;
            *)
                echo -e "${RED}無效的選擇，請重新輸入${NC}"
                sleep 1
                ;;
        esac
    done
}

# 顯示幫助資訊
show_help() {
    echo -e "${CYAN}${BOLD}增強版環境選擇器 v2.0${NC}"
    echo ""
    echo -e "${BOLD}使用方式:${NC}"
    echo "  $0 [command]"
    echo ""
    echo -e "${BOLD}可用命令:${NC}"
    echo "  selector     啟動增強版互動式環境選擇器 (預設)"
    echo "  compare      顯示環境比較表"
    echo "  details <env> 顯示指定環境的詳細資訊"
    echo "  health       檢查所有環境健康狀態"
    echo "  help         顯示此幫助資訊"
    echo ""
    echo -e "${BOLD}互動式選擇器快捷鍵:${NC}"
    echo "  1-2          切換到對應環境"
    echo "  E            切換環境 (手動輸入)"
    echo "  S            顯示當前環境狀態"
    echo "  H            健康檢查所有環境"
    echo "  D            顯示詳細資訊"
    echo "  C            環境比較"
    echo "  R            重新整理"
    echo "  Q            退出"
    echo ""
    echo -e "${BOLD}範例:${NC}"
    echo "  $0                    # 啟動互動式選擇器"
    echo "  $0 selector          # 啟動互動式選擇器"
    echo "  $0 compare           # 顯示環境比較"
    echo "  $0 details staging   # 顯示 staging 環境詳細資訊"
    echo "  $0 health            # 檢查所有環境健康狀態"
    echo ""
}

# 主程式邏輯
main() {
    local command="${1:-selector}"
    
    case "$command" in
        selector|"")
            enhanced_env_selector
            ;;
        compare)
            compare_environments
            ;;
        details)
            if [[ -n "$2" ]]; then
                show_env_details "$2"
            else
                echo -e "${RED}錯誤: 請指定環境名稱${NC}"
                echo "使用方式: $0 details <environment_name>"
                exit 1
            fi
            ;;
        health)
            echo -e "${YELLOW}${STATUS_CHECKING} 檢查所有環境健康狀態...${NC}"
            echo ""
            for env_dir in "$PROJECT_ROOT/configs"/*; do
                if [[ -d "$env_dir" ]]; then
                    local env_name=$(basename "$env_dir")
                    local health_result=$(enhanced_env_health_check "$env_name")
                    echo -e "${env_name}: ${health_result}"
                fi
            done
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}錯誤: 未知命令 '$command'${NC}"
            echo "使用 '$0 help' 查看可用命令"
            exit 1
            ;;
    esac
}

# 執行主程式
main "$@"
