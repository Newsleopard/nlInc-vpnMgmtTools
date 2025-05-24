<!-- markdownlint-disable MD051 -->
<!-- filepath: /Users/ctyeh/Documents/NewsLeopard/nlm-codes/nlInc-vpnMgmtTools/vpn_connection_manual.md -->
# 📖 AWS Client VPN 連接完整使用手冊

**版本：** 2.0
**適用於：** macOS 使用者
**更新日期：** 2024年12月

---

## 📋 目錄

1. [概述](#概述)
2. [雙環境架構介紹](#雙環境架構介紹)
3. [前置作業檢查](#前置作業檢查)
4. [環境選擇與管理](#環境選擇與管理)
5. [AWS VPN Client 安裝與設定](#aws-vpn-client-安裝與設定)
6. [VPN 連接步驟](#vpn-連接步驟)
7. [連接驗證](#連接驗證)
8. [日常使用指南](#日常使用指南)
9. [環境切換操作](#環境切換操作)
10. [故障排除](#故障排除)
11. [安全最佳實踐](#安全最佳實踐)
12. [常見問題 FAQ](#常見問題-faq)
13. [緊急聯絡資訊](#緊急聯絡資訊)

---

## 概述

本手冊將指導您如何使用我們的**雙環境 AWS Client VPN 管理系統**成功連接到公司的網路資源。新系統支援 **Staging（測試）** 和 **Production（生產）** 兩個環境，讓開發和生產工作完全分離。

### 🎯 新功能亮點

- **🔄 環境自動切換**: 透過 `vpn_env.sh` 輕鬆在 Staging 和 Production 環境間切換
- **🎛️ 互動式環境選擇器**: 使用 `enhanced_env_selector.sh` 獲得完整的視覺化環境管理介面
- **🛡️ 生產環境保護**: Production 環境具備額外的確認機制，防止誤操作
- **📊 即時環境監控**: 查看環境健康狀態、連線數和資源使用情況
- **🔐 環境隔離安全**: 每個環境使用獨立的憑證和配置，確保完全隔離

### 💡 重要提醒

- **Staging 環境**: 用於開發測試、功能驗證、新功能除錯
- **Production 環境**: 僅用於生產環境除錯和緊急維護
- 請依據工作性質選擇適當的環境
- 使用完畢後立即斷開連接
- 嚴禁分享您的 VPN 配置文件或憑證

---

## 雙環境架構介紹

### 🏗️ 架構概覽

新的雙環境 VPN 管理系統提供完整的環境隔離和管理功能：

```text
AWS Client VPN 雙環境架構
├── 🎛️ 環境管理層
│   ├── vpn_env.sh                    # 環境管理入口點

│   ├── enhanced_env_selector.sh      # 互動式環境選擇器

│   └── lib/
│       ├── env_manager.sh           # 核心環境管理

│       └── enhanced_confirmation.sh  # 生產環境確認

├── 🌐 Staging 環境
│   ├── configs/staging/staging.env   # Staging 配置

│   ├── certs/staging/               # Staging 憑證

│   └── logs/staging/                # Staging 日誌

└── 🏭 Production 環境
    ├── configs/production/production.env # Production 配置

    ├── certs/production/            # Production 憑證

    └── logs/production/             # Production 日誌

```text

### 🔧 環境管理工具

1. **vpn_env.sh - 環境管理入口**

   ```bash
   ./vpn_env.sh status              # 顯示當前環境狀態

   ./vpn_env.sh switch staging      # 切換到 Staging 環境

   ./vpn_env.sh switch production   # 切換到 Production 環境

   ./vpn_env.sh health              # 檢查環境健康狀態

      ./vpn_env.sh selector            # 啟動互動式選擇器
   ```

1. **enhanced_env_selector.sh - 互動式環境選擇器**

   提供完整的視覺化管理介面：

   ```text
   ╭──────────────────────────────────────────────────╮
   │        🎛️ Enhanced Environment Selector         │
   ├──────────────────────────────────────────────────┤
   │ 當前環境: Production 🏭                          │
   │ 狀態: 🟢 健康 │ 連線數: 8 │ 資源: CPU 45% MEM 67% │
   ├──────────────────────────────────────────────────┤
   │ [E] 環境切換     [S] 狀態總覽     [H] 健康檢查    │
   │ [D] 除錯模式     [C] 連線管理     [R] 重新載入    │
   │ [Q] 退出                                        │
   ╰──────────────────────────────────────────────────╯

   ```text

### 🔒 環境安全特性

- **Production 安全確認**: 切換到 Production 環境需要輸入確認碼
- **環境隔離**: 每個環境使用獨立的憑證和配置目錄
- **操作日誌**: 所有環境切換和連線操作都會被記錄
- **健康監控**: 即時監控環境狀態和連線情況

---

## 環境選擇與管理

### 🎛️ 使用環境管理工具

在開始連接 VPN 之前，您需要先選擇適當的環境。我們提供兩種方式來管理環境：

#### 方法一：使用命令列工具

1. **查看當前環境狀態**

   ```bash
   ./vpn_env.sh status

   ```text

   輸出範例：

   ```text
   === AWS Client VPN 環境狀態 ===
   當前環境: staging
   環境狀態: 🟢 健康
   配置路徑: /path/to/configs/staging/staging.env
   憑證目錄: /path/to/certs/staging/
   日誌目錄: /path/to/logs/staging/
   最後更新: 2024-12-XX 10:30:25

   ```text

2. **切換到 Staging 環境**

   ```bash
   ./vpn_env.sh switch staging

   ```text

   輸出範例：

   ```text
   === 環境切換 ===
   目標環境: staging
   正在驗證環境配置...
   ✅ 環境配置有效
   ✅ 憑證檔案存在
   ✅ 目錄權限正確

   🔄 環境已成功切換到: staging

   ```text

3. **切換到 Production 環境**

   ```bash
   ./vpn_env.sh switch production

   ```text

   由於 Production 環境的重要性，系統會要求您進行額外確認：

   ```text
   ⚠️  警告: 您即將切換到 Production 環境

   請確認以下事項：
   □ 我了解這是生產環境
   □ 我需要訪問生產資源進行除錯
   □ 我會在使用完畢後立即斷開連接

   請輸入確認碼 [PROD]: PROD

   🔄 環境已成功切換到: production

   ```text

#### 方法二：使用互動式環境選擇器

啟動視覺化環境管理介面：

```bash
./enhanced_env_selector.sh

```text

您將看到類似以下的介面：

```text
╭─────────────────────────────────────────────────────────────╮
│              🎛️ Enhanced Environment Selector              │
├─────────────────────────────────────────────────────────────┤
│ 當前環境: Staging 🧪                                        │
│ 狀態: 🟢 健康 │ 連線: 3 │ 資源: CPU 15% MEM 32% NET 2.3MB/s │
├─────────────────────────────────────────────────────────────┤
│ 可用環境:                                                   │
│   • 🧪 Staging    - 開發測試環境 [當前]                      │
│   • 🏭 Production - 生產環境                                │
├─────────────────────────────────────────────────────────────┤
│ 操作選項:                                                   │
│ [E] 環境切換     [S] 狀態總覽     [H] 健康檢查               │
│ [D] 除錯模式     [C] 連線管理     [R] 重新載入               │
│ [Q] 退出                                                   │
├─────────────────────────────────────────────────────────────┤
│ 最近操作:                                                   │
│ • 10:30 - 切換到 Staging 環境                               │
│ • 10:25 - 健康檢查完成                                      │
│ • 10:20 - 啟動環境選擇器                                    │
╰─────────────────────────────────────────────────────────────╯

請選擇操作 [E/S/H/D/C/R/Q]:

```text

### 🔍 環境健康檢查

無論使用哪種方法，都建議在連接前檢查環境健康狀態：

```bash
./vpn_env.sh health

```text

或在互動式選擇器中按 `H`。

健康檢查輸出範例：

```text
=== 環境健康檢查 ===
環境: staging

📋 配置檔案檢查:
  ✅ staging.env 存在且可讀
  ✅ 必要變數已設定
  ✅ 路徑配置正確

🔐 憑證檢查:
  ✅ CA 憑證有效
  ✅ 用戶憑證有效 (到期: 2025-06-15)
  ✅ 私鑰檔案存在且權限正確

📁 目錄結構:
  ✅ 憑證目錄: /certs/staging/
  ✅ 日誌目錄: /logs/staging/
  ✅ 配置目錄: /configs/staging/

📊 環境統計:
  • 目前連線數: 3
  • 平均連線時間: 45 分鐘
  • 最後連線: 2024-12-XX 10:15

總體狀態: 🟢 健康

```text

---

## 前置作業檢查

### ✅ 步驟 1：確認環境管理系統

執行完 `team_member_setup.sh` 後，您的專案目錄應包含完整的雙環境架構：

```bash
專案目錄/
├── vpn_env.sh                      # 🎛️ 環境管理入口點

├── enhanced_env_selector.sh        # 🎨 互動式環境選擇器

├── lib/                            # 📚 核心程式庫

│   ├── env_manager.sh              # 🔧 環境管理核心

│   └── enhanced_confirmation.sh    # 🛡️ 生產環境確認

├── configs/                        # ⚙️ 環境配置

│   ├── staging/
│   │   └── staging.env
│   └── production/
│       └── production.env
├── certs/                          # 🔒 環境憑證（高度敏感）

│   ├── staging/
│   │   ├── ca.crt
│   │   ├── [您的用戶名].crt
│   │   └── [您的用戶名].key
│   └── production/
│       ├── ca.crt
│       ├── [您的用戶名].crt
│       └── [您的用戶名].key
├── logs/                           # 📝 環境日誌

│   ├── staging/
│   └── production/
└── vpn-config/                     # 📄 VPN 配置檔案

    ├── staging-[您的用戶名]-config.ovpn
    └── production-[您的用戶名]-config.ovpn

```text

### ✅ 步驟 2：驗證環境管理工具

1. **測試環境管理工具**

   ```bash
   ./vpn_env.sh status

   ```text

   如果看到環境狀態資訊，表示系統正常運作。

2. **測試環境切換**

   ```bash
   # 切換到 staging（相對安全）

   ./vpn_env.sh switch staging

   # 檢查切換結果

   ./vpn_env.sh status

   ```text

3. **測試互動式選擇器**

   ```bash
   ./enhanced_env_selector.sh

   ```text

   按 `Q` 退出測試。

### ✅ 步驟 3：檢查環境特定文件

1. **Staging 環境文件檢查**

   ```bash
   ls -la configs/staging/
   ls -la certs/staging/
   ls -la vpn-config/staging-*-config.ovpn

   ```text

2. **Production 環境文件檢查**

   ```bash
   ls -la configs/production/
   ls -la certs/production/
   ls -la vpn-config/production-*-config.ovpn

   ```text

3. **權限驗證**

   ```bash
   # 檢查敏感文件權限

   find certs/ -type f -exec ls -la {} \;
   find vpn-config/ -name "*.ovpn" -exec ls -la {} \;

   ```text

   所有敏感文件應顯示 `-rw-------` (600) 權限。

---

## AWS VPN Client 安裝與設定

### 📱 步驟 1：確認 AWS VPN Client 已安裝

1. **檢查應用程式是否存在**

   ```bash
   # 在終端機中執行：

   ls -la "/Applications/AWS VPN Client.app"

   ```text

2. **如果應用程式存在**
   - 您應該看到類似：`drwxr-xr-x ... AWS VPN Client.app`
   - 跳到「步驟 2」

3. **如果應用程式不存在**
   - 檢查 Downloads 資料夾是否有安裝檔：

   ```bash
   ls -la ~/Downloads/AWS_VPN_Client.pkg

   ```text

   - 如果存在，雙擊安裝檔進行安裝
   - 如果不存在，請聯繫 IT 管理員

### 📱 步驟 2：啟動 AWS VPN Client

1. #### 方法一：使用 Spotlight

   - 按 `⌘ + 空格鍵` 開啟 Spotlight
   - 輸入 "AWS VPN Client"
   - 按 `Enter` 啟動

2. #### 方法二：使用 Finder

   - 開啟 Finder
   - 點擊左側的「應用程式」
   - 找到並雙擊「AWS VPN Client」

3. #### 方法三：使用 Launchpad

   - 按 `F4` 或點擊 Dock 中的 Launchpad 圖示
   - 找到並點擊「AWS VPN Client」

### 📱 步驟 3：首次啟動設定

第一次啟動時，您可能會看到：

1. **macOS 安全提示**
   - 如果出現「無法打開，因為來自未識別的開發者」
   - 點擊「取消」
   - 前往「系統偏好設定」>「安全性與隱私權」
   - 點擊「仍要打開」

2. **應用程式許可**
   - 允許 AWS VPN Client 訪問網路
   - 點擊「允許」

---

## VPN 連接步驟

### 🎯 重要：環境確認

在開始連接前，**務必確認您選擇了正確的環境**：

```bash

# 檢查當前環境

./vpn_env.sh status

```text

如果需要切換環境：

```bash

# 切換到 Staging（開發測試）

./vpn_env.sh switch staging

# 切換到 Production（生產環境，需要確認）

./vpn_env.sh switch production

```text

### 🔧 步驟 1：開啟設定檔管理

1. 在 AWS VPN Client 中，點擊選單列的：

   ```text
   檔案 (File) → 管理設定檔 (Manage Profiles)
   ```text

2. 或使用快捷鍵：`⌘ + ,`

3. 設定檔管理視窗將會開啟

### 🔧 步驟 2：添加環境專用設定檔

根據您當前選擇的環境，添加對應的設定檔：

1. **點擊「添加設定檔」按鈕**
   - 位於設定檔管理視窗的左下角
   - 按鈕文字為「Add Profile」或「添加設定檔」

2. **選擇導入方式**
   - 選擇「從檔案導入」(Import from file)
   - 或「選擇檔案」(Choose file)

### 🔧 步驟 3：選擇環境專用配置檔案

⚠️ **重要：根據當前環境選擇正確的配置檔案**

1. **導航到您的專案目錄**
   - 在檔案選擇器中，找到您執行腳本的資料夾
   - 進入 `vpn-config/` 子資料夾

2. **選擇對應環境的配置檔案**

   **如果當前環境是 Staging：**
   - 檔案名稱：`staging-[您的用戶名]-config.ovpn`
   - 例如：`staging-john.doe-config.ovpn`

   **如果當前環境是 Production：**
   - 檔案名稱：`production-[您的用戶名]-config.ovpn`
   - 例如：`production-john.doe-config.ovpn`

3. **確認並開啟**
   - 仔細檢查檔案名稱包含正確的環境前綴
   - 點擊「開啟」(Open) 按鈕

### 🔧 步驟 4：設定環境識別設定檔

1. **輸入清楚的設定檔名稱**

   **Staging 環境：**

   ```text
   🧪 Staging VPN - [您的姓名]
   ```text
   例如：`🧪 Staging VPN - John Doe`

   **Production 環境：**

   ```text
   🏭 Production VPN - [您的姓名]
   ```text
   例如：`🏭 Production VPN - John Doe`

2. **檢查配置資訊**
   - 確認顯示的伺服器位址對應正確環境
   - Staging 和 Production 應該有不同的伺服器端點
   - 確認沒有錯誤提示

3. **完成添加**
   - 點擊「添加設定檔」(Add Profile) 按鈕
   - 關閉設定檔管理視窗

### 🔧 步驟 5：環境感知連接

1. **選擇正確的設定檔**
   - 在 AWS VPN Client 主視窗中
   - 從下拉選單選擇對應當前環境的設定檔
   - **再次確認**：設定檔名稱應包含正確的環境標識

2. **最終環境確認**

   **連接前雙重確認：**

   ```bash
   # 最後一次確認當前環境

   ./vpn_env.sh status

   ```text

   確保顯示的環境與您要連接的設定檔一致！

3. **開始連接**
   - 點擊「連接」(Connect) 按鈕
   - 狀態指示器會變化：
     - 🔴 紅色：未連接
     - 🟡 黃色：正在連接...
     - 🟢 綠色：已連接

4. **等待連接完成**
   - 初次連接可能需要 30-60 秒
   - 請耐心等待，不要重複點擊

### ⚠️ 環境混淆防護

為避免環境混淆，請注意：

1. **設定檔命名規範**
   - 必須在設定檔名稱中包含環境標識
   - 使用 emoji 圖示便於視覺識別
   - Staging: 🧪 Production: 🏭

2. **連接前確認清單**
   - ✅ 已執行 `./vpn_env.sh status` 確認當前環境
   - ✅ 選擇的 .ovpn 檔案名稱包含正確環境前綴
   - ✅ AWS VPN Client 中的設定檔名稱包含正確環境標識
   - ✅ 對於 Production 環境，已完成額外確認流程

3. **錯誤預防**
   - ❌ 絕不使用錯誤環境的配置檔案
   - ❌ 不要同時在兩個環境中保持連接
   - ❌ 不要忽略環境確認步驟

---

## 連接驗證

### ✅ 確認連接狀態

連接成功後，您應該看到：

1. **AWS VPN Client 顯示**

   ```text
   狀態：已連接 (Connected)
   伺服器：[VPN伺服器地址]
   分配的 IP：172.16.x.x
   連接時間：00:01:23

   ```text

2. **系統通知**
   - macOS 可能會顯示「VPN 已連接」的通知

### ✅ 網路連接測試

在終端機中執行以下測試：

1. **檢查 VPN 介面**

   ```bash
   ifconfig | grep -A 3 utun

   ```text
   應該顯示類似：
   ```text
   utun3: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1436
   inet 172.16.0.10 --> 172.16.0.10 netmask 0xffffff00

   ```text

2. **檢查路由表**

   ```bash
   netstat -rn | grep utun

   ```text

3. **測試內部資源訪問**

   ```bash
   # 請向 IT 管理員索取測試 IP 地址

   ping 10.0.1.10

   # 或測試內部服務

   curl -I http://internal-api.company.com

   ```text

### ✅ DNS 解析測試

```bash

# 測試內部域名解析（如果有的話）

nslookup internal.company.com

# 檢查 DNS 設定

scutil --dns | grep nameserver

```text

---

## 環境切換操作

### 🔄 日常環境切換流程

當您需要在 Staging 和 Production 環境間切換時，請遵循以下流程：

#### 步驟 1：斷開當前 VPN 連接

1. **在 AWS VPN Client 中斷開連接**
   - 點擊「中斷連接」(Disconnect) 按鈕
   - 確認狀態變為 🔴 紅色（未連接）

2. **確認完全斷開**

   ```bash
   # 檢查 VPN 介面是否已移除

   ifconfig | grep utun
   # 應該沒有相關的 VPN 介面

   ```text

#### 步驟 2：切換環境

使用命令列工具或互動式選擇器：

#### 方法一：命令列切換

```bash

# 切換到 Staging

./vpn_env.sh switch staging

# 切換到 Production（需要確認）

./vpn_env.sh switch production

```text

#### 方法二：互動式選擇器

```bash

# 啟動選擇器

./enhanced_env_selector.sh

# 按 'E' 選擇環境切換
# 依照畫面指示選擇目標環境

```text

#### 步驟 3：更新 AWS VPN Client 設定檔

1. **檢查當前環境**

   ```bash
   ./vpn_env.sh status

   ```text

2. **在 AWS VPN Client 中選擇對應設定檔**
   - 開啟 AWS VPN Client
   - 從設定檔下拉選單中選擇對應新環境的設定檔
   - 確認設定檔名稱包含正確的環境標識

#### 步驟 4：重新連接

1. **連接到新環境**
   - 點擊「連接」(Connect) 按鈕
   - 等待連接完成

2. **驗證環境切換成功**

   ```bash
   # 檢查連接狀態

   ./vpn_env.sh status

   # 執行健康檢查

   ./vpn_env.sh health

   ```text

### 🔄 環境切換安全確認

#### Staging 到 Production 切換

當您從 Staging 切換到 Production 時，系統會執行額外的安全確認：

```text
⚠️  警告: 您即將切換到 Production 環境

請確認以下事項：
□ 我了解這是生產環境
□ 我需要訪問生產資源進行除錯
□ 我會在使用完畢後立即斷開連接
□ 我已經在 Staging 環境中完成初步測試

請輸入確認碼 [PROD]: PROD

✅ 額外確認：
請輸入您的用戶名稱: [您的用戶名]

🔄 環境已成功切換到: production

```text

#### Production 到 Staging 切換

從 Production 切換回 Staging 相對簡單：

```text
🔄 環境切換
目標環境: staging
正在驗證環境配置...
✅ 環境配置有效
✅ 憑證檔案存在
✅ 目錄權限正確

🔄 環境已成功切換到: staging

```text

### 🔄 環境切換最佳實踐

1. **切換前準備**
   - ✅ 完成當前環境的所有工作
   - ✅ 記錄當前環境的工作狀態
   - ✅ 確認目標環境的用途

2. **切換過程**
   - ✅ 先斷開 VPN 連接
   - ✅ 使用環境管理工具切換
   - ✅ 更新 AWS VPN Client 設定檔
   - ✅ 重新連接並驗證

3. **切換後驗證**
   - ✅ 執行環境健康檢查
   - ✅ 測試環境特定資源的可達性
   - ✅ 確認設定檔和憑證匹配

### 🔄 緊急環境切換

如果遇到緊急情況需要快速切換環境：

```bash

# 緊急斷開所有 VPN 連接

sudo pkill -f "AWS VPN Client"

# 快速切換到需要的環境

./vpn_env.sh switch production  # 或 staging

# 啟動 AWS VPN Client 並連接

open "/Applications/AWS VPN Client.app"

```text

**⚠️ 注意：** 緊急切換後，請確保執行完整的驗證流程。

---

## 日常使用指南

### 🔄 雙環境日常工作流程

#### 典型開發日工作流程

1. **上午：開發測試（Staging 環境）**

   ```bash
   # 切換到 Staging 環境

   ./vpn_env.sh switch staging

   # 檢查環境狀態

   ./vpn_env.sh status

   # 連接 VPN

   # 在 AWS VPN Client 中選擇 "🧪 Staging VPN - [您的姓名]"

   ```text

2. **下午：生產除錯（Production 環境）**

   ```bash
   # 斷開 Staging VPN 連接

   # 切換到 Production 環境

   ./vpn_env.sh switch production

   # 完成額外確認流程

   # 連接到 Production VPN

   # 在 AWS VPN Client 中選擇 "🏭 Production VPN - [您的姓名]"

   ```text

3. **工作結束：清理**

   ```bash
   # 斷開所有 VPN 連接

   # 檢查最終狀態

   ./vpn_env.sh status

   ```text

### 🔄 正常連接流程（環境感知版）

1. **確認目標環境**

   ```bash
   ./vpn_env.sh status

   ```text

2. **如需切換環境**

   ```bash
   ./vpn_env.sh switch [target_environment]

   ```text

3. **開啟 AWS VPN Client**
4. **選擇對應環境的設定檔**
5. **點擊連接**
6. **等待狀態變為綠色**
7. **開始工作**
8. **完成後立即斷開**

### 🔄 中斷連接

1. #### 方法一：正常中斷

   - 在 AWS VPN Client 中點擊「中斷連接」(Disconnect)

2. #### 方法二：強制中斷

   - 如果無法正常中斷，可以完全退出應用程式
   - `⌘ + Q` 或選單中的「退出」

3. #### 方法三：系統中斷

   ```bash
   # 在終端機中執行（緊急情況）

   sudo pkill -f "AWS VPN Client"

   ```text

### 🔄 環境感知連接管理

新的雙環境系統支援智慧型連接管理：

1. **環境狀態檢查**

   ```bash
   # 檢查當前連接的環境

   ./vpn_env.sh status

   ```text

2. **環境特定連接驗證**

   ```bash
   # 執行環境健康檢查

   ./vpn_env.sh health

   ```text

3. **連接統計查看**
   - 在 AWS VPN Client 中點擊「詳細資料」
   - 注意檢查：
     - 分配的 IP 是否符合環境範圍
     - 連接的伺服器端點是否正確
     - 環境標識是否在設定檔名稱中清楚顯示

3. #### 方法三：系統中斷

   ```bash
   # 在終端機中執行（緊急情況）

   sudo pkill -f "AWS VPN Client"

   ```text

### 🔄 查看連接統計

在 AWS VPN Client 中：

- 點擊「詳細資料」或「Details」
- 查看：
  - 連接時間
  - 上傳/下載流量
  - 伺服器資訊
  - 分配的 IP 地址

### 🔄 管理多個設定檔

如果您需要訪問不同的環境：

1. **添加設定檔**
   - 重複「VPN 連接步驟」添加其他環境的設定檔
   - 使用清楚的命名：
     - `Production VPN - [姓名]`
     - `Staging VPN - [姓名]`

2. **切換設定檔**
   - 先中斷當前連接
   - 選擇新的設定檔
   - 重新連接

---

## 故障排除

### ❌ 雙環境相關問題

#### 問題 1：環境切換失敗

**症狀：**
- 執行 `./vpn_env.sh switch` 出現錯誤
- 提示「環境切換失敗」

**解決步驟：**

1. **檢查環境管理工具**

   ```bash
   # 檢查工具是否存在

   ls -la vpn_env.sh enhanced_env_selector.sh
   ls -la lib/env_manager.sh lib/enhanced_confirmation.sh

   ```text

2. **確認環境配置文件**

   ```bash
   # 檢查環境配置

   ls -la configs/staging/staging.env
   ls -la configs/production/production.env

   ```text

3. **重新初始化環境管理**

   ```bash
   ./vpn_env.sh init

   ```text

#### 問題 2：環境與設定檔不匹配

**症狀：**
- 當前環境是 Staging，但連接的是 Production 設定檔
- 連接成功但無法訪問預期的資源

**解決步驟：**

1. **檢查當前環境**

   ```bash
   ./vpn_env.sh status

   ```text

2. **確認 AWS VPN Client 設定檔**
   - 檢查選擇的設定檔名稱
   - 確保包含正確的環境標識（🧪 或 🏭）

3. **重新同步環境和設定檔**
   - 中斷 VPN 連接
   - 切換到正確環境：`./vpn_env.sh switch [correct_env]`
   - 選擇對應的設定檔重新連接

#### 問題 3：Production 環境確認失敗

**症狀：**
- 無法通過 Production 環境的額外確認
- 提示確認碼錯誤

**解決步驟：**

1. **確認輸入格式**
   - 確認碼必須是大寫：`PROD`
   - 用戶名稱必須與您的實際用戶名一致

2. **檢查確認模組**

   ```bash
   # 測試確認模組

   source lib/enhanced_confirmation.sh

   ```text

3. **使用互動式選擇器**

   ```bash
   # 嘗試使用視覺化介面

   ./enhanced_env_selector.sh

   ```text

### ❌ 傳統 VPN 問題（更新版）

#### 問題 4：無法導入環境專用配置檔案

**症狀：**
- 選擇環境專用 .ovpn 檔案後出現錯誤
- 提示「無效的配置檔案」

**解決步驟：**

1. **確認選擇了正確的環境配置檔案**

   ```bash
   # 檢查當前環境

   ./vpn_env.sh status

   # 確認對應的配置檔案存在

   ls -la vpn-config/staging-*-config.ovpn
   ls -la vpn-config/production-*-config.ovpn

   ```text

2. **檢查檔案完整性**

   ```bash
   # 檢查 Staging 配置

   cat vpn-config/staging-[您的用戶名]-config.ovpn | head -10

   # 檢查 Production 配置

   cat vpn-config/production-[您的用戶名]-config.ovpn | head -10

   ```text

3. **重新生成環境配置**

   ```bash
   # 重新執行設置腳本

   ./team_member_setup.sh

   ```text

#### 問題 5：環境特定認證錯誤

**症狀：**
- 連接失敗，錯誤訊息包含認證相關問題
- 在某個環境可以連接，但另一個環境不行

**解決步驟：**

1. **檢查環境專用憑證**

   ```bash
   # 檢查 Staging 憑證

   openssl x509 -in certs/staging/[您的用戶名].crt -noout -dates

   # 檢查 Production 憑證

   openssl x509 -in certs/production/[您的用戶名].crt -noout -dates

   ```text

2. **驗證憑證與私鑰匹配**

   ```bash
   # Staging 環境驗證

   openssl x509 -noout -modulus -in certs/staging/[您的用戶名].crt | openssl md5
   openssl rsa -noout -modulus -in certs/staging/[您的用戶名].key | openssl md5

   # Production 環境驗證

   openssl x509 -noout -modulus -in certs/production/[您的用戶名].crt | openssl md5
   openssl rsa -noout -modulus -in certs/production/[您的用戶名].key | openssl md5

   ```text

3. **執行環境健康檢查**

   ```bash
   ./vpn_env.sh health

   ```text

#### 問題 6：環境混淆導致的連接問題

**症狀：**
- 連接成功但無法訪問預期的內部資源
- IP 分配與環境不符

**解決步驟：**

1. **驗證環境一致性**

   ```bash
   # 檢查當前環境

   ./vpn_env.sh status

   # 檢查 VPN 分配的 IP

   ifconfig | grep -A 2 utun

   ```text

2. **確認路由表正確性**

   ```bash
   netstat -rn | grep utun
   route -n get 10.0.0.0

   ```text

3. **測試環境特定資源**

   ```bash
   # 測試 Staging 專用資源

   ping staging-internal.company.com

   # 測試 Production 專用資源

   ping production-internal.company.com

   ```text

### ❌ 環境健康檢查失敗

#### 問題 7：環境健康檢查報告異常

**症狀：**
- `./vpn_env.sh health` 顯示錯誤狀態
- 環境標記為不健康

**解決步驟：**

1. **查看詳細健康報告**

   ```bash
   ./vpn_env.sh health -v  # 如果支援詳細模式

   ```text

2. **檢查環境組件**

   ```bash
   # 檢查配置文件

   source configs/staging/staging.env && echo "Staging config OK"
   source configs/production/production.env && echo "Production config OK"

   # 檢查憑證有效性

   find certs/ -name "*.crt" -exec openssl x509 -in {} -noout -dates \;

   ```text

3. **修復權限問題**

   ```bash
   # 修復所有環境的權限

   chmod 600 certs/staging/*
   chmod 600 certs/production/*
   chmod 600 vpn-config/*.ovpn

   ```text

### ❌ 一般 VPN 連接問題

#### 問題 8：DNS 解析問題（環境感知版）

**症狀：**
- 無法解析環境特定的內部域名
- 某些環境的 DNS 正常，其他環境不正常

**解決步驟：**

1. **檢查環境特定 DNS 設定**

   ```bash
   scutil --dns | grep nameserver

   ```text

2. **測試環境特定域名解析**

   ```bash
   # 測試 Staging 域名

   nslookup staging.internal.company.com

   # 測試 Production 域名

   nslookup production.internal.company.com

   ```text

3. **刷新 DNS 快取後重新連接**

   ```bash
   sudo dscacheutil -flushcache
   sudo killall -HUP mDNSResponder

   ```text

#### 問題 9：連接速度問題（環境相關）

**症狀：**
- 特定環境的連接速度明顯較慢
- 環境間性能差異明顯

**解決步驟：**

1. **比較環境性能**

   ```bash
   # 測試不同環境的延遲

   # 切換到 Staging

   ./vpn_env.sh switch staging
   ping [staging-gateway-ip]

   # 切換到 Production

   ./vpn_env.sh switch production
   ping [production-gateway-ip]

   ```text

2. **檢查環境負載**

   ```bash
   # 使用互動式選擇器查看環境統計

   ./enhanced_env_selector.sh
   # 按 'S' 查看狀態總覽

   ```text

### ❌ 緊急故障排除

#### 快速診斷流程

如果遇到嚴重問題，請按順序執行：

```bash

# 1. 檢查環境狀態

./vpn_env.sh status

# 2. 執行健康檢查

./vpn_env.sh health

# 3. 強制斷開所有連接

sudo pkill -f "AWS VPN Client"

# 4. 重新初始化環境

./vpn_env.sh init

# 5. 切換到 Staging（相對安全）

./vpn_env.sh switch staging

# 6. 重新啟動 AWS VPN Client

open "/Applications/AWS VPN Client.app"

```text

#### 聯繫支援時提供的信息

當需要技術支援時，請準備以下信息：

```bash

# 收集環境診斷信息

echo "=== 環境狀態 ===" > diagnosis.txt
./vpn_env.sh status >> diagnosis.txt

echo "=== 健康檢查 ===" >> diagnosis.txt
./vpn_env.sh health >> diagnosis.txt

echo "=== 文件結構 ===" >> diagnosis.txt
find configs/ certs/ vpn-config/ -type f >> diagnosis.txt

echo "=== 權限檢查 ===" >> diagnosis.txt
find certs/ vpn-config/ -type f -exec ls -la {} \; >> diagnosis.txt

```text

將生成的 `diagnosis.txt` 文件內容提供給支援團隊（注意移除敏感信息）。

---

## 安全最佳實踐

### 🔐 雙環境安全原則

1. **環境隔離**
   - ✅ Staging 和 Production 環境完全隔離
   - ✅ 使用不同的憑證和配置文件
   - ✅ 獨立的日誌和狀態追蹤
   - ❌ 禁止在 Staging 環境處理生產數據
   - ❌ 禁止跨環境複製憑證或配置

2. **Production 環境保護**
   - 🔒 額外確認機制防止誤連
   - 🔒 所有 Production 操作都有詳細日誌
   - 🔒 限制 Production 環境使用時間
   - 🔒 定期審核 Production 環境訪問記錄

3. **環境切換安全**

   ```bash
   # 確認當前環境

   ./vpn_env.sh status

   # 安全切換流程

   ./vpn_env.sh switch [target_environment]

   # 驗證切換結果

   ./vpn_env.sh health

   ```text

### 🔐 憑證和配置文件安全

1. **文件權限**

   ```bash
   # 定期檢查敏感文件權限

   find . -name "*.ovpn" -o -name "*.key" -o -name "*.crt" | xargs ls -la

   # 確保權限正確

   chmod 600 vpn-config/*.ovpn
   chmod 600 certs/staging/*.key
   chmod 600 certs/staging/*.crt
   chmod 600 certs/production/*.key
   chmod 600 certs/production/*.crt

   ```text

2. **環境分離備份**

   ```bash
   # 創建環境特定的加密備份

   tar -czf staging-backup-$(date +%Y%m%d).tar.gz certs/staging/ configs/staging/
   tar -czf production-backup-$(date +%Y%m%d).tar.gz certs/production/ configs/production/

   # 加密備份文件

   gpg --symmetric --cipher-algo AES256 staging-backup-$(date +%Y%m%d).tar.gz
   gpg --symmetric --cipher-algo AES256 production-backup-$(date +%Y%m%d).tar.gz

   # 清理未加密備份

   rm *-backup-$(date +%Y%m%d).tar.gz

   ```text

3. **絕對禁止的行為**
   - ❌ 不要通過電子郵件發送配置文件
   - ❌ 不要將文件上傳到雲端儲存（Dropbox、Google Drive 等）
   - ❌ 不要將文件提交到 Git 儲存庫
   - ❌ 不要在多台電腦上使用同一個配置文件
   - ❌ 不要分享您的用戶憑證給其他人
   - ❌ 不要混用 Staging 和 Production 憑證
   - ❌ 不要同時連接多個環境

### 🔐 VPN 使用安全

1. **連接管理**
   - ✅ 僅在需要時連接 VPN
   - ✅ 完成工作後立即斷開連接
   - ✅ 不要讓 VPN 保持長時間連接
   - ✅ 避免在公共 Wi-Fi 上使用 VPN 進行敏感操作

2. **監控和日誌**

   ```bash
   # 檢查連接日誌

   tail -f /var/log/system.log | grep -i vpn

   # 檢查網路活動

   netstat -an | grep 443

   ```text

3. **定期安全檢查**
   - 每月檢查證書有效期
   - 定期更新 AWS VPN Client
   - 確認沒有未授權的 VPN 連接

### 🔐 事件響應

如果發生以下情況，請立即聯繫 IT 安全團隊：

1. **安全事件**
   - 懷疑配置文件被洩露
   - 發現未授權的 VPN 連接
   - 電腦被惡意軟體感染

2. **異常活動**
   - 無法解釋的網路流量
   - 異常的連接位置或時間
   - 無法正常中斷 VPN 連接

---

## 常見問題 FAQ

### ❓ Q1：什麼時候應該使用 Staging 環境？什麼時候使用 Production 環境？

**A1：** 使用指南：

**Staging 環境 🧪：**
- 日常開發和測試工作
- 新功能的驗證和除錯
- 程式碼部署前的最終測試
- 學習和練習使用內部系統

**Production 環境 🏭：**
- 僅限生產環境的緊急除錯
- 必要的生產數據查詢
- 生產系統維護工作
- 客戶問題的直接診斷

### ❓ Q2：我可以同時連接兩個環境嗎？

**A2：** **強烈不建議**，因為：
- 會造成路由表衝突
- 可能導致數據流向錯誤的環境
- 增加安全風險
- 系統設計為互斥使用

### ❓ Q3：如何確認我當前連接的是哪個環境？

**A3：** 使用多種方法確認：

```bash

# 方法 1：環境狀態檢查

./vpn_env.sh status

# 方法 2：互動式選擇器

./enhanced_env_selector.sh

# 方法 3：檢查 VPN Client 設定檔名稱
# 應該顯示 🧪 Staging 或 🏭 Production

```text

### ❓ Q4：我在切換環境時被要求輸入確認碼，這是什麼？

**A4：** 這是 **Production 環境保護機制**：
- 當切換到 Production 環境時會觸發
- 確認碼會顯示在命令行介面中
- 必須準確輸入才能完成切換
- 防止意外訪問生產環境

### ❓ Q5：我可以在多台電腦上使用同一個配置文件嗎？

**A5：** 不建議，也不安全。每台電腦都應該有獨立的憑證和配置。如果您需要在多台電腦上使用 VPN，請為每台電腦分別執行 `team_member_setup.sh`。

### ❓ Q6：VPN 連接會影響我訪問外部網站的速度嗎？

**A6：** 會有一定影響，因為：
- 流量需要經過 VPN 伺服器路由
- 加密/解密會增加延遲
- 建議只在需要訪問內部資源時連接

### ❓ Q7：如果我忘記斷開 VPN 連接會怎樣？

**A7：** 系統有多種保護機制：
- 自動超時斷開（依設定而定）
- 連接時間會被記錄在日誌中
- 管理員可以遠端終止連接
- 建議養成使用完畢立即斷開的習慣

### ❓ Q8：我可以在家工作時使用 VPN 嗎？

**A8：** 可以，但需要注意：
- 確保家用網路安全
- 避免在公共 Wi-Fi 上處理敏感數據
- 使用加密的 Wi-Fi 連接
- 保持電腦防毒軟體更新

### ❓ Q9：每次重新啟動 AWS VPN Client 後都需要重新連接嗎？

**A9：** 通常不需要。如果遇到連接問題，可以嘗試：

1. 先中斷連接
2. 等待 10 秒
3. 重新連接

如果仍有問題，再考慮重新啟動應用程式。

### ❓ Q10：我可以在虛擬機器中使用 VPN 嗎？

**A10：** 技術上可行，但可能需要額外的網路配置。建議在主機系統中直接使用 VPN。

### ❓ Q11：為什麼我的環境健康檢查失敗？

**A11：** 常見原因：
- 憑證過期或損壞
- 環境配置文件問題
- 網路連接問題
- 權限設定錯誤

解決方法：

```bash

# 檢查詳細狀態

./vpn_env.sh health

# 重新初始化環境

./vpn_env.sh init

# 如果問題持續，聯繫 IT 支援

```text

---

## 緊急聯絡資訊

### 🚨 緊急情況聯絡方式

如果您遇到以下緊急情況，請立即聯絡相關人員：

#### 🔴 生產環境緊急問題

- **聯絡人**: IT 系統管理員
- **電話**: +886-2-XXXX-XXXX (24小時)
- **Email**: <it-emergency@company.com>
- **Slack**: #emergency-it

#### 🟡 一般 VPN 技術支援

- **聯絡人**: IT 技術支援團隊
- **電話**: +886-2-XXXX-XXXX (上班時間)
- **Email**: <it-support@company.com>
- **Slack**: #it-support
- **支援時間**: 週一至週五 9:00-18:00

#### 📋 問題回報注意事項

當聯絡技術支援時，請準備以下資訊：

1. **環境資訊**
   - 目前使用的環境 (Staging/Production)
   - 作業系統版本
   - AWS VPN Client 版本

2. **問題描述**
   - 具體錯誤訊息
   - 問題發生時間
   - 重現步驟

3. **環境狀態**

```bash
./vpn_env.sh status
./vpn_env.sh health

```text

1. **日誌檔案**
   - 環境相關日誌: `logs/[environment]/`
   - AWS VPN Client 日誌

### 📞 管理層緊急聯絡

在極緊急情況下，您也可以聯絡：

- **技術主管**: tech-lead@company.com
- **IT 主管**: it-manager@company.com

---

**祝您使用順利！** 🎉
