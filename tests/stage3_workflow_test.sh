#!/bin/bash

# 階段三工作流程測試
# 測試完整的使用者操作流程

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 測試計數器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 測試結果記錄
TEST_RESULTS=()

# 日誌函數
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
    TEST_RESULTS+=("✅ $1")
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
    TEST_RESULTS+=("❌ $1")
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 測試函數
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    ((TOTAL_TESTS++))
    log_info "執行測試: $test_name"
    
    # 執行測試命令
    if eval "$test_command"; then
        if [[ "$expected_result" == "success" ]]; then
            log_success "$test_name"
            return 0
        else
            log_error "$test_name (預期失敗但成功了)"
            return 1
        fi
    else
        if [[ "$expected_result" == "fail" ]]; then
            log_success "$test_name (預期失敗)"
            return 0
        else
            log_error "$test_name"
            return 1
        fi
    fi
}

# 效能測試函數
performance_test() {
    local test_name="$1"
    local test_command="$2"
    local max_time="$3"
    
    ((TOTAL_TESTS++))
    log_info "效能測試: $test_name (限時 ${max_time}s)"
    
    local start_time=$(date +%s.%N)
    if eval "$test_command" > /dev/null 2>&1; then
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l)
        local duration_int=$(echo "$duration" | cut -d. -f1)
        
        if (( duration_int <= max_time )); then
            log_success "$test_name (耗時: ${duration}s)"
            return 0
        else
            log_error "$test_name (耗時: ${duration}s, 超過限制 ${max_time}s)"
            return 1
        fi
    else
        log_error "$test_name (執行失敗)"
        return 1
    fi
}

echo -e "${PURPLE}========================================${NC}"
echo -e "${PURPLE}     階段三工作流程測試套件${NC}"
echo -e "${PURPLE}========================================${NC}"
echo

# 1. 環境準備測試
echo -e "${CYAN}=== 1. 環境準備測試 ===${NC}"

# 檢查核心檔案存在
run_test "檢查增強環境選擇器存在" \
    "[ -f '../enhanced_env_selector.sh' ]" \
    "success"

run_test "檢查增強確認模組存在" \
    "[ -f '../lib/enhanced_confirmation.sh' ]" \
    "success"

run_test "檢查環境管理器存在" \
    "[ -f '../lib/env_manager.sh' ]" \
    "success"

# 檢查環境配置檔案
run_test "檢查 staging 環境配置" \
    "[ -f '../envs/staging.env' ]" \
    "success"

run_test "檢查 production 環境配置" \
    "[ -f '../envs/production.env' ]" \
    "success"

echo

# 2. 模組載入測試
echo -e "${CYAN}=== 2. 模組載入測試 ===${NC}"

# 測試模組載入
run_test "載入環境管理器模組" \
    "source '../lib/env_manager.sh' 2>/dev/null" \
    "success"

run_test "載入增強確認模組" \
    "source '../lib/enhanced_confirmation.sh' 2>/dev/null" \
    "success"

# 檢查函數可用性
run_test "驗證環境管理器函數可用" \
    "source '../lib/env_manager.sh' && type env_load > /dev/null 2>&1" \
    "success"

run_test "驗證增強確認函數可用" \
    "source '../lib/enhanced_confirmation.sh' && type smart_operation_confirmation > /dev/null 2>&1" \
    "success"

echo

# 3. 基本功能測試
echo -e "${CYAN}=== 3. 基本功能測試 ===${NC}"

# 環境載入測試
run_test "測試 staging 環境載入" \
    "cd .. && source lib/env_manager.sh && env_load staging > /dev/null 2>&1" \
    "success"

run_test "測試環境狀態檢查" \
    "cd .. && source lib/env_manager.sh && env_load staging > /dev/null 2>&1 && env_status > /dev/null 2>&1" \
    "success"

run_test "測試環境驗證" \
    "cd .. && source lib/env_manager.sh && env_load staging > /dev/null 2>&1 && env_validate > /dev/null 2>&1" \
    "success"

echo

# 4. 效能測試
echo -e "${CYAN}=== 4. 效能測試 ===${NC}"

# 環境切換效能測試
performance_test "環境載入效能測試" \
    "cd .. && source lib/env_manager.sh && env_load staging" \
    10

performance_test "環境狀態檢查效能測試" \
    "cd .. && source lib/env_manager.sh && env_load staging && env_status" \
    5

performance_test "增強環境選擇器啟動測試" \
    "cd .. && timeout 5s bash enhanced_env_selector.sh <<< 'q'" \
    5

echo

# 5. 確認機制測試
echo -e "${CYAN}=== 5. 確認機制測試 ===${NC}"

# 測試不同風險等級的確認
run_test "測試低風險操作確認" \
    "cd .. && source lib/enhanced_confirmation.sh && echo 'y' | smart_operation_confirmation 'test_op' 1 'staging' > /dev/null 2>&1" \
    "success"

run_test "測試中風險操作確認" \
    "cd .. && source lib/enhanced_confirmation.sh && echo -e 'y\\ny' | smart_operation_confirmation 'test_op' 2 'staging' > /dev/null 2>&1" \
    "success"

# 測試生產環境保護
run_test "測試生產環境保護機制" \
    "cd .. && source lib/enhanced_confirmation.sh && echo -e 'PRODUCTION\\nyes' | enhanced_production_confirmation 'critical_op' > /dev/null 2>&1" \
    "success"

echo

# 6. 邊界條件測試
echo -e "${CYAN}=== 6. 邊界條件測試 ===${NC}"

# 測試不存在的環境
run_test "測試載入不存在環境 (應該失敗)" \
    "cd .. && source lib/env_manager.sh && env_load nonexistent_env > /dev/null 2>&1" \
    "fail"

# 測試空參數
run_test "測試空環境名稱 (應該失敗)" \
    "cd .. && source lib/env_manager.sh && env_load '' > /dev/null 2>&1" \
    "fail"

# 測試無效風險等級
run_test "測試無效風險等級 (應該使用預設值)" \
    "cd .. && source lib/enhanced_confirmation.sh && echo 'y' | smart_operation_confirmation 'test' 'invalid' 'staging' > /dev/null 2>&1" \
    "success"

echo

# 7. 整合工作流程測試
echo -e "${CYAN}=== 7. 整合工作流程測試 ===${NC}"

# 完整工作流程測試
run_test "完整環境切換工作流程" \
    "cd .. && source lib/env_manager.sh && source lib/enhanced_confirmation.sh && env_load staging > /dev/null 2>&1 && env_status > /dev/null 2>&1 && env_validate > /dev/null 2>&1" \
    "success"

# 測試環境管理器與確認系統整合
run_test "環境管理器與確認系統整合" \
    "cd .. && source lib/env_manager.sh && type env_enhanced_operation_confirm > /dev/null 2>&1 && type env_aware_operation > /dev/null 2>&1" \
    "success"

echo

# 8. 使用者體驗測試
echo -e "${CYAN}=== 8. 使用者體驗測試 ===${NC}"

# 測試腳本可執行性
run_test "增強環境選擇器可執行性" \
    "[ -x '../enhanced_env_selector.sh' ]" \
    "success"

# 測試腳本語法
run_test "增強環境選擇器語法檢查" \
    "bash -n '../enhanced_env_selector.sh'" \
    "success"

run_test "增強確認模組語法檢查" \
    "bash -n '../lib/enhanced_confirmation.sh'" \
    "success"

run_test "環境管理器語法檢查" \
    "bash -n '../lib/env_manager.sh'" \
    "success"

echo

# 測試結果摘要
echo -e "${PURPLE}========================================${NC}"
echo -e "${PURPLE}           測試結果摘要${NC}"
echo -e "${PURPLE}========================================${NC}"
echo
echo -e "${BLUE}總測試數:${NC} $TOTAL_TESTS"
echo -e "${GREEN}通過測試:${NC} $PASSED_TESTS"
echo -e "${RED}失敗測試:${NC} $FAILED_TESTS"
echo
echo -e "${BLUE}成功率:${NC} $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
echo

# 詳細結果
if [ ${#TEST_RESULTS[@]} -gt 0 ]; then
    echo -e "${CYAN}=== 詳細測試結果 ===${NC}"
    for result in "${TEST_RESULTS[@]}"; do
        echo "$result"
    done
    echo
fi

# 建議和下一步
echo -e "${CYAN}=== 建議和下一步 ===${NC}"
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}🎉 所有測試通過！階段三實施可以進入最終驗證階段。${NC}"
    echo
    echo "建議下一步："
    echo "1. 執行生產環境部署準備"
    echo "2. 進行使用者接受測試"
    echo "3. 更新使用者手冊"
    echo "4. 準備版本發布"
else
    echo -e "${YELLOW}⚠️  有 $FAILED_TESTS 個測試失敗，建議檢查以下項目：${NC}"
    echo
    echo "1. 檢查模組路徑和相依性"
    echo "2. 驗證環境配置檔案"
    echo "3. 確認權限設定"
    echo "4. 檢查系統相依性"
fi

echo
echo -e "${BLUE}測試完成時間:${NC} $(date)"
echo -e "${PURPLE}========================================${NC}"

# 回傳退出碼
if [ $FAILED_TESTS -eq 0 ]; then
    exit 0
else
    exit 1
fi
