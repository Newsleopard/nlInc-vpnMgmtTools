#!/bin/bash

# 測試安全輸入函數
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/core_functions.sh"

echo "測試安全輸入函數 read_secure_input"
echo "======================================"

# 測試 1: 正常的用戶名輸入
echo "測試 1: 請輸入一個有效的用戶名 (3-32個字符，只能包含字母、數字、連字符和底線)"
if read_secure_input "用戶名: " test_username "validate_username"; then
    echo "✓ 輸入驗證成功，用戶名: $test_username"
else
    echo "✗ 輸入驗證失敗"
fi

echo -e "\n測試完成！"
