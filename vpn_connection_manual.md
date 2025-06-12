<!-- markdownlint-disable MD051 -->
<!-- filepath: /Users/ctyeh/Documents/NewsLeopard/nlm-codes/nlInc-vpnMgmtTools/vpn_connection_manual.md -->
# 📖 AWS Client VPN 雙環境管理工具套件完整使用手冊

**版本：** 2.1
**適用於：** macOS 使用者及管理員
**更新日期：** YYYY年MM月DD日

---

## 📋 目錄

1.  [引言](#引言)
    1.  [手冊概述](#手冊概述)
    2.  [2.0 版本新特性](#20-版本新特性)
    3.  [重要提醒](#重要提醒)
2.  [系統架構](#系統架構)
    1.  [雙環境架構介紹](#雙環境架構介紹)
    2.  [工具組件概覽](#工具組件概覽)
    3.  [函式庫架構](#函式庫架構)
3.  [初始設置 (管理員)](#初始設置-管理員)
    1.  [系統要求](#系統要求)
    2.  [下載和準備](#下載和準備)
    3.  [首次 AWS 配置](#首次-aws-配置)
    4.  [驗證設置](#驗證設置)
4.  [環境管理工具詳解](#環境管理工具詳解)
    1.  [`vpn_env.sh` - 環境管理入口](#vpn_envsh---環境管理入口)
    2.  [`enhanced_env_selector.sh` - 互動式環境選擇器](#enhanced_env_selectorsh---互動式環境選擇器)
5.  [用戶 VPN 設定與連接](#用戶-vpn-設定與連接)
    1.  [前置作業檢查 (用戶端)](#前置作業檢查-用戶端)
    2.  [AWS VPN Client 安裝與設定](#aws-vpn-client-安裝與設定)
    3.  [`team_member_setup.sh` - 團隊成員設置工具 (用戶端使用)](#team_member_setupsh---團隊成員設置工具-用戶端使用)
    4.  [VPN 連接步驟 (環境感知)](#vpn-連接步驟-環境感知)
    5.  [連接驗證](#連接驗證)
6.  [管理員工具詳細指南](#管理員工具詳細指南)
    1.  [`aws_vpn_admin.sh` - 管理員主控台](#aws_vpn_adminsh---管理員主控台)
    2.  [`revoke_member_access.sh` - 權限撤銷工具](#revoke_member_accesssh---權限撤銷工具)
    3.  [`employee_offboarding.sh` - 離職處理系統](#employee_offboardingsh---離職處理系統)
7.  [日常操作指南](#日常操作指南)
    1.  [雙環境日常工作流程](#雙環境日常工作流程)
    2.  [環境切換操作詳解](#環境切換操作詳解)
8.  [檔案系統影響](#檔案系統影響)
    1.  [`aws_vpn_admin.sh` 的檔案影響](#aws_vpn_adminsh-的檔案影響)
    2.  [`team_member_setup.sh` 的檔案影響](#team_member_setupsh-的檔案影響)
    3.  [`revoke_member_access.sh` 的檔案影響](#revoke_member_accesssh-的檔案影響)
    4.  [`employee_offboarding.sh` 的檔案影響](#employee_offboardingsh-的檔案影響)
    5.  [檔案權限和安全設定](#檔案權限和安全設定)
9.  [維護和監控](#維護和監控)
    1.  [定期維護任務](#定期維護任務)
    2.  [自動化監控範例](#自動化監控範例)
10. [安全最佳實踐](#安全最佳實踐)
    1.  [雙環境安全原則](#雙環境安全原則)
    2.  [證書安全管理](#證書安全管理)
    3.  [訪問控制](#訪問控制)
    4.  [配置文件安全](#配置文件安全)
    5.  [VPN 使用安全](#vpn-使用安全)
    6.  [事件響應](#事件響應)
11. [故障排除](#故障排除)
    1.  [雙環境相關問題](#雙環境相關問題-1)
    2.  [管理工具常見問題](#管理工具常見問題)
    3.  [用戶端連接常見問題](#用戶端連接常見問題)
    4.  [日誌文件分析](#日誌文件分析)
12. [AWS 資源和成本管理](#aws-資源和成本管理)
    1.  [創建的 AWS 資源](#創建的-aws-資源)
    2.  [成本優化建議](#成本優化建議)
13. [完整移除指南](#完整移除指南)
    1.  [停止所有服務](#停止所有服務)
    2.  [使用工具清理 AWS 資源](#使用工具清理-aws-資源)
    3.  [清理本地文件](#清理本地文件)
    4.  [移除應用程式](#移除應用程式)
14. [附錄](#附錄)
    1.  [常用 AWS CLI 命令](#常用-aws-cli-命令)
    2.  [配置文件範例 (`.vpn_config`)](#配置文件範例-vpn_config)
    3.  [IAM 權限政策範例](#iam-權限政策範例)
    4.  [緊急聯絡範本](#緊急聯絡範本)
15. [常見問題 FAQ](#常見問題-faq)
16. [緊急聯絡資訊](#緊急聯絡資訊)

---

## 1. 引言

### 1.1 手冊概述

本手冊為 AWS Client VPN 雙環境管理工具套件的完整使用說明，旨在指導**一般使用者**如何安全連接至 Staging（測試）和 Production（生產）環境，並為**管理員**提供工具套件的安裝、配置、管理及維護指南。新系統強調環境隔離、安全管理及操作便捷性，旨在為企業提供一個可靠且易於擴展的 VPN 管理框架。

透過雙環境設計，企業能夠在 Staging 環境中安全地進行測試、開發和配置驗證，而 Production 環境則保持穩定運行，服務於正式的業務需求。這種分離確保了生產系統的穩定性，同時為新功能和變更提供了安全的測試平台。

### 1.2 2.0 版本新特性

- ✨ **雙環境支援** - 完全分離的 Staging 和 Production 環境。
- 🔄 **智能環境切換** - 一鍵切換不同環境配置 (`vpn_env.sh`, `enhanced_env_selector.sh`)。
- 🛡️ **增強安全確認** - Production 環境操作需要多重確認。
- 📊 **環境健康監控** - 即時監控兩個環境的運行狀態。
- 🎯 **環境比較工具** - 快速比較不同環境的配置差異 (透過 `enhanced_env_selector.sh`)。

### 1.3 重要提醒

- **Staging 環境**: 用於開發測試、功能驗證、新功能除錯。
- **Production 環境**: 僅用於生產環境除錯和緊急維護。
- 請依據工作性質選擇適當的環境。
- 使用完畢後立即斷開連接。
- 嚴禁分享您的 VPN 配置文件或憑證。
- 管理員應妥善保管 CA 金鑰及相關敏感配置。

---

## 2. 系統架構

### 2.1 雙環境架構介紹

本工具套件支援完全分離的雙環境架構，確保開發測試與生產操作的獨立性。關鍵資源如配置文件、證書和日誌均按環境存放：

```bash
configs/
├── staging/                 # 🟡 Staging 環境配置
│   └── staging.env
└── production/             # 🔴 Production 環境配置
    └── production.env

certs/
├── staging/                # Staging 環境證書
└── production/             # Production 環境證書

logs/
├── staging/                # Staging 環境日誌
└── production/             # Production 環境日誌
```

**環境特性:**

#### Staging 環境 🟡
- **用途**: 開發、測試、實驗。
- **安全級別**: 標準。
- **確認要求**: 基本確認。
- **適用對象**: 開發團隊、QA 團隊。

#### Production 環境 🔴
- **用途**: 生產環境、正式服務。
- **安全級別**: 最高。
- **確認要求**: 多重確認、輸入驗證。
- **適用對象**: 運維團隊、資深工程師。

### 2.2 工具組件概覽

1.  **`vpn_env.sh`** - 🆕 環境管理入口（新增）。
2.  **`enhanced_env_selector.sh`** - 🆕 增強環境選擇器（新增）。
3.  **`aws_vpn_admin.sh`** - 管理員主控台（核心管理工具）。
4.  **`team_member_setup.sh`** - 團隊成員設置工具。
5.  **`revoke_member_access.sh`** - 權限撤銷工具。
6.  **`employee_offboarding.sh`** - 離職處理系統。

### 2.3 函式庫架構

本工具套件採用模組化函式庫設計，核心功能分佈於 `lib/` 目錄下：
```bash
lib/
├── core_functions.sh        # 核心函式和通用工具 (日誌, 驗證等)
├── env_manager.sh          # 🆕 環境管理核心功能 (切換, 狀態, 健康檢查)
├── enhanced_confirmation.sh # 🆕 增強確認系統 (用於 Production 環境操作)
├── aws_setup.sh            # AWS CLI 配置和驗證相關函式
├── cert_management.sh      # Easy-RSA 憑證生成和管理函式
├── endpoint_creation.sh    # AWS Client VPN 端點創建和配置函式
└── endpoint_management.sh  # 端點關聯、授權、路由等管理函式
```

---

## 3. 初始設置 (管理員)

本章節指導管理員完成工具套件的初始部署和配置。

### 3.1 系統要求

#### 硬體要求
- macOS 10.15+ (Catalina 或更新版本)
- 至少 4GB RAM
- 2GB 可用磁碟空間
- 穩定的網路連接

#### 軟體依賴
本套件會自動嘗試安裝以下工具（若尚未安裝）：
- **Homebrew** - macOS 套件管理器 (用於安裝其他依賴)
- **AWS CLI** - AWS 命令列工具
- **jq** - JSON 處理工具
- **Easy-RSA** - 證書管理工具 (通常隨 OpenVPN 或可獨立安裝)
- **OpenSSL** - 加密工具 (macOS 通常內建)

#### AWS 權限要求
運行本工具套件中的不同腳本需要特定的 AWS IAM 權限。詳細的 JSON 政策範例請參閱 [附錄 14.3 IAM 權限政策範例](#iam-權限政策範例)。
- **管理員權限 (`aws_vpn_admin.sh`)**: 需要管理 Client VPN 端點、ACM 證書、日誌、VPC 和子網路等資源的權限。
- **團隊成員設置權限 (`team_member_setup.sh` 由管理員準備基礎文件時可能間接使用部分權限，用戶端執行時也需要權限)**: 需要描述 VPN 端點、導出客戶端配置、以及管理個人 ACM 證書的權限。
- **高權限操作 (`employee_offboarding.sh`)**: 可能需要更廣泛的權限，例如 IAM 管理、S3 存取等。

### 3.2 下載和準備

1.  **獲取工具套件**:
    通常由開發團隊提供壓縮檔或 Git 儲存庫存取權限。

2.  **創建工作目錄**:
    ```bash
    mkdir -p ~/aws-vpn-tools
    cd ~/aws-vpn-tools
    ```

3.  **解壓或複製文件**:
    確保工具套件的文件結構如下：
    ```bash
    .
    ├── aws_vpn_admin.sh
    ├── employee_offboarding.sh
    ├── enhanced_env_selector.sh
    ├── readme.md
    ├── revoke_member_access.sh
    ├── team_member_setup.sh
    ├── vpn_connection_manual.md
    ├── vpn_env.sh
    └── lib/
        ├── aws_setup.sh
        ├── cert_management.sh
        ├── core_functions.sh
        ├── endpoint_creation.sh
        ├── endpoint_management.sh
        ├── enhanced_confirmation.sh
        └── env_manager.sh
    ```

4.  **設置執行權限**:
    ```bash
    chmod +x *.sh
    chmod +x lib/*.sh
    ```
    (注意: `readme.md` 和 `vpn_connection_manual.md` 不需要執行權限)

### 3.3 首次 AWS 配置

管理員首次執行 `aws_vpn_admin.sh` 或任何需要 AWS 互動的腳本時，若尚未配置 AWS CLI，系統會引導進行配置。

```bash
# 建議先手動配置 AWS CLI，確保權限正確
aws configure
```
系統會提示輸入：
- AWS Access Key ID
- AWS Secret Access Key
- Default region name (例如：ap-northeast-1)
- Default output format (建議：json)

或者，腳本中的 `lib/aws_setup.sh` 會檢查並提示配置。

### 3.4 驗證設置

1.  **驗證 AWS 配置**:
    ```bash
    aws sts get-caller-identity
    ```
    如果成功，會顯示您的帳戶、用戶 ID 和 ARN。

2.  **檢查 VPC 訪問權限** (根據您計劃使用的區域):
    ```bash
    aws ec2 describe-vpcs --region your-chosen-region
    ```

3.  **初始化環境管理系統** (首次使用工具套件前):
    ```bash
    ./vpn_env.sh init
    ```
    這將創建必要的配置文件目錄 (`configs/staging`, `configs/production`) 和其他支持性結構。

---

## 4. 環境管理工具詳解

本節詳細介紹用於管理 Staging 和 Production 環境的工具。

### 4.1 `vpn_env.sh` - 環境管理入口

`vpn_env.sh` 是管理和切換 VPN 環境的主要命令列工具。

#### 基本操作

1.  **查看當前環境狀態 (`status`)**
    ```bash
    ./vpn_env.sh status
    ```
    輸出範例：
    ```text
    === 當前 VPN 環境狀態 ===
    環境: 🟡 Staging Environment
    名稱: staging
    狀態: 🟢 健康
    配置文件: /path/to/configs/staging/staging.env
    ========================
    ```

2.  **切換環境 (`switch`)**
    - **切換到 Staging 環境**:
      ```bash
      ./vpn_env.sh switch staging
      ```
      輸出：
      ```text
      🔄 環境已成功切換到 Staging
      ```
    - **切換到 Production 環境** (需要額外確認):
      ```bash
      ./vpn_env.sh switch production
      ```
      輸出範例：
      ```text
      ⚠️  Production 環境切換確認

      您即將切換到生產環境：
      • 所有後續操作將影響正式系統
      • 請確保您有適當的權限和授權
      • 操作將被記錄在審計日誌中

      確認切換到 Production 環境？ [yes/NO]: yes
      ✅ 環境已成功切換到 Production
      ```

3.  **檢查環境健康狀態 (`health`)**
    - **檢查所有環境**:
      ```bash
      ./vpn_env.sh health
      ```
      輸出範例：
      ```text
      === 環境健康狀態檢查 ===
      staging: 🟢 健康 (100% 正常)
      production: 🟡 警告 (證書即將到期)
      ===========================
      ```
    - **檢查特定環境**:
      ```bash
      ./vpn_env.sh health staging
      ```

4.  **啟動互動式選擇器 (`selector`)**
    ```bash
    ./vpn_env.sh selector
    ```
    這將啟動 `enhanced_env_selector.sh`。

5.  **初始化環境配置 (`init`)** (主要供首次設定或修復使用)
    ```bash
    ./vpn_env.sh init
    ```
    此命令會創建 `configs/staging/staging.env` 和 `configs/production/production.env` 的基礎模板（如果它們不存在），以及相關的 `certs` 和 `logs` 目錄結構。

### 4.2 `enhanced_env_selector.sh` - 互動式環境選擇器

提供一個菜單驅動的界面來管理 VPN 環境。

```bash
# 啟動互動式環境管理控制台
./enhanced_env_selector.sh
```

**控制台界面預覽:**
```text
╔══════════════════════════════════════════════════════════════════╗
║               AWS Client VPN 多環境管理控制台 v2.0               ║
╚══════════════════════════════════════════════════════════════════╝

當前環境: 🟡 Staging Environment (🟢 健康)

可用環境:
  1. 🟡 Staging    - 開發測試環境 ← 當前
     健康狀態: 🟢 健康 (100%)  活躍連線: 3 個
     
  2. 🔴 Production - 生產營運環境
     健康狀態: 🟡 警告 (85%)   活躍連線: 8 個

快速操作:
  [E] 切換環境    [S] 環境狀態    [H] 健康檢查
  [D] 詳細資訊    [C] 環境比較    [R] 重新整理
  [Q] 退出

請選擇環境或操作 [1-2/E/S/H/D/C/R/Q]:
```

**功能說明:**
- **[E] 切換環境**: 互動式環境切換，到 Production 環境時會有安全確認。
- **[S] 環境狀態**: 查看當前選擇環境的詳細資訊和健康狀態。
- **[H] 健康檢查**: 檢查所有已配置環境的健康狀態，包含詳細診斷。
- **[D] 詳細資訊**: 顯示選定環境的完整配置資訊 (從 `.env` 文件讀取)。
- **[C] 環境比較**: (如果實現) 比較 Staging 和 Production 環境的關鍵配置參數差異。
- **[R] 重新整理**: 更新顯示的環境狀態資訊。
- **[Q] 退出**: 離開控制台。

---

## 5. 用戶 VPN 設定與連接

本章節主要為一般使用者提供 VPN 連接指南。

### 5.1 前置作業檢查 (用戶端)

在團隊成員開始使用 `team_member_setup.sh` 之前，管理員應提供以下文件/信息：
1.  `team_member_setup.sh` 腳本本身。
2.  `ca.crt` (CA 證書) 文件，此文件應與目標 VPN 環境 (Staging/Production) 的伺服器證書對應。管理員可從 `certs/[environment]/ca.crt` (在管理員機器上生成後) 或 `team-configs/ca.crt` (由 `aws_vpn_admin.sh` 導出團隊配置時生成) 獲取。
3.  目標環境的 VPN 端點 ID (Client VPN Endpoint ID)。

使用者應將 `team_member_setup.sh` 和 `ca.crt` 放置在同一個目錄下。

執行完 `team_member_setup.sh` 後，用戶的專案目錄應包含針對其個人和選定環境的配置：
```bash
您的工作目錄/
├── team_member_setup.sh
├── ca.crt                          # 由管理員提供
├── .user_vpn_config                # 用戶配置 (敏感)
├── user_vpn_setup.log              # 用戶設置日誌
├── user-certificates/              # 用戶證書目錄 (高度敏感)
│   ├── [username].crt              # 用戶證書
│   └── [username].key              # 用戶私鑰 (極度敏感)
└── vpn-config/                     # VPN 配置檔案
    └── [username]-[environment]-config.ovpn # 個人 VPN 配置 (含私鑰)
```
(注意: 新版雙環境用戶端工具可能直接整合環境選擇，目錄結構請以實際腳本輸出為準)

### 5.2 AWS VPN Client 安輸與設定

(此部分內容基本與 `vpn_connection_manual.md` v2.0 版本一致，此處僅作結構調整確認)

#### 步驟 1：確認 AWS VPN Client 已安裝
檢查 `/Applications/AWS VPN Client.app` 是否存在。若無，請從 AWS 官方網站下載並安裝。

#### 步驟 2：啟動 AWS VPN Client
可透過 Spotlight, Finder 或 Launchpad 啟動。

#### 步驟 3：首次啟動設定
處理 macOS 安全提示及應用程式許可。

### 5.3 `team_member_setup.sh` - 團隊成員設置工具 (用戶端使用)

此工具旨在簡化團隊成員獲取和配置其個人 VPN 客戶端所需的證書和 `.ovpn` 配置文件。

**假設管理員已提供 `team_member_setup.sh` 和對應環境的 `ca.crt`。**

**用戶端執行流程：**
1.  **將 `team_member_setup.sh` 和 `ca.crt` 放入同一目錄。**
2.  **開啟終端機，`cd`到該目錄。**
3.  **賦予腳本執行權限：**
    ```bash
    chmod +x team_member_setup.sh
    ```
4.  **執行腳本：**
    ```bash
    ./team_member_setup.sh
    ```
5.  **遵循腳本提示操作：**
    *   **選擇目標環境**: 腳本可能會提示選擇 Staging 或 Production。
    *   **AWS 配置**: 可能提示輸入 AWS Access Key ID, Secret Access Key, Region (用於上傳用戶證書到 ACM)。
    *   **用戶資訊**: 輸入用戶名 (例如 `john.doe`) 和電子郵件。
    *   **證書生成**: 腳本會在本地生成用戶的私鑰 (`.key`) 和證書 (`.crt`)。
    *   **導入證書到 ACM**: 腳本會嘗試將用戶證書上傳到 AWS Certificate Manager (ACM)。
    *   **生成 `.ovpn` 配置文件**: 腳本會使用用戶證書、私鑰和 `ca.crt` 生成個人化的 `.ovpn` 配置文件，例如 `john.doe-staging-config.ovpn`。

**成功執行後，用戶將獲得：**
-   `user-certificates/` 目錄下的個人證書和私鑰。
-   `vpn-config/` 目錄下的個人 `.ovpn` 配置文件。

用戶應妥善保管這些文件，尤其是私鑰和 `.ovpn` 文件。

### 5.4 VPN 連接步驟 (環境感知)

(此部分內容基本與 `vpn_connection_manual.md` v2.0 版本一致，強調環境選擇)

**關鍵步驟：**
1.  **確認/選擇環境**: (若用戶端工具不直接管理環境切換) 使用管理員提供的 `vpn_env.sh` (如果適用於用戶端) 或根據指導手動確認目標環境。對於 `team_member_setup.sh` 生成的特定環境配置文件，用戶應清楚自己要連接哪個環境。
2.  **開啟設定檔管理**: 在 AWS VPN Client 中 `File > Manage Profiles`。
3.  **添加環境專用設定檔**: 點擊 "Add Profile"。
4.  **選擇環境專用配置檔案**: 導航到 `vpn-config/` 並選擇對應的 `[username]-[environment]-config.ovpn` 文件。
5.  **設定環境識別設定檔**: 命名時明確標註環境，例如 `Staging VPN - John Doe` 或 `Production VPN - John Doe`。
6.  **環境感知連接**: 選擇正確的設定檔後點擊 "Connect"。

### 5.5 連接驗證

(此部分內容與 `vpn_connection_manual.md` v2.0 版本一致)
- 確認 AWS VPN Client 狀態。
- 網路連接測試 (ifconfig, netstat, ping 內部資源)。
- DNS 解析測試。

---

## 6. 管理員工具詳細指南

本章節為管理員提供核心管理工具的詳細使用說明。**執行這些工具前，請使用 `vpn_env.sh switch <environment>` 切換到目標操作環境 (Staging 或 Production)。**

### 6.1 `aws_vpn_admin.sh` - 管理員主控台

這是核心管理工具，用於創建、管理和維護 AWS Client VPN 端點及其相關資源。

**啟動方式:**
```bash
# 確保已切換到目標環境 (staging/production)
./vpn_env.sh status # 確認當前環境
./admin-tools/aws_vpn_admin.sh
```

**主要功能選單 (示例):**
1.  **建立新的 VPN 端點**:
    *   引導管理員完成 VPN 端點的創建流程。
    *   自動處理 CA、伺服器、管理員證書的生成與 ACM 導入 (使用 `lib/cert_management.sh`)。
    *   配置網路 (選擇 VPC、子網路)、DNS 伺服器、分割通道等 (使用 `lib/endpoint_creation.sh`)。
    *   設置授權規則和路由。
    *   根據當前選擇的 `staging.env` 或 `production.env` 中的配置進行。
2.  **查看現有 VPN 端點**: 列出當前環境配置的 VPN 端點及其狀態。
3.  **管理 VPN 端點設定**:
    *   修改授權規則 (允許哪些網路訪問)。
    *   管理路由 (將哪些流量導入 VPN)。
    *   關聯/取消關聯目標網路。
4.  **刪除 VPN 端點**: 安全地刪除 VPN 端點及相關 AWS 資源 (如 ACM 中的證書、CloudWatch 日誌組)。**此操作極具破壞性，務必謹慎。**
5.  **查看連接日誌**: 指引如何訪問 CloudWatch 中的 VPN 連接日誌。
6.  **匯出團隊成員設定檔**:
    *   為新成員準備基礎設置文件包 (`team-configs/`)。
    *   包含 `team_member_setup.sh` 腳本副本、當前環境的 `ca.crt`、`team-setup-info.txt` (包含 VPN 端點 ID 等信息) 和基礎的 `team-config-base.ovpn`。
7.  **系統健康檢查**: 檢查當前環境 VPN 端點和相關配置的健康狀態。
8.  **多 VPC 管理**: (若支持) 配置 VPN 端點與多個 VPC 的關聯和路由。

### 6.2 `revoke_member_access.sh` - 權限撤銷工具

用於撤銷特定團隊成員的 VPN 訪問權限。

**啟動方式:**
```bash
# 確保已切換到目標環境
./admin-tools/revoke_member_access.sh
```

**撤銷流程 (示例):**
1.  **檢查工具和權限**: 確保執行者有足夠權限。
2.  **獲取撤銷資訊**: 提示輸入要撤銷的用戶名和目標 VPN 端點 ID (通常從當前環境配置讀取)。
3.  **搜尋用戶證書**: 在 ACM 中根據用戶名和相關標籤搜索用戶證書。
4.  **檢查當前連接**: (可選) 檢查該用戶是否有活躍的 VPN 連接。
5.  **撤銷證書和權限**:
    *   從 AWS Client VPN 端點撤銷用戶證書的授權。
    *   (可選) 刪除 ACM 中的用戶證書。
    *   (可選) 終止該用戶的活躍 VPN 連接。
6.  **檢查和移除 IAM 權限**: (可選，如果用戶有特定 IAM 權限與 VPN 相關聯)。
7.  **生成撤銷報告**: 記錄撤銷操作的詳細信息到日誌文件。

### 6.3 `employee_offboarding.sh` - 離職處理系統

提供一個標準化流程，用於處理員工離職時的全面訪問權限移除及相關安全審計。

**啟動方式:**
```bash
# 確保已切換到目標環境 (通常應同時檢查 Staging 和 Production)
./admin-tools/employee_offboarding.sh
```

**離職處理流程 (示例):**
1.  **收集離職人員資訊**: 輸入員工用戶名、離職日期等。
2.  **風險評估**: (可選) 根據員工角色評估風險等級。
3.  **執行緊急安全措施**: (高風險情況下) 可能包括立即禁用相關帳戶。
4.  **撤銷 VPN 訪問權限**:
    *   自動調用 `revoke_member_access.sh` 的邏輯，或執行類似步驟。
    *   確保在 Staging 和 Production 兩個環境都執行撤銷。
5.  **清理 IAM 權限**: 檢查並移除該員工不再需要的 IAM 用戶/角色權限。
6.  **審計訪問日誌**: 檢查 VPN 連接日誌、CloudTrail 日誌等，尋找異常活動。
7.  **檢查殘留資源**: 檢查是否有該員工創建或擁有的雲資源需要處理。
8.  **生成安全事件報告**: 記錄整個離職處理過程和發現。
9.  **生成離職檢查清單**: 供 HR 和 IT 確認所有步驟已完成。

---

## 7. 日常操作指南

(此部分內容基本與 `vpn_connection_manual.md` v2.0 版本一致，進行了結構調整和強調)

### 7.1 雙環境日常工作流程

#### 典型開發日工作流程
1.  **上午：開發測試（Staging 環境）**
    ```bash
    # (若有 vpn_env.sh) 切換到 Staging 環境
    ./vpn_env.sh switch staging
    # (若有 vpn_env.sh) 檢查環境狀態
    ./vpn_env.sh status
    # 在 AWS VPN Client 中選擇 "Staging VPN - [您的姓名]" 並連接
    ```
2.  **下午：生產除錯（Production 環境）**
    ```bash
    # 斷開 Staging VPN 連接
    # (若有 vpn_env.sh) 切換到 Production 環境
    ./vpn_env.sh switch production # 完成額外確認流程
    # 在 AWS VPN Client 中選擇 "Production VPN - [您的姓名]" 並連接
    ```
3.  **工作結束：清理**
    - 斷開所有 VPN 連接。
    - (若有 vpn_env.sh) 檢查最終狀態: `./vpn_env.sh status`

### 7.2 環境切換操作詳解

(此部分內容基本與 `vpn_connection_manual.md` v2.0 版本一致，整合 `vpn_env.sh` 和 `enhanced_env_selector.sh` 的使用)

**關鍵步驟：**
1.  **斷開當前 VPN 連接**。
2.  **使用 `vpn_env.sh switch <target_env>` 或 `enhanced_env_selector.sh` 切換環境**。
3.  **更新 AWS VPN Client 設定檔選擇** (選擇與新環境匹配的 Profile)。
4.  **重新連接並驗證**。

**安全確認：**
- 切換到 Production 環境時，會有嚴格的確認提示。

---

## 8. 檔案系統影響

本節描述執行各主要腳本後，在本地文件系統中創建或修改的文件和目錄。

### 8.1 `aws_vpn_admin.sh` 的檔案影響

```bash
專案根目錄/
├── configs/                        # 管理員 VPN 配置
│   ├── staging/staging.env        # Staging 環境配置 (可能由此腳本創建或填充)
│   └── production/production.env  # Production 環境配置 (同上)
├── .vpn_config                      # ⚠️ 主配置檔案 (敏感, 記錄當前環境等)
├── vpn_admin.log                    # 主操作日誌 (分環境記錄，例如 vpn_admin_staging.log)
├── certificates/                   # 🔒 證書目錄 (高度敏感)
│   ├── staging/                    # Staging 環境證書
│   │   ├── pki/                    # PKI 結構 (ca.crt, private/ca.key, issued/server.crt 等)
│   │   ├── admin-config-base.ovpn # Staging 管理員基礎配置
│   │   └── admin-config.ovpn      # Staging 管理員完整配置 (含私鑰)
│   └── production/                 # Production 環境證書 (結構同 Staging)
│       ├── pki/
│       ├── admin-config-base.ovpn
│       └── admin-config.ovpn
└── team-configs/                   # 團隊分發檔案 (分環境)
    ├── staging/
    │   ├── team_member_setup.sh  # 腳本副本
    │   ├── ca.crt                # Staging CA 證書副本
    │   ├── team-setup-info.txt   # Staging 設置資訊
    │   └── team-config-base.ovpn # Staging 團隊基礎配置
    └── production/ (結構同 Staging)
        ├── team_member_setup.sh
        ├── ca.crt
        ├── team-setup-info.txt
        └── team-config-base.ovpn
```

### 8.2 `team_member_setup.sh` 的檔案影響 (用戶端)

```bash
用戶執行目錄/
├── .user_vpn_config               # ⚠️ 用戶選擇的環境等配置 (敏感)
├── user_vpn_setup.log             # 用戶設置日誌
├── user-certificates/             # 🔒 用戶證書目錄 (高度敏感)
│   ├── [username].crt             # 用戶證書
│   └── [username].key             # 🔐 用戶私鑰 (極度敏感)
└── vpn-config/                    # VPN 配置檔案
    └── [username]-[environment]-config.ovpn # 🔒 個人 VPN 配置 (含私鑰)
```

### 8.3 `revoke_member_access.sh` 的檔案影響

```bash
專案根目錄/ (或指定日誌目錄)
└── revocation-logs/               # 撤銷日誌目錄 (分環境)
    ├── staging_revocation.log
    ├── production_revocation.log
    └── [username]_revocation_[timestamp].log  # 📋 個別撤銷報告
```

### 8.4 `employee_offboarding.sh` 的檔案影響

```bash
專案根目錄/ (或指定日誌目錄)
└── offboarding-logs/                           # 離職處理日誌目錄
    ├── offboarding_main.log                   # 主要離職日誌
    ├── security_report_[employee]_[timestamp].txt      # 📋 安全報告
    ├── offboarding_checklist_[employee]_[timestamp].txt # 📋 檢查清單
    └── audit-[employee_id]-[date]/            # 審計資料目錄
        ├── audit_summary.txt                 # 審計摘要
        ├── cloudtrail_events.json           # CloudTrail 事件記錄
        └── vpn_events_*.json                # VPN 事件日誌
```

### 8.5 檔案權限和安全設定

所有腳本在創建敏感文件（如私鑰 `.key`，包含私鑰的 `.ovpn` 配置文件，環境配置文件 `.env`）時，會自動設置嚴格的文件權限 (通常是 `chmod 600`，僅所有者可讀寫)。
敏感目錄（如 `certificates/`, `user-certificates/`）也會設置適當權限 (通常是 `chmod 700`)。

---

## 9. 維護和監控

### 9.1 定期維護任務

#### 每週檢查清單 (管理員)
- [ ] 檢查 Staging 和 Production VPN 端點狀態 (AWS Console, `aws_vpn_admin.sh`)。
- [ ] 審查 VPN 連接日誌 (CloudWatch Logs)，注意異常登錄嘗試或連接模式。
- [ ] 檢查 `vpn_env.sh health` 的輸出，關注警告。

#### 每月檢查清單 (管理員)
- [ ] 更新團隊成員清單，撤銷不再需要的訪問權限 (`revoke_member_access.sh`)。
- [ ] 審查 IAM 權限，確保最小權限原則。
- [ ] 檢查多 VPC 網路配置 (如果適用)。
- [ ] 備份 Staging 和 Production 環境的配置 (`configs/`) 和證書 (`certificates/`) 文件 (加密存儲)。

#### 每季檢查清單 (管理員)
- [ ] 執行一次全面的安全審計 (IAM 策略, 安全組, NACL, VPN 配置)。
- [ ] 考慮更新 AWS 權限政策。
- [ ] 規劃證書輪換 (尤其是客戶端證書，參見[證書安全管理](#證書安全管理))。
- [ ] 測試災難恢復流程 (例如，從備份恢復 VPN 端點配置)。

### 9.2 自動化監控範例

管理員可以設置 CloudWatch Alarms 來監控 VPN 的關鍵指標。
此外，可以編寫簡單的本地腳本進行定期健康檢查，並通過 cron job 運行。

```bash
#!/bin/bash
# health_check_cron.sh - 簡易 VPN 健康檢查腳本範例
# 注意: 直接在 cron 中運行需要處理非互動式確認，
# 例如 Production 環境切換。此處的 --auto-confirm 是假設性參數。
# 實際部署可能需要 expect 腳本或修改 vpn_env.sh 以支持非互動模式。
LOG_FILE=~/vpn_health_cron.log
VPN_TOOLS_DIR=~/aws-vpn-tools # 修改為您的工具目錄

echo "=== Cron Health Check Started: $(date) ===" >> $LOG_FILE

cd $VPN_TOOLS_DIR

# 檢查 Staging 環境
echo "--- Checking Staging ---" >> $LOG_FILE
./vpn_env.sh switch staging >> $LOG_FILE 2>&1
./vpn_env.sh health >> $LOG_FILE 2>&1
# 可選：檢查 Staging 端點活躍連接數
# aws ec2 describe-client-vpn-connections --client-vpn-endpoint-id $(grep VPN_ENDPOINT_ID configs/staging/staging.env | cut -d'=' -f2) --query "Connections[?Status.Code=='active'] | length(@)" --output text >> $LOG_FILE

# 檢查 Production 環境
echo "--- Checking Production ---" >> $LOG_FILE
./vpn_env.sh switch production --auto-confirm # 假設腳本有此類非互動選項，否則 cron 會卡住
./vpn_env.sh health >> $LOG_FILE 2>&1
# 可選：檢查 Production 端點活躍連接數

echo "=== Cron Health Check Ended: $(date) ===" >> $LOG_FILE
echo "" >> $LOG_FILE

# 如果檢測到 "警告" 或 "錯誤"，可以發送郵件通知
# if grep -q "警告\|錯誤" $LOG_FILE; then
#    mail -s "VPN Health Alert" admin@example.com < $LOG_FILE
# fi
```
**注意**: 上述腳本僅為範例，實際用於 cron 時需處理好非互動執行和錯誤捕捉。

---

## 10. 安全最佳實踐

(整合 `readme.md` 的詳細內容和 `vpn_connection_manual.md` v2.0 的原則)

### 10.1 雙環境安全原則
- **環境隔離**: Staging 和 Production 數據、憑證、配置嚴格分離。
- **Production 環境保護**: 增強確認，限制訪問，詳細日誌。
- **環境切換安全**: 驗證當前環境，安全切換，驗證切換結果。

### 10.2 證書安全管理
1.  **證書輪換策略**:
    *   CA 證書: 每 2-5 年 (根據組織策略)。
    *   伺服器證書: 每年。
    *   客戶端證書: 每 6-12 個月 (或員工離職/設備丟失時立即撤銷)。
    *   使用 `aws_vpn_admin.sh` 中的功能（如果支持）或手動流程配合 Easy-RSA 進行輪換。
2.  **私鑰保護**:
    *   所有 `.key` 文件自動設為 `600` 權限。
    *   CA 私鑰 (`certificates/[environment]/pki/private/ca.key`) 是最重要的資產，應離線備份到加密存儲，並嚴格控制訪問。
    *   考慮使用硬體安全模組 (HSM) 管理 CA 私鑰 (高級選項)。
3.  **證書備份 (管理員)**:
    ```bash
    # 創建特定環境的加密備份 (示例)
    ENV_NAME="staging" # 或 "production"
    BACKUP_FILE="vpn-certs-${ENV_NAME}-$(date +%Y%m%d).tar.gz"
    tar -czf "${BACKUP_FILE}" "certificates/${ENV_NAME}/" "configs/${ENV_NAME}/"
    gpg --symmetric --cipher-algo AES256 "${BACKUP_FILE}"
    # 安全刪除原始 tar 文件
    # rm "${BACKUP_FILE}"
    # 將 .gpg 文件存儲到安全的多個離線位置
    ```

### 10.3 訪問控制
1.  **最小權限原則**:
    *   為管理員和用戶分配僅執行其任務所必需的最小 IAM 權限 (參見[附錄 IAM 政策](#iam-權限政策範例))。
    *   定期審查 AWS 權限。
    *   推薦為 AWS Client VPN 啟用多因素認證 (MFA)。
2.  **網路分段**:
    *   合理規劃 VPN 客戶端地址池 (CIDR) 和 VPC 內部網路的 CIDR，避免重疊。
    *   建議的 CIDR 分配 (示例):
        *   VPN 客戶端 (Staging): `172.16.0.0/22`
        *   VPN 客戶端 (Production): `172.20.0.0/22`
        *   內部 Staging VPC: `10.10.0.0/16`
        *   內部 Production VPC: `10.20.0.0/16`
    *   使用安全組和 NACL嚴格控制從 VPN 到 VPC 內部資源的訪問。
3.  **監控和審計**:
    *   啟用 CloudTrail 詳細記錄所有 AWS API 調用。
    *   設置 CloudWatch Logs 保存 VPN 連接日誌，並可設置警報。
    *   定期檢查連接日誌和審計日誌。

### 10.4 配置文件安全
- 檢查敏感文件權限 (如 `.ovpn`, `.key`, `.env` 文件應為 `600`)。
- 定期執行權限檢查腳本 (管理員):
  ```bash
  #!/bin/bash
  echo "=== 敏感文件權限檢查 ==="
  find . -type f \( -name "*.key" -o -name "*.ovpn" -o -name "*.env" -o -name ".vpn_config" -o -name ".user_vpn_config" \) -print0 | \
  while IFS= read -r -d $'\0' file; do
      perms=$(stat -f "%Lp" "$file" 2>/dev/null || stat -c "%a" "$file")
      expected_perms="600"
      # 某些目錄下的 ovpn 可能是 644，但含私鑰的應為 600
      # 此處簡化為全部檢查 600，可根據實際情況調整
      if [ "$perms" = "$expected_perms" ]; then
          echo "✓ $file ($perms)"
      else
          echo "✗ $file ($perms, 應為 $expected_perms)"
      fi
  done
  ```

### 10.5 VPN 使用安全 (用戶)
- 僅在需要時連接 VPN。
- 完成工作後立即斷開。
- 不在公共 Wi-Fi 上處理高度敏感數據 (即使通過 VPN)。
- 嚴禁分享個人 VPN 配置文件或憑證。

### 10.6 事件響應
- **用戶**: 若懷疑配置文件洩露或電腦感染，立即通知 IT 管理員。
- **管理員**:
    - 準備好應急程序 (參見[緊急聯絡範本](#緊急聯絡範本))。
    - 發生安全事件時，立即使用 `revoke_member_access.sh` 撤銷相關人員權限。
    - 分析日誌，確定影響範圍。
    - 根據情況執行 `employee_offboarding.sh` 中的部分流程。

---

## 11. 故障排除

(整合 `readme.md` 的詳細內容和 `vpn_connection_manual.md` v2.0 的內容)

### 11.1 雙環境相關問題
(參考 `vpn_connection_manual.md` v2.0 已有的 "雙環境相關問題" 並擴充)
- **環境切換失敗**: 檢查 `vpn_env.sh` 及 `lib/env_manager.sh` 是否存在且有執行權限，`configs/[env]/[env].env` 文件是否正確。嘗試 `vpn_env.sh init`。
- **環境與設定檔不匹配**: 執行 `./vpn_env.sh status` 確認當前 shell 環境，對比 AWS VPN Client 中選擇的 Profile 名稱。
- **Production 環境確認失敗**: 確認碼為大寫 `PROD`，用戶名需匹配。

### 11.2 管理工具常見問題
- **模組載入錯誤 (`core_functions.sh not found`)**:
    - **原因**: `lib` 目錄或核心函式庫文件缺失或路徑不對。
    - **解決**: 確保執行腳本時位於專案根目錄，`lib` 目錄及內部 `.sh` 文件存在且有讀取權限。
- **AWS 權限錯誤 (`AccessDenied`)**:
    - **原因**: 執行腳本的 IAM 用戶/角色權限不足。
    - **解決**: 使用 `aws sts get-caller-identity` 檢查當前身份。對照[附錄 IAM 政策](#iam-權限政策範例)檢查並補齊所需權限。確認 AWS CLI 配置的區域正確。
- **證書生成失敗 (PKI 初始化失敗 / Easy-RSA 錯誤)**:
    - **原因**: `certificates/[environment]/pki` 目錄權限問題，或 Easy-RSA 工具問題。
    - **解決**: 確保 `certificates` 目錄可寫。可嘗試刪除 (備份後) `certificates/[environment]/pki` 並讓 `aws_vpn_admin.sh` 重新初始化 (如果它負責初始化)。確保 Easy-RSA 已正確安裝並在 PATH 中。
- **配置文件 `.vpn_config` 或 `[env].env` 損壞/缺失**:
    - **原因**: 文件被意外修改或刪除。
    - **解決**: 如果是 `.vpn_config` (記錄當前環境等)，可由 `vpn_env.sh switch` 自動重建。如果是 `configs/[env]/[env].env`，需從備份恢復或根據模板手動重建關鍵參數。

### 11.3 用戶端連接常見問題
(參考 `vpn_connection_manual.md` v2.0 已有的 "傳統 VPN 問題（更新版）" 及 "一般 VPN 連接問題")
- **無法導入環境專用配置檔案**: 檢查 `.ovpn` 文件是否完整，是否選對了 Staging/Production 對應的配置文件。
- **環境特定認證錯誤**: 檢查用戶證書 (`.crt`) 和私鑰 (`.key`) 是否匹配，證書是否過期。
- **DNS 解析問題 (環境感知版)**: `scutil --dns` 查看當前 DNS，`nslookup` 測試。

### 11.4 日誌文件分析
- **管理員日誌**:
    - `vpn_admin_[environment].log` (由 `aws_vpn_admin.sh` 等工具生成)
    - `revocation-logs/[environment]_revocation.log`
    - `offboarding-logs/offboarding_main.log`
- **用戶端日誌**:
    - `user_vpn_setup.log` (由 `team_member_setup.sh` 生成)
- **系統日誌 (macOS)**:
    - `Console.app` 中搜索 "AWS VPN Client" 或 "NEKit"。
    - 命令行: `log stream --level debug --predicate 'subsystem contains "com.apple.networkextension" or processImagePath contains "AWS VPN Client"'` (可能需要調整謂詞)
- **CloudWatch Logs**: AWS Client VPN 端點連接日誌。

---

## 12. AWS 資源和成本管理

### 12.1 創建的 AWS 資源

執行本工具套件（主要是 `aws_vpn_admin.sh`）會在 AWS 中創建和管理以下資源：

#### 核心資源 (每個環境獨立)
-   **AWS Client VPN Endpoint**:
    *   例如 `cvpn-endpoint-xxxxxxxxxxxxxxxxx`
    *   成本: 按小時收費的端點關聯費 + 每客戶端連接按小時收費。
-   **AWS Certificate Manager (ACM) 證書**:
    *   伺服器證書 (例如 `server-[environment]-cert`)。
    *   客戶端 CA 證書 (例如 `client-ca-[environment]-cert`)。
    *   (如果 `team_member_setup.sh` 上傳用戶證書) 個別用戶證書。
    *   ACM 提供的證書本身免費，但通過 Client VPN 使用它們產生上述端點費用。
-   **CloudWatch Log Group**:
    *   例如 `/aws/clientvpn/[VPN_Endpoint_Name]`。
    *   成本: 日誌存儲費用 + 日誌攝入費用。

#### 網路資源 (每個環境獨立)
-   **目標網路關聯**: VPN 端點與 VPC 子網路的關聯。
-   **授權規則**: 定義哪些客戶端 CIDR 可以訪問哪些目標網路。
-   **路由規則**: 定義流量如何通過 VPN 路由。

### 12.2 成本優化建議

1.  **按需使用**:
    *   僅在需要時保持 VPN 端點的網路關聯。若某環境長期不用，可考慮取消關聯或刪除端點 (注意數據備份)。
    *   教育用戶在使用完畢後立即斷開 VPN 連接，以減少客戶端連接小時數。
2.  **監控活躍連接**:
    ```bash
    # 針對特定環境的端點 ID
    aws ec2 describe-client-vpn-connections \
        --client-vpn-endpoint-id cvpn-endpoint-xxxxxxxxxxxxxxxxx \
        --query 'Connections[?Status.Code==`active`]' \
        --output table
    ```
3.  **日誌保留策略**:
    *   為 CloudWatch Log Group 設置合理的日誌保留期限 (例如 30-90 天)，避免無限期存儲產生過高費用。
    ```bash
    aws logs put-retention-policy \
        --log-group-name "/aws/clientvpn/[VPN_Endpoint_Name]" \
        --retention-in-days 30 # 自定義天數
    ```
4.  **選擇合適區域**: 不同 AWS 區域的定價可能有細微差別。
5.  **分割通道 (Split-Tunneling)**:
    *   啟用分割通道可以讓非目標網路的流量 (例如訪問公開網站) 不經過 VPN，減少 VPN 負載和潛在的數據傳輸成本。腳本默認應啟用此功能。

---

## 13. 完整移除指南 (管理員)

本指南描述如何徹底移除由本工具套件創建的 AWS 資源和本地文件。**操作具有破壞性，請謹慎執行並提前備份重要數據。**

### 13.1 停止所有服務

1.  **通知用戶**: 提前通知所有用戶將要停用 VPN 服務。
2.  **斷開所有 VPN 連接**:
    *   指導用戶手動斷開。
    *   管理員可從 AWS Console 或使用 AWS CLI 強制終止活躍連接：
    ```bash
    # 針對 Staging 環境 (示例，替換為實際端點ID)
    STAGING_ENDPOINT_ID=$(grep VPN_ENDPOINT_ID configs/staging/staging.env | cut -d'=' -f2)
    aws ec2 describe-client-vpn-connections --client-vpn-endpoint-id $STAGING_ENDPOINT_ID --query "Connections[*].ConnectionId" --output text | \
    xargs -I {} aws ec2 terminate-client-vpn-connections --client-vpn-endpoint-id $STAGING_ENDPOINT_ID --connection-id {}

    # 針對 Production 環境 (示例)
    PROD_ENDPOINT_ID=$(grep VPN_ENDPOINT_ID configs/production/production.env | cut -d'=' -f2)
    # ... 重復上述命令
    ```

### 13.2 使用工具清理 AWS 資源

推薦使用 `aws_vpn_admin.sh` 腳本（如果其 "刪除 VPN 端點" 功能完善）來清理對應環境的 AWS 資源，因為它了解所創建資源的關聯性。

```bash
# 清理 Staging 環境
./vpn_env.sh switch staging
./admin-tools/aws_vpn_admin.sh
# 選擇選項 4: 刪除 VPN 端點 (仔細確認提示)

# 清理 Production 環境
./vpn_env.sh switch production
./admin-tools/aws_vpn_admin.sh
# 選擇選項 4: 刪除 VPN 端點 (仔細確認提示)
```

**如果手動清理，主要步驟包括 (每個環境都要做):**
1.  **刪除 Client VPN Endpoint**:
    ```bash
    aws ec2 delete-client-vpn-endpoint --client-vpn-endpoint-id cvpn-endpoint-xxxxxxxxxxxxxxxxx
    ```
2.  **刪除 ACM 中的證書**:
    *   伺服器證書 ARN (從 `[env].env` 文件獲取 `SERVER_CERT_ARN`)
    *   客戶端 CA 證書 ARN (從 `[env].env` 文件獲取 `CLIENT_CERT_ARN`)
    *   (如果適用) 用戶證書
    ```bash
    aws acm delete-certificate --certificate-arn arn:aws:acm:region:account:certificate/xxxxxx
    ```
3.  **刪除 CloudWatch Log Group**:
    ```bash
    aws logs delete-log-group --log-group-name "/aws/clientvpn/[VPN_Endpoint_Name]"
    ```
4.  **檢查並清理相關 IAM 角色/政策** (如果創建了專用角色)。
5.  **檢查並清理相關安全組** (如果創建了專用安全組)。

### 13.3 清理本地文件

```bash
# 備份重要文件後執行！
# 刪除配置文件目錄
rm -rf configs/
# 刪除證書目錄
rm -rf certificates/
# 刪除團隊配置緩存目錄
rm -rf team-configs/
# 刪除日誌目錄
rm -rf logs/
rm -rf revocation-logs/
rm -rf offboarding-logs/
# 刪除主要腳本產生的狀態/日誌文件
rm -f .vpn_config vpn_admin_*.log user_vpn_setup.log .user_vpn_config
# （可選）刪除函式庫和腳本本身
# rm -rf lib/
# rm -f *.sh readme.md vpn_connection_manual.md
```

### 13.4 移除應用程式 (用戶端)
- **移除 AWS VPN Client**:
  ```bash
  sudo rm -rf "/Applications/AWS VPN Client.app"
  # 清理相關用戶配置 (如果存在)
  rm -rf ~/Library/Application\ Support/AWS\ VPN\ Client/
  rm -rf ~/Library/Preferences/com.amazon.awsvpnclient.plist
  ```
- **可選：移除 Homebrew 安裝的工具** (如果管理員機器不再需要):
  ```bash
  brew uninstall awscli jq easy-rsa openssl # 根據實際安裝情況
  ```

---

## 14. 附錄

### 14.1 常用 AWS CLI 命令
(這些命令在腳本內部被廣泛使用，管理員手動排錯時也可能用到)
```bash
# VPN 端點管理
aws ec2 describe-client-vpn-endpoints
aws ec2 create-client-vpn-endpoint --client-ipv4-cidr <value> --server-certificate-arn <value> --authentication-options Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn=<value>} --connection-log-options Enabled=true,CloudwatchLogGroup=<value> --dns-servers <value> <value> --transport-protocol udp --split-tunnel --tag-specifications 'ResourceType=client-vpn-endpoint,Tags=[{Key=Name,Value=<YourVPNName>}]'
aws ec2 delete-client-vpn-endpoint --client-vpn-endpoint-id <value>
aws ec2 modify-client-vpn-endpoint --client-vpn-endpoint-id <value> --server-certificate-arn <value>

# 網路關聯
aws ec2 associate-client-vpn-target-network --client-vpn-endpoint-id <value> --subnet-id <value>
aws ec2 disassociate-client-vpn-target-network --client-vpn-endpoint-id <value> --association-id <value>
aws ec2 describe-client-vpn-target-networks --client-vpn-endpoint-id <value>

# 授權管理
aws ec2 authorize-client-vpn-ingress --client-vpn-endpoint-id <value> --target-network-cidr <value> --authorize-all-groups | --access-group-id <value>
aws ec2 revoke-client-vpn-ingress --client-vpn-endpoint-id <value> --target-network-cidr <value> --revoke-all-groups | --access-group-id <value>
aws ec2 describe-client-vpn-authorization-rules --client-vpn-endpoint-id <value>

# 路由管理
aws ec2 create-client-vpn-route --client-vpn-endpoint-id <value> --destination-cidr-block <value> --target-subnet-id <value>
aws ec2 delete-client-vpn-route --client-vpn-endpoint-id <value> --destination-cidr-block <value> --target-subnet-id <value>
aws ec2 describe-client-vpn-routes --client-vpn-endpoint-id <value>

# 連接管理
aws ec2 describe-client-vpn-connections --client-vpn-endpoint-id <value>
aws ec2 terminate-client-vpn-connections --client-vpn-endpoint-id <value> --connection-id <value>

# 證書管理 (ACM)
aws acm list-certificates --certificate-statuses ISSUED
aws acm import-certificate --certificate fileb://path/to/cert.pem --private-key fileb://path/to/key.pem --certificate-chain fileb://path/to/chain.pem --tags Key=Name,Value=YourCertName
aws acm delete-certificate --certificate-arn <value>
aws acm describe-certificate --certificate-arn <value>
```

### 14.2 配置文件範例 (`.vpn_config`)
此文件由 `vpn_env.sh` 管理，存儲當前激活的環境。
```bash
# .vpn_config 示例
CURRENT_ENV_NAME="staging"
CURRENT_ENV_FILE="/path/to/your/project/configs/staging/staging.env"
```

**`configs/[environment]/[environment].env` 範例結構:**
```bash
# configs/staging/staging.env 示例
# AWS Configuration
AWS_REGION="ap-northeast-1"
AWS_PROFILE="default" # Optional: specify AWS CLI profile

# VPN Endpoint Configuration
VPN_NAME_PREFIX="StagingVPN"
VPN_CLIENT_CIDR="172.16.0.0/22" # Client IPv4 CIDR
SERVER_CERT_ARN="" # To be filled by script
CLIENT_CERT_ARN="" # To be filled by script
DNS_SERVERS="8.8.8.8 8.8.4.4" # Or internal DNS servers
TRANSPORT_PROTOCOL="udp" # udp or tcp
SPLIT_TUNNEL="true" # true or false
CONNECTION_LOG_GROUP_PREFIX="/aws/clientvpn" # CloudWatch Log Group name prefix

# Target Network (Primary VPC and Subnet)
TARGET_VPC_ID="vpc-xxxxxxxxxxxxxxxxx" # Primary VPC for this VPN
TARGET_SUBNET_IDS="subnet-xxxxxxxxxxxxxxxxx,subnet-yyyyyyyyyyyyyyyyy" # Comma-separated list of subnet IDs for association

# Authorization Rules (CIDRs to allow access to)
AUTHORIZATION_TARGET_CIDRS="10.10.0.0/16,0.0.0.0/0" # Example: VPC CIDR and all internet

# Easy-RSA Configuration (used by cert_management.sh)
EASYRSA_DIR="/usr/local/opt/easy-rsa/share/easy-rsa" # Path to easy-rsa scripts, adjust if different
CERT_ROOT_DIR="./certificates/staging" # Output for generated certs, relative to project root
PKI_DIR="${CERT_ROOT_DIR}/pki"
CA_CERT_FILENAME="ca.crt"
SERVER_CERT_FILENAME_PREFIX="server"
CLIENT_CERT_FILENAME_PREFIX="client" # For generic client certs, user certs are separate
CERT_VALIDITY_DAYS_CA=3650 # 10 years for CA
CERT_VALIDITY_DAYS_SERVER=365 # 1 year for server
CERT_VALIDITY_DAYS_CLIENT=180 # 6 months for client

# Tags for AWS resources
TAG_ENV="Staging"
TAG_PROJECT="ClientVPNManagement"

# VPN Endpoint ID (filled after creation)
VPN_ENDPOINT_ID=""
```

### 14.3 IAM 權限政策範例

#### 管理員權限 (`aws_vpn_admin.sh`, `revoke_member_access.sh`, `employee_offboarding.sh`)
此為較寬鬆範例，請根據最小權限原則調整。
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateClientVpnEndpoint",
                "ec2:ModifyClientVpnEndpoint",
                "ec2:DeleteClientVpnEndpoint",
                "ec2:DescribeClientVpnEndpoints",
                "ec2:AssociateClientVpnTargetNetwork",
                "ec2:DisassociateClientVpnTargetNetwork",
                "ec2:DescribeClientVpnTargetNetworks",
                "ec2:AuthorizeClientVpnIngress",
                "ec2:RevokeClientVpnIngress",
                "ec2:DescribeClientVpnAuthorizationRules",
                "ec2:CreateClientVpnRoute",
                "ec2:DeleteClientVpnRoute",
                "ec2:DescribeClientVpnRoutes",
                "ec2:DescribeClientVpnConnections",
                "ec2:TerminateClientVpnConnections",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:CreateTags",
                "ec2:DeleteTags",
                "acm:ImportCertificate",
                "acm:DeleteCertificate",
                "acm:DescribeCertificate",
                "acm:ListCertificates",
                "acm:AddTagsToCertificate",
                "logs:CreateLogGroup",
                "logs:DeleteLogGroup",
                "logs:DescribeLogGroups",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "iam:GetUser", // For employee_offboarding.sh
                "iam:ListUserPolicies", // For employee_offboarding.sh
                "iam:ListAttachedUserPolicies", // For employee_offboarding.sh
                "iam:DeleteUser", // For employee_offboarding.sh (use with extreme caution)
                "iam:DetachUserPolicy", // For employee_offboarding.sh
                "iam:DeleteLoginProfile", // For employee_offboarding.sh
                "sts:GetCallerIdentity"
            ],
            "Resource": "*" // For production, scope down resources where possible
        }
    ]
}
```

#### 團隊成員設置權限 (`team_member_setup.sh` 用戶端執行時)
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeClientVpnEndpoints", // To get endpoint details for config
                "acm:ImportCertificate",          // To upload their own client certificate
                "acm:AddTagsToCertificate"        // To tag their certificate
            ],
            "Resource": "*" // Scope down if possible, e.g., specific VPN endpoint ARN for describe
                           // For acm:ImportCertificate, it's harder to scope down without pre-creating placeholders
        },
        {
            "Effect": "Allow",
            "Action": "sts:GetCallerIdentity",
            "Resource": "*"
        }
    ]
}
```

### 14.4 緊急聯絡範本
(此為管理員內部使用範本，或提供給關鍵用戶)
```text
=== VPN 緊急事件處理指引 ===

事件類型： (例如：VPN 連接完全中斷 / 安全漏洞疑似 / 關鍵用戶無法連接)
報告時間： YYYY-MM-DD HH:MM
報告人：

受影響環境： [ ] Staging [ ] Production [ ] Both

現象描述：
...

已嘗試的初步排除步驟：
1. ./vpn_env.sh status
2. ./vpn_env.sh health [environment]
3. ...

AWS 資源信息 (若已知)：
Staging VPN 端點 ID: cvpn-xxxxxxxx (從 configs/staging/staging.env 獲取)
Production VPN 端點 ID: cvpn-yyyyyyyy (從 configs/production/production.env 獲取)
相關 CloudWatch Log Group: /aws/clientvpn/[VPN_Name]

緊急聯絡人：
1. 主要 VPN 管理員: [姓名], [電話], [Email]
2. 備用 VPN 管理員: [姓名], [電話], [Email]
3. IT 安全部門: [聯繫方式]

處理記錄：
(時間 - 操作 - 結果)
...
```

---

## 15. 常見問題 FAQ

(此部分內容與 `vpn_connection_manual.md` v2.0 版本一致，可根據新功能酌情增補)
- Q1：什麼時候應該使用 Staging 環境？什麼時候使用 Production 環境？
- Q2：我可以同時連接兩個環境嗎？ (A: 強烈不建議)
- Q3：如何確認我當前連接的是哪個環境？ (A: `./vpn_env.sh status`, Client Profile Name)
- Q4：我在切換環境時被要求輸入確認碼，這是什麼？ (A: Production 環境保護機制)
- ...

---

## 16. 緊急聯絡資訊

(此部分內容與 `vpn_connection_manual.md` v2.0 版本一致，確保資訊最新)

### 🚨 緊急情況聯絡方式
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

---

**祝您使用順利！** 🎉
