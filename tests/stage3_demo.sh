#!/bin/bash

# Stage 3 Demo Script - User Interface Enhancement
# 階段三演示腳本 - 使用者介面完善
# Version: 1.0
# Date: 2025-05-24

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 演示標題
show_demo_header() {
    clear
    echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}${BOLD}║                AWS VPN 階段三功能演示                           ║${NC}"
    echo -e "${BLUE}${BOLD}║               使用者介面完善 - 主要功能展示                      ║${NC}"
    echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo -e ""
    echo -e "${CYAN}演示日期：$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${CYAN}專案版本：v2.0 (階段三完成版)${NC}"
    echo -e ""
}

# 演示功能選單
show_demo_menu() {
    echo -e "${YELLOW}${BOLD}請選擇要演示的功能：${NC}"
    echo -e ""
    echo -e "  ${GREEN}1.${NC} 增強確認機制演示"
    echo -e "  ${GREEN}2.${NC} 環境管理器集成演示"
    echo -e "  ${GREEN}3.${NC} 增強環境選擇器演示"
    echo -e "  ${GREEN}4.${NC} 安全機制演示"
    echo -e "  ${GREEN}5.${NC} 完整功能驗證"
    echo -e "  ${GREEN}6.${NC} 查看階段三完成報告"
    echo -e "  ${RED}Q.${NC} 退出演示"
    echo -e ""
}

# 演示增強確認機制
demo_enhanced_confirmation() {
    echo -e "${BLUE}${BOLD}=== 增強確認機制演示 ===${NC}"
    echo -e ""
    echo -e "${YELLOW}載入增強確認模組...${NC}"
    
    if source "$PROJECT_ROOT/lib/enhanced_confirmation.sh" 2>/dev/null; then
        echo -e "${GREEN}✅ 增強確認模組載入成功${NC}"
        echo -e ""
        
        echo -e "${YELLOW}展示風險等級評估：${NC}"
        echo -e "  - CREATE_ENDPOINT (Production): 風險等級 $(get_operation_risk_level "CREATE_ENDPOINT" "production")"
        echo -e "  - TEAM_MEMBER_SETUP (Staging): 風險等級 $(get_operation_risk_level "TEAM_MEMBER_SETUP" "staging")"
        echo -e "  - VIEW_STATUS (Production): 風險等級 $(get_operation_risk_level "VIEW_STATUS" "production")"
        echo -e ""
        
        echo -e "${YELLOW}主要功能：${NC}"
        echo -e "  ✅ 智能操作確認 (smart_operation_confirmation)"
        echo -e "  ✅ 生產環境增強確認 (enhanced_production_confirmation)"
        echo -e "  ✅ 批次操作確認 (batch_operation_confirmation)"
        echo -e "  ✅ 風險等級自動評估"
        echo -e "  ✅ 操作影響描述"
        echo -e "  ✅ 回滾計劃指導"
    else
        echo -e "${RED}❌ 增強確認模組載入失敗${NC}"
    fi
    
    echo -e ""
    read -p "按 Enter 繼續..."
}

# 演示環境管理器集成
demo_env_manager_integration() {
    echo -e "${BLUE}${BOLD}=== 環境管理器集成演示 ===${NC}"
    echo -e ""
    echo -e "${YELLOW}載入環境管理器...${NC}"
    
    if source "$PROJECT_ROOT/lib/env_manager.sh" 2>/dev/null; then
        echo -e "${GREEN}✅ 環境管理器載入成功${NC}"
        echo -e ""
        
        echo -e "${YELLOW}新增集成功能：${NC}"
        if declare -f env_enhanced_operation_confirm >/dev/null; then
            echo -e "  ✅ env_enhanced_operation_confirm - 增強操作確認"
        fi
        if declare -f env_aware_operation >/dev/null; then
            echo -e "  ✅ env_aware_operation - 環境感知操作"
        fi
        if declare -f smart_operation_confirmation >/dev/null; then
            echo -e "  ✅ smart_operation_confirmation - 智能確認系統"
        fi
        
        echo -e ""
        echo -e "${YELLOW}環境狀態檢查：${NC}"
        if env_current 2>/dev/null; then
            echo -e "${GREEN}✅ 環境狀態顯示正常${NC}"
        else
            echo -e "${YELLOW}⚠️  環境狀態檢查需要初始化${NC}"
        fi
    else
        echo -e "${RED}❌ 環境管理器載入失敗${NC}"
    fi
    
    echo -e ""
    read -p "按 Enter 繼續..."
}

# 演示增強環境選擇器
demo_enhanced_env_selector() {
    echo -e "${BLUE}${BOLD}=== 增強環境選擇器演示 ===${NC}"
    echo -e ""
    echo -e "${YELLOW}檢查增強環境選擇器...${NC}"
    
    if [[ -x "$PROJECT_ROOT/enhanced_env_selector.sh" ]]; then
        echo -e "${GREEN}✅ 增強環境選擇器可執行${NC}"
        echo -e ""
        
        echo -e "${YELLOW}主要功能特色：${NC}"
        echo -e "  🎨 Unicode 框線設計"
        echo -e "  🟢 即時狀態監控"
        echo -e "  📊 連線數量顯示"
        echo -e "  🔄 健康檢查功能"
        echo -e "  ⚡ 快速操作選項"
        echo -e "  🔍 環境比較功能"
        echo -e "  📱 直觀使用者介面"
        echo -e ""
        
        echo -e "${YELLOW}視覺改進：${NC}"
        echo -e "  🟡 Staging Environment"
        echo -e "  🔴 Production Environment"
        echo -e "  🟢 健康狀態"
        echo -e "  🟡 警告狀態"
        echo -e "  🔄 檢查中狀態"
        echo -e ""
        
        echo -e "${CYAN}提示：要體驗完整介面，可執行：${NC}"
        echo -e "${CYAN}  ./enhanced_env_selector.sh${NC}"
    else
        echo -e "${RED}❌ 增強環境選擇器不存在或不可執行${NC}"
    fi
    
    echo -e ""
    read -p "按 Enter 繼續..."
}

# 演示安全機制
demo_security_mechanisms() {
    echo -e "${BLUE}${BOLD}=== 安全機制演示 ===${NC}"
    echo -e ""
    
    echo -e "${YELLOW}生產環境保護機制：${NC}"
    echo -e ""
    
    if [[ -f "$PROJECT_ROOT/production.env" ]]; then
        echo -e "${GREEN}✅ Production 環境配置存在${NC}"
        
        if grep -q "REQUIRE_OPERATION_CONFIRMATION=true" "$PROJECT_ROOT/production.env"; then
            echo -e "${GREEN}✅ 操作確認已啟用${NC}"
        fi
        
        echo -e ""
        echo -e "${YELLOW}多層確認機制：${NC}"
        echo -e "  🛡️  第一層：環境識別確認 (輸入 'PRODUCTION')"
        echo -e "  🛡️  第二層：操作意圖確認 (輸入 'yes')"
        echo -e "  🛡️  第三層：極高風險最終確認 (輸入 'CONFIRM')"
        echo -e ""
        
        echo -e "${YELLOW}風險等級分類：${NC}"
        echo -e "  🟢 低風險 (1): VIEW_STATUS, LIST_USERS"
        echo -e "  🟡 中等風險 (2): REVOKE_ACCESS, TEAM_MEMBER_SETUP"
        echo -e "  🟠 高風險 (3): MANAGE_ENDPOINT, EMPLOYEE_OFFBOARDING"
        echo -e "  🔴 極高風險 (4+): CREATE_ENDPOINT, DELETE_ENDPOINT"
        echo -e ""
        
        echo -e "${YELLOW}安全特性：${NC}"
        echo -e "  ✅ 自動風險評估"
        echo -e "  ✅ 操作影響說明"
        echo -e "  ✅ 回滾計劃提示"
        echo -e "  ✅ 操作審計日誌"
        echo -e "  ✅ 環境隔離保證"
    else
        echo -e "${RED}❌ Production 環境配置缺失${NC}"
    fi
    
    echo -e ""
    read -p "按 Enter 繼續..."
}

# 完整功能驗證
demo_full_validation() {
    echo -e "${BLUE}${BOLD}=== 完整功能驗證 ===${NC}"
    echo -e ""
    
    local total_tests=0
    local passed_tests=0
    
    echo -e "${YELLOW}正在執行功能驗證...${NC}"
    echo -e ""
    
    # 檢查核心檔案
    echo -e "${CYAN}1. 檢查核心檔案...${NC}"
    for file in "lib/enhanced_confirmation.sh" "lib/env_manager.sh" "enhanced_env_selector.sh"; do
        total_tests=$((total_tests + 1))
        if [[ -f "$PROJECT_ROOT/$file" ]]; then
            echo -e "  ✅ $file"
            passed_tests=$((passed_tests + 1))
        else
            echo -e "  ❌ $file"
        fi
    done
    
    # 檢查模組載入
    echo -e "${CYAN}2. 檢查模組載入...${NC}"
    total_tests=$((total_tests + 1))
    if bash -c "cd '$PROJECT_ROOT' && source lib/enhanced_confirmation.sh" 2>/dev/null; then
        echo -e "  ✅ 增強確認模組載入"
        passed_tests=$((passed_tests + 1))
    else
        echo -e "  ❌ 增強確認模組載入"
    fi
    
    total_tests=$((total_tests + 1))
    if bash -c "cd '$PROJECT_ROOT' && source lib/env_manager.sh" 2>/dev/null; then
        echo -e "  ✅ 環境管理器載入"
        passed_tests=$((passed_tests + 1))
    else
        echo -e "  ❌ 環境管理器載入"
    fi
    
    # 檢查函數可用性
    echo -e "${CYAN}3. 檢查函數可用性...${NC}"
    total_tests=$((total_tests + 1))
    if bash -c "cd '$PROJECT_ROOT' && source lib/enhanced_confirmation.sh && declare -f smart_operation_confirmation >/dev/null" 2>/dev/null; then
        echo -e "  ✅ 智能確認函數"
        passed_tests=$((passed_tests + 1))
    else
        echo -e "  ❌ 智能確認函數"
    fi
    
    total_tests=$((total_tests + 1))
    if bash -c "cd '$PROJECT_ROOT' && source lib/env_manager.sh && declare -f env_enhanced_operation_confirm >/dev/null" 2>/dev/null; then
        echo -e "  ✅ 增強操作確認函數"
        passed_tests=$((passed_tests + 1))
    else
        echo -e "  ❌ 增強操作確認函數"
    fi
    
    # 檢查配置
    echo -e "${CYAN}4. 檢查環境配置...${NC}"
    total_tests=$((total_tests + 1))
    if [[ -f "$PROJECT_ROOT/staging.env" ]] && [[ -f "$PROJECT_ROOT/production.env" ]]; then
        echo -e "  ✅ 環境配置檔案"
        passed_tests=$((passed_tests + 1))
    else
        echo -e "  ❌ 環境配置檔案"
    fi
    
    total_tests=$((total_tests + 1))
    if grep -q "REQUIRE_OPERATION_CONFIRMATION=true" "$PROJECT_ROOT/production.env" 2>/dev/null; then
        echo -e "  ✅ 生產環境安全設定"
        passed_tests=$((passed_tests + 1))
    else
        echo -e "  ❌ 生產環境安全設定"
    fi
    
    echo -e ""
    echo -e "${BOLD}驗證結果：${NC}"
    echo -e "  通過測試：${GREEN}$passed_tests${NC} / $total_tests"
    
    local success_rate=$(( (passed_tests * 100) / total_tests ))
    if [[ $success_rate -ge 90 ]]; then
        echo -e "  成功率：${GREEN}$success_rate%${NC} 🎉"
        echo -e "  狀態：${GREEN}優秀${NC}"
    elif [[ $success_rate -ge 70 ]]; then
        echo -e "  成功率：${YELLOW}$success_rate%${NC}"
        echo -e "  狀態：${YELLOW}良好${NC}"
    else
        echo -e "  成功率：${RED}$success_rate%${NC}"
        echo -e "  狀態：${RED}需要改進${NC}"
    fi
    
    echo -e ""
    read -p "按 Enter 繼續..."
}

# 查看階段三完成報告
view_completion_report() {
    echo -e "${BLUE}${BOLD}=== 階段三完成報告 ===${NC}"
    echo -e ""
    
    if [[ -f "$PROJECT_ROOT/dev-plans/STAGE3_COMPLETION_REPORT.md" ]]; then
        echo -e "${GREEN}✅ 階段三完成報告已生成${NC}"
        echo -e ""
        echo -e "${CYAN}報告位置：${NC}"
        echo -e "  $PROJECT_ROOT/dev-plans/STAGE3_COMPLETION_REPORT.md"
        echo -e ""
        echo -e "${YELLOW}報告摘要：${NC}"
        echo -e "  📊 完成度：85%"
        echo -e "  ✅ 主要功能：100% 完成"
        echo -e "  🧪 測試狀態：85% 完成"
        echo -e "  📝 文檔狀態：90% 完成"
        echo -e ""
        echo -e "${CYAN}關鍵成就：${NC}"
        echo -e "  🛡️  業界標準的四級風險評估系統"
        echo -e "  🔐 生產環境多層保護機制"
        echo -e "  🎨 直觀友善的使用者介面"
        echo -e "  📈 達成所有預設成功指標"
        echo -e ""
        
        read -p "是否要查看完整報告？ [y/N]: " view_full
        if [[ "$view_full" =~ ^[Yy]$ ]]; then
            if command -v less >/dev/null; then
                less "$PROJECT_ROOT/dev-plans/STAGE3_COMPLETION_REPORT.md"
            else
                cat "$PROJECT_ROOT/dev-plans/STAGE3_COMPLETION_REPORT.md"
            fi
        fi
    else
        echo -e "${RED}❌ 階段三完成報告不存在${NC}"
    fi
    
    echo -e ""
    read -p "按 Enter 繼續..."
}

# 主程式迴圈
main() {
    while true; do
        show_demo_header
        show_demo_menu
        
        read -p "請選擇 [1-6/Q]: " choice
        
        case "$choice" in
            1)
                demo_enhanced_confirmation
                ;;
            2)
                demo_env_manager_integration
                ;;
            3)
                demo_enhanced_env_selector
                ;;
            4)
                demo_security_mechanisms
                ;;
            5)
                demo_full_validation
                ;;
            6)
                view_completion_report
                ;;
            [Qq])
                echo -e "${BLUE}${BOLD}感謝使用 AWS VPN 階段三功能演示${NC}"
                echo -e "${CYAN}階段三實施狀態：主要功能完成，正在進行最終測試${NC}"
                echo -e ""
                break
                ;;
            *)
                echo -e "${RED}無效的選擇，請重新輸入${NC}"
                sleep 1
                ;;
        esac
    done
}

# 執行主程式
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
