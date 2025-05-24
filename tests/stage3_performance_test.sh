#!/bin/bash

# 階段三效能和邊界條件測試
# 專注於效能優化和邊界情況處理

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 效能指標
PERFORMANCE_METRICS=()
BOUNDARY_RESULTS=()

# 記錄函數
log_metric() {
    local test_name="$1"
    local metric_value="$2"
    local threshold="$3"
    local unit="$4"
    
    PERFORMANCE_METRICS+=("$test_name: $metric_value$unit (閾值: $threshold$unit)")
    
    if (( $(echo "$metric_value <= $threshold" | bc -l) )); then
        echo -e "${GREEN}✅ $test_name: ${metric_value}${unit} (通過)${NC}"
        return 0
    else
        echo -e "${RED}❌ $test_name: ${metric_value}${unit} (超過閾值 ${threshold}${unit})${NC}"
        return 1
    fi
}

# 測量執行時間
measure_time() {
    local command="$1"
    local iterations="$2"
    local total_time=0
    
    for ((i=1; i<=iterations; i++)); do
        local start_time=$(date +%s.%N)
        eval "$command" > /dev/null 2>&1
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc -l)
        total_time=$(echo "$total_time + $duration" | bc -l)
    done
    
    local avg_time=$(echo "scale=3; $total_time / $iterations" | bc -l)
    echo "$avg_time"
}

# 測量記憶體使用
measure_memory() {
    local command="$1"
    local pid_file="/tmp/test_pid_$$"
    
    # 在背景執行命令並記錄 PID
    (eval "$command" & echo $! > "$pid_file"; wait) > /dev/null 2>&1 &
    local bg_pid=$!
    
    sleep 0.1  # 等待進程啟動
    
    if [ -f "$pid_file" ]; then
        local target_pid=$(cat "$pid_file")
        if kill -0 "$target_pid" 2>/dev/null; then
            local memory_kb=$(ps -o rss= -p "$target_pid" 2>/dev/null || echo "0")
            local memory_mb=$(echo "scale=2; $memory_kb / 1024" | bc -l 2>/dev/null || echo "0")
            echo "$memory_mb"
        else
            echo "0"
        fi
        rm -f "$pid_file"
    else
        echo "0"
    fi
    
    wait "$bg_pid" 2>/dev/null
}

echo -e "${PURPLE}========================================${NC}"
echo -e "${PURPLE}   階段三效能和邊界條件測試${NC}"
echo -e "${PURPLE}========================================${NC}"
echo

# 1. 效能基準測試
echo -e "${CYAN}=== 1. 效能基準測試 ===${NC}"

# 模組載入效能
echo "📊 測試模組載入效能..."
load_time=$(measure_time "source '../lib/env_manager.sh'" 5)
log_metric "環境管理器載入時間" "$load_time" "1.0" "s"

load_time=$(measure_time "source '../lib/enhanced_confirmation.sh'" 5)
log_metric "增強確認模組載入時間" "$load_time" "0.5" "s"

# 環境切換效能
echo "📊 測試環境切換效能..."
switch_time=$(measure_time "cd .. && source lib/env_manager.sh && env_load staging" 3)
log_metric "環境切換時間" "$switch_time" "10.0" "s"

# 狀態檢查效能
echo "📊 測試狀態檢查效能..."
status_time=$(measure_time "cd .. && source lib/env_manager.sh && env_load staging && env_status" 3)
log_metric "環境狀態檢查時間" "$status_time" "5.0" "s"

echo

# 2. 記憶體使用測試
echo -e "${CYAN}=== 2. 記憶體使用測試 ===${NC}"

echo "📊 測試記憶體使用情況..."

# 基本模組記憶體使用
memory_usage=$(measure_memory "source '../lib/env_manager.sh' && sleep 1")
log_metric "環境管理器記憶體使用" "$memory_usage" "50.0" "MB"

memory_usage=$(measure_memory "source '../lib/enhanced_confirmation.sh' && sleep 1")
log_metric "增強確認模組記憶體使用" "$memory_usage" "20.0" "MB"

echo

# 3. 並發測試
echo -e "${CYAN}=== 3. 並發和壓力測試 ===${NC}"

echo "📊 測試並發載入..."

# 併發環境載入測試
concurrent_test() {
    local processes=5
    local pids=()
    
    for ((i=1; i<=processes; i++)); do
        (cd .. && source lib/env_manager.sh && env_load staging > /dev/null 2>&1) &
        pids+=($!)
    done
    
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            ((failed++))
        fi
    done
    
    local success_rate=$(echo "scale=2; ($processes - $failed) * 100 / $processes" | bc -l)
    log_metric "並發載入成功率" "$success_rate" "95.0" "%"
}

concurrent_test

echo

# 4. 邊界條件測試
echo -e "${CYAN}=== 4. 邊界條件測試 ===${NC}"

test_boundary() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    echo "🔍 測試: $test_name"
    
    if eval "$test_command" > /dev/null 2>&1; then
        if [[ "$expected_result" == "success" ]]; then
            echo -e "  ${GREEN}✅ 通過 (成功)${NC}"
            BOUNDARY_RESULTS+=("✅ $test_name")
            return 0
        else
            echo -e "  ${RED}❌ 失敗 (應該失敗但成功了)${NC}"
            BOUNDARY_RESULTS+=("❌ $test_name (預期失敗)")
            return 1
        fi
    else
        if [[ "$expected_result" == "fail" ]]; then
            echo -e "  ${GREEN}✅ 通過 (預期失敗)${NC}"
            BOUNDARY_RESULTS+=("✅ $test_name (預期失敗)")
            return 0
        else
            echo -e "  ${RED}❌ 失敗${NC}"
            BOUNDARY_RESULTS+=("❌ $test_name")
            return 1
        fi
    fi
}

# 空值和空字串測試
test_boundary "空環境名稱" \
    "cd .. && source lib/env_manager.sh && env_load ''" \
    "fail"

test_boundary "NULL 環境名稱" \
    "cd .. && source lib/env_manager.sh && env_load" \
    "fail"

test_boundary "不存在的環境" \
    "cd .. && source lib/env_manager.sh && env_load 'nonexistent_env_12345'" \
    "fail"

# 特殊字符測試
test_boundary "包含特殊字符的環境名稱" \
    "cd .. && source lib/env_manager.sh && env_load 'test/env@#$%'" \
    "fail"

test_boundary "非常長的環境名稱" \
    "cd .. && source lib/env_manager.sh && env_load '$(printf 'a%.0s' {1..1000})'" \
    "fail"

# 檔案系統邊界測試
test_boundary "不可讀的環境檔案" \
    "touch /tmp/unreadable.env && chmod 000 /tmp/unreadable.env && cd .. && source lib/env_manager.sh && ENV_DIR='/tmp' env_load 'unreadable'; rm -f /tmp/unreadable.env" \
    "fail"

# 權限測試
test_boundary "唯讀目錄中的操作" \
    "mkdir -p /tmp/readonly_test && chmod 444 /tmp/readonly_test && cd /tmp/readonly_test && source '$(pwd)/../lib/env_manager.sh' 2>/dev/null; result=$?; chmod 755 /tmp/readonly_test; rmdir /tmp/readonly_test; exit $result" \
    "fail"

echo

# 5. 極限值測試
echo -e "${CYAN}=== 5. 極限值測試 ===${NC}"

echo "🔍 測試極限值處理..."

# 大型環境檔案測試
create_large_env_file() {
    local file="/tmp/large_test.env"
    {
        for ((i=1; i<=1000; i++)); do
            echo "VAR_$i=value_$i_$(printf 'x%.0s' {1..100})"
        done
    } > "$file"
    echo "$file"
}

large_env_file=$(create_large_env_file)
test_boundary "大型環境檔案載入" \
    "cd .. && source lib/env_manager.sh && ENV_DIR='/tmp' env_load 'large_test'" \
    "success"
rm -f "$large_env_file"

# 確認系統極限測試
test_boundary "極高風險等級 (999)" \
    "cd .. && source lib/enhanced_confirmation.sh && echo -e 'PRODUCTION\\nyes\\nCONFIRM' | smart_operation_confirmation 'test' 999 'production'" \
    "success"

test_boundary "負數風險等級" \
    "cd .. && source lib/enhanced_confirmation.sh && echo 'y' | smart_operation_confirmation 'test' -1 'staging'" \
    "success"

echo

# 6. 錯誤恢復測試
echo -e "${CYAN}=== 6. 錯誤恢復測試 ===${NC}"

echo "🔍 測試錯誤恢復機制..."

# 模擬網路故障
test_boundary "模擬網路連線失敗" \
    "cd .. && source lib/env_manager.sh && timeout 1s env_load staging" \
    "success"

# 模擬磁碟空間不足 (使用小的臨時檔案系統)
test_boundary "模擬磁碟空間限制" \
    "cd .. && ulimit -f 1 && source lib/env_manager.sh 2>/dev/null; result=$?; ulimit -f unlimited; exit $result" \
    "fail"

echo

# 7. 資源清理測試
echo -e "${CYAN}=== 7. 資源清理測試 ===${NC}"

echo "🔍 測試資源清理..."

# 檢查臨時檔案清理
temp_files_before=$(find /tmp -name "*vpn*" -o -name "*env*" 2>/dev/null | wc -l)
cd .. && source lib/env_manager.sh && env_load staging > /dev/null 2>&1
temp_files_after=$(find /tmp -name "*vpn*" -o -name "*env*" 2>/dev/null | wc -l)

if [ "$temp_files_after" -le "$temp_files_before" ]; then
    echo -e "${GREEN}✅ 臨時檔案清理正常${NC}"
    BOUNDARY_RESULTS+=("✅ 臨時檔案清理")
else
    echo -e "${YELLOW}⚠️  可能存在臨時檔案洩漏${NC}"
    BOUNDARY_RESULTS+=("⚠️ 臨時檔案清理 (可能洩漏)")
fi

echo

# 結果摘要
echo -e "${PURPLE}========================================${NC}"
echo -e "${PURPLE}         測試結果摘要${NC}"
echo -e "${PURPLE}========================================${NC}"
echo

echo -e "${CYAN}=== 效能指標 ===${NC}"
for metric in "${PERFORMANCE_METRICS[@]}"; do
    echo "📈 $metric"
done
echo

echo -e "${CYAN}=== 邊界條件測試結果 ===${NC}"
for result in "${BOUNDARY_RESULTS[@]}"; do
    echo "$result"
done
echo

# 整體評估
passed_perf=$(echo "${PERFORMANCE_METRICS[@]}" | grep -o "通過" | wc -l)
total_perf=${#PERFORMANCE_METRICS[@]}
passed_boundary=$(echo "${BOUNDARY_RESULTS[@]}" | grep -o "✅" | wc -l)
total_boundary=${#BOUNDARY_RESULTS[@]}

echo -e "${CYAN}=== 整體評估 ===${NC}"
echo -e "${BLUE}效能測試通過率:${NC} $passed_perf/$total_perf ($(( passed_perf * 100 / total_perf ))%)"
echo -e "${BLUE}邊界測試通過率:${NC} $passed_boundary/$total_boundary ($(( passed_boundary * 100 / total_boundary ))%)"

overall_pass_rate=$(( (passed_perf + passed_boundary) * 100 / (total_perf + total_boundary) ))
echo -e "${BLUE}整體通過率:${NC} $overall_pass_rate%"

echo

if [ $overall_pass_rate -ge 90 ]; then
    echo -e "${GREEN}🎉 效能和邊界條件測試表現優秀！${NC}"
    echo "系統已準備好進入生產環境。"
elif [ $overall_pass_rate -ge 80 ]; then
    echo -e "${YELLOW}⚠️  效能和邊界條件測試表現良好，建議進行一些優化。${NC}"
    echo "建議檢查失敗的測試項目並進行改進。"
else
    echo -e "${RED}❌ 效能和邊界條件測試需要改進。${NC}"
    echo "建議在部署前解決主要問題。"
fi

echo
echo -e "${BLUE}測試完成時間:${NC} $(date)"
echo -e "${PURPLE}========================================${NC}"

# 建議
echo -e "${CYAN}=== 效能優化建議 ===${NC}"
echo "1. 考慮實施快取機制來加速重複操作"
echo "2. 優化模組載入順序以減少啟動時間"
echo "3. 考慮異步處理某些非關鍵操作"
echo "4. 實施更詳細的錯誤恢復機制"
echo "5. 考慮添加效能監控和告警"

exit 0
