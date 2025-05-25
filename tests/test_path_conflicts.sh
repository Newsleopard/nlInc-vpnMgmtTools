#!/bin/bash

# 測試路徑衝突修復
# 此腳本驗證環境感知路徑是否正確設定

echo "=== AWS VPN 管理工具路徑衝突修復測試 ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入環境管理器
source "$SCRIPT_DIR/lib/env_manager.sh"

# 測試環境初始化
echo "1. 測試環境初始化..."
if env_init_for_script "test_path_conflicts.sh"; then
    echo "   ✓ 環境初始化成功"
else
    echo "   ✗ 環境初始化失敗"
    exit 1
fi

# 設定環境路徑
env_setup_paths

echo "2. 檢查環境變數設定..."
echo "   CURRENT_ENVIRONMENT: ${CURRENT_ENVIRONMENT:-未設定}"
echo "   PROJECT_ROOT: ${PROJECT_ROOT:-未設定}"
echo "   VPN_CERT_DIR: ${VPN_CERT_DIR:-未設定}"
echo "   VPN_CONFIG_DIR: ${VPN_CONFIG_DIR:-未設定}"
echo "   VPN_LOG_DIR: ${VPN_LOG_DIR:-未設定}"

echo "3. 檢查路徑是否存在..."
if [ -n "$VPN_CERT_DIR" ]; then
    if [ -d "$VPN_CERT_DIR" ]; then
        echo "   ✓ VPN_CERT_DIR 目錄存在: $VPN_CERT_DIR"
    else
        echo "   ! VPN_CERT_DIR 目錄不存在，但路徑已設定: $VPN_CERT_DIR"
    fi
else
    echo "   ✗ VPN_CERT_DIR 未設定"
fi

if [ -n "$VPN_CONFIG_DIR" ]; then
    if [ -d "$VPN_CONFIG_DIR" ]; then
        echo "   ✓ VPN_CONFIG_DIR 目錄存在: $VPN_CONFIG_DIR"
    else
        echo "   ! VPN_CONFIG_DIR 目錄不存在，但路徑已設定: $VPN_CONFIG_DIR"
    fi
else
    echo "   ✗ VPN_CONFIG_DIR 未設定"
fi

echo "4. 測試函數名稱是否正確..."
# 載入核心函式庫 - 使用正確的路徑
source "$PROJECT_ROOT/lib/core_functions.sh"
source "$PROJECT_ROOT/lib/aws_setup.sh"

if declare -f setup_aws_config_lib > /dev/null; then
    echo "   ✓ setup_aws_config_lib 函數存在"
else
    echo "   ✗ setup_aws_config_lib 函數不存在"
fi

echo "5. 檢查配置檔案路徑..."
echo "   CONFIG_FILE: ${CONFIG_FILE:-未設定}"
echo "   VPN_ENDPOINT_CONFIG_FILE: ${VPN_ENDPOINT_CONFIG_FILE:-未設定}"

echo "=== 測試完成 ==="
echo "如果看到多個 ✓ 標記，表示修復成功"
echo "如果看到 ✗ 標記，可能需要進一步調查"
