# AWS Client VPN 雙環境管理工具套件概述

<!-- markdownlint-disable MD051 -->

## 目錄

1. [概述](#概述)
2. [雙環境架構](#雙環境架構)
3. [環境管理簡介](#環境管理簡介)
4. [系統要求](#系統要求)
5. [工具介紹](#工具介紹)
6. [診斷和修復工具](#診斷和修復工具)
7. [安全最佳實踐](#安全最佳實踐)
8. [詳細文檔](#詳細文檔)

---

## 概述

AWS Client VPN 雙環境管理工具套件是一個專為 macOS 設計的企業級模組化自動化解決方案，核心目標是高效管理 AWS Client VPN 連接以及團隊成員在 **Staging** 和 **Production** 兩種獨立環境中的訪問權限。本套件採用函式庫架構設計，強調環境隔離、安全管理及操作便捷性，旨在為企業提供一個可靠且易於擴展的 VPN 管理框架。

透過雙環境設計，企業能夠在 Staging 環境中安全地進行測試、開發和配置驗證，而 Production 環境則保持穩定運行，服務於正式的業務需求。這種分離確保了生產系統的穩定性，同時為新功能和變更提供了安全的測試平台。

**主要優勢:**
- **環境隔離:** Staging 和 Production 環境完全分離，降低風險。
- **安全強化:** Production 環境操作具備增強的安全確認機制。
- **高效管理:** 提供自動化工具簡化 VPN 端點、用戶權限和證書的管理。
- **模組化設計:** 函式庫易於維護、擴展和客製化。

---

## 雙環境架構

### 🏗️ 環境結構概覽

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
```bash

### 🎯 環境特性

#### Staging 環境 🟡

- **用途**: 主要用於開發、功能測試、配置實驗和模擬。允許開發和 QA 團隊在一個安全的沙箱環境中工作，而不影響生產系統。
- **安全級別**: 標準安全措施，操作確認流程相對簡化。
- **適用對象**: 開發團隊、QA 團隊、需要進行 VPN 配置測試的工程師。

#### Production 環境 🔴

- **用途**: 用於支持實際業務運營的正式生產環境。所有配置和操作都應謹慎處理，以確保服務的穩定性和安全性。
- **安全級別**: 最高安全級別，所有關鍵操作均需要多重確認和嚴格的權限驗證。
- **適用對象**: 運維團隊、負責生產系統維護的資深工程師、以及需要訪問生產資源的授權用戶。

### 🔄 環境切換機制概述

工具套件提供便捷的命令列工具（如 `vpn_env.sh`）來查看當前環境狀態和在不同環境間切換。切換到 Production 環境時，系統會要求額外確認，以防止誤操作。詳細的切換指令和操作指南請參閱 `vpn_connection_manual.md`。

---

## 環境管理簡介

本工具套件提供 `vpn_env.sh` 作為環境管理的主要入口點。它允許用戶進行核心的環境操作，如：

- **查看當前環境狀態**：顯示目前啟用的環境 (Staging 或 Production) 及其基本健康狀況。
- **切換環境**：允許用戶在 Staging 和 Production 環境之間進行切換。切換至 Production 環境時會有額外的安全確認步驟。
- **環境健康檢查**：提供對各個環境健康狀況的快速檢查。

詳細的環境管理操作、指令範例及 `enhanced_env_selector.sh`（增強環境選擇器）的使用方法，請參閱 `vpn_connection_manual.md`。

---

## 系統要求

### 硬體要求

- macOS 10.15+ (Catalina 或更新版本)
- 至少 4GB RAM
- 2GB 可用磁碟空間
- 穩定的網路連接

### 軟體依賴

本套件在首次運行時會嘗試自動安裝必要的依賴工具，包括：

- **Homebrew** - macOS 套件管理器
- **AWS CLI** - AWS 命令列工具
- **jq** - JSON 處理工具
- **Easy-RSA** - 證書管理工具
- **OpenSSL** - 加密工具

### AWS 權限要求

運行本工具套件中的不同腳本需要特定的 AWS IAM 權限。管理員、團隊成員以及執行特殊操作（如員工離職處理）所需的權限各不相同。

- **管理員權限**: 需要管理 Client VPN 端點、ACM 證書、日誌、VPC 和子網路等資源的權限。
- **團隊成員權限**: 需要描述 VPN 端點、導出客戶端配置、以及管理個人 ACM 證書的權限。
- **高權限操作**: 某些特定工具（如 `employee_offboarding.sh`）可能需要更廣泛的權限，例如 IAM 管理、S3 存取等。

詳細的 IAM 權限 JSON 政策範本，請參閱 `vpn_connection_manual.md` 中的初始設置或附錄章節。

---

## 工具介紹

本套件包含一系列腳本工具，以支持雙環境 VPN 的管理：

### 🌟 主要管理工具

1.  **`vpn_env.sh`** - 環境管理入口工具。用於切換和查看 Staging/Production 環境狀態，以及執行環境健康檢查。
2.  **`enhanced_env_selector.sh`** - 增強型互動式環境選擇器。提供一個控制台界面，方便用戶進行環境切換、狀態查看和比較等操作。
3.  **`admin-tools/aws_vpn_admin.sh`** - 管理員主控台。核心管理工具，用於創建、查看、管理和刪除 VPN 端點，以及管理團隊設定等。此工具會根據當前選定的環境（Staging/Production）執行操作。
4.  **`team_member_setup.sh`** - 團隊成員設置工具。引導團隊成員完成 VPN 客戶端的配置，包括生成個人證書和 VPN 設定檔。**自動配置進階 DNS 分流和 AWS 服務路由功能**。
5.  **`admin-tools/revoke_member_access.sh`** - 權限撤銷工具。用於安全地撤銷特定用戶的 VPN 訪問權限，包括註銷其證書和斷開現有連接。
6.  **`admin-tools/employee_offboarding.sh`** - 員工離職處理系統。提供一個標準化流程，用於處理員工離職時的 VPN 訪問權限移除及相關安全審計。

### 🔧 診斷和修復工具 (admin-tools/tools/)

7.  **`fix_endpoint_id.sh`** - 自動修復 VPN 端點 ID 配置不匹配問題。自動檢測 AWS 認證狀態、列出可用端點並提供互動式選擇界面。
8.  **`simple_endpoint_fix.sh`** - 簡化的診斷工具。提供詳細的手動修復指導步驟和常見診斷命令。
9.  **`debug_vpn_creation.sh`** - VPN 端點創建診斷工具。全面診斷 VPN 端點創建問題，檢查 AWS 配置、網路資源、證書狀態和 JSON 格式。
10. **`fix_vpn_config.sh`** - VPN 配置修復工具。自動修復常見配置問題，包括子網配置、證書替換和資源衝突清理。
11. **`complete_vpn_setup.sh`** - 完整 VPN 設置工具。從 "pending-associate" 狀態繼續完成 VPN 端點設置流程。
12. **`validate_config.sh`** - 配置驗證工具。驗證所有環境的配置正確性並自動修復簡單的配置問題。
13. **`verify_config_update_fix.sh`** - 配置更新修復驗證工具。驗證配置文件更新修復是否正確工作。

### 📚 核心庫文件 (lib/)

本套件採用模組化設計，核心功能由以下庫文件提供：

- **`core_functions.sh`** - 核心工具函式庫（顏色設定、日誌記錄、驗證函式）
- **`env_manager.sh`** - 環境管理核心功能（雙環境支援）
- **`aws_setup.sh`** - AWS 配置管理庫
- **`cert_management.sh`** - 證書管理庫（Easy-RSA 初始化、證書生成、ACM 匯入）
- **`endpoint_creation.sh`** - VPN 端點創建庫
- **`endpoint_management.sh`** - VPN 端點管理庫（端點列表、配置生成、團隊設定）
- **`enhanced_confirmation.sh`** - 增強版操作確認機制

每個工具的詳細使用方法、參數說明和操作流程，請參閱 `vpn_connection_manual.md`。

### 完整工具清單

總共包含 **13個主要腳本** 和 **7個核心庫文件**，提供從環境管理、VPN 端點創建、團隊管理到故障診斷的完整解決方案。所有工具都支援雙環境（Staging/Production）架構，並提供自動備份和錯誤恢復功能。

詳細的診斷和修復工具說明請參考: [`admin-tools/tools/README.md`](admin-tools/tools/README.md)

---

## 🌐 進階 VPN 配置功能

### DNS 分流與 AWS 服務整合

`team_member_setup.sh` 工具在生成個人 VPN 配置文件時，會自動配置進階的 DNS 分流和路由功能，確保無縫存取 AWS 服務和內部資源。

#### 🔍 自動配置的 DNS 功能

**智慧 DNS 分流設定:**
```bash
dhcp-option DNS-priority 1                    # 設定 VPN DNS 優先級
dhcp-option DOMAIN internal                   # 內部網域解析
dhcp-option DOMAIN us-east-1.compute.internal # EC2 區域特定域名
dhcp-option DOMAIN ec2.internal               # EC2 內部域名
dhcp-option DOMAIN us-east-1.elb.amazonaws.com # ELB 服務域名
dhcp-option DOMAIN us-east-1.rds.amazonaws.com # RDS 服務域名  
dhcp-option DOMAIN us-east-1.s3.amazonaws.com  # S3 服務域名
dhcp-option DOMAIN *.amazonaws.com             # 所有 AWS 服務域名
```

#### 🛣️ 進階路由配置

**AWS 核心服務路由:**
```bash
route 169.254.169.254 255.255.255.255  # EC2 Metadata Service (IMDS)
route 169.254.169.253 255.255.255.255  # VPC DNS Resolver
```

#### ✨ 主要優勢和功能

**🔧 開發環境整合:**
- **EC2 實例發現**: 可以透過私有 DNS 名稱存取 EC2 實例
- **服務發現**: 支援 ECS、EKS 等容器化服務的內部發現機制
- **Metadata 存取**: 應用程式可以正常存取 EC2 metadata 和 IAM 角色憑證

**🚀 效能最佳化:**
- **內部網路路由**: AWS 服務間通訊使用內部網路，減少延遲
- **頻寬節省**: 只有 AWS 相關流量走 VPN，其他網路流量保持本地路由
- **DNS 快取**: 利用 VPC DNS 解析器的快取機制

**🔒 安全性增強:**
- **網路隔離**: 確保敏感的內部服務只能透過 VPN 存取
- **流量分流**: 避免所有流量都經過 VPN，減少安全風險
- **存取控制**: 配合 AWS 安全群組和 NACL 實現精細的存取控制

#### 🎯 實際應用場景

1. **本地開發環境**: 開發者可以直接連接到 VPC 內的 RDS、ElastiCache 等服務
2. **除錯和測試**: 可以存取內部 Load Balancer 和私有子網路的服務
3. **管理操作**: 透過私有 IP 直接管理 EC2 實例，無需跳板機
4. **應用程式整合**: 本地運行的應用程式可以無縫整合 AWS 服務

#### ⚙️ 技術實現細節

- **區域感知**: 自動根據 AWS 設定檔的區域配置對應的服務域名
- **動態配置**: 根據目標環境（Staging/Production）自動調整路由規則  
- **相容性**: 支援 macOS、Linux 和 Windows 的 OpenVPN 客戶端
- **故障排除**: 包含詳細的連線測試和診斷指令

---

## 快速使用指南

### 常用操作流程

#### 🚀 初始環境設置
```bash
# 查看當前環境狀態
./vpn_env.sh status

# 切換到 staging 環境進行測試
./vpn_env.sh switch staging

# 啟動互動式環境選擇器
./vpn_env.sh selector
```

#### 🔧 VPN 管理操作
```bash
# 啟動管理員控制台
./admin-tools/aws_vpn_admin.sh

# 設置團隊成員 VPN 訪問
./team_member_setup.sh

# 撤銷用戶訪問權限
./admin-tools/revoke_member_access.sh
```

#### 🔍 故障診斷與修復
```bash
# 快速診斷端點 ID 問題
./admin-tools/tools/simple_endpoint_fix.sh

# 自動修復端點 ID 配置
./admin-tools/tools/fix_endpoint_id.sh

# 診斷 VPN 創建問題
./admin-tools/tools/debug_vpn_creation.sh

# 驗證配置正確性
./admin-tools/tools/validate_config.sh
```

---

## 安全最佳實踐

管理雙環境 AWS Client VPN 時，應遵循以下安全最佳實踐，以保護您的基礎設施和數據：

1.  **最小權限原則 (Principle of Least Privilege)**:
    *   為管理員和用戶分配僅執行其任務所必需的最小 IAM 權限。
    *   定期審查和更新 IAM 政策，移除不再需要的權限。
    *   針對 Staging 和 Production 環境使用不同的 IAM 角色或政策，以實現更細緻的權限控制。

2.  **證書安全管理**:
    *   安全地存儲和處理 CA 證書及私鑰，尤其是 Production 環境的證書。
    *   實施證書輪換策略，定期更新伺服器和客戶端證書。
    *   使用強密碼保護私鑰，並限制對私鑰的訪問。

3.  **強身份驗證**:
    *   考慮為 AWS Client VPN 啟用多因素認證 (MFA) 以增強安全性。
    *   確保團隊成員使用強大且唯一的密碼來保護其本地系統和 VPN 憑證。

4.  **環境隔離與確認**:
    *   嚴格分離 Staging 和 Production 環境的配置、證書和日誌。
    *   在對 Production 環境進行任何更改之前，務必進行多重確認，並尽可能先在 Staging 環境中測試。

5.  **監控與審計**:
    *   啟用並定期審查 AWS CloudTrail 日誌和 VPN 連接日誌。
    *   針對可疑活動或安全事件設置 CloudWatch 警報。
    *   記錄所有管理操作，特別是針對 Production 環境的操作。

6.  **配置文件安全**:
    *   保護本地存儲的 `.ovpn` 配置文件和任何包含敏感信息的腳本配置。
    *   確保敏感文件具有嚴格的文件權限 (例如 `chmod 600`)。

7.  **定期安全審查**:
    *   定期對 VPN 設置、IAM 權限、安全組規則和網路配置進行安全審查。
    *   及時更新和修補 VPN 客戶端軟件及相關依賴項。

詳細的安全配置指南和操作步驟，請參閱 `vpn_connection_manual.md`。

---

## 詳細文檔

本 `readme.md` 文件提供了 AWS Client VPN 雙環境管理工具套件的高級概述。

有關**初始設置、詳細的工具使用指南、具體的操作步驟、環境管理詳情、故障排除、維護流程、AWS 資源管理、移除指南以及附錄內容（如完整的 IAM 政策範例和配置文件結構）**，請參閱配套的完整使用說明書：

📄 `vpn_connection_manual.md`

此說明書將為您提供成功部署、管理和維護雙環境 VPN 解決方案所需的所有詳細信息。

---

**最後更新：** 2025年5月25日
**文檔版本：** 2.2 (已同步所有腳本功能)
**適用工具版本：** 2.0
**架構：** 模組化函式庫設計
