#!/bin/bash

# Team Member Setup 雙 Profile 配置測試腳本
# 用途：測試 team_member_setup.sh 在雙 profile 環境下的功能
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
    elif [ "$result" = "SKIP" ]; then
        echo -e "${YELLOW}⏭ SKIP${NC}: $test_name - $message"
        TEST_RESULTS+=("SKIP: $test_name - $message")
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗ FAIL${NC}: $test_name - $message"
        TEST_RESULTS+=("FAIL: $test_name - $message")
    fi
}

# 測試 team_member_setup.sh 檔案存在和權限
test_script_availability() {
    echo -e "${CYAN}=== 測試腳本可用性 ===${NC}"
    
    local script_path="$PARENT_DIR/team_member_setup.sh"
    
    if [ -f "$script_path" ]; then
        record_test_result "team_member_setup.sh exists" "PASS"
        
        if [ -x "$script_path" ]; then
            record_test_result "team_member_setup.sh is executable" "PASS"
        else
            record_test_result "team_member_setup.sh is executable" "FAIL" "File not executable"
        fi
    else
        record_test_result "team_member_setup.sh exists" "FAIL" "File not found"
    fi
}

# 測試環境參數處理
test_environment_parameter_handling() {
    echo -e "${CYAN}=== 測試環境參數處理 ===${NC}"
    
    local script_path="$PARENT_DIR/team_member_setup.sh"
    
    if [ ! -x "$script_path" ]; then
        record_test_result "Environment parameter handling" "SKIP" "Script not available"
        return
    fi
    
    # 測試 --help 參數
    if "$script_path" --help >/dev/null 2>&1; then
        record_test_result "Help parameter works" "PASS"
    else
        record_test_result "Help parameter works" "FAIL" "Help command failed"
    fi
    
    # 測試無效環境參數（不實際執行設置）
    local help_output
    help_output=$("$script_path" --help 2>&1)
    if echo "$help_output" | grep -q "environment\|--env\|-e"; then
        record_test_result "Environment parameter documented" "PASS"
    else
        record_test_result "Environment parameter documented" "FAIL" "Environment parameter not found in help"
    fi
}

# 測試 profile 整合準備狀態
test_profile_integration_readiness() {
    echo -e "${CYAN}=== 測試 Profile 整合準備狀態 ===${NC}"
    
    # 檢查環境配置檔案中的 profile 變數
    for env in staging production; do
        local config_file="$PARENT_DIR/configs/$env/${env}.env"
        if [ -f "$config_file" ]; then
            if grep -q "ENV_AWS_PROFILE=" "$config_file"; then
                record_test_result "$env profile variable configured" "PASS"
            else
                record_test_result "$env profile variable configured" "FAIL" "ENV_AWS_PROFILE not found"
            fi
        else
            record_test_result "$env profile variable configured" "FAIL" "Config file not found"
        fi
    done
    
    # 檢查 S3 bucket 配置
    for env in staging production; do
        local config_file="$PARENT_DIR/configs/$env/${env}.env"
        if [ -f "$config_file" ]; then
            local bucket_var
            if [ "$env" = "staging" ]; then
                bucket_var="STAGING_S3_BUCKET"
            else
                bucket_var="PRODUCTION_S3_BUCKET"
            fi
            if grep -q "${bucket_var}=" "$config_file"; then
                record_test_result "$env S3 bucket configured" "PASS"
            else
                record_test_result "$env S3 bucket configured" "FAIL" "$bucket_var not found"
            fi
        fi
    done
}

# 測試零接觸工作流程依賴
test_zero_touch_dependencies() {
    echo -e "${CYAN}=== 測試零接觸工作流程依賴 ===${NC}"
    
    # 檢查必要的 admin 工具
    local admin_tools=(
        "setup_csr_s3_bucket.sh"
        "publish_endpoints.sh"
        "sign_csr.sh"
    )
    
    for tool in "${admin_tools[@]}"; do
        local tool_path="$PARENT_DIR/admin-tools/$tool"
        if [ -f "$tool_path" ] && [ -x "$tool_path" ]; then
            record_test_result "$tool available" "PASS"
        else
            record_test_result "$tool available" "FAIL" "Tool not found or not executable"
        fi
    done
    
    # 檢查所需的命令行工具
    local required_tools=("aws" "openssl" "jq")
    
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            record_test_result "$tool command available" "PASS"
        else
            record_test_result "$tool command available" "FAIL" "Command not found"
        fi
    done
}

# 測試環境切換功能
test_environment_switching() {
    echo -e "${CYAN}=== 測試環境切換功能 ===${NC}"
    
    # 保存當前環境
    local original_env="$CURRENT_ENVIRONMENT"
    
    # 測試環境狀態檢查
    if "$PARENT_DIR/vpn_env.sh" status >/dev/null 2>&1; then
        record_test_result "Environment status check" "PASS"
    else
        record_test_result "Environment status check" "FAIL" "Status command failed"
    fi
    
    # 測試 staging 環境（如果有配置）
    if [ -f "$PARENT_DIR/configs/staging/staging.env" ]; then
        # 這裡不實際切換，只檢查配置可用性
        record_test_result "Staging environment configured" "PASS"
    else
        record_test_result "Staging environment configured" "FAIL" "Staging config not found"
    fi
    
    # 測試 production 環境（如果有配置）
    if [ -f "$PARENT_DIR/configs/production/production.env" ]; then
        record_test_result "Production environment configured" "PASS"
    else
        record_test_result "Production environment configured" "FAIL" "Production config not found"
    fi
}

# 測試 DNS 和路由配置功能
test_dns_routing_configuration() {
    echo -e "${CYAN}=== 測試 DNS 和路由配置功能 ===${NC}"
    
    # 檢查是否有環境特定的區域配置
    for env in staging production; do
        local config_file="$PARENT_DIR/configs/$env/${env}.env"
        if [ -f "$config_file" ]; then
            if grep -q "AWS_REGION=" "$config_file"; then
                record_test_result "$env AWS region configured" "PASS"
            else
                record_test_result "$env AWS region configured" "FAIL" "AWS_REGION not found"
            fi
        fi
    done
    
    # 檢查 team_member_setup.sh 是否包含 DNS 配置代碼
    local script_path="$PARENT_DIR/team_member_setup.sh"
    if [ -f "$script_path" ]; then
        if grep -q "dhcp-option DNS\|compute.internal\|amazonaws.com" "$script_path"; then
            record_test_result "DNS configuration code present" "PASS"
        else
            record_test_result "DNS configuration code present" "FAIL" "DNS config code not found"
        fi
        
        # 檢查元數據服務路由
        if grep -q "169.254.169.254\|169.254.169.253" "$script_path"; then
            record_test_result "Metadata service routing present" "PASS"
        else
            record_test_result "Metadata service routing present" "FAIL" "Metadata routing not found"
        fi
    fi
}

# 測試安全配置
test_security_configuration() {
    echo -e "${CYAN}=== 測試安全配置 ===${NC}"
    
    # 檢查證書目錄結構
    for env in staging production; do
        local cert_dir="$PARENT_DIR/certs/$env"
        if [ -d "$cert_dir" ]; then
            record_test_result "$env certificate directory exists" "PASS"
        else
            record_test_result "$env certificate directory exists" "FAIL" "Directory not found"
        fi
    done
    
    # 檢查日誌目錄結構
    for env in staging production; do
        local log_dir="$PARENT_DIR/logs/$env"
        if [ -d "$log_dir" ]; then
            record_test_result "$env log directory exists" "PASS"
        else
            record_test_result "$env log directory exists" "FAIL" "Directory not found"
        fi
    done
    
    # 檢查權限設置（證書文件應該有受限權限）
    local cert_files
    cert_files=$(find "$PARENT_DIR/certs" -name "*.key" 2>/dev/null)
    
    local secure_permissions=true
    for cert_file in $cert_files; do
        local perms
        perms=$(stat -c "%a" "$cert_file" 2>/dev/null || stat -f "%A" "$cert_file" 2>/dev/null)
        if [[ "$perms" != "600" ]] && [[ "$perms" != "0600" ]]; then
            secure_permissions=false
            break
        fi
    done
    
    if [ "$secure_permissions" = true ]; then
        record_test_result "Certificate file permissions secure" "PASS"
    else
        record_test_result "Certificate file permissions secure" "FAIL" "Some cert files have loose permissions"
    fi
}

# 模擬工作流程測試（不實際執行，只檢查可行性）
test_workflow_simulation() {
    echo -e "${CYAN}=== 模擬工作流程測試 ===${NC}"
    
    # 檢查零接觸初始化的可能性
    local script_path="$PARENT_DIR/team_member_setup.sh"
    if [ -x "$script_path" ]; then
        # 檢查 --init 參數是否存在
        if "$script_path" --help 2>&1 | grep -q "\-\-init"; then
            record_test_result "Zero-touch init parameter available" "PASS"
        else
            record_test_result "Zero-touch init parameter available" "FAIL" "--init parameter not found"
        fi
        
        # 檢查 --resume 參數是否存在
        if "$script_path" --help 2>&1 | grep -q "\-\-resume"; then
            record_test_result "Zero-touch resume parameter available" "PASS"
        else
            record_test_result "Zero-touch resume parameter available" "FAIL" "--resume parameter not found"
        fi
    fi
    
    # 檢查 S3 bucket 設置工具可用性
    local bucket_tool="$PARENT_DIR/admin-tools/setup_csr_s3_bucket.sh"
    if [ -x "$bucket_tool" ]; then
        record_test_result "S3 bucket setup tool available" "PASS"
    else
        record_test_result "S3 bucket setup tool available" "FAIL" "Tool not executable"
    fi
}

# 生成測試報告
generate_test_report() {
    echo -e "\n${CYAN}=== Team Member Setup 測試報告 ===${NC}"
    echo -e "${BLUE}總測試數量: $TESTS_TOTAL${NC}"
    echo -e "${GREEN}通過: $TESTS_PASSED${NC}"
    echo -e "${RED}失敗: $TESTS_FAILED${NC}"
    
    local success_rate=0
    if [ $TESTS_TOTAL -gt 0 ]; then
        success_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
    fi
    echo -e "${YELLOW}成功率: $success_rate%${NC}"
    
    # 保存詳細報告
    local report_file="$SCRIPT_DIR/team_setup_test_results_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "Team Member Setup 雙 Profile 配置測試報告"
        echo "========================================"
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
        echo "建議下一步:"
        echo "----------"
        if [ $TESTS_FAILED -eq 0 ]; then
            echo "✓ 所有測試通過，可以進行實際的端到端測試"
            echo "✓ 建議在測試環境中執行完整的零接觸工作流程"
            echo "✓ 準備用戶文檔和培訓材料"
        else
            echo "⚠ 請修復失敗的測試項目"
            echo "⚠ 確保所有依賴工具已安裝"
            echo "⚠ 驗證環境配置檔案的完整性"
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
    echo -e "${BLUE}Team Member Setup 雙 Profile 配置測試開始${NC}"
    echo -e "${BLUE}=========================================${NC}\n"
    
    # 初始化環境（如果尚未初始化）
    if ! env_init_for_script "test_team_member_setup.sh" >/dev/null 2>&1; then
        echo -e "${YELLOW}注意: 環境管理器初始化失敗，但繼續測試${NC}"
    fi
    
    # 執行各項測試
    test_script_availability
    echo
    
    test_environment_parameter_handling
    echo
    
    test_profile_integration_readiness
    echo
    
    test_zero_touch_dependencies
    echo
    
    test_environment_switching
    echo
    
    test_dns_routing_configuration
    echo
    
    test_security_configuration
    echo
    
    test_workflow_simulation
    echo
    
    # 生成報告
    generate_test_report
}

# 只有在腳本直接執行時才執行主程序
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi