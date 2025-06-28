# AWS Client VPN 雙環境管理工具套件概述

<!-- markdownlint-disable MD051 -->

## 目錄

1. [概述](#概述)
2. [雙環境架構](#雙環境架構)
3. [系統要求](#系統要求)
4. [工具介紹](#工具介紹)
5. [🌐 進階 VPN 配置功能](#🌐-進階-vpn-配置功能)
6. [🛡️ AWS Client VPN 安全群組最佳實踐](#🛡️-aws-client-vpn-安全群組最佳實踐)
7. [🔐 安全 CSR 工作流程](#🔐-安全-csr-工作流程)
8. [快速使用指南](#快速使用指南)
9. [🚀 首次部署建議流程](#🚀-首次部署建議流程)
10. [🤖 自動化部署指南](#🤖-自動化部署指南)
11. [🔄 VPN Endpoint 重新建立流程](#🔄-vpn-endpoint-重新建立流程)
12. [💰 成本試算與注意事項](#💰-成本試算與注意事項)
13. [詳細文檔](#詳細文檔)

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
├── staging/                    # 🟡 Staging 環境配置
│   ├── staging.env            # 主配置文件（基本/靜態配置）
│   └── vpn_endpoint.conf      # 端點專用配置（證書/動態配置）
├── prod/                      # 🔴 Production 環境配置  
│   ├── prod.env              # 主配置文件（基本/靜態配置）
│   └── vpn_endpoint.conf     # 端點專用配置（證書/動態配置）
└── template.env.example       # 配置模板

certs/
├── staging/                   # Staging 環境證書
└── production/                # Production 環境證書

logs/
├── staging/                   # Staging 環境日誌
└── production/                # Production 環境日誌
```

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

工具套件提供便捷的命令列工具（如 `admin-tools/vpn_env.sh`）來查看當前環境狀態和在不同環境間切換。切換到 Production 環境時，系統會要求額外確認，以防止誤操作。詳細的切換指令和操作指南請參閱 `vpn_connection_manual.md`。

---

## 環境管理簡介

本工具套件提供 `admin-tools/vpn_env.sh` 作為環境管理的主要入口點。它允許用戶進行核心的環境操作，如：

- **查看當前環境狀態**：顯示目前啟用的環境 (Staging 或 Production) 及其基本健康狀況。
- **切換環境**：允許用戶在 Staging 和 Production 環境之間進行切換。切換至 Production 環境時會有額外的安全確認步驟。
- **環境健康檢查**：提供對各個環境健康狀況的快速檢查。

### 🔗 AWS Profile 與環境設定關聯

本工具套件透過環境設置檔自動管理 AWS Profile 設定，確保在正確的 AWS 帳戶中執行操作：

#### 設置檔結構
```bash
configs/staging/staging.env       # Staging 環境設定
configs/production/production.env # Production 環境設定
```

#### AWS Profile 設定
環境設置檔中的 `AWS_PROFILE` 變數決定該環境使用的 AWS 認證：
```bash
# configs/staging/staging.env
AWS_PROFILE=staging-vpn-admin
AWS_REGION=ap-northeast-1

# configs/production/production.env
AWS_PROFILE=production-vpn-admin
AWS_REGION=ap-northeast-1
```

#### 優先順序機制
當執行 VPN 管理操作時，系統依照以下順序確定 AWS Profile：
1. **環境設置檔中的 `ENV_AWS_PROFILE`** - 環境特定覆寫設定
2. **環境設置檔中的 `AWS_PROFILE`** - 標準設定 ⭐ **建議使用**
3. **系統預設對應** - staging → `default`, production → `production`
4. **AWS CLI 預設 profile** - 系統回退選項

#### 驗證工具
使用內建驗證腳本檢查設定正確性：
```bash
# 驗證 AWS Profile 與環境設定關聯
./validate_aws_profile_config.sh
```

詳細的環境管理操作、指令範例及 `enhanced_env_selector.sh`（增強環境選擇器）的使用方法，請參閱 `vpn_connection_manual.md` 和 `AWS_PROFILE_配置關聯說明.md`。

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

1.  **`admin-tools/vpn_env.sh`** - 環境管理入口工具。用於切換和查看 Staging/Production 環境狀態，以及執行環境健康檢查。
2.  **`enhanced_env_selector.sh`** - 增強型互動式環境選擇器。提供一個控制台界面，方便用戶進行環境切換、狀態查看和比較等操作。
3.  **`admin-tools/aws_vpn_admin.sh`** - 管理員主控台。核心管理工具，用於創建、查看、管理和刪除 VPN 端點，以及管理團隊設定等。此工具會根據當前選定的環境（Staging/Production）執行操作。
4.  **`team_member_setup.sh`** - 團隊成員設置工具。引導團隊成員完成 VPN 客戶端的配置，使用**安全的 CSR 工作流程**生成證書請求並等待管理員簽署。**自動配置進階 DNS 分流和 AWS 服務路由功能**。
5.  **`admin-tools/revoke_member_access.sh`** - 權限撤銷工具。用於安全地撤銷特定用戶的 VPN 訪問權限，包括註銷其證書和斷開現有連接。
6.  **`admin-tools/employee_offboarding.sh`** - 員工離職處理系統。提供一個標準化流程，用於處理員工離職時的 VPN 訪問權限移除及相關安全審計。

### 🔧 CSR 管理工具 (admin-tools/)

7.  **`sign_csr.sh`** - CSR 簽署工具。管理員專用，用於安全地簽署團隊成員的證書請求，保持 CA 私鑰隔離。
8.  **`setup_csr_s3_bucket.sh`** - S3 CSR 交換桶設置工具。創建和配置用於安全 CSR 交換的 S3 存儲桶，包括 IAM 政策生成。
9.  **`process_csr_batch.sh`** - CSR 批次處理工具。支援批次下載、簽署和上傳 CSR，以及監控模式自動處理。
10. **`run-vpn-analysis.sh`** - 多合一 VPN 分析工具。提供環境感知的全面 VPN 配置分析、連通性測試和詳細報告生成。

### 🔧 診斷和修復工具 (admin-tools/tools/)

10.  **`fix_endpoint_id.sh`** - 自動修復 VPN 端點 ID 配置不匹配問題。自動檢測 AWS 認證狀態、列出可用端點並提供互動式選擇界面。
11. **`simple_endpoint_fix.sh`** - 簡化的診斷工具。提供詳細的手動修復指導步驟和常見診斷命令。
12. **`debug_vpn_creation.sh`** - VPN 端點創建診斷工具。全面診斷 VPN 端點創建問題，檢查 AWS 配置、網路資源、證書狀態和 JSON 格式。
13. **`fix_vpn_config.sh`** - VPN 配置修復工具。自動修復常見配置問題，包括子網配置、證書替換和資源衝突清理。
14. **`complete_vpn_setup.sh`** - 完整 VPN 設置工具。從 "pending-associate" 狀態繼續完成 VPN 端點設置流程。
15. **`validate_config.sh`** - 配置驗證工具。驗證所有環境的配置正確性並自動修復簡單的配置問題。
16. **`verify_config_update_fix.sh`** - 配置更新修復驗證工具。驗證配置文件更新修復是否正確工作。
17. **`fix_internet_access.sh`** - VPN 網際網路存取修復工具。為現有 VPN 端點新增缺少的網際網路路由 (0.0.0.0/0)，解決無法存取網際網路的問題。

### 📚 核心庫文件 (lib/)

### 📊 VPN 分析和報告工具

**`run-vpn-analysis.sh`** 是一個環境感知的多合一 VPN 分析工具，提供全面的配置分析、連通性測試和詳細報告生成功能。

#### 🎯 主要功能

1. **環境感知分析**: 自動檢測並分析 Staging 或 Production 環境的 VPN 配置
2. **全面連通性測試**: 驗證 VPN 端點對各種 AWS 服務的存取權限
3. **智能報告生成**: 生成 Markdown 和 JSON 格式的詳細分析報告
4. **先決條件檢查**: 自動驗證運行環境和 AWS 認證設置
5. **服務覆蓋分析**: 深度分析 RDS、Redis、HBase、EKS 等服務的存取狀況

#### 🚀 使用方法

```bash
# 分析 staging 環境（預設）
./admin-tools/run-vpn-analysis.sh

# 分析 production 環境
./admin-tools/run-vpn-analysis.sh production

# 使用環境參數
./admin-tools/run-vpn-analysis.sh --env=staging

# 使用環境變數
VPN_ENV=production ./admin-tools/run-vpn-analysis.sh
```

#### 📋 分析項目

**1. VPN 端點配置檢查**
- 端點狀態和可用性驗證
- 客戶端 CIDR 和安全群組配置
- VPC 整合和路由配置分析

**2. 安全群組關聯分析**
- 發現引用 VPN 安全群組的所有安全群組
- 計算總體服務覆蓋範圍
- 驗證安全群組最佳實踐

**3. 資料來源存取測試**
- **RDS/MySQL** (Port 3306): 資料庫存取測試
- **Redis/ElastiCache** (Port 6379): 快取服務存取測試  
- **HBase** (Port 8765): 大數據平台存取測試
- **HBase 擴展端口** (16010, 16020, 8080, 8000): 管理介面存取
- **EKS/Kubernetes** (Port 443): 容器平台 API 存取測試

**4. 綜合狀態評估**
- 計算總體配置品質評分
- 識別潛在的存取問題
- 提供改善建議和最佳實踐指南

#### 📊 報告輸出

**Markdown 報告** (`vpn-analysis-report-{environment}.md`)
- 可讀的詳細分析報告
- 包含配置狀態、服務存取矩陣、改善建議
- 支援直接在瀏覽器中查看或列印

**JSON 數據** (`vpn-analysis-report-{environment}.json`)
- 結構化數據格式，便於程式化處理
- 包含完整的配置詳情和測試結果
- 支援與其他工具和監控系統整合

#### 🔧 先決條件檢查

工具會自動檢查並驗證：
- **Bash 版本**: 需要 4.0+ 以支援關聯陣列
- **AWS CLI**: 檢查安裝狀態和認證配置
- **jq**: JSON 處理工具可用性
- **AWS 服務連通性**: EC2、VPC、Client VPN 服務存取測試
- **環境配置**: 驗證環境設定檔的正確性

#### 🎯 使用場景

1. **部署後驗證**: 確認 VPN 端點正確配置並可存取所需服務
2. **定期健康檢查**: 監控 VPN 配置的持續正確性
3. **故障排除**: 快速識別 VPN 存取問題的根本原因
4. **合規審計**: 生成詳細報告以滿足安全和合規要求
5. **環境比較**: 比較不同環境間的 VPN 配置差異

#### 💡 高級功能

**環境自動檢測**
- 智能環境檢測和配置載入
- 支援多種環境指定方式
- 自動配置文件創建和模板生成

**互動式結果展示**
- 彩色終端輸出增強可讀性
- 互動式報告查看選項
- 支援多種報告格式和查看器

**錯誤處理和恢復**
- 詳細的錯誤訊息和故障排除指南
- 自動環境修復建議
- 優雅的錯誤處理和狀態回報

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

總共包含 **18個主要腳本** 和 **7個核心庫文件**，提供從環境管理、VPN 端點創建、安全 CSR 管理、團隊管理、全面分析報告到故障診斷的完整解決方案。所有工具都支援雙環境（Staging/Production）架構，並提供自動備份和錯誤恢復功能。

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

## 🛡️ AWS Client VPN 安全群組最佳實踐

### 概述

本工具套件實施了 **AWS Client VPN 專用安全群組架構**，這是根據 AWS 最佳實踐設計的企業級安全管理方法。透過為 Client VPN 用戶創建專用的安全群組，我們能夠實現更細緻的存取控制、更好的安全隔離，以及更簡化的管理流程。

### 🏗️ 架構設計原則

#### 專用安全群組方法 (AWS 推薦)
```bash
# 自動創建專用的 Client VPN 安全群組
CLIENT_VPN_SECURITY_GROUP_ID="sg-xxxxx"  # 保存在 vpn_endpoint.conf
```

**設計優勢:**
- **🔒 安全隔離**: VPN 用戶與其他網路流量完全分離
- **📋 集中管理**: 透過單一安全群組管理所有 VPN 用戶的存取權限
- **🎯 最小權限原則**: 精確控制 VPN 用戶可以存取的服務和端口
- **📊 審計友好**: 簡化安全審計和合規檢查流程

### 🔧 自動化實施流程

#### 1. 專用安全群組創建
```bash
# 工具套件自動執行以下操作：
aws ec2 create-security-group \
    --group-name "client-vpn-sg-${environment}" \
    --description "Dedicated security group for Client VPN users - ${environment} environment" \
    --vpc-id ${VPC_ID} \
    --region ${AWS_REGION}
```

#### 2. 基礎規則配置
```bash
# 允許所有出站流量（提供基本網路連接）
aws ec2 authorize-security-group-egress \
    --group-id ${CLIENT_VPN_SECURITY_GROUP_ID} \
    --protocol -1 \
    --cidr 0.0.0.0/0 \
    --region ${AWS_REGION}
```

#### 3. 服務存取規則配置
工具套件會自動生成針對現有服務安全群組的存取規則：

**資料庫服務存取:**
```bash
# MySQL/RDS 存取
aws ec2 authorize-security-group-ingress \
    --group-id sg-503f5e1b \
    --protocol tcp --port 3306 \
    --source-group ${CLIENT_VPN_SECURITY_GROUP_ID}

# Redis 存取  
aws ec2 authorize-security-group-ingress \
    --group-id sg-503f5e1b \
    --protocol tcp --port 6379 \
    --source-group ${CLIENT_VPN_SECURITY_GROUP_ID}
```

**大數據服務存取:**
```bash
# HBase Master Web UI
aws ec2 authorize-security-group-ingress \
    --group-id sg-503f5e1b \
    --protocol tcp --port 16010 \
    --source-group ${CLIENT_VPN_SECURITY_GROUP_ID}

# Phoenix Query Server
aws ec2 authorize-security-group-ingress \
    --group-id sg-503f5e1b \
    --protocol tcp --port 8765 \
    --source-group ${CLIENT_VPN_SECURITY_GROUP_ID}
```

**容器服務存取:**
```bash
# EKS API Server 存取
aws ec2 authorize-security-group-ingress \
    --group-id sg-0d59c6a9f577eb225 \
    --protocol tcp --port 443 \
    --source-group ${CLIENT_VPN_SECURITY_GROUP_ID}
```

### 📋 配置文件組織

#### 環境特定配置分離
```bash
# AUTO-GENERATED: 保存在 vpn_endpoint.conf（自動生成資訊）
CLIENT_VPN_SECURITY_GROUP_ID="sg-xxxxx"

# USER-CONFIGURABLE: 保存在 staging.env/production.env（用戶配置）
VPC_ID="vpc-xxxxx"
SUBNET_ID="subnet-xxxxx" 
VPN_CIDR="172.16.0.0/22"
```

**檔案組織原則:**
- **`.env` 檔案**: 用戶可配置的環境設定
- **`.conf` 檔案**: 系統自動生成的運行時資訊
- **清晰分離**: 避免配置混淆，便於維護和故障排除

### 🔍 管理和監控

#### 安全群組狀態檢查
```bash
# 檢視當前 VPN 安全群組配置
aws ec2 describe-security-groups \
    --group-ids ${CLIENT_VPN_SECURITY_GROUP_ID} \
    --region ${AWS_REGION}
```

#### 存取日誌和審計
- **CloudTrail 整合**: 自動記錄所有安全群組變更
- **VPC Flow Logs**: 監控 VPN 用戶的網路流量模式
- **標籤管理**: 自動為安全群組添加環境和用途標籤

### 💡 最佳實踐建議

1. **定期審查**: 定期檢查和更新安全群組規則
2. **最小權限**: 只開放必要的服務端口
3. **環境隔離**: Staging 和 Production 使用不同的安全群組
4. **監控告警**: 設定 CloudWatch 告警監控異常流量
5. **文檔記錄**: 維護安全群組規則的變更記錄

### 🚀 實施效益

- **🔒 增強安全性**: 比傳統 IP 白名單方法更安全
- **⚡ 簡化管理**: 集中管理所有 VPN 用戶存取權限
- **📈 可擴展性**: 輕鬆支援大量 VPN 用戶
- **🛡️ 合規性**: 符合企業安全和合規要求
- **🔧 故障排除**: 更容易診斷和解決連接問題

這種專用安全群組架構不僅符合 AWS 的安全最佳實踐，也為企業提供了一個可靠、可擴展且易於管理的 VPN 存取控制解決方案。

### 🔧 新 AWS 服務 VPN 存取管理

當企業新增 AWS 服務並使用新的安全群組時，本工具套件提供多種方式來自動授予 VPN 存取權限：

#### 🚀 選項 1：自動發現和配置（建議）

工具套件的智慧發現系統能夠自動偵測新服務：

```bash
# 重新執行發現以尋找新服務
./admin-tools/manage_vpn_service_access.sh discover sg-0b324ca8f7b16f95c

# 然後為新發現的服務配置存取權限
./admin-tools/manage_vpn_service_access.sh create sg-0b324ca8f7b16f95c
```

#### 🎯 選項 2：手動安全群組存取

如果您知道新服務的安全群組 ID：

```bash
# 為特定安全群組授予 VPN 存取權限
aws ec2 authorize-security-group-ingress \
    --group-id <NEW_SERVICE_SECURITY_GROUP_ID> \
    --source-group sg-0b324ca8f7b16f95c \
    --protocol tcp \
    --port <SERVICE_PORT>
```

#### 🔍 選項 3：新增服務到發現配置

為了永久包含新服務，可以將其新增到發現系統中（編輯 `manage_vpn_service_access.sh` 第 30 行）：

```bash
SERVICES="MySQL_RDS:3306 Redis:6379 HBase_Master:16010 HBase_RegionServer:16020 HBase_Custom:8765 Phoenix_Query:8000 Phoenix_Web:8080 EKS_API:443 NEW_SERVICE:PORT"
```

#### 🔄 可用的發現方法

系統使用多種發現方法，通常能自動找到新服務：

1. **實際規則分析** - 掃描現有安全群組規則
2. **資源驗證發現** - 將實際 AWS 資源對應到安全群組
3. **標籤基礎發現** - 透過 AWS 標籤尋找服務
4. **模式基礎發現** - 透過命名模式識別服務

#### 📋 新服務的建議工作流程

```bash
# 1. 執行發現檢查是否偵測到新服務
./admin-tools/manage_vpn_service_access.sh discover sg-0b324ca8f7b16f95c

# 2. 檢查發現了什麼
./admin-tools/manage_vpn_service_access.sh report --summary

# 3. 如果新服務出現，配置存取權限
./admin-tools/manage_vpn_service_access.sh create sg-0b324ca8f7b16f95c

# 4. 如果未被發現，手動新增規則
aws ec2 authorize-security-group-ingress \
    --group-id <NEW_SERVICE_SG> \
    --source-group sg-0b324ca8f7b16f95c \
    --protocol tcp \
    --port <PORT>
```

#### 📊 VPN 存取追蹤和報告

使用整合的報告系統檢視和管理 VPN 存取規則：

```bash
# 檢視 VPN 存取規則摘要
./admin-tools/manage_vpn_service_access.sh report --summary

# 檢視詳細報告
./admin-tools/manage_vpn_service_access.sh report

# 包含移除指令
./admin-tools/manage_vpn_service_access.sh report --commands

# 檢視報告說明
./admin-tools/manage_vpn_service_access.sh report --help
```

#### 💡 最佳實踐建議

- **定期執行發現**: 發現系統相當全面，應該能自動偵測大多數新服務
- **使用追蹤系統**: 所有 VPN 存取修改都會記錄在 `vpn_security_groups_tracking.conf` 中
- **檢查報告**: 定期檢視 VPN 存取報告以確保適當的存取控制
- **環境隔離**: 新服務存取規則會自動按環境（Staging/Production）分離管理

---

## 🔐 安全 CSR 工作流程

### 概述

本工具套件採用**兩階段證書簽署請求 (CSR) 工作流程**，確保 CA 私鑰始終保持在管理員系統上，從不暴露給團隊成員。這種方法大幅提升了安全性，同時保持了自助服務的便利性。

### 工作流程步驟

#### 📝 階段一：團隊成員生成 CSR
```bash
# 團隊成員執行（生成私鑰和 CSR）
./team_member_setup.sh
```
- 生成個人私鑰（保留在本地）
- 創建證書簽署請求 (CSR)
- 提供上傳指示
- 腳本暫停等待管理員簽署

#### 🔒 階段二：管理員簽署證書
```bash
# 管理員選項 1：簽署單個 CSR
./admin-tools/sign_csr.sh -e production user.csr

# 管理員選項 2：批次處理多個 CSR
./admin-tools/process_csr_batch.sh download -e production
./admin-tools/process_csr_batch.sh process -e production
./admin-tools/process_csr_batch.sh upload --auto-upload
```
- 驗證 CSR 格式和內容
- 使用 CA 私鑰安全簽署
- 生成有效的客戶端證書

#### ✅ 階段三：團隊成員完成設置
```bash
# 團隊成員恢復設置（當收到簽署證書後）
./team_member_setup.sh --resume-cert
```
- 驗證簽署證書
- 完成 VPN 客戶端配置
- 導入證書到 AWS ACM

### S3 安全交換（可選）

管理員可設置 S3 存儲桶進行安全的 CSR/證書交換：

```bash
# 設置 S3 交換桶
./admin-tools/setup_csr_s3_bucket.sh

# 監控模式自動處理
./admin-tools/process_csr_batch.sh monitor -e staging
```

### 安全優勢

- **🔐 CA 私鑰隔離**：CA 私鑰永不離開管理員系統
- **🛡️ 最小權限**：團隊成員只能生成 CSR，無法簽署證書
- **📋 審計追蹤**：所有簽署操作都有完整記錄
- **🔄 自動化支持**：支援批次處理和監控模式
- **☁️ 安全交換**：透過 S3 和 IAM 政策控制文件交換

---

## 快速使用指南

### 常用操作流程

#### 🚀 初始環境設置
```bash
# 查看當前環境狀態
./admin-tools/vpn_env.sh status

# 切換到 staging 環境進行測試
./admin-tools/vpn_env.sh switch staging

# 啟動互動式環境選擇器
./admin-tools/vpn_env.sh selector
```

#### 🔧 VPN 管理操作
```bash
# 啟動管理員控制台
./admin-tools/aws_vpn_admin.sh

# 設置團隊成員 VPN 訪問（生成 CSR）
./team_member_setup.sh

# 完成證書設置（當管理員簽署後）
./team_member_setup.sh --resume-cert

# 撤銷用戶訪問權限
./admin-tools/revoke_member_access.sh
```

#### 🔐 CSR 管理操作（管理員專用）
```bash
# 設置 S3 CSR 交換桶
./admin-tools/setup_csr_s3_bucket.sh

# 簽署單個 CSR
./admin-tools/sign_csr.sh -e production user.csr

# 批次處理多個 CSR
./admin-tools/process_csr_batch.sh download -e production
./admin-tools/process_csr_batch.sh process -e production
./admin-tools/process_csr_batch.sh upload --auto-upload

# 監控模式自動處理
./admin-tools/process_csr_batch.sh monitor -e staging
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

# 修復 VPN 網際網路存取問題
./admin-tools/tools/fix_internet_access.sh

# 修復特定端點的網際網路存取
./admin-tools/tools/fix_internet_access.sh cvpn-endpoint-xxxxx
```

#### 📊 VPN 分析和報告操作
```bash
# 全面 VPN 配置分析（staging 環境）
./admin-tools/run-vpn-analysis.sh

# 分析 production 環境
./admin-tools/run-vpn-analysis.sh production

# 使用環境參數
./admin-tools/run-vpn-analysis.sh --env=staging

# 使用環境變數
VPN_ENV=production ./admin-tools/run-vpn-analysis.sh
```

---

## 🚀 首次部署建議流程

### **完整部署序列 (推薦)**

本節提供首次部署 VPN Cost Automation 系統的完整步驟指南，確保順利建立雙環境架構。

#### **步驟 1: 部署前準備**

**1.1 配置 AWS Profiles**
```bash
# 配置 Production 環境 AWS Profile
aws configure --profile prod
# 輸入: Access Key ID, Secret Access Key, Region (建議: us-east-1), Output format (json)

# 配置 Staging 環境 AWS Profile  
aws configure --profile default  # 或自定義名稱
# 輸入: Access Key ID, Secret Access Key, Region (建議: us-east-1), Output format (json)
```

**1.2 驗證 AWS Profiles 運作正常**
```bash
# 驗證 Production Profile
aws sts get-caller-identity --profile prod

# 驗證 Staging Profile
aws sts get-caller-identity --profile default

# 確認兩個 Profile 都能正常回傳 Account ID 和 User ARN
```

**1.3 檢查環境狀態**
```bash
# 檢查當前環境和 AWS profile 配置
./admin-tools/admin-tools/vpn_env.sh status
```

**1.4 確認必要權限**
確保兩個 AWS 帳戶都具備以下權限：
- CloudFormation 完整權限
- Lambda 服務權限
- API Gateway 權限
- Systems Manager Parameter Store 權限
- KMS 金鑰管理權限
- IAM 角色建立權限

#### **步驟 2: 部署基礎設施**

**2.1 執行雙環境部署**
```bash
# 部署 Production 和 Staging 環境（含安全參數管理）
./scripts/deploy.sh both --secure-parameters
```

**部署過程說明：**
- ✅ **先部署 Production 環境**：建立主要基礎設施和 API Gateway
- ✅ **再部署 Staging 環境**：建立測試環境並配置跨帳戶路由
- ✅ **自動建立 KMS 金鑰**：用於加密敏感參數
- ✅ **建立 Lambda 函數**：包含 Slack 整合和 VPN 控制邏輯
- ⚠️ **參數為預設值**：需要後續手動配置實際數值

**預期部署時間：** 15-20 分鐘

#### **步驟 3: 配置系統參數**

**3.1 準備 Slack 整合資訊**
在執行參數配置前，請先準備：
- **Slack Webhook URL**: `https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK`
- **Slack Signing Secret**: 從 Slack App 設定中取得
- **Slack Bot Token**: `xoxb-` 開頭的 Bot User OAuth Token

**3.2 配置所有環境參數**
```bash
# 配置 Production 環境參數
./scripts/setup-parameters.sh --env production --auto-read --secure \
  --slack-webhook 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK' \
  --slack-secret 'your-slack-signing-secret' \
  --slack-bot-token 'xoxb-your-slack-bot-token'

# 配置 Staging 環境參數  
./scripts/setup-parameters.sh --env staging --auto-read --secure \
  --slack-webhook 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK' \
  --slack-secret 'your-slack-signing-secret' \
  --slack-bot-token 'xoxb-your-slack-bot-token'
```

**替代方案：使用 --all 配置（如果腳本支援）**
```bash
# 一次配置兩個環境的參數（須確認腳本支援此功能）
./scripts/setup-parameters.sh --all --auto-read --secure \
  --slack-webhook 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK' \
  --slack-secret 'your-slack-signing-secret' \
  --slack-bot-token 'xoxb-your-slack-bot-token'
```

**參數配置說明：**
- `--all`: 同時配置 staging 和 production 環境
- `--auto-read`: 自動從配置檔案讀取 VPN endpoint 和 subnet 資訊
- `--secure`: 使用 KMS 加密敏感參數（Slack 相關資訊）

#### **步驟 4: 驗證部署結果**

**4.1 檢查部署狀態**
```bash
# 檢查兩個環境的部署狀態
./scripts/deploy.sh status
```

**預期輸出：**
```
✅ Production environment is deployed
   Production API: https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/
✅ Staging environment is deployed  
   Staging API: https://yyyyyyyyyy.execute-api.us-east-1.amazonaws.com/prod/
```

**4.2 驗證跨帳戶路由**
```bash
# 驗證 Staging 到 Production 的跨帳戶路由配置
./scripts/deploy.sh validate-routing
```

**4.3 測試 VPN 分析功能**
```bash
# 測試 Staging 環境
./admin-tools/run-vpn-analysis.sh staging

# 測試 Production 環境  
./admin-tools/run-vpn-analysis.sh production
```

#### **步驟 5: Slack 整合設定**

**5.1 配置 Slack App**

**⚠️ 重要：只需配置 Staging URL**

由於系統採用智能路由架構，Slack App 只需要配置 **Staging 環境** 的 URL：

1. 在 Slack App 設定中，將 **Request URL** 設定為：
   ```
   https://yyyyyyyyyy.execute-api.us-east-1.amazonaws.com/prod/slack
   ```
   （使用 Staging API Gateway URL）

2. 確認 Slash Command 設定：
   - Command: `/vpn`
   - Request URL: 只使用 **Staging** 環境的 URL

**路由邏輯說明：**
- Staging 環境會智能路由 Production 指令到 Production 環境
- Production 指令：`/vpn check production` → Staging 自動轉發到 Production
- Staging 指令：`/vpn check staging` → Staging 本地處理
- 這樣設計確保單一 Slack App 可以管理兩個環境

**5.2 測試 Slack 整合**
```bash
# 在 Slack 中測試指令
/vpn check staging
/vpn check production
```

#### **步驟 6: 系統驗證與測試**

**6.1 環境狀態檢查**
```bash
# 檢查當前環境狀態
./admin-tools/admin-tools/vpn_env.sh status

# 切換環境測試
./admin-tools/admin-tools/vpn_env.sh switch staging
./admin-tools/admin-tools/vpn_env.sh switch production
```

**6.2 完整功能測試**
```bash
# 測試 VPN 管理功能
./admin-tools/aws_vpn_admin.sh

# 測試團隊成員設定流程
./team_member_setup.sh
```

### **部署後檢查清單**

- [ ] **AWS Profiles 配置正確**：兩個環境都能正常存取
- [ ] **基礎設施部署成功**：CloudFormation stacks 建立完成
- [ ] **參數配置完成**：Slack 整合資訊已正確設定
- [ ] **KMS 金鑰運作正常**：敏感參數已加密儲存
- [ ] **API Gateway 端點可存取**：兩個環境的 API 都能回應
- [ ] **跨帳戶路由正常**：Staging 能正確路由到 Production
- [ ] **Slack 整合測試通過**：指令能正常執行並回應
- [ ] **VPN 分析功能正常**：能產生環境分析報告

### **常見問題排除**

#### **部署失敗**
```bash
# 檢查 CDK bootstrap 狀態
aws cloudformation describe-stacks --stack-name CDKToolkit --profile production
aws cloudformation describe-stacks --stack-name CDKToolkit --profile staging

# 如果未 bootstrap，手動執行
cd cdklib
AWS_PROFILE=production cdk bootstrap
AWS_PROFILE=staging cdk bootstrap
```

#### **參數配置失敗**
```bash
# 檢查 KMS 金鑰狀態
aws kms describe-key --key-id alias/vpn-parameter-store-production --profile production
aws kms describe-key --key-id alias/vpn-parameter-store-staging --profile staging

# 檢查參數是否存在
aws ssm get-parameter --name "/vpn/slack/webhook" --profile production
```

#### **Slack 整合問題**
```bash
# 檢查 API Gateway 端點狀態
curl -X POST https://your-api-gateway-url/slack \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "token=test&command=/vpn&text=check"
```

### **安全注意事項**

- 🔐 **敏感資訊保護**：所有 Slack 相關參數都使用 KMS 加密
- 🛡️ **最小權限原則**：IAM 角色僅授予必要權限
- 📋 **審計追蹤**：所有操作都記錄在 CloudWatch Logs
- 🔄 **環境隔離**：Staging 和 Production 完全分離
- 🚨 **監控告警**：重要錯誤會觸發 CloudWatch 告警

### **效能最佳化建議**

- ⚡ **區域選擇**：建議使用 `us-east-1` 以獲得最佳效能
- 📊 **監控設定**：啟用 CloudWatch 詳細監控
- 🔧 **定期維護**：定期檢查和更新 Lambda 函數
- 💾 **日誌管理**：設定適當的日誌保留期限

---

## 🤖 自動化部署指南

### **✅ 完全自動化的部署流程**

經過系統優化，`deploy.sh` 和 `setup-parameters.sh` 腳本現在支援完全自動化部署，無需手動設定環境變數或處理配置問題。

#### **前置條件**

1. **配置 AWS Profiles**
   ```bash
   # 配置生產環境 profile
   aws configure --profile prod
   
   # 配置測試環境 profile（如果需要）
   aws configure --profile default
   ```

2. **獲取正確的 Slack 配置**
   - **Slack Webhook URL**: 從 Slack App 設定中取得
   - **Slack Signing Secret**: **必須是 32 字元的十六進位字串**
     - 前往 https://api.slack.com/apps
     - 選擇您的 App → Basic Information → App Credentials
     - 複製 "Signing Secret"（應該是 32 個字元）
   - **Slack Bot Token**: 格式為 `xoxb-XXXXXXXX-XXXXXXXX-XXXXXXXXXXXXXXXX`

#### **一鍵部署命令**

```bash
# 部署兩個環境（推薦）
./scripts/deploy.sh both --secure-parameters

# 設定所有參數
./scripts/setup-parameters.sh --all --secure --auto-read \
  --slack-webhook "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK" \
  --slack-secret "YOUR_64_CHARACTER_HEX_SIGNING_SECRET" \
  --slack-bot-token "xoxb-YOUR-BOT-TOKEN"
```

#### **自動化特性**

✅ **自動 CDK 環境檢測**: 腳本會自動從 AWS profiles 偵測帳戶 ID 和區域  
✅ **智能參數驗證**: 自動驗證 Slack 參數格式，提供詳細錯誤訊息  
✅ **環境名稱映射**: 自動處理 `prod` ↔ `production` 環境名稱對應  
✅ **KMS 金鑰管理**: 自動檢測和使用正確的 KMS 金鑰別名  
✅ **錯誤處理**: 提供清楚的錯誤訊息和解決建議  

#### **常見問題自動解決**

1. **CDK 環境變數未設置**
   - ❌ 以前：需要手動設定 `CDK_DEFAULT_ACCOUNT` 和 `CDK_DEFAULT_REGION`
   - ✅ 現在：自動從 AWS profile 偵測並設定

2. **Slack 參數驗證錯誤**
   - ❌ 以前：`ParameterPatternMismatchException` 錯誤難以理解
   - ✅ 現在：詳細的驗證錯誤訊息和修正建議

3. **環境名稱不一致**
   - ❌ 以前：`prod` vs `production` 命名混淆
   - ✅ 現在：自動映射和處理不同的環境名稱

#### **驗證部署**

```bash
# 檢查部署狀態
./scripts/deploy.sh status

# 測試 Slack 整合
curl -X POST YOUR_STAGING_API_URL/slack \
  -H "Content-Type: application/json" \
  -d '{"text":"test","user_name":"testuser"}'
```

#### **如果遇到問題**

1. **Slack Signing Secret 格式錯誤**
   ```bash
   # 正確範例（32 字元）
   c9c157368cbc83e2feeff2e774219fe4
   
   # 錯誤範例（64 字元 - 太長）
   a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2
   ```

2. **使用 Placeholder 進行測試**
   ```bash
   # 如果暫時沒有正確的 signing secret，可以使用 placeholder
   ./scripts/setup-parameters.sh --env staging --secure \
     --slack-secret "PLACEHOLDER_$(openssl rand -hex 32)_update_with_real_64char_secret"
   ```

### **升級指南：從手動部署到自動化**

如果您之前使用過舊版本的手動部署流程，新的自動化版本向後相容。只需使用新的命令即可享受自動化部署的便利。

---

## 🔄 VPN Endpoint 重新建立流程

當需要重新建立 VPN endpoint（例如：因為網路配置變更、安全性考量、或故障排除）時，請遵循以下步驟確保系統正常運作。

### **🎯 重新建立 VPN Endpoint 的完整流程**

#### **步驟 1: 確認要重新建立的環境**

```bash
# 檢查當前環境狀態
./admin-tools/admin-tools/vpn_env.sh status

# 檢查兩個環境的部署狀態
./scripts/deploy.sh status
```

#### **步驟 2: 使用管理工具重新建立 Endpoint（推薦方法）**

```bash
# 切換到要重新建立的環境
./admin-tools/admin-tools/vpn_env.sh switch production  # 或 staging

# 使用管理工具重新建立 endpoint
./admin-tools/aws_vpn_admin.sh
# 在選單中選擇刪除現有 endpoint，然後建立新的 endpoint
```

#### **步驟 3: 更新 CDK 部署**

**方法 A: 自動重新部署（推薦）**
```bash
# 重新部署受影響的環境，系統會自動偵測新的 endpoint
./scripts/deploy.sh production --secure-parameters  # 如果重建了 production
./scripts/deploy.sh staging --secure-parameters     # 如果重建了 staging
```

**方法 B: 手動更新參數（進階用戶）**
```bash
# 取得新的 endpoint ID
NEW_ENDPOINT_ID="cvpn-endpoint-NEW_ID_HERE"

# 更新 Production 環境參數
aws ssm put-parameter \
  --name "/vpn/prod/endpoint/conf" \
  --value "{\"ENDPOINT_ID\":\"$NEW_ENDPOINT_ID\",\"SUBNET_ID\":\"subnet-93ca50d9\"}" \
  --type "String" \
  --overwrite \
  --profile prod

# 更新 Staging 環境參數  
aws ssm put-parameter \
  --name "/vpn/staging/endpoint/conf" \
  --value "{\"ENDPOINT_ID\":\"$NEW_ENDPOINT_ID\",\"SUBNET_ID\":\"subnet-93ca50d9\"}" \
  --type "String" \
  --overwrite \
  --profile prod

# 重新部署 CDK
./scripts/deploy.sh production --secure-parameters
```

#### **步驟 4: 更新跨環境路由配置（如果重建 Production）**

如果重新建立了 **Production** endpoint，需要更新 Staging 的跨帳戶路由配置：

```bash
# 部署腳本會自動處理，但也可以手動檢查
./scripts/deploy.sh validate-routing

# 或者手動觸發 Staging 重新部署來更新路由
./scripts/deploy.sh staging --secure-parameters
```

#### **步驟 5: 更新團隊成員配置**

```bash
# 重新生成團隊成員的 VPN 配置檔案
./team_member_setup.sh --resume

# 或使用零接觸工作流程
./team_member_setup.sh --init
```

#### **步驟 6: 驗證系統功能**

```bash
# 檢查部署狀態
./scripts/deploy.sh status

# 驗證跨帳戶路由
./scripts/deploy.sh validate-routing

# 測試 Slack 整合
# 在 Slack 中執行：/vpn check production 或 /vpn check staging
```

### **⚠️ 重要注意事項**

1. **操作順序很重要**：
   - 先重新建立 VPN endpoint
   - 再更新參數存儲庫
   - 最後重新部署 CDK

2. **備份現有配置**：
   ```bash
   # 在重新建立前備份當前配置
   aws ssm get-parameter --name "/vpn/prod/endpoint/conf" --profile prod
   aws ssm get-parameter --name "/vpn/staging/endpoint/conf" --profile prod
   ```

3. **測試建議**：
   - 優先在 Staging 環境測試整個流程
   - 確認無誤後再操作 Production 環境

4. **團隊通知**：
   - 重新建立 endpoint 後，所有團隊成員需要下載新的 `.ovpn` 配置檔案
   - API Gateway 端點會自動更新指向新的 VPN endpoint

5. **自動化功能**：
   - 部署腳本會自動更新 Staging 環境的跨帳戶路由配置
   - CDK 會自動更新 API Gateway 來指向新的 VPN endpoint

### **故障排除**

如果遇到問題，可以使用以下工具進行診斷：

```bash
# 檢查配置檔案
./admin-tools/tools/validate_config.sh

# 修復 endpoint ID 問題
./admin-tools/tools/fix_endpoint_id.sh

# 診斷 VPN 建立問題
./admin-tools/tools/debug_vpn_creation.sh
```

---

## 💰 成本試算與注意事項

### 成本試算 (us-east-1)

**假設條件**  
- 有 staging 與 production 兩個 AWS 環境，但團隊成員同一時段只會連線其中一個環境（不會同時連線兩邊）。
- 兩個環境的端點皆長期啟用（若僅啟用一個，端點費用可減半）。
- 5 位員工，每人每天連線 5 h、每週 5 天 (約 4 週 / 20 個工作日)。

**AWS 官方單價**  
- 端點關聯：USD 0.10／h  
- 作用中連線：USD 0.05／h／連線  

**最大化評估（兩環境端點皆啟用）**

| 項目         | 計算式                                 | 月費 (USD) |
|--------------|----------------------------------------|------------|
| 端點關聯     | 0.10 × 24 h × 30 d × 2                 | 144        |
| 用戶端連線   | 0.05 × 5 人 × 5 h × 5 d × 4 週         | 25         |
| 合計         | 144 + 25                               | **169**    |

- 若僅啟用一個環境的端點，端點關聯費用為 72，合計約 97。
- 用戶端連線費用以「單一環境最大同時連線數」計算，假設所有人同時連線其中一環境。
- 原則上只有在維護、部署、整合測試的時候才需要連線。

### 補充注意

- 若端點位於具 Internet Gateway 的子網路，AWS 會自動分配彈性 IPv4；EIP 處於 **已連接狀態** 時約 USD 0.005／h，需要時再加計。  
- 經由 VPN 傳出的流量若離開 AWS（Internet、跨區），仍會產生 EC2 Data Transfer Out。
- 啟用 CloudWatch Logs（連線/授權/路由等）將依日誌量付費；同理，若使用 Client Connect Handler 觸發 Lambda 也會另計費。

因此，在不考慮流量、日誌與 EIP 的前提下，本案例每月開銷約 **USD 169**。停用端點或限制使用者連線時段即可對應等比例降費。

---

## 詳細文檔

本 `readme.md` 文件提供了 AWS Client VPN 雙環境管理工具套件的高級概述。

有關**初始設置、詳細的工具使用指南、具體的操作步驟、環境管理詳情、故障排除、維護流程、AWS 資源管理、移除指南以及附錄內容（如完整的 IAM 政策範例和配置文件結構）**，請參閱配套的完整使用說明書：

📄 `vpn_connection_manual.md`

此說明書將為您提供成功部署、管理和維護雙環境 VPN 解決方案所需的所有詳細信息。

---

**最後更新：** 2025年6月12日
**文檔版本：** 2.3 (已整合安全 CSR 工作流程)
**適用工具版本：** 2.1
**架構：** 模組化函式庫設計 + 安全 CSR 管理
