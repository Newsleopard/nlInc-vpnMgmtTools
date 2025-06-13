#!/bin/bash

# 雙 AWS Profile 管理功能測試腳本
# 用途：測試 Phase 1-3 實施的所有 profile 管理功能
# 版本：1.0

# 設定測試環境
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# 載入測試所需的庫
source "$PARENT_DIR/lib/env_manager.sh"
source "$PARENT_DIR/lib/core_functions.sh"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 測試結果計數器
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# 測試結果記錄
TEST_RESULTS=()

# 記錄測試結果
record_test_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [ "$result" = "PASS" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        TEST_RESULTS+=("PASS: $test_name")
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗ FAIL${NC}: $test_name - $message"
        TEST_RESULTS+=("FAIL: $test_name - $message")
    fi
}

# 測試 AWS CLI wrapper 函數
test_aws_wrapper_functions() {
    echo -e "${CYAN}=== 測試 AWS CLI Wrapper 函數 ===${NC}"
    
    # 測試 aws_with_profile 函數存在
    if declare -f aws_with_profile >/dev/null; then
        record_test_result "aws_with_profile function exists" "PASS"
    else
        record_test_result "aws_with_profile function exists" "FAIL" "Function not found"
    fi
    
    # 測試 aws_with_env_profile 函數存在
    if declare -f aws_with_env_profile >/dev/null; then
        record_test_result "aws_with_env_profile function exists" "PASS"
    else
        record_test_result "aws_with_env_profile function exists" "FAIL" "Function not found"
    fi
    
    # 測試 AWS profile 檢測（如果有可用的 profiles）
    local available_profiles
    available_profiles=$(aws configure list-profiles 2>/dev/null)
    if [ -n "$available_profiles" ]; then
        local first_profile
        first_profile=$(echo "$available_profiles" | head -1)
        
        # 測試 aws_with_profile 基本調用
        if aws_with_profile sts get-caller-identity --profile "$first_profile" >/dev/null 2>&1; then
            record_test_result "aws_with_profile basic call" "PASS"
        else
            record_test_result "aws_with_profile basic call" "FAIL" "AWS call failed with profile $first_profile"
        fi
    else
        record_test_result "aws_with_profile basic call" "FAIL" "No AWS profiles configured"
    fi
}

# 測試 profile 管理函數
test_profile_management_functions() {
    echo -e "${CYAN}=== 測試 Profile 管理函數 ===${NC}"
    
    # 測試所有核心函數是否存在
    local functions=(
        "detect_available_aws_profiles"
        "detect_environment_from_profile"
        "validate_aws_profile_config"
        "map_environment_to_profiles"
        "validate_profile_matches_environment"
        "select_aws_profile_for_environment"
        "load_profile_from_config"
        "save_profile_to_config"
        "get_env_default_profile"
        "get_env_profile"
    )
    
    for func in "${functions[@]}"; do
        if declare -f "$func" >/dev/null; then
            record_test_result "$func function exists" "PASS"
        else
            record_test_result "$func function exists" "FAIL" "Function not found"
        fi
    done
    
    # 測試 profile 檢測功能
    local profiles
    profiles=$(detect_available_aws_profiles 2>/dev/null)
    if [ $? -eq 0 ]; then
        record_test_result "detect_available_aws_profiles execution" "PASS"
    else
        record_test_result "detect_available_aws_profiles execution" "FAIL" "Function execution failed"
    fi
    
    # 測試環境到 profile 的映射
    local staging_suggestions
    staging_suggestions=$(map_environment_to_profiles "staging" 2>/dev/null)
    if [ $? -eq 0 ]; then
        record_test_result "map_environment_to_profiles for staging" "PASS"
    else
        record_test_result "map_environment_to_profiles for staging" "FAIL" "Function execution failed"
    fi
    
    local production_suggestions
    production_suggestions=$(map_environment_to_profiles "production" 2>/dev/null)
    if [ $? -eq 0 ]; then
        record_test_result "map_environment_to_profiles for production" "PASS"
    else
        record_test_result "map_environment_to_profiles for production" "FAIL" "Function execution failed"
    fi
}

# 測試環境管理器整合
test_environment_manager_integration() {
    echo -e "${CYAN}=== 測試環境管理器整合 ===${NC}"
    
    # 測試環境管理器函數存在
    local env_functions=(
        "env_set_profile"
        "env_get_profile"
        "env_validate_profile_integration"
        "env_load_with_profile"
        "env_switch_with_profile"
    )
    
    for func in "${env_functions[@]}"; do
        if declare -f "$func" >/dev/null; then
            record_test_result "$func function exists" "PASS"
        else
            record_test_result "$func function exists" "FAIL" "Function not found"
        fi
    done
    
    # 測試當前環境檢測
    if [ -n "$CURRENT_ENVIRONMENT" ]; then
        record_test_result "CURRENT_ENVIRONMENT variable set" "PASS"
    else
        record_test_result "CURRENT_ENVIRONMENT variable set" "FAIL" "Variable not set"
    fi
    
    # 測試 profile 驗證功能
    if env_validate_profile_integration "$CURRENT_ENVIRONMENT" "false" >/dev/null 2>&1; then
        record_test_result "env_validate_profile_integration execution" "PASS"
    else
        record_test_result "env_validate_profile_integration execution" "FAIL" "Function execution failed"
    fi
}

# 測試配置文件整合
test_configuration_integration() {
    echo -e "${CYAN}=== 測試配置文件整合 ===${NC}"
    
    # 檢查環境配置文件
    for env in staging production; do
        local config_file="$PARENT_DIR/configs/$env/${env}.env"
        if [ -f "$config_file" ]; then
            record_test_result "$env environment config exists" "PASS"
            
            # 檢查必要變數是否存在
            if grep -q "ENV_AWS_PROFILE=" "$config_file"; then
                record_test_result "$env ENV_AWS_PROFILE variable exists" "PASS"
            else
                record_test_result "$env ENV_AWS_PROFILE variable exists" "FAIL" "Variable not found in config"
            fi
            
            if grep -q "STAGING_ACCOUNT_ID=\|PRODUCTION_ACCOUNT_ID=" "$config_file"; then
                record_test_result "$env account ID variable exists" "PASS"
            else
                record_test_result "$env account ID variable exists" "FAIL" "Account ID variable not found"
            fi
        else
            record_test_result "$env environment config exists" "FAIL" "Config file not found"
        fi
    done
}

# 測試錯誤處理和邊界情況
test_error_handling() {
    echo -e "${CYAN}=== 測試錯誤處理 ===${NC}"
    
    # 測試無效環境名稱
    if ! validate_profile_matches_environment "default" "invalid_environment" >/dev/null 2>&1; then
        record_test_result "Invalid environment rejection" "PASS"
    else
        record_test_result "Invalid environment rejection" "FAIL" "Should reject invalid environment"
    fi
    
    # 測試無效 profile 名稱
    if ! validate_aws_profile_config "nonexistent_profile" >/dev/null 2>&1; then
        record_test_result "Invalid profile rejection" "PASS"
    else
        record_test_result "Invalid profile rejection" "FAIL" "Should reject nonexistent profile"
    fi
    
    # 測試空參數處理
    if ! map_environment_to_profiles "" >/dev/null 2>&1; then
        record_test_result "Empty parameter handling" "PASS"
    else
        record_test_result "Empty parameter handling" "FAIL" "Should handle empty parameters gracefully"
    fi
}

# 測試真實 AWS 操作（可選，需要有效憑證）
test_real_aws_operations() {
    echo -e "${CYAN}=== 測試真實 AWS 操作（可選） ===${NC}"
    
    local available_profiles
    available_profiles=$(aws configure list-profiles 2>/dev/null)
    
    if [ -z "$available_profiles" ]; then
        record_test_result "Real AWS operations" "SKIP" "No AWS profiles configured"
        return
    fi
    
    local first_profile
    first_profile=$(echo "$available_profiles" | head -1)
    
    # 測試身份驗證
    local identity
    identity=$(aws_with_profile sts get-caller-identity --profile "$first_profile" 2>/dev/null)
    if [ $? -eq 0 ]; then
        record_test_result "AWS identity verification" "PASS"
        
        # 測試帳戶 ID 提取
        local account_id
        account_id=$(echo "$identity" | jq -r '.Account' 2>/dev/null)
        if [ -n "$account_id" ] && [ "$account_id" != "null" ]; then
            record_test_result "Account ID extraction" "PASS"
        else
            record_test_result "Account ID extraction" "FAIL" "Could not extract account ID"
        fi
    else
        record_test_result "AWS identity verification" "FAIL" "AWS authentication failed"
    fi
}

# 生成測試報告
generate_test_report() {
    echo -e "\n${CYAN}=== 測試報告 ===${NC}"
    echo -e "${BLUE}總測試數量: $TESTS_TOTAL${NC}"
    echo -e "${GREEN}通過: $TESTS_PASSED${NC}"
    echo -e "${RED}失敗: $TESTS_FAILED${NC}"
    
    local success_rate=0
    if [ $TESTS_TOTAL -gt 0 ]; then
        success_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
    fi
    echo -e "${YELLOW}成功率: $success_rate%${NC}"
    
    # 保存詳細報告
    local report_file="$SCRIPT_DIR/test_results_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "雙 AWS Profile 管理功能測試報告"
        echo "================================="
        echo "測試時間: $(date)"
        echo "測試腳本: $0"
        echo ""
        echo "總計: $TESTS_TOTAL 個測試"
        echo "通過: $TESTS_PASSED 個"
        echo "失敗: $TESTS_FAILED 個"
        echo "成功率: $success_rate%"
        echo ""
        echo "詳細結果:"
        echo "----------"
        for result in "${TEST_RESULTS[@]}"; do
            echo "$result"
        done
        echo ""
        echo "建議:"
        echo "-----"
        if [ $TESTS_FAILED -gt 0 ]; then
            echo "- 請檢查失敗的測試項目並修復相關問題"
            echo "- 確保所有必要的函數都已正確實施"
            echo "- 驗證 AWS 配置和憑證設置"
        else
            echo "- 所有測試通過，系統已準備就緒"
            echo "- 可以繼續進行用戶驗收測試"
        fi
    } > "$report_file"
    
    echo -e "\n${GREEN}測試報告已保存到: $report_file${NC}"
    
    # 根據結果設置退出碼
    if [ $TESTS_FAILED -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# 主測試函數
main() {
    echo -e "${BLUE}雙 AWS Profile 管理功能測試開始${NC}"
    echo -e "${BLUE}==============================${NC}\n"
    
    # 初始化環境（如果尚未初始化）
    if ! env_init_for_script "test_profile_management.sh" >/dev/null 2>&1; then
        echo -e "${YELLOW}注意: 環境管理器初始化失敗，但繼續測試${NC}"
    fi
    
    # 執行各項測試
    test_aws_wrapper_functions
    echo
    
    test_profile_management_functions
    echo
    
    test_environment_manager_integration
    echo
    
    test_configuration_integration
    echo
    
    test_error_handling
    echo
    
    test_real_aws_operations
    echo
    
    # 生成報告
    generate_test_report
}

# 只有在腳本直接執行時才執行主程序
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi