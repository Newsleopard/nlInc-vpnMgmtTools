# VPN Management Tools

This directory contains specialized tools for VPN management and troubleshooting.

## 可用工具 (Available Tools)

### 🆔 `fix_endpoint_id.sh` ⭐ 推薦

**目的**: 自動修復 VPN 端點 ID 配置不匹配問題

**功能**:
- 自動檢測 AWS 認證狀態
- 列出區域中所有可用的 VPN 端點
- 驗證配置檔案中的端點 ID
- 互動式端點選擇界面
- 自動備份和更新配置
- 驗證修復結果

**使用方法**:
```bash
cd /path/to/nlInc-vpnMgmtTools
# 確保設定正確的環境
./vpn_env.sh switch staging  # 或 production
# 執行修復工具
./admin/tools/fix_endpoint_id.sh
```

**適用場景**:
- 出現 "InvalidClientVpnEndpointId.NotFound" 錯誤
- 配置檔案中的端點 ID 與實際 AWS 資源不匹配
- 手動變更後需要重新對應到正確的端點 ID

### 🔍 `simple_endpoint_fix.sh` ⭐ 新增

**目的**: 簡化的診斷工具和手動修復指導

**功能**:
- 顯示當前配置狀態
- 提供詳細的手動修復步驟
- 列出常用診斷命令
- 自動備份配置檔案

**使用方法**:
```bash
./admin/tools/simple_endpoint_fix.sh
```

**適用場景**:
- 快速診斷端點 ID 問題
- 需要手動修復步驟指導
- 網路限制阻止自動修復時

### 🔍 `debug_vpn_creation.sh`

**目的**: 全面的 VPN 端點創建診斷工具

**功能**:
- AWS CLI 配置驗證
- VPC/子網可訪問性檢查
- 證書狀態驗證
- 現有端點衝突檢測
- JSON 參數格式驗證
- AWS CLI 命令預覽

**使用方法**:
```bash
cd /path/to/nlInc-vpnMgmtTools
./admin/tools/debug_vpn_creation.sh
```

**適用場景**:
- VPN 端點創建失敗
- AWS CLI 返回錯誤代碼 254
- 需要在創建前驗證配置
- 診斷證書或網路問題

### 🔧 `fix_vpn_config.sh`

**目的**: 自動化配置修復工具

**功能**:
- 自動修復子網配置問題
- 證書有效性檢查和替換
- 衝突資源清理
- 配置備份和驗證

**使用方法**:
```bash
cd /path/to/nlInc-vpnMgmtTools
./admin/tools/fix_vpn_config.sh
```

**適用場景**:
- 子網 ID 變為無效
- 證書過期或無法訪問
- 存在衝突的 VPN 端點
- 需要清理孤立的 CloudWatch 日誌群組

### 🔧 `complete_vpn_setup.sh`

**目的**: 完整的 VPN 端點設置和配置工具

**功能**:
- 檢查端點狀態
- 配置子網關聯
- 設置授權規則
- 驗證設置完整性

**使用方法**:
```bash
cd /path/to/nlInc-vpnMgmtTools
./admin/tools/complete_vpn_setup.sh
```

**適用場景**:
- 從 "pending-associate" 狀態繼續設置
- 完成中斷的 VPN 設置流程
- 重新配置現有端點

### ✅ `validate_config.sh`

**目的**: 配置驗證和自動修復工具

**功能**:
- 驗證所有環境的配置正確性
- 自動修復簡單的配置問題
- 提供配置健康狀態報告
- 支援多環境驗證

**使用方法**:
```bash
cd /path/to/nlInc-vpnMgmtTools
./admin/tools/validate_config.sh
```

**適用場景**:
- 定期配置健康檢查
- 多環境配置驗證
- 配置檔案完整性檢查

### 🔬 `verify_config_update_fix.sh`

**目的**: 配置更新修復驗證工具

**功能**:
- 驗證配置文件更新邏輯的正確性
- 模擬配置文件更新過程
- 確認現有配置項得到保留
- 驗證新配置項被正確添加/更新

**使用方法**:
```bash
cd /path/to/nlInc-vpnMgmtTools
./admin/tools/verify_config_update_fix.sh
```

**適用場景**:
- 驗證配置更新修復是否正確工作
- 測試配置文件安全更新機制
- 開發和測試環境中的配置完整性驗證

## 快速問題解決指南

### 問題 1: "InvalidClientVpnEndpointId.NotFound" 錯誤

**症狀**: 執行 VPN 管理操作時收到端點 ID 未找到錯誤

**解決方案**:
1. 使用 `fix_endpoint_id.sh` 進行自動修復
2. 或使用 `simple_endpoint_fix.sh` 獲取手動修復指導

### 問題 2: 端點存在但操作失敗

**症狀**: 端點 ID 正確但操作仍然失敗

**解決方案**:
1. 檢查 AWS 權限
2. 驗證端點狀態（available/pending 等）
3. 使用 `complete_vpn_setup.sh` 重新配置

### 問題 3: 配置檔案損壞

**症狀**: 載入配置檔案時出錯

**解決方案**:
1. 從備份檔案恢復（所有工具都會自動建立備份）
2. 使用 `fix_vpn_config.sh` 修復配置

## 最佳實踐

1. **總是備份**: 所有工具都會自動建立備份，請保留它們
2. **驗證環境**: 執行工具前確保設定正確的環境
3. **檢查權限**: 確保有足夠的 AWS 權限
4. **逐步執行**: 建議按順序執行修復步驟
5. **驗證結果**: 修復後使用系統健康檢查進行驗證

## 系統需求

這些工具可直接使用，無需額外安裝。它們依賴於：

- 配置適當權限的 AWS CLI
- jq（JSON 處理器）- 通常在 macOS 上預先安裝
- Bash shell

## 配置

工具讀取以下配置：

```bash
configs/staging/staging.env
# 或
configs/production/production.env
```

確保檔案包含有效的：
- VPC_ID
- SUBNET_ID
- VPN_CIDR
- SERVER_CERT_ARN
- CLIENT_CERT_ARN
- VPN_NAME
- ENDPOINT_ID

## 退出代碼

- **0**: 成功
- **1**: 配置或驗證錯誤
- **254**: AWS CLI 參數解析錯誤（這些工具設計來修復的原始問題）

## 故障排除

如果遇到問題：

1. 首先執行診斷工具：`./admin/tools/debug_vpn_creation.sh`
2. 如果發現端點 ID 問題，執行：`./admin/tools/fix_endpoint_id.sh`
3. 如果發現其他問題，執行修復工具：`./admin/tools/fix_vpn_config.sh`
4. 重新執行診斷確認修復
5. 繼續正常的 VPN 端點創建

## 常用手動診斷命令

```bash
# 檢查 AWS 認證
aws sts get-caller-identity

# 列出區域中所有 VPN 端點
aws ec2 describe-client-vpn-endpoints --region us-east-1

# 檢查特定端點
aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids cvpn-endpoint-xxxxx --region us-east-1

# 測試端點連接性
aws ec2 describe-client-vpn-target-networks --client-vpn-endpoint-id cvpn-endpoint-xxxxx --region us-east-1
```

## 維護

- 證書更新時檢視和更新證書 ARN
- 網路拓撲變更時更新子網 ID
- 定期清理舊的備份配置檔案
- 監控 AWS CloudWatch 日誌以排查 VPN 連接問題

## 安全考量

- 工具會自動備份配置檔案，請定期清理舊備份
- 避免在生產環境中直接修改配置，先在 staging 環境測試
- 修復操作可能會暫時中斷 VPN 服務

## 相關檔案

- 主要 VPN 創建邏輯：`lib/endpoint_creation.sh`
- 配置範本：`configs/template.env.example`
- 主要設置腳本：`team_member_setup.sh`
- 核心函式：`lib/core_functions.sh`

---

**最後更新**：2025年5月25日  
**工具版本**：2.0  
**支援環境**：Staging & Production