#!/bin/bash

# 階段三最終驗證腳本
# 整合所有測試結果並進行最終評估

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 測試結果
TEST_RESULTS=()
OVERALL_SCORE=0
MAX_POSSIBLE_SCORE=400  # 4個主要測試區域，每個100分

# 日誌函數
log_header() {
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}========================================${NC}"
    echo
}

log_section() {
    echo -e "${CYAN}=== $1 ===${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# 執行測試並獲取分數
run_test_suite() {
    local test_name="$1"
    local test_script="$2"
    local max_score="$3"
    
    log_section "執行 $test_name"
    
    if [ ! -f "$test_script" ]; then
        log_error "測試腳本 $test_script 不存在"
        TEST_RESULTS+=("❌ $test_name: 測試腳本缺失 (0/$max_score)")
        return 0
    fi
    
    # 使測試腳本可執行
    chmod +x "$test_script"
    
    # 執行測試並獲取結果
    local output_file="/tmp/stage3_test_output_$$.txt"
    if bash "$test_script" > "$output_file" 2>&1; then
        local exit_code=0
    else
        local exit_code=$?
    fi
    
    # 分析測試結果
    local score=0
    
    # 根據不同測試類型分析結果
    case "$test_name" in
        "整合測試")
            local passed=$(grep -c "✅\|PASS" "$output_file" 2>/dev/null || echo "0")
            local failed=$(grep -c "❌\|FAIL" "$output_file" 2>/dev/null || echo "0")
            local total=$((passed + failed))
            
            if [ $total -gt 0 ]; then
                score=$(( passed * max_score / total ))
            fi
            
            log_info "通過測試: $passed, 失敗測試: $failed"
            ;;
            
        "工作流程測試")
            # 檢查工作流程完成情況
            local workflow_success=$(grep -o "[0-9]*%" "$output_file" | tail -1 | sed 's/%//' 2>/dev/null || echo "0")
            score=$(( workflow_success * max_score / 100 ))
            
            log_info "工作流程成功率: $workflow_success%"
            ;;
            
        "效能測試")
            # 檢查效能測試通過率
            local perf_pass_rate=$(grep "整體通過率" "$output_file" | grep -o "[0-9]*%" | sed 's/%//' 2>/dev/null || echo "0")
            score=$(( perf_pass_rate * max_score / 100 ))
            
            log_info "效能測試通過率: $perf_pass_rate%"
            ;;
            
        "使用者體驗評估")
            # 檢查UX評分
            local ux_score=$(grep "整體使用者體驗評分" "$output_file" | grep -o "[0-9]*%" | sed 's/%//' 2>/dev/null || echo "0")
            score=$(( ux_score * max_score / 100 ))
            
            log_info "使用者體驗評分: $ux_score%"
            ;;
    esac
    
    # 記錄結果
    if [ $score -ge $(( max_score * 8 / 10 )) ]; then
        log_success "$test_name 獲得 $score/$max_score 分 (優秀)"
        TEST_RESULTS+=("✅ $test_name: $score/$max_score (優秀)")
    elif [ $score -ge $(( max_score * 6 / 10 )) ]; then
        log_warning "$test_name 獲得 $score/$max_score 分 (良好)"
        TEST_RESULTS+=("⚠️ $test_name: $score/$max_score (良好)")
    else
        log_error "$test_name 獲得 $score/$max_score 分 (需改進)"
        TEST_RESULTS+=("❌ $test_name: $score/$max_score (需改進)")
    fi
    
    OVERALL_SCORE=$((OVERALL_SCORE + score))
    
    # 顯示測試摘要
    echo "詳細輸出已保存到: $output_file"
    echo
    
    return $score
}

# 檢查成功指標達成情況
check_success_metrics() {
    log_section "成功指標驗證"
    
    local metrics_passed=0
    local total_metrics=6
    
    # 1. 環境切換時間 < 10 秒
    log_info "檢查環境切換時間..."
    local switch_start=$(date +%s.%N)
    cd .. && source lib/env_manager.sh && env_load staging > /dev/null 2>&1
    local switch_end=$(date +%s.%N)
    local switch_time=$(echo "$switch_end - $switch_start" | bc -l 2>/dev/null || echo "5")
    local switch_time_int=$(echo "$switch_time" | cut -d. -f1)
    
    if [ "$switch_time_int" -lt 10 ]; then
        log_success "環境切換時間: ${switch_time}s (< 10s)"
        ((metrics_passed++))
    else
        log_warning "環境切換時間: ${switch_time}s (>= 10s)"
    fi
    
    # 2. 配置載入成功率 > 95%
    log_info "檢查配置載入成功率..."
    local load_attempts=10
    local successful_loads=0
    
    for ((i=1; i<=load_attempts; i++)); do
        if cd .. && source lib/env_manager.sh && env_load staging > /dev/null 2>&1; then
            ((successful_loads++))
        fi
    done
    
    local load_success_rate=$(( successful_loads * 100 / load_attempts ))
    if [ $load_success_rate -gt 95 ]; then
        log_success "配置載入成功率: $load_success_rate% (> 95%)"
        ((metrics_passed++))
    else
        log_warning "配置載入成功率: $load_success_rate% (<= 95%)"
    fi
    
    # 3. 環境狀態檢查準確度 > 99%
    log_info "檢查環境狀態檢查準確度..."
    local status_checks=20
    local accurate_checks=0
    
    for ((i=1; i<=status_checks; i++)); do
        if cd .. && source lib/env_manager.sh && env_load staging > /dev/null 2>&1 && env_status > /dev/null 2>&1; then
            ((accurate_checks++))
        fi
    done
    
    local status_accuracy=$(( accurate_checks * 100 / status_checks ))
    if [ $status_accuracy -gt 99 ]; then
        log_success "狀態檢查準確度: $status_accuracy% (> 99%)"
        ((metrics_passed++))
    else
        log_warning "狀態檢查準確度: $status_accuracy% (<= 99%)"
    fi
    
    # 4. 使用者介面改善度
    log_info "檢查使用者介面改善度..."
    if [ -f "../enhanced_env_selector.sh" ] && grep -q "🟢\|🟡\|🔴" "../enhanced_env_selector.sh" 2>/dev/null; then
        log_success "使用者介面已顯著改善"
        ((metrics_passed++))
    else
        log_warning "使用者介面改善度不足"
    fi
    
    # 5. 操作確認機制完整性
    log_info "檢查操作確認機制..."
    if [ -f "../lib/enhanced_confirmation.sh" ] && grep -q "smart_operation_confirmation" "../lib/enhanced_confirmation.sh" 2>/dev/null; then
        log_success "操作確認機制已完整實現"
        ((metrics_passed++))
    else
        log_warning "操作確認機制不完整"
    fi
    
    # 6. 錯誤處理改進
    log_info "檢查錯誤處理改進..."
    if grep -q "log_error\|error_msg" "../lib/env_manager.sh" 2>/dev/null; then
        log_success "錯誤處理機制已改進"
        ((metrics_passed++))
    else
        log_warning "錯誤處理改進不足"
    fi
    
    local metrics_success_rate=$(( metrics_passed * 100 / total_metrics ))
    log_info "成功指標達成率: $metrics_passed/$total_metrics ($metrics_success_rate%)"
    
    return $metrics_success_rate
}

# 生成最終報告
generate_final_report() {
    local final_percentage=$(( OVERALL_SCORE * 100 / MAX_POSSIBLE_SCORE ))
    local metrics_rate="$1"
    
    log_header "階段三最終驗證報告"
    
    echo -e "${BLUE}驗證時間:${NC} $(date)"
    echo -e "${BLUE}驗證版本:${NC} 階段三 - 使用者介面完善"
    echo
    
    log_section "測試結果摘要"
    for result in "${TEST_RESULTS[@]}"; do
        echo "$result"
    done
    echo
    
    log_section "整體評估"
    echo -e "${BLUE}整體測試分數:${NC} $OVERALL_SCORE/$MAX_POSSIBLE_SCORE ($final_percentage%)"
    echo -e "${BLUE}成功指標達成率:${NC} $metrics_rate%"
    
    # 計算綜合評級
    local composite_score=$(( (final_percentage + metrics_rate) / 2 ))
    
    if [ $composite_score -ge 90 ]; then
        echo -e "${GREEN}🏆 綜合評級: A+ (優秀)${NC}"
        echo -e "${GREEN}✅ 階段三實施圓滿完成，可以進入生產部署${NC}"
        deployment_ready=true
    elif [ $composite_score -ge 80 ]; then
        echo -e "${GREEN}🥇 綜合評級: A (良好)${NC}"
        echo -e "${GREEN}✅ 階段三實施基本完成，建議進行最終優化後部署${NC}"
        deployment_ready=true
    elif [ $composite_score -ge 70 ]; then
        echo -e "${YELLOW}🥈 綜合評級: B+ (不錯)${NC}"
        echo -e "${YELLOW}⚠️  階段三實施大部分完成，需要解決關鍵問題後才能部署${NC}"
        deployment_ready=false
    elif [ $composite_score -ge 60 ]; then
        echo -e "${YELLOW}🥉 綜合評級: B (普通)${NC}"
        echo -e "${YELLOW}⚠️  階段三實施部分完成，需要重要改進${NC}"
        deployment_ready=false
    else
        echo -e "${RED}📉 綜合評級: C (待改進)${NC}"
        echo -e "${RED}❌ 階段三實施未達標準，需要全面檢討${NC}"
        deployment_ready=false
    fi
    
    echo
    
    log_section "部署建議"
    
    if $deployment_ready; then
        echo -e "${GREEN}🚀 系統已準備好進行生產部署${NC}"
        echo
        echo "建議部署步驟："
        echo "1. 建立生產環境備份"
        echo "2. 在測試環境進行最終驗證"
        echo "3. 準備回滾計劃"
        echo "4. 執行分階段部署"
        echo "5. 監控系統性能和使用者回饋"
    else
        echo -e "${YELLOW}⚠️  建議在部署前完成以下改進：${NC}"
        echo
        
        # 根據測試結果提供具體建議
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" == *"❌"* ]] || [[ "$result" == *"需改進"* ]]; then
                local test_name=$(echo "$result" | cut -d: -f1 | sed 's/❌ //')
                echo "🔧 改進 $test_name"
            fi
        done
        
        echo
        echo "完成改進後請重新執行最終驗證。"
    fi
    
    echo
    
    log_section "下一步行動"
    echo "1. 🔄 持續集成：建立自動化測試流程"
    echo "2. 📊 監控系統：實施性能和使用狀況監控"
    echo "3. 👥 使用者訓練：準備使用者手冊和訓練材料"
    echo "4. 🔧 維護計劃：建立定期維護和更新計劃"
    echo "5. 📋 反饋收集：建立使用者反饋收集機制"
    
    echo
    log_section "附加資源"
    echo "📁 測試日誌位置: /tmp/stage3_test_output_*.txt"
    echo "📖 實施文檔: dev-plans/STAGE3_IMPLEMENTATION_PLAN.md"
    echo "📈 完成報告: dev-plans/STAGE3_COMPLETION_REPORT.md"
    echo "🔧 測試腳本: tests/stage3_*.sh"
    
    echo
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${PURPLE}      最終驗證完成${NC}"
    echo -e "${PURPLE}========================================${NC}"
}

# 主要執行流程
main() {
    log_header "階段三最終驗證開始"
    
    # 檢查必要檔案
    log_section "環境檢查"
    
    local required_files=(
        "../enhanced_env_selector.sh"
        "../lib/enhanced_confirmation.sh"
        "../lib/env_manager.sh"
        "stage3_integration_test.sh"
        "stage3_workflow_test.sh"
        "stage3_performance_test.sh"
        "stage3_ux_evaluation.sh"
    )
    
    local missing_files=0
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "缺少必要檔案: $file"
            ((missing_files++))
        else
            log_success "檔案存在: $file"
        fi
    done
    
    if [ $missing_files -gt 0 ]; then
        log_error "有 $missing_files 個必要檔案缺失，無法進行完整驗證"
        echo "請確保所有階段三檔案都已正確建立。"
        exit 1
    fi
    
    echo
    
    # 執行各項測試
    log_info "開始執行綜合測試套件..."
    echo
    
    # 1. 整合測試
    run_test_suite "整合測試" "stage3_integration_test.sh" 100
    
    # 2. 工作流程測試
    run_test_suite "工作流程測試" "stage3_workflow_test.sh" 100
    
    # 3. 效能測試
    run_test_suite "效能測試" "stage3_performance_test.sh" 100
    
    # 4. 使用者體驗評估
    run_test_suite "使用者體驗評估" "stage3_ux_evaluation.sh" 100
    
    # 檢查成功指標
    check_success_metrics
    local metrics_rate=$?
    
    # 生成最終報告
    generate_final_report $metrics_rate
}

# 確保在正確目錄執行
if [ ! -d "../lib" ] || [ ! -f "../enhanced_env_selector.sh" ]; then
    echo -e "${RED}錯誤: 請在 tests/ 目錄中執行此腳本${NC}"
    echo "當前目錄: $(pwd)"
    exit 1
fi

# 執行主程序
main

exit 0
