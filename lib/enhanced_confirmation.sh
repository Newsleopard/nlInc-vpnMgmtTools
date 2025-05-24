#!/bin/bash

# Enhanced Operation Confirmation Module
# 增強版操作確認機制 - 階段三實施
# Version: 2.0
# Date: 2025-05-24

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
BLINK='\033[5m'
NC='\033[0m' # No Color

# 操作風險等級定義
RISK_LOW=1
RISK_MEDIUM=2
RISK_HIGH=3
RISK_CRITICAL=4

# 獲取操作風險等級
get_operation_risk_level() {
    local operation="$1"
    local env_name="$2"
    
    # Production 環境所有操作都有更高風險
    local base_risk=0
    if [[ "$env_name" == "production" ]]; then
        base_risk=1
    fi
    
    case "$operation" in
        "CREATE_ENDPOINT"|"DELETE_ENDPOINT")
            echo $((RISK_CRITICAL + base_risk))
            ;;
        "MANAGE_ENDPOINT"|"EMPLOYEE_OFFBOARDING")
            echo $((RISK_HIGH + base_risk))
            ;;
        "REVOKE_ACCESS"|"TEAM_MEMBER_SETUP")
            echo $((RISK_MEDIUM + base_risk))
            ;;
        "VIEW_STATUS"|"LIST_USERS")
            echo $((RISK_LOW + base_risk))
            ;;
        *)
            echo $((RISK_MEDIUM + base_risk))
            ;;
    esac
}

# 獲取風險等級描述
get_risk_level_description() {
    local risk_level="$1"
    
    case "$risk_level" in
        1)
            echo "${GREEN}低風險${NC}"
            ;;
        2)
            echo "${YELLOW}中等風險${NC}"
            ;;
        3)
            echo "${RED}高風險${NC}"
            ;;
        4|5)
            echo "${RED}${BLINK}極高風險${NC}"
            ;;
        *)
            echo "${BLUE}未知風險${NC}"
            ;;
    esac
}

# 獲取操作影響範圍描述
get_operation_impact_description() {
    local operation="$1"
    local env_name="$2"
    
    local env_display="$env_name"
    if [[ "$env_name" == "production" ]]; then
        env_display="${RED}${BOLD}PRODUCTION${NC}"
    elif [[ "$env_name" == "staging" ]]; then
        env_display="${YELLOW}STAGING${NC}"
    fi
    
    case "$operation" in
        "CREATE_ENDPOINT")
            echo "• 在 $env_display 環境創建新的 VPN 端點"
            echo "• 可能影響網路連接和安全設定"
            echo "• 需要確保 AWS 資源配置正確"
            ;;
        "DELETE_ENDPOINT")
            echo "• 在 $env_display 環境刪除 VPN 端點"
            echo -e "• ${RED}${BOLD}將中斷所有現有 VPN 連線${NC}"
            echo "• 無法復原，需要重新創建端點"
            ;;
        "MANAGE_ENDPOINT")
            echo "• 修改 $env_display 環境的 VPN 端點設定"
            echo "• 可能暫時影響用戶連線"
            echo "• 變更會立即生效"
            ;;
        "TEAM_MEMBER_SETUP")
            echo "• 為新團隊成員設定 $env_display 環境 VPN 存取"
            echo "• 將生成新的證書和配置檔案"
            echo "• 授予網路資源存取權限"
            ;;
        "REVOKE_ACCESS")
            echo "• 撤銷團隊成員的 $env_display 環境 VPN 存取"
            echo "• 將使現有證書失效"
            echo "• 立即中斷目標用戶的連線"
            ;;
        "EMPLOYEE_OFFBOARDING")
            echo "• 執行員工離職的完整 $env_display 環境清理"
            echo "• 撤銷所有相關存取權限"
            echo -e "• ${RED}包含證書撤銷和帳戶清理${NC}"
            ;;
        *)
            echo "• 在 $env_display 環境執行 $operation"
            echo "• 具體影響範圍待確認"
            ;;
    esac
}

# 獲取回滾計劃
get_rollback_plan() {
    local operation="$1"
    local env_name="$2"
    
    case "$operation" in
        "CREATE_ENDPOINT")
            echo "• 如發生問題，可使用刪除端點功能回滾"
            echo "• 備份原有配置以便恢復"
            echo "• 準備緊急聯絡人清單"
            ;;
        "DELETE_ENDPOINT")
            echo -e "• ${RED}${BOLD}警告：此操作無法回滾${NC}"
            echo "• 請確保已備份所有配置和證書"
            echo "• 準備重新創建程序文檔"
            ;;
        "MANAGE_ENDPOINT")
            echo "• 記錄變更前的設定狀態"
            echo "• 可透過 AWS 控制台手動回滾"
            echo "• 保留配置備份檔案"
            ;;
        "TEAM_MEMBER_SETUP")
            echo "• 可使用撤銷存取功能移除權限"
            echo "• 刪除生成的證書檔案"
            echo "• 清理相關日誌記錄"
            ;;
        "REVOKE_ACCESS"|"EMPLOYEE_OFFBOARDING")
            echo -e "• ${YELLOW}警告：存取撤銷後需重新設定才能恢復${NC}"
            echo "• 需要重新執行團隊成員設定流程"
            echo "• 證書撤銷無法復原"
            ;;
        *)
            echo "• 具體回滾計劃需根據操作類型確定"
            echo "• 建議在執行前進行完整備份"
            ;;
    esac
}

# 增強版生產環境操作確認
enhanced_production_confirmation() {
    local operation="$1"
    local env_name="$2"
    local user_context="$3"
    
    echo -e "${RED}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║                    PRODUCTION 環境操作確認                        ║${NC}"
    echo -e "${RED}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # 風險評估
    local risk_level=$(get_operation_risk_level "$operation" "$env_name")
    local risk_desc=$(get_risk_level_description "$risk_level")
    
    echo -e "${BOLD}操作詳情:${NC}"
    echo -e "  操作類型: ${CYAN}$operation${NC}"
    echo -e "  目標環境: ${RED}${BOLD}PRODUCTION${NC}"
    echo -e "  風險等級: $risk_desc"
    echo -e "  操作者: ${USER:-unknown}"
    echo -e "  時間: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""
    
    # 影響範圍說明
    echo -e "${BOLD}影響範圍:${NC}"
    get_operation_impact_description "$operation" "$env_name"
    echo ""
    
    # 回滾計劃
    echo -e "${BOLD}回滾計劃:${NC}"
    get_rollback_plan "$operation" "$env_name"
    echo ""
    
    # 額外警告 (高風險操作)
    if [[ $risk_level -ge 4 ]]; then
        echo -e "${RED}${BOLD}${BLINK}⚠️  極高風險操作警告 ⚠️${NC}"
        echo -e "${RED}此操作具有極高風險，可能對生產環境造成重大影響${NC}"
        echo -e "${RED}建議在維護時間窗口內執行，並通知相關團隊${NC}"
        echo ""
    fi
    
    # 第一重確認：輸入 PRODUCTION
    echo -e "${BOLD}安全確認 (第一步):${NC}"
    echo -e "請輸入 '${RED}${BOLD}PRODUCTION${NC}' 確認您了解正在操作生產環境："
    read -p "> " first_confirm
    
    if [[ "$first_confirm" != "PRODUCTION" ]]; then
        echo -e "${YELLOW}操作已取消 - 第一步確認失敗${NC}"
        return 1
    fi
    
    # 第二重確認：輸入 yes
    echo ""
    echo -e "${BOLD}安全確認 (第二步):${NC}"
    echo -e "請輸入 '${GREEN}${BOLD}yes${NC}' 最終確認執行此操作："
    read -p "> " second_confirm
    
    if [[ ! "$second_confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${YELLOW}操作已取消 - 第二步確認失敗${NC}"
        return 1
    fi
    
    # 最終警告 (極高風險操作)
    if [[ $risk_level -ge 4 ]]; then
        echo ""
        echo -e "${RED}${BOLD}最終警告 - 極高風險操作${NC}"
        echo -e "${RED}您即將執行可能對生產環境造成重大影響的操作${NC}"
        echo -e "最後機會取消，請輸入 '${RED}${BOLD}CONFIRM${NC}' 繼續："
        read -p "> " final_confirm
        
        if [[ "$final_confirm" != "CONFIRM" ]]; then
            echo -e "${YELLOW}操作已取消 - 最終確認失敗${NC}"
            return 1
        fi
    fi
    
    echo ""
    echo -e "${GREEN}✅ 所有安全確認已通過，正在執行操作...${NC}"
    echo ""
    
    return 0
}

# 批次操作確認
batch_operation_confirmation() {
    local operation="$1"
    local target_count="$2"
    local env_name="$3"
    
    echo -e "${BLUE}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}${BOLD}║                       批次操作確認                                ║${NC}"
    echo -e "${BLUE}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BOLD}批次操作詳情:${NC}"
    echo -e "  操作類型: ${CYAN}$operation${NC}"
    echo -e "  目標環境: ${env_name}"
    echo -e "  影響對象: ${YELLOW}${target_count}${NC} 個項目"
    echo -e "  預估時間: $((target_count * 2)) 分鐘"
    echo ""
    
    echo -e "${BOLD}批次操作影響:${NC}"
    echo "• 將對 $target_count 個目標執行相同操作"
    echo "• 操作過程中無法單獨取消個別項目"
    echo "• 建議在低使用量時段執行"
    echo ""
    
    echo -e "${BOLD}操作確認:${NC}"
    read -p "確認執行批次操作？ [yes/NO]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${YELLOW}批次操作已取消${NC}"
        return 1
    fi
    
    return 0
}

# 智能操作確認 - 根據風險等級決定確認流程
smart_operation_confirmation() {
    local operation="$1"
    local env_name="$2"
    local batch_count="${3:-1}"
    local user_context="$4"
    
    # 獲取風險等級
    local risk_level=$(get_operation_risk_level "$operation" "$env_name")
    
    # 批次操作處理
    if [[ $batch_count -gt 1 ]]; then
        if ! batch_operation_confirmation "$operation" "$batch_count" "$env_name"; then
            return 1
        fi
    fi
    
    # Production 環境特殊處理
    if [[ "$env_name" == "production" ]]; then
        if ! enhanced_production_confirmation "$operation" "$env_name" "$user_context"; then
            return 1
        fi
    else
        # 非 Production 環境的確認流程
        case "$risk_level" in
            1|2)
                # 低風險：簡單確認
                echo -e "${BLUE}操作確認${NC}"
                echo -e "操作: ${operation}"
                echo -e "環境: ${env_name}"
                read -p "確認執行？ [Y/n]: " confirm
                if [[ "$confirm" =~ ^[Nn]$ ]]; then
                    echo -e "${YELLOW}操作已取消${NC}"
                    return 1
                fi
                ;;
            3|4)
                # 高風險：詳細確認
                echo -e "${YELLOW}${BOLD}高風險操作確認${NC}"
                echo -e "操作: ${operation}"
                echo -e "環境: ${env_name}"
                echo -e "風險等級: $(get_risk_level_description "$risk_level")"
                echo ""
                get_operation_impact_description "$operation" "$env_name"
                echo ""
                read -p "確認執行此高風險操作？ [yes/NO]: " confirm
                if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
                    echo -e "${YELLOW}操作已取消${NC}"
                    return 1
                fi
                ;;
        esac
    fi
    
    return 0
}

# 操作摘要和預覽
show_operation_preview() {
    local operation="$1"
    local env_name="$2"
    local target_list="$3"
    
    echo -e "${CYAN}${BOLD}═══ 操作預覽 ═══${NC}"
    echo -e "${BOLD}操作:${NC} $operation"
    echo -e "${BOLD}環境:${NC} $env_name"
    echo -e "${BOLD}時間:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    if [[ -n "$target_list" ]]; then
        echo -e "${BOLD}目標列表:${NC}"
        echo "$target_list" | while IFS= read -r target; do
            echo "  • $target"
        done
        echo ""
    fi
    
    # 顯示預期結果
    echo -e "${BOLD}預期結果:${NC}"
    case "$operation" in
        "TEAM_MEMBER_SETUP")
            echo "  • 生成用戶證書和配置檔案"
            echo "  • 建立 VPN 存取權限"
            echo "  • 記錄操作日誌"
            ;;
        "REVOKE_ACCESS")
            echo "  • 撤銷用戶 VPN 存取權限"
            echo "  • 使證書失效"
            echo "  • 中斷現有連線"
            ;;
        *)
            echo "  • 執行 $operation 相關操作"
            ;;
    esac
    echo ""
}

# 快速重複操作支援
quick_repeat_operation() {
    local last_operation="$1"
    local last_env="$2"
    
    if [[ -z "$last_operation" || -z "$last_env" ]]; then
        return 1
    fi
    
    echo -e "${BLUE}${BOLD}快速重複操作${NC}"
    echo -e "上次操作: ${last_operation} (${last_env})"
    read -p "重複執行上次操作？ [y/N]: " repeat_confirm
    
    if [[ "$repeat_confirm" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# 錯誤恢復指導
show_error_recovery_guide() {
    local error_type="$1"
    local operation="$2"
    local env_name="$3"
    
    echo -e "${RED}${BOLD}錯誤恢復指導${NC}"
    echo -e "錯誤類型: $error_type"
    echo -e "失敗操作: $operation"
    echo -e "目標環境: $env_name"
    echo ""
    
    case "$error_type" in
        "CONFIG_ERROR")
            echo -e "${BOLD}建議解決方案:${NC}"
            echo "1. 檢查環境配置檔案格式"
            echo "2. 驗證必要變數是否設定"
            echo "3. 重新載入環境配置"
            ;;
        "PERMISSION_ERROR")
            echo -e "${BOLD}建議解決方案:${NC}"
            echo "1. 檢查 AWS 憑證設定"
            echo "2. 驗證 IAM 權限"
            echo "3. 確認檔案存取權限"
            ;;
        "NETWORK_ERROR")
            echo -e "${BOLD}建議解決方案:${NC}"
            echo "1. 檢查網路連線"
            echo "2. 驗證 AWS 服務可用性"
            echo "3. 重試操作"
            ;;
        *)
            echo -e "${BOLD}一般解決方案:${NC}"
            echo "1. 檢查操作日誌"
            echo "2. 驗證環境狀態"
            echo "3. 聯絡系統管理員"
            ;;
    esac
    echo ""
    
    read -p "是否需要查看詳細日誌？ [y/N]: " show_logs
    if [[ "$show_logs" =~ ^[Yy]$ ]]; then
        echo "日誌檔案位置: /path/to/logs/${env_name}/"
        echo "建議使用: tail -f /path/to/logs/${env_name}/error.log"
    fi
}

# 匯出函數供其他腳本使用
export -f get_operation_risk_level
export -f get_risk_level_description
export -f get_operation_impact_description
export -f get_rollback_plan
export -f enhanced_production_confirmation
export -f batch_operation_confirmation
export -f smart_operation_confirmation
export -f show_operation_preview
export -f quick_repeat_operation
export -f show_error_recovery_guide
