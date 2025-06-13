#!/bin/bash

# Admin Tools Profile 整合測試腳本
# 用途：測試所有 admin tools 的 profile 整合和跨帳戶安全功能
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

# Admin tools 列表
ADMIN_TOOLS=(
    "aws_vpn_admin.sh"
    "revoke_member_access.sh"
    "employee_offboarding.sh"
    "setup_csr_s3_bucket.sh"
    "publish_endpoints.sh"
    "process_csr_batch.sh"
    "sign_csr.sh"
)

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
    elif [ "$result" = "SKIP" ]; then
        echo -e "${YELLOW}⏭ SKIP${NC}: $test_name - $message"
        TEST_RESULTS+=("SKIP: $test_name - $message")
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗ FAIL${NC}: $test_name - $message"
        TEST_RESULTS+=("FAIL: $test_name - $message")
    fi
}

# 測試 admin tools 可用性
test_admin_tools_availability() {
    echo -e "${CYAN}=== 測試 Admin Tools 可用性 ===${NC}"
    
    for tool in "${ADMIN_TOOLS[@]}"; do
        local tool_path="$PARENT_DIR/admin-tools/$tool"
        
        if [ -f "$tool_path" ]; then
            record_test_result "$tool exists" "PASS"
            
            if [ -x "$tool_path" ]; then
                record_test_result "$tool is executable" "PASS"
            else
                record_test_result "$tool is executable" "FAIL" "File not executable"
            fi
        else
            record_test_result "$tool exists" "FAIL" "File not found"
        fi
    done
}

# 測試環境管理器整合
test_environment_manager_integration() {
    echo -e "${CYAN}=== 測試環境管理器整合 ===${NC}"
    
    for tool in "${ADMIN_TOOLS[@]}"; do
        local tool_path="$PARENT_DIR/admin-tools/$tool"
        
        if [ -f "$tool_path" ]; then
            # 檢查是否載入環境管理器
            if grep -q "source.*env_manager.sh" "$tool_path"; then
                record_test_result "$tool loads env_manager" "PASS"
            else
                record_test_result "$tool loads env_manager" "FAIL" "env_manager.sh not loaded"
            fi
            
            # 檢查是否初始化環境
            if grep -q "env_init_for_script" "$tool_path"; then
                record_test_result "$tool initializes environment" "PASS"
            else
                record_test_result "$tool initializes environment" "FAIL" "env_init_for_script not found"
            fi
        fi
    done
}

# 測試 AWS Profile 驗證整合
test_aws_profile_validation() {
    echo -e "${CYAN}=== 測試 AWS Profile 驗證整合 ===${NC}"
    
    for tool in "${ADMIN_TOOLS[@]}"; do
        local tool_path="$PARENT_DIR/admin-tools/$tool"
        
        if [ -f "$tool_path" ]; then
            # 檢查是否有 profile 驗證
            if grep -q "env_validate_profile_integration" "$tool_path"; then
                record_test_result "$tool validates AWS profile" "PASS"
            else
                record_test_result "$tool validates AWS profile" "FAIL" "Profile validation not found"
            fi
        fi
    done
}

# 測試 AWS CLI Wrapper 使用
test_aws_cli_wrapper_usage() {
    echo -e "${CYAN}=== 測試 AWS CLI Wrapper 使用 ===${NC}"
    
    for tool in "${ADMIN_TOOLS[@]}"; do
        local tool_path="$PARENT_DIR/admin-tools/$tool"
        
        if [ -f "$tool_path" ]; then
            # 檢查是否使用 aws_with_profile
            local aws_wrapper_count
            aws_wrapper_count=$(grep -c "aws_with_profile" "$tool_path" 2>/dev/null || echo "0")
            
            # 檢查是否有直接的 aws 調用（應該避免）
            local direct_aws_count
            direct_aws_count=$(grep -c "\\baws\\s" "$tool_path" 2>/dev/null || echo "0")
            
            if [ "$aws_wrapper_count" -gt 0 ]; then
                record_test_result "$tool uses aws_with_profile" "PASS"
            else
                # 某些工具可能不需要 AWS 操作
                if [ "$direct_aws_count" -eq 0 ]; then
                    record_test_result "$tool uses aws_with_profile" "SKIP" "No AWS operations detected"
                else
                    record_test_result "$tool uses aws_with_profile" "FAIL" "Uses direct AWS calls"
                fi
            fi
        fi
    done
}

# 測試環境感知標題顯示
test_environment_aware_headers() {
    echo -e "${CYAN}=== 測試環境感知標題顯示 ===${NC}"
    
    for tool in "${ADMIN_TOOLS[@]}"; do
        local tool_path="$PARENT_DIR/admin-tools/$tool"
        
        if [ -f "$tool_path" ]; then
            # 檢查是否使用環境感知標題
            if grep -q "show_env_aware_header" "$tool_path"; then
                record_test_result "$tool shows environment-aware header" "PASS"
            else
                record_test_result "$tool shows environment-aware header" "FAIL" "Environment header not found"
            fi
        fi
    done
}

# 測試 AWS Profile 資訊顯示
test_aws_profile_display() {
    echo -e "${CYAN}=== 測試 AWS Profile 資訊顯示 ===${NC}"
    
    for tool in "${ADMIN_TOOLS[@]}"; do
        local tool_path="$PARENT_DIR/admin-tools/$tool"
        
        if [ -f "$tool_path" ]; then
            # 檢查是否顯示 profile 資訊
            if grep -q "env_get_profile.*CURRENT_ENVIRONMENT" "$tool_path"; then
                record_test_result "$tool displays profile info" "PASS"
            else
                record_test_result "$tool displays profile info" "FAIL" "Profile info display not found"
            fi
        fi
    done
}

# 測試環境特定配置
test_environment_specific_configuration() {
    echo -e "${CYAN}=== 測試環境特定配置 ===${NC}"
    
    # 測試環境感知的預設值
    local tools_with_env_defaults=(
        "setup_csr_s3_bucket.sh"
        "publish_endpoints.sh"
        "process_csr_batch.sh"
    )
    
    for tool in "${tools_with_env_defaults[@]}"; do
        local tool_path="$PARENT_DIR/admin-tools/$tool"
        
        if [ -f "$tool_path" ]; then
            # 檢查是否有環境感知的預設值函數
            if grep -q "get_default_bucket_name\|CURRENT_ENVIRONMENT" "$tool_path"; then
                record_test_result "$tool has environment-aware defaults" "PASS"
            else
                record_test_result "$tool has environment-aware defaults" "FAIL" "Environment-aware defaults not found"
            fi
        fi
    done
}

# 測試 help/usage 參數
test_help_parameter_handling() {
    echo -e "${CYAN}=== 測試 Help 參數處理 ===${NC}"
    
    for tool in "${ADMIN_TOOLS[@]}"; do
        local tool_path="$PARENT_DIR/admin-tools/$tool"
        
        if [ -x "$tool_path" ]; then
            # 測試 --help 參數
            if "$tool_path" --help >/dev/null 2>&1; then
                record_test_result "$tool handles --help parameter" "PASS"
            elif "$tool_path" -h >/dev/null 2>&1; then
                record_test_result "$tool handles -h parameter" "PASS"
            else
                record_test_result "$tool handles help parameter" "FAIL" "Help parameter not working"
            fi
        fi
    done
}

# 測試錯誤處理和安全檢查
test_error_handling_and_security() {
    echo -e "${CYAN}=== 測試錯誤處理和安全檢查 ===${NC}"
    
    for tool in "${ADMIN_TOOLS[@]}"; do
        local tool_path="$PARENT_DIR/admin-tools/$tool"
        
        if [ -f "$tool_path" ]; then
            # 檢查是否有錯誤處理
            if grep -q "exit 1\|return 1\|handle_error" "$tool_path"; then
                record_test_result "$tool has error handling" "PASS"
            else
                record_test_result "$tool has error handling" "FAIL" "Error handling not found"
            fi
            
            # 檢查是否有安全確認（針對危險操作）
            if [[ "$tool" == *"revoke"* ]] || [[ "$tool" == *"offboarding"* ]]; then
                if grep -q "read -p.*確認\|確認.*y/n" "$tool_path"; then
                    record_test_result "$tool has security confirmation" "PASS"
                else
                    record_test_result "$tool has security confirmation" "FAIL" "Security confirmation not found"
                fi
            fi
        fi
    done
}

# 測試特定工具的高級功能
test_advanced_tool_features() {
    echo -e "${CYAN}=== 測試特定工具的高級功能 ===${NC}"
    
    # 測試 S3 bucket 工具的環境感知
    local s3_tool="$PARENT_DIR/admin-tools/setup_csr_s3_bucket.sh"
    if [ -f "$s3_tool" ]; then
        if grep -q "staging-vpn-csr-exchange\|production-vpn-csr-exchange" "$s3_tool"; then
            record_test_result "S3 bucket tool has environment-specific names" "PASS"
        else
            record_test_result "S3 bucket tool has environment-specific names" "FAIL" "Environment-specific naming not found"
        fi
    fi
    
    # 測試 CSR 簽署工具的零接觸功能
    local sign_tool="$PARENT_DIR/admin-tools/sign_csr.sh"
    if [ -f "$sign_tool" ]; then
        if grep -q "\-\-upload-s3\|upload_certificate_to_s3" "$sign_tool"; then
            record_test_result "CSR signing tool supports zero-touch upload" "PASS"
        else
            record_test_result "CSR signing tool supports zero-touch upload" "FAIL" "Zero-touch upload not found"
        fi
    fi
    
    # 測試批次處理工具的監控模式
    local batch_tool="$PARENT_DIR/admin-tools/process_csr_batch.sh"
    if [ -f "$batch_tool" ]; then
        if grep -q "monitor.*mode\|while true" "$batch_tool"; then
            record_test_result "Batch processing tool supports monitor mode" "PASS"
        else
            record_test_result "Batch processing tool supports monitor mode" "FAIL" "Monitor mode not found"
        fi
    fi
}

# 測試日誌記錄功能
test_logging_functionality() {
    echo -e "${CYAN}=== 測試日誌記錄功能 ===${NC}"
    
    for tool in "${ADMIN_TOOLS[@]}"; do
        local tool_path="$PARENT_DIR/admin-tools/$tool"
        
        if [ -f "$tool_path" ]; then
            # 檢查是否有日誌記錄
            if grep -q "log_message\|LOG_FILE\|logger" "$tool_path"; then
                record_test_result "$tool has logging capability" "PASS"
            else
                record_test_result "$tool has logging capability" "FAIL" "Logging not found"
            fi
        fi
    done
}

# 生成測試報告
generate_test_report() {
    echo -e "\n${CYAN}=== Admin Tools 測試報告 ===${NC}"
    echo -e "${BLUE}總測試數量: $TESTS_TOTAL${NC}"
    echo -e "${GREEN}通過: $TESTS_PASSED${NC}"
    echo -e "${RED}失敗: $TESTS_FAILED${NC}"
    
    local success_rate=0
    if [ $TESTS_TOTAL -gt 0 ]; then
        success_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
    fi
    echo -e "${YELLOW}成功率: $success_rate%${NC}"
    
    # 保存詳細報告
    local report_file="$SCRIPT_DIR/admin_tools_test_results_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "Admin Tools Profile 整合測試報告"
        echo "==============================="
        echo "測試時間: $(date)"
        echo "測試腳本: $0"
        echo ""
        echo "測試的 Admin Tools:"
        for tool in "${ADMIN_TOOLS[@]}"; do
            echo "  - $tool"
        done
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
        echo "評估結果:"
        echo "---------"
        if [ $success_rate -ge 90 ]; then
            echo "✓ 優秀 - Admin tools 已準備好投入生產使用"
        elif [ $success_rate -ge 75 ]; then
            echo "△ 良好 - 大部分功能正常，需要少量修復"
        else
            echo "⚠ 需要改進 - 請修復失敗的測試項目"
        fi
        echo ""
        echo "建議下一步:"
        echo "----------"
        if [ $TESTS_FAILED -eq 0 ]; then
            echo "✓ 所有測試通過，可以開始編寫用戶文檔"
            echo "✓ 準備進行完整的端到端測試"
            echo "✓ 可以開始培訓管理員使用新功能"
        else
            echo "⚠ 請修復失敗的測試項目"
            echo "⚠ 確保所有 admin tools 正確整合環境管理器"
            echo "⚠ 驗證 AWS CLI wrapper 的正確使用"
        fi
    } > "$report_file"
    
    echo -e "\n${GREEN}測試報告已保存到: $report_file${NC}"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# 主測試函數
main() {
    echo -e "${BLUE}Admin Tools Profile 整合測試開始${NC}"
    echo -e "${BLUE}===============================${NC}\n"
    
    # 初始化環境（如果尚未初始化）
    if ! env_init_for_script "test_admin_tools.sh" >/dev/null 2>&1; then
        echo -e "${YELLOW}注意: 環境管理器初始化失敗，但繼續測試${NC}"
    fi
    
    # 執行各項測試
    test_admin_tools_availability
    echo
    
    test_environment_manager_integration
    echo
    
    test_aws_profile_validation
    echo
    
    test_aws_cli_wrapper_usage
    echo
    
    test_environment_aware_headers
    echo
    
    test_aws_profile_display
    echo
    
    test_environment_specific_configuration
    echo
    
    test_help_parameter_handling
    echo
    
    test_error_handling_and_security
    echo
    
    test_advanced_tool_features
    echo
    
    test_logging_functionality
    echo
    
    # 生成報告
    generate_test_report
}

# 只有在腳本直接執行時才執行主程序
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi