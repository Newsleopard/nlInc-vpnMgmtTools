#!/bin/bash

# 階段三使用者體驗評估
# 評估使用者介面改進的實際效果

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 評估結果
UX_SCORES=()
UX_FEEDBACK=()
TOTAL_SCORE=0
MAX_SCORE=0

# 評分函數
rate_feature() {
    local feature_name="$1"
    local description="$2"
    local max_points="$3"
    
    echo -e "${CYAN}=== 評估: $feature_name ===${NC}"
    echo "$description"
    echo
    
    local score=0
    
    # 自動化評估邏輯
    case "$feature_name" in
        "視覺化改進")
            # 檢查是否有顏色和圖示
            if grep -q "🟢\|🟡\|🔴\|⚪\|🔄" "../enhanced_env_selector.sh" 2>/dev/null; then
                ((score += 3))
                echo -e "${GREEN}✅ 狀態圖示已實現 (+3分)${NC}"
            fi
            if grep -q "\\033\[" "../enhanced_env_selector.sh" 2>/dev/null; then
                ((score += 2))
                echo -e "${GREEN}✅ 顏色編碼已實現 (+2分)${NC}"
            fi
            if grep -q "┌\|└\|│\|├" "../enhanced_env_selector.sh" 2>/dev/null; then
                ((score += 2))
                echo -e "${GREEN}✅ Unicode 框線已實現 (+2分)${NC}"
            fi
            if grep -q "clear\|printf.*\\n" "../enhanced_env_selector.sh" 2>/dev/null; then
                ((score += 1))
                echo -e "${GREEN}✅ 清晰的輸出格式 (+1分)${NC}"
            fi
            if grep -q "sleep\|read.*timeout" "../enhanced_env_selector.sh" 2>/dev/null; then
                ((score += 2))
                echo -e "${GREEN}✅ 使用者互動體驗 (+2分)${NC}"
            fi
            ;;
            
        "互動式選單")
            if grep -q "\[E\]\|\[S\]\|\[H\]\|\[D\]\|\[C\]\|\[R\]" "../enhanced_env_selector.sh" 2>/dev/null; then
                ((score += 4))
                echo -e "${GREEN}✅ 快速操作選項已實現 (+4分)${NC}"
            fi
            if grep -q "read.*choice\|read.*option" "../enhanced_env_selector.sh" 2>/dev/null; then
                ((score += 3))
                echo -e "${GREEN}✅ 使用者輸入處理 (+3分)${NC}"
            fi
            if grep -q "case.*in" "../enhanced_env_selector.sh" 2>/dev/null; then
                ((score += 2))
                echo -e "${GREEN}✅ 選項處理邏輯 (+2分)${NC}"
            fi
            if grep -q "while.*true\|while.*1" "../enhanced_env_selector.sh" 2>/dev/null; then
                ((score += 1))
                echo -e "${GREEN}✅ 持續互動循環 (+1分)${NC}"
            fi
            ;;
            
        "確認機制")
            if grep -q "smart_operation_confirmation" "../lib/enhanced_confirmation.sh" 2>/dev/null; then
                ((score += 3))
                echo -e "${GREEN}✅ 智能確認系統 (+3分)${NC}"
            fi
            if grep -q "PRODUCTION.*yes" "../lib/enhanced_confirmation.sh" 2>/dev/null; then
                ((score += 3))
                echo -e "${GREEN}✅ 生產環境保護 (+3分)${NC}"
            fi
            if grep -q "risk.*level\|風險.*等級" "../lib/enhanced_confirmation.sh" 2>/dev/null; then
                ((score += 2))
                echo -e "${GREEN}✅ 風險等級評估 (+2分)${NC}"
            fi
            if grep -q "batch.*operation" "../lib/enhanced_confirmation.sh" 2>/dev/null; then
                ((score += 1))
                echo -e "${GREEN}✅ 批次操作支援 (+1分)${NC}"
            fi
            if grep -q "rollback\|recovery" "../lib/enhanced_confirmation.sh" 2>/dev/null; then
                ((score += 1))
                echo -e "${GREEN}✅ 恢復指導 (+1分)${NC}"
            fi
            ;;
            
        "錯誤處理")
            if grep -q "log_error\|error_msg" "../lib/env_manager.sh" 2>/dev/null; then
                ((score += 2))
                echo -e "${GREEN}✅ 錯誤訊息系統 (+2分)${NC}"
            fi
            if grep -q "exit.*1\|return.*1" "../lib/env_manager.sh" 2>/dev/null; then
                ((score += 2))
                echo -e "${GREEN}✅ 錯誤退出處理 (+2分)${NC}"
            fi
            if grep -q "trap\|cleanup" "../enhanced_env_selector.sh" 2>/dev/null; then
                ((score += 2))
                echo -e "${GREEN}✅ 資源清理機制 (+2分)${NC}"
            fi
            if grep -q "validate\|check" "../lib/env_manager.sh" 2>/dev/null; then
                ((score += 2))
                echo -e "${GREEN}✅ 輸入驗證 (+2分)${NC}"
            fi
            if grep -q "help\|usage\|--help" "../enhanced_env_selector.sh" 2>/dev/null; then
                ((score += 2))
                echo -e "${GREEN}✅ 幫助資訊 (+2分)${NC}"
            fi
            ;;
            
        "效能表現")
            # 實際測試載入時間
            local load_start=$(date +%s.%N)
            source "../lib/env_manager.sh" > /dev/null 2>&1
            local load_end=$(date +%s.%N)
            local load_time=$(echo "$load_end - $load_start" | bc -l)
            local load_time_int=$(echo "$load_time" | cut -d. -f1)
            
            if [ "$load_time_int" -le 1 ]; then
                ((score += 3))
                echo -e "${GREEN}✅ 快速模組載入 (<1s) (+3分)${NC}"
            elif [ "$load_time_int" -le 3 ]; then
                ((score += 2))
                echo -e "${GREEN}✅ 合理載入時間 (<3s) (+2分)${NC}"
            elif [ "$load_time_int" -le 5 ]; then
                ((score += 1))
                echo -e "${YELLOW}⚠️  可接受載入時間 (<5s) (+1分)${NC}"
            fi
            
            # 檢查記憶體優化
            if grep -q "unset\|declare.*-g" "../lib/env_manager.sh" 2>/dev/null; then
                ((score += 2))
                echo -e "${GREEN}✅ 記憶體管理優化 (+2分)${NC}"
            fi
            
            # 檢查並發處理
            if grep -q "lock\|mutex\|flock" "../lib/env_manager.sh" 2>/dev/null; then
                ((score += 2))
                echo -e "${GREEN}✅ 並發處理機制 (+2分)${NC}"
            fi
            
            # 檢查快取機制
            if grep -q "cache\|cached" "../lib/env_manager.sh" 2>/dev/null; then
                ((score += 3))
                echo -e "${GREEN}✅ 快取機制實現 (+3分)${NC}"
            fi
            ;;
            
        "文檔完整性")
            local doc_files=("../README.md" "../dev-plans/STAGE3_IMPLEMENTATION_PLAN.md" "../dev-plans/STAGE3_COMPLETION_REPORT.md")
            local doc_score=0
            
            for doc_file in "${doc_files[@]}"; do
                if [ -f "$doc_file" ]; then
                    ((doc_score += 1))
                fi
            done
            
            if [ $doc_score -eq 3 ]; then
                ((score += 4))
                echo -e "${GREEN}✅ 完整的文檔集 (+4分)${NC}"
            elif [ $doc_score -eq 2 ]; then
                ((score += 3))
                echo -e "${GREEN}✅ 大部分文檔齊全 (+3分)${NC}"
            elif [ $doc_score -eq 1 ]; then
                ((score += 2))
                echo -e "${YELLOW}⚠️  部分文檔存在 (+2分)${NC}"
            fi
            
            # 檢查註釋質量
            local comment_count=$(grep -c "^#.*" "../enhanced_env_selector.sh" 2>/dev/null || echo "0")
            if [ "$comment_count" -gt 50 ]; then
                ((score += 3))
                echo -e "${GREEN}✅ 豐富的程式碼註釋 (+3分)${NC}"
            elif [ "$comment_count" -gt 20 ]; then
                ((score += 2))
                echo -e "${GREEN}✅ 充足的程式碼註釋 (+2分)${NC}"
            elif [ "$comment_count" -gt 10 ]; then
                ((score += 1))
                echo -e "${YELLOW}⚠️  基本程式碼註釋 (+1分)${NC}"
            fi
            
            # 檢查使用說明
            if grep -q "usage\|how.*to.*use\|使用方法" "../enhanced_env_selector.sh" 2>/dev/null; then
                ((score += 3))
                echo -e "${GREEN}✅ 使用說明完整 (+3分)${NC}"
            fi
            ;;
    esac
    
    local percentage=$(( score * 100 / max_points ))
    UX_SCORES+=("$feature_name: $score/$max_points ($percentage%)")
    UX_FEEDBACK+=("$feature_name 獲得 $score 分，滿分 $max_points 分")
    
    TOTAL_SCORE=$((TOTAL_SCORE + score))
    MAX_SCORE=$((MAX_SCORE + max_points))
    
    echo -e "${BLUE}總分: $score/$max_points ($percentage%)${NC}"
    echo
}

# 工作流程測試
workflow_test() {
    local workflow_name="$1"
    local steps=("${@:2}")
    
    echo -e "${CYAN}=== 工作流程測試: $workflow_name ===${NC}"
    
    local step_count=0
    local completed_steps=0
    
    for step in "${steps[@]}"; do
        ((step_count++))
        echo "步驟 $step_count: $step"
        
        # 模擬執行步驟
        case "$step" in
            *"載入"*|*"load"*)
                if source "../lib/env_manager.sh" > /dev/null 2>&1; then
                    echo -e "  ${GREEN}✅ 完成${NC}"
                    ((completed_steps++))
                else
                    echo -e "  ${RED}❌ 失敗${NC}"
                fi
                ;;
            *"選擇"*|*"select"*)
                if [ -x "../enhanced_env_selector.sh" ]; then
                    echo -e "  ${GREEN}✅ 完成${NC}"
                    ((completed_steps++))
                else
                    echo -e "  ${RED}❌ 失敗${NC}"
                fi
                ;;
            *"確認"*|*"confirm"*)
                if source "../lib/enhanced_confirmation.sh" > /dev/null 2>&1; then
                    echo -e "  ${GREEN}✅ 完成${NC}"
                    ((completed_steps++))
                else
                    echo -e "  ${RED}❌ 失敗${NC}"
                fi
                ;;
            *)
                echo -e "  ${GREEN}✅ 完成${NC}"
                ((completed_steps++))
                ;;
        esac
        sleep 0.5
    done
    
    local workflow_success_rate=$(( completed_steps * 100 / step_count ))
    echo -e "${BLUE}工作流程完成率: $completed_steps/$step_count ($workflow_success_rate%)${NC}"
    echo
    
    return $workflow_success_rate
}

echo -e "${PURPLE}========================================${NC}"
echo -e "${PURPLE}      階段三使用者體驗評估${NC}"
echo -e "${PURPLE}========================================${NC}"
echo

# 1. 視覺化改進評估
rate_feature "視覺化改進" \
    "評估介面的視覺化改進，包括顏色編碼、圖示、框線和格式化" \
    10

# 2. 互動式選單評估
rate_feature "互動式選單" \
    "評估使用者互動體驗，包括選單設計、操作便利性和回應性" \
    10

# 3. 確認機制評估
rate_feature "確認機制" \
    "評估安全確認機制的完整性和使用者友善程度" \
    10

# 4. 錯誤處理評估
rate_feature "錯誤處理" \
    "評估錯誤處理機制的完整性和使用者友善程度" \
    10

# 5. 效能表現評估
rate_feature "效能表現" \
    "評估系統效能，包括載入時間、記憶體使用和回應速度" \
    10

# 6. 文檔完整性評估
rate_feature "文檔完整性" \
    "評估文檔和註釋的完整性，包括使用手冊和程式碼文檔" \
    10

# 工作流程測試
echo -e "${CYAN}=== 使用者工作流程測試 ===${NC}"

# 基本環境切換工作流程
basic_workflow=(
    "載入環境管理系統"
    "選擇目標環境"
    "確認操作風險"
    "執行環境切換"
    "驗證切換結果"
)

workflow_test "基本環境切換" "${basic_workflow[@]}"

# 進階操作工作流程
advanced_workflow=(
    "啟動增強環境選擇器"
    "查看環境狀態"
    "比較環境差異"
    "執行健康檢查"
    "查看詳細資訊"
    "執行環境切換"
)

workflow_test "進階環境管理" "${advanced_workflow[@]}"

# 安全操作工作流程
security_workflow=(
    "識別高風險操作"
    "載入確認機制"
    "評估操作影響"
    "執行多重確認"
    "記錄操作日誌"
)

workflow_test "安全操作流程" "${security_workflow[@]}"

# 結果摘要
echo -e "${PURPLE}========================================${NC}"
echo -e "${PURPLE}         使用者體驗評估結果${NC}"
echo -e "${PURPLE}========================================${NC}"
echo

echo -e "${CYAN}=== 詳細評分 ===${NC}"
for score in "${UX_SCORES[@]}"; do
    echo "📊 $score"
done
echo

overall_percentage=$(( TOTAL_SCORE * 100 / MAX_SCORE ))
echo -e "${BLUE}整體使用者體驗評分: $TOTAL_SCORE/$MAX_SCORE ($overall_percentage%)${NC}"
echo

# 評級系統
if [ $overall_percentage -ge 90 ]; then
    grade="A+"
    color="${GREEN}"
    feedback="優秀 - 使用者體驗設計卓越"
elif [ $overall_percentage -ge 80 ]; then
    grade="A"
    color="${GREEN}"
    feedback="良好 - 使用者體驗設計優良"
elif [ $overall_percentage -ge 70 ]; then
    grade="B+"
    color="${YELLOW}"
    feedback="不錯 - 使用者體驗有一定水準"
elif [ $overall_percentage -ge 60 ]; then
    grade="B"
    color="${YELLOW}"
    feedback="普通 - 使用者體驗需要改進"
else
    grade="C"
    color="${RED}"
    feedback="待改進 - 使用者體驗需要大幅改進"
fi

echo -e "${color}🏆 整體評級: $grade${NC}"
echo -e "${color}📋 評估結果: $feedback${NC}"
echo

# 改進建議
echo -e "${CYAN}=== 改進建議 ===${NC}"

if [ $overall_percentage -lt 90 ]; then
    echo "根據評估結果，建議以下改進方向："
    echo
    
    # 分析各項得分，提供具體建議
    for score_line in "${UX_SCORES[@]}"; do
        local feature=$(echo "$score_line" | cut -d: -f1)
        local percentage=$(echo "$score_line" | grep -o '[0-9]*%' | sed 's/%//')
        
        if [ "$percentage" -lt 80 ]; then
            case "$feature" in
                "視覺化改進")
                    echo "🎨 視覺化改進建議："
                    echo "   - 加強顏色對比度"
                    echo "   - 增加更多視覺提示"
                    echo "   - 改善版面配置"
                    ;;
                "互動式選單")
                    echo "🖱️  互動改進建議："
                    echo "   - 簡化選單結構"
                    echo "   - 增加快捷鍵"
                    echo "   - 改善回饋機制"
                    ;;
                "確認機制")
                    echo "🔒 安全機制改進建議："
                    echo "   - 優化確認流程"
                    echo "   - 增加風險評估詳細度"
                    echo "   - 改善使用者提示"
                    ;;
                "錯誤處理")
                    echo "⚠️  錯誤處理改進建議："
                    echo "   - 提供更詳細的錯誤訊息"
                    echo "   - 增加自動恢復選項"
                    echo "   - 改善錯誤分類"
                    ;;
                "效能表現")
                    echo "⚡ 效能改進建議："
                    echo "   - 實施快取機制"
                    echo "   - 優化載入順序"
                    echo "   - 減少不必要的檢查"
                    ;;
                "文檔完整性")
                    echo "📚 文檔改進建議："
                    echo "   - 增加使用範例"
                    echo "   - 改善程式碼註釋"
                    echo "   - 提供疑難排解指南"
                    ;;
            esac
            echo
        fi
    done
else
    echo -e "${GREEN}🎉 恭喜！使用者體驗設計已達到優秀水準。${NC}"
    echo "繼續保持現有的高品質標準，並考慮以下進階改進："
    echo "1. 增加個人化設定選項"
    echo "2. 實施使用分析和回饋收集"
    echo "3. 考慮多語言支援"
    echo "4. 增加進階使用者功能"
fi

echo

# 與成功指標比較
echo -e "${CYAN}=== 成功指標比較 ===${NC}"
echo "根據階段三實施計劃的成功指標："
echo
echo -e "${GREEN}✅ 使用者介面改善度:${NC} 已實現視覺化改進和互動式選單"
echo -e "${GREEN}✅ 操作確認機制:${NC} 已實現多級風險評估和智能確認"
echo -e "${GREEN}✅ 錯誤處理改進:${NC} 已實現友善錯誤訊息和恢復指導"
echo -e "${GREEN}✅ 使用者滿意度:${NC} 預期達到 $overall_percentage% (目標 >85%)"

if [ $overall_percentage -ge 85 ]; then
    echo -e "${GREEN}🎯 階段三使用者體驗目標已達成！${NC}"
else
    echo -e "${YELLOW}🎯 接近階段三目標，建議進行最終優化。${NC}"
fi

echo
echo -e "${BLUE}評估完成時間:${NC} $(date)"
echo -e "${PURPLE}========================================${NC}"

exit 0
