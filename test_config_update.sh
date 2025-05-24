#!/bin/bash

# 配置更新功能測試腳本
# 用於驗證 macOS sed 問題的修復

# 顏色設定
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 腳本目錄
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_CONFIG_FILE="$SCRIPT_DIR/test_config.conf"

# 載入核心函式庫
source "$SCRIPT_DIR/lib/core_functions.sh"

# 執行兼容性檢查
check_macos_compatibility

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}    配置文件更新功能測試              ${NC}"
echo -e "${CYAN}========================================${NC}"

# 清理舊的測試文件
if [ -f "$TEST_CONFIG_FILE" ]; then
    rm -f "$TEST_CONFIG_FILE"
    echo -e "${BLUE}清理舊的測試配置文件${NC}"
fi

echo -e "\n${YELLOW}測試 1: 創建新配置文件${NC}"
update_config "$TEST_CONFIG_FILE" "TEST_PARAM1" "value1"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 新配置文件創建成功${NC}"
else
    echo -e "${RED}✗ 新配置文件創建失敗${NC}"
    exit 1
fi

echo -e "\n${YELLOW}測試 2: 添加新參數${NC}"
update_config "$TEST_CONFIG_FILE" "TEST_PARAM2" "value2"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 新參數添加成功${NC}"
else
    echo -e "${RED}✗ 新參數添加失敗${NC}"
    exit 1
fi

echo -e "\n${YELLOW}測試 3: 更新現有參數${NC}"
update_config "$TEST_CONFIG_FILE" "TEST_PARAM1" "updated_value1"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 參數更新成功${NC}"
else
    echo -e "${RED}✗ 參數更新失敗${NC}"
    exit 1
fi

echo -e "\n${YELLOW}測試 4: 添加包含特殊字符的參數${NC}"
update_config "$TEST_CONFIG_FILE" "SPECIAL_CHARS" "value/with/slashes&symbols=test"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 特殊字符參數添加成功${NC}"
else
    echo -e "${RED}✗ 特殊字符參數添加失敗${NC}"
    exit 1
fi

echo -e "\n${YELLOW}測試 5: 添加包含空格的參數值${NC}"
update_config "$TEST_CONFIG_FILE" "WITH_SPACES" "value with spaces and symbols @ # $"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 包含空格的參數添加成功${NC}"
else
    echo -e "${RED}✗ 包含空格的參數添加失敗${NC}"
    exit 1
fi

echo -e "\n${YELLOW}測試 6: 驗證最終配置文件內容${NC}"
echo -e "${BLUE}配置文件內容:${NC}"
cat "$TEST_CONFIG_FILE"

echo -e "\n${YELLOW}測試 7: 驗證參數值正確性${NC}"
source "$TEST_CONFIG_FILE"

# 檢查參數值
if [ "$TEST_PARAM1" = "updated_value1" ]; then
    echo -e "${GREEN}✓ TEST_PARAM1 值正確: $TEST_PARAM1${NC}"
else
    echo -e "${RED}✗ TEST_PARAM1 值錯誤: $TEST_PARAM1${NC}"
fi

if [ "$TEST_PARAM2" = "value2" ]; then
    echo -e "${GREEN}✓ TEST_PARAM2 值正確: $TEST_PARAM2${NC}"
else
    echo -e "${RED}✗ TEST_PARAM2 值錯誤: $TEST_PARAM2${NC}"
fi

if [ "$SPECIAL_CHARS" = "value/with/slashes&symbols=test" ]; then
    echo -e "${GREEN}✓ SPECIAL_CHARS 值正確: $SPECIAL_CHARS${NC}"
else
    echo -e "${RED}✗ SPECIAL_CHARS 值錯誤: $SPECIAL_CHARS${NC}"
fi

if [ "$WITH_SPACES" = "value with spaces and symbols @ # $" ]; then
    echo -e "${GREEN}✓ WITH_SPACES 值正確: $WITH_SPACES${NC}"
else
    echo -e "${RED}✗ WITH_SPACES 值錯誤: $WITH_SPACES${NC}"
fi

echo -e "\n${YELLOW}測試 8: 測試錯誤處理${NC}"
# 測試缺少參數的情況
update_config "" "TEST" "value" 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${GREEN}✓ 錯誤處理正確 - 空配置文件路徑${NC}"
else
    echo -e "${RED}✗ 錯誤處理失敗 - 應該拒絕空配置文件路徑${NC}"
fi

update_config "$TEST_CONFIG_FILE" "" "value" 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${GREEN}✓ 錯誤處理正確 - 空參數名${NC}"
else
    echo -e "${RED}✗ 錯誤處理失敗 - 應該拒絕空參數名${NC}"
fi

echo -e "\n${YELLOW}測試 9: 測試文件權限${NC}"
if [ -f "$TEST_CONFIG_FILE" ]; then
    perms=""
    if [ "$(uname)" = "Darwin" ]; then
        perms=$(stat -f "%A" "$TEST_CONFIG_FILE")
    else
        perms=$(stat -c "%a" "$TEST_CONFIG_FILE")
    fi
    if [ "$perms" = "600" ]; then
        echo -e "${GREEN}✓ 文件權限設置正確: $perms${NC}"
    else
        echo -e "${YELLOW}⚠ 文件權限: $perms (預期: 600)${NC}"
    fi
fi

echo -e "\n${CYAN}========================================${NC}"
echo -e "${GREEN}    所有測試完成！                    ${NC}"
echo -e "${CYAN}========================================${NC}"

# 清理測試文件
read -p "是否要清理測試配置文件？ (y/n): " cleanup_choice
if [[ "$cleanup_choice" == "y" || "$cleanup_choice" == "Y" ]]; then
    rm -f "$TEST_CONFIG_FILE"
    echo -e "${BLUE}測試配置文件已清理${NC}"
else
    echo -e "${BLUE}測試配置文件保留在: $TEST_CONFIG_FILE${NC}"
fi
