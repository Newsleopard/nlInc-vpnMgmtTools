#!/bin/bash

# Stage 3 Integration Test Suite
# 階段三集成測試套件 - 使用者介面完善驗證
# Version: 1.0
# Date: 2025-05-24

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# 測試計數器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 測試結果記錄
TEST_RESULTS=()

# 測試輔助函數
test_assert() {
    local description="$1"
    local condition="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if eval "$condition"; then
        echo -e "${GREEN}✅ PASS${NC}: $description"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: $description")
    else
        echo -e "${RED}❌ FAIL${NC}: $description"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: $description")
    fi
}

test_file_exists() {
    local description="$1"
    local file_path="$2"
    
    test_assert "$description" "[[ -f '$file_path' ]]"
}

test_function_exists() {
    local description="$1"
    local function_name="$2"
    local script_file="$3"
    
    test_assert "$description" "source '$script_file' && declare -f '$function_name' > /dev/null"
}

# 測試標題
show_test_header() {
    echo -e "${BLUE}========================================================${NC}"
    echo -e "${BLUE}${BOLD}    階段三使用者介面完善 - 集成測試套件${NC}"
    echo -e "${BLUE}========================================================${NC}"
    echo -e ""
    echo -e "測試日期: $(date)"
    echo -e "專案路徑: $PROJECT_ROOT"
    echo -e ""
}

# 1. 測試增強確認模組
test_enhanced_confirmation_module() {
    echo -e "${YELLOW}📋 測試增強確認模組...${NC}"
    
    local confirmation_script="$PROJECT_ROOT/lib/enhanced_confirmation.sh"
    
    test_file_exists "增強確認模組檔案存在" "$confirmation_script"
    test_function_exists "風險等級函數存在" "get_operation_risk_level" "$confirmation_script"
    test_function_exists "智能確認函數存在" "smart_operation_confirmation" "$confirmation_script"
    test_function_exists "批次確認函數存在" "batch_operation_confirmation" "$confirmation_script"
    test_function_exists "生產環境確認函數存在" "production_environment_confirmation" "$confirmation_script"
    
    echo ""
}

# 2. 測試環境管理器集成
test_env_manager_integration() {
    echo -e "${YELLOW}📋 測試環境管理器集成...${NC}"
    
    local env_manager="$PROJECT_ROOT/lib/env_manager.sh"
    
    test_file_exists "環境管理器檔案存在" "$env_manager"
    
    # 檢查是否載入增強確認模組
    test_assert "環境管理器載入增強確認模組" "grep -q 'enhanced_confirmation.sh' '$env_manager'"
    
    # 檢查新增的函數
    test_function_exists "增強操作確認函數存在" "env_enhanced_operation_confirm" "$env_manager"
    test_function_exists "環境感知操作函數存在" "env_aware_operation" "$env_manager"
    
    echo ""
}

# 3. 測試增強環境選擇器
test_enhanced_env_selector() {
    echo -e "${YELLOW}📋 測試增強環境選擇器...${NC}"
    
    local selector_script="$PROJECT_ROOT/enhanced_env_selector.sh"
    
    test_file_exists "增強環境選擇器檔案存在" "$selector_script"
    test_assert "環境選擇器可執行" "[[ -x '$selector_script' ]]"
    
    # 檢查是否載入增強確認模組
    test_assert "環境選擇器載入增強確認模組" "grep -q 'enhanced_confirmation.sh' '$selector_script'"
    
    echo ""
}

# 4. 測試環境配置完整性
test_environment_configurations() {
    echo -e "${YELLOW}📋 測試環境配置完整性...${NC}"
    
    test_file_exists "Staging 環境配置存在" "$PROJECT_ROOT/staging.env"
    test_file_exists "Production 環境配置存在" "$PROJECT_ROOT/production.env"
    
    # 檢查環境配置包含必要參數
    test_assert "Staging 配置包含確認設定" "grep -q 'REQUIRE_OPERATION_CONFIRMATION' '$PROJECT_ROOT/staging.env'"
    test_assert "Production 配置包含確認設定" "grep -q 'REQUIRE_OPERATION_CONFIRMATION' '$PROJECT_ROOT/production.env'"
    
    echo ""
}

# 5. 測試目錄結構
test_directory_structure() {
    echo -e "${YELLOW}📋 測試目錄結構...${NC}"
    
    test_assert "lib 目錄存在" "[[ -d '$PROJECT_ROOT/lib' ]]"
    test_assert "tests 目錄存在" "[[ -d '$PROJECT_ROOT/tests' ]]"
    test_assert "certs 目錄存在" "[[ -d '$PROJECT_ROOT/certs' ]]"
    test_assert "configs 目錄存在" "[[ -d '$PROJECT_ROOT/configs' ]]"
    test_assert "logs 目錄存在" "[[ -d '$PROJECT_ROOT/logs' ]]"
    
    echo ""
}

# 6. 功能集成測試
test_functional_integration() {
    echo -e "${YELLOW}📋 測試功能集成...${NC}"
    
    # 測試環境載入
    if source "$PROJECT_ROOT/lib/env_manager.sh" 2>/dev/null; then
        test_assert "環境管理器可成功載入" "true"
        
        # 測試基本函數可用性
        if declare -f load_current_env > /dev/null; then
            test_assert "載入當前環境函數可用" "true"
        else
            test_assert "載入當前環境函數可用" "false"
        fi
        
        if declare -f env_validate_operation > /dev/null; then
            test_assert "環境驗證操作函數可用" "true"
        else
            test_assert "環境驗證操作函數可用" "false"
        fi
    else
        test_assert "環境管理器可成功載入" "false"
    fi
    
    echo ""
}

# 7. 安全機制驗證
test_security_mechanisms() {
    echo -e "${YELLOW}📋 測試安全機制...${NC}"
    
    # 檢查生產環境確認設定
    if [[ -f "$PROJECT_ROOT/production.env" ]]; then
        source "$PROJECT_ROOT/production.env"
        test_assert "Production 環境啟用操作確認" "[[ '$REQUIRE_OPERATION_CONFIRMATION' == 'true' ]]"
    else
        test_assert "Production 環境配置存在" "false"
    fi
    
    # 檢查風險等級定義
    if source "$PROJECT_ROOT/lib/enhanced_confirmation.sh" 2>/dev/null; then
        test_assert "風險等級常數已定義" "[[ -n '$RISK_CRITICAL' ]]"
    else
        test_assert "增強確認模組可載入" "false"
    fi
    
    echo ""
}

# 生成測試報告
generate_test_report() {
    echo -e "${BLUE}========================================================${NC}"
    echo -e "${BLUE}${BOLD}                   測試結果摘要${NC}"
    echo -e "${BLUE}========================================================${NC}"
    echo -e ""
    echo -e "總測試數: ${BOLD}$TOTAL_TESTS${NC}"
    echo -e "通過測試: ${GREEN}${BOLD}$PASSED_TESTS${NC}"
    echo -e "失敗測試: ${RED}${BOLD}$FAILED_TESTS${NC}"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e ""
        echo -e "${GREEN}${BOLD}🎉 所有測試通過！階段三集成成功！${NC}"
        echo -e ""
        echo -e "✅ 增強確認模組已集成"
        echo -e "✅ 環境管理器已更新"
        echo -e "✅ 增強環境選擇器已就緒"
        echo -e "✅ 安全機制已啟用"
    else
        echo -e ""
        echo -e "${YELLOW}⚠️  存在失敗的測試，需要檢查：${NC}"
        echo -e ""
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" == FAIL:* ]]; then
                echo -e "${RED}  • ${result#FAIL: }${NC}"
            fi
        done
    fi
    
    echo -e ""
    echo -e "${BLUE}階段三實施進度評估:${NC}"
    
    local progress_percentage=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    
    if [[ $progress_percentage -ge 90 ]]; then
        echo -e "${GREEN}進度: ${progress_percentage}% - 接近完成${NC}"
    elif [[ $progress_percentage -ge 70 ]]; then
        echo -e "${YELLOW}進度: ${progress_percentage}% - 大部分完成${NC}"
    else
        echo -e "${RED}進度: ${progress_percentage}% - 需要更多工作${NC}"
    fi
    
    echo -e "${BLUE}========================================================${NC}"
}

# 主執行流程
main() {
    show_test_header
    
    test_enhanced_confirmation_module
    test_env_manager_integration
    test_enhanced_env_selector
    test_environment_configurations
    test_directory_structure
    test_functional_integration
    test_security_mechanisms
    
    generate_test_report
    
    # 返回適當的退出代碼
    if [[ $FAILED_TESTS -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# 如果直接執行腳本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
