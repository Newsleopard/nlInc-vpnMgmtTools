# VPN Management CLI Tool — Rust 重構規劃

> **Status**: RFC (Request for Comments)
> **Author**: CT Yeh
> **Date**: 2026-03-07

## 目錄

1. [現況評估](#1-現況評估)
2. [為何選用 Rust](#2-為何選用-rust)
3. [CLI 設計規範](#3-cli-設計規範)
4. [指令架構設計](#4-指令架構設計)
5. [實作規劃](#5-實作規劃)
6. [Rust Crate 選型](#6-rust-crate-選型)
7. [專案結構](#7-專案結構)
8. [遷移策略](#8-遷移策略)
9. [安全性考量](#9-安全性考量)
10. [發佈與分發](#10-發佈與分發)

---

## 1. 現況評估

### 1.1 現有腳本清單

| 腳本 | 角色 | 功能 | 複雜度 |
|------|------|------|--------|
| `aws_vpn_admin.sh` | Admin | 互動式 VPN 管理主控台 | 高 |
| `manage_vpn_users.sh` | Admin | 使用者權限管理 (add/remove/list/batch) | 中 |
| `sign_csr.sh` | Admin | CSR 簽署、S3 上傳 | 中 |
| `setup_csr_s3_bucket.sh` | Admin | S3 基礎建設初始化 | 中 |
| `publish_endpoints.sh` | Admin | 發佈 VPN metadata 至 S3 | 低 |
| `employee_offboarding.sh` | Admin | 員工離職流程 (高風險) | 高 |
| `revoke_member_access.sh` | Admin | 撤銷個別使用者存取 | 中 |
| `manage_vpn_service_access.sh` | Admin | AWS 服務發現 & SG 規則管理 | 高 |
| `admin-handover-export.sh` | Admin | 管理員交接匯出 | 中 |
| `admin-handover-import.sh` | Admin | 管理員交接匯入 | 中 |
| `vpn_tracking_report.sh` | Admin | VPN 使用報告 | 低 |
| `vpn_subnet_manager.sh` | Admin | Subnet 關聯管理 | 中 |
| `run-vpn-analysis.sh` | Admin | VPN 健康分析 | 低 |
| `team_member_setup.sh` | Member | 團隊成員 VPN 設定 (--init/--resume) | 中 |

### 1.2 共用函式庫

| 檔案 | 功能 |
|------|------|
| `lib/profile_selector.sh` | AWS Profile 管理、環境偵測、跨帳號驗證 |
| `lib/core_functions.sh` | 基礎工具函式、AWS CLI 包裝、驗證 |
| `lib/env_core.sh` | 輕量環境管理 |
| `lib/cert_management.sh` | 憑證操作、Easy-RSA 整合 |
| `lib/endpoint_management.sh` | VPN Endpoint CRUD |
| `lib/endpoint_creation.sh` | 基礎建設佈建 |
| `lib/endpoint_operations.sh` | Endpoint 生命週期管理 |
| `lib/security_group_operations.sh` | Security Group 規則管理 |
| `lib/vpc_operations.sh` | VPC & Subnet 操作 |
| `lib/enhanced_confirmation.sh` | 風險分級確認機制 |
| `lib/aws_profile_wrapper.sh` | Profile-aware AWS CLI 包裝 |

### 1.3 現有問題

| 問題 | 說明 |
|------|------|
| **不一致的 CLI 介面** | 部分腳本用 flag (`--upload-s3`)，部分用 positional args (`add username`)，部分是互動式選單 |
| **無法組合使用** | 每個腳本獨立運作，難以在 CI/CD 或自動化流程中串接 |
| **相依性管理困難** | 需要 bash 4+、jq、openssl、aws-cli 等，跨平台安裝不一致 |
| **錯誤處理有限** | `set -e` 為主，缺乏結構化錯誤類型與回復機制 |
| **無版本管理** | 腳本沒有版本號，難以追蹤相容性 |
| **測試困難** | Bash 腳本難以撰寫單元測試 |
| **安全性風險** | Shell injection 可能、密鑰處理缺乏型別安全 |

---

## 2. 為何選用 Rust

### 2.1 與其他語言比較

| 特性 | Rust | Go | Python | Node.js |
|------|------|----|--------|---------|
| 單一 binary 分發 | ✅ 靜態連結 | ✅ 靜態連結 | ❌ 需要 runtime | ❌ 需要 runtime |
| 記憶體安全 | ✅ 編譯期保證 | ✅ GC | ✅ GC | ✅ GC |
| 效能 | ✅ 零成本抽象 | ✅ 良好 | ⚠️ 較慢 | ⚠️ 較慢 |
| 跨平台編譯 | ✅ cross-compilation | ✅ 內建 | ⚠️ 需 pyinstaller | ⚠️ 需 pkg |
| CLI 生態系 | ✅ clap (業界標準) | ✅ cobra | ⚠️ click/argparse | ⚠️ commander |
| 型別安全 | ✅ 嚴格 | ✅ 嚴格 | ⚠️ 可選 | ⚠️ TypeScript |
| 錯誤處理 | ✅ Result/Option | ⚠️ error return | ⚠️ exception | ⚠️ exception |
| 與本專案契合度 | ✅ 安全+效能+分發 | ✅ 良好 | ⚠️ 需打包 | ⚠️ 已有 Lambda 層 |

### 2.2 選擇 Rust 的核心理由

1. **零依賴分發**: 編譯成單一 binary，團隊成員不需安裝 runtime
2. **記憶體安全**: 處理憑證和 AWS credentials 時提供編譯期安全保證
3. **業界趨勢**: AWS 官方 SDK 提供 Rust 版本 (`aws-sdk-rust`)
4. **跨平台**: 透過 `cross` 輕鬆編譯 macOS (aarch64/x86_64)、Linux
5. **強型別錯誤處理**: `Result<T, E>` 確保所有錯誤路徑都被處理

---

## 3. CLI 設計規範

### 3.1 遵循業界慣例

參考 [Command Line Interface Guidelines](https://clig.dev/) 和 [12 Factor CLI Apps](https://medium.com/@jdxcode/12-factor-cli-apps-dd3c227a0e46):

| 原則 | 實作方式 |
|------|----------|
| **Subcommand 模式** | `nlvpn user add john` 而非 `manage_vpn_users.sh add john` |
| **一致的 flag 命名** | 全域 flag: `--profile`, `--env`, `--verbose`, `--json` |
| **可程式化輸出** | 預設人類可讀，`--json` 輸出 JSON 供腳本使用 |
| **尊重 exit code** | 0=成功, 1=一般錯誤, 2=使用錯誤, 78=設定錯誤 |
| **支援 stdin/stdout** | 可接受 pipe 輸入，輸出可被 pipe 處理 |
| **Shell completion** | 自動產生 bash/zsh/fish 補全腳本 |
| **色彩控制** | 自動偵測 TTY，支援 `NO_COLOR` 環境變數 |
| **版本資訊** | `nlvpn --version` 顯示版本、commit hash、build date |

### 3.2 全域 Flags

```
Global Options:
  -p, --profile <PROFILE>     AWS profile name
  -e, --env <ENV>             Target environment [staging|production]
  -v, --verbose               Increase verbosity (-vv for debug)
  -q, --quiet                 Suppress non-essential output
      --json                  Output in JSON format
      --dry-run               Show what would be done without executing
      --no-color              Disable colored output
  -h, --help                  Print help
  -V, --version               Print version
```

---

## 4. 指令架構設計

### 4.1 指令樹狀結構

```
nlvpn
├── init                              # 團隊成員初始化 VPN 設定
├── setup                             # 團隊成員完成 VPN 設定 (resume)
│
├── endpoint                          # VPN Endpoint 管理
│   ├── list                          # 列出所有 endpoints
│   ├── create                        # 建立 VPN endpoint
│   ├── delete <endpoint-id>          # 刪除 VPN endpoint
│   ├── status [endpoint-id]          # 檢視 endpoint 狀態
│   └── health                        # 健康檢查 & 診斷
│
├── user                              # 使用者管理
│   ├── add <username>                # 新增使用者
│   ├── remove <username>             # 移除使用者
│   ├── list                          # 列出所有使用者
│   ├── status <username>             # 檢查使用者狀態
│   └── offboard <username>           # 員工離職流程
│
├── cert                              # 憑證管理
│   ├── sign <username|csr-file>      # 簽署 CSR
│   │   ├── --upload-s3               # 上傳至 S3
│   │   └── --validity <days>         # 有效期 (預設 365)
│   ├── revoke <username>             # 撤銷憑證
│   ├── list                          # 列出所有憑證
│   └── status <username>             # 檢查憑證狀態
│
├── service                           # AWS 服務存取管理
│   ├── discover                      # 掃描 VPC 中的服務
│   ├── list                          # 列出已發現的服務
│   ├── grant <security-group-id>     # 建立 VPN 存取規則
│   └── revoke <security-group-id>    # 移除 VPN 存取規則
│
├── subnet                            # Subnet 關聯管理
│   ├── add <subnet-id>               # 新增 subnet 關聯
│   ├── remove <subnet-id>            # 移除 subnet 關聯
│   └── list                          # 列出 subnet 關聯
│
├── infra                             # 基礎建設管理
│   ├── setup-bucket                  # 設定 S3 CSR 交換 bucket
│   │   └── --publish-assets          # 同時發佈 CA 憑證
│   └── publish                       # 發佈 VPN metadata 至 S3
│
├── report                            # 報告
│   ├── usage                         # VPN 使用報告
│   └── cost                          # 成本分析報告
│
├── admin                             # 管理員交接
│   ├── export                        # 匯出管理員設定
│   └── import                        # 匯入管理員設定
│
├── config                            # 本地設定管理
│   ├── show                          # 顯示目前設定
│   ├── set <key> <value>             # 設定值
│   └── validate                      # 驗證設定完整性
│
└── completion                        # Shell 補全
    ├── bash                          # 產生 bash 補全腳本
    ├── zsh                           # 產生 zsh 補全腳本
    └── fish                          # 產生 fish 補全腳本
```

### 4.2 指令映射對照表

| 原始腳本 | 新 CLI 指令 |
|----------|-------------|
| `team_member_setup.sh --init` | `nlvpn init` |
| `team_member_setup.sh --resume` | `nlvpn setup` |
| `aws_vpn_admin.sh` (互動選單) | `nlvpn endpoint list/create/delete/...` |
| `manage_vpn_users.sh add user` | `nlvpn user add user` |
| `manage_vpn_users.sh remove user` | `nlvpn user remove user` |
| `manage_vpn_users.sh list` | `nlvpn user list` |
| `sign_csr.sh --upload-s3 user` | `nlvpn cert sign user --upload-s3` |
| `revoke_member_access.sh user` | `nlvpn cert revoke user` |
| `employee_offboarding.sh` | `nlvpn user offboard user` |
| `setup_csr_s3_bucket.sh` | `nlvpn infra setup-bucket` |
| `publish_endpoints.sh` | `nlvpn infra publish` |
| `manage_vpn_service_access.sh discover` | `nlvpn service discover` |
| `manage_vpn_service_access.sh create sg` | `nlvpn service grant sg` |
| `vpn_tracking_report.sh` | `nlvpn report usage` |
| `vpn_subnet_manager.sh` | `nlvpn subnet add/remove/list` |
| `admin-handover-export.sh` | `nlvpn admin export` |
| `admin-handover-import.sh` | `nlvpn admin import` |

### 4.3 使用範例

```bash
# 團隊成員設定
nlvpn init --env staging
nlvpn setup --env staging

# 管理使用者
nlvpn user add john --env production --profile prod-admin
nlvpn user list --env staging --json
nlvpn user list --env staging --json | jq '.[] | .username'

# 憑證操作
nlvpn cert sign john --upload-s3 --env production
nlvpn cert sign ./john.csr --validity 180

# Endpoint 管理
nlvpn endpoint list --env production
nlvpn endpoint create --env staging --dry-run
nlvpn endpoint status cvpn-endpoint-12345 --env production

# 報告
nlvpn report usage --env production --json
nlvpn report cost --last 30d

# 互動模式 (取代原本的選單式介面)
nlvpn endpoint create --env production   # 引導式建立 (有必填欄位時進入互動模式)

# 基礎建設
nlvpn infra setup-bucket --publish-assets --env staging
```

---

## 5. 實作規劃

### 5.1 分階段實施

#### Phase 1: 核心框架 & 唯讀指令 (MVP)

**目標**: 建立 CLI 框架，實作不修改狀態的查詢指令

- [ ] 專案初始化 (`cargo init`)
- [ ] CLI 解析框架 (clap + subcommands)
- [ ] AWS Profile 管理 & 環境偵測
- [ ] 設定檔讀取 (staging.env / production.env)
- [ ] `nlvpn config show / validate`
- [ ] `nlvpn endpoint list / status`
- [ ] `nlvpn user list / status`
- [ ] `nlvpn report usage / cost`
- [ ] `nlvpn completion bash/zsh/fish`
- [ ] JSON 輸出模式 (`--json`)
- [ ] 色彩化終端輸出

#### Phase 2: 使用者管理 & 憑證操作

**目標**: 實作日常最常用的寫入操作

- [ ] `nlvpn user add / remove`
- [ ] `nlvpn cert sign / revoke / list / status`
- [ ] `nlvpn init / setup` (團隊成員流程)
- [ ] 風險分級確認機制 (對應 `enhanced_confirmation.sh`)
- [ ] S3 操作 (CSR 上傳/下載)
- [ ] OpenSSL 整合 (CSR 簽署)

#### Phase 3: 基礎建設 & 進階管理

**目標**: 實作管理員專用的基礎建設操作

- [ ] `nlvpn endpoint create / delete`
- [ ] `nlvpn subnet add / remove / list`
- [ ] `nlvpn service discover / grant / revoke`
- [ ] `nlvpn infra setup-bucket / publish`
- [ ] `nlvpn user offboard`
- [ ] `nlvpn admin export / import`

#### Phase 4: 品質 & 分發

**目標**: 產品化準備

- [ ] 完整單元測試 & 整合測試
- [ ] CI/CD pipeline (GitHub Actions)
- [ ] 跨平台編譯 (macOS aarch64/x86_64, Linux x86_64)
- [ ] Homebrew formula 或 GitHub Releases 分發
- [ ] 遷移文件與使用者指南

### 5.2 時間軸預估

| 階段 | 範圍 | 建議 |
|------|------|------|
| Phase 1 | 核心框架 + 唯讀指令 | 優先完成，可立即提供價值 |
| Phase 2 | 使用者管理 + 憑證 | 取代最常用的腳本 |
| Phase 3 | 基礎建設 + 進階管理 | 完整取代所有腳本 |
| Phase 4 | 品質 + 分發 | 產品化 |

---

## 6. Rust Crate 選型

### 6.1 核心依賴

| 用途 | Crate | 說明 |
|------|-------|------|
| CLI 解析 | [`clap`](https://crates.io/crates/clap) v4 | derive macro，業界標準 |
| AWS SDK | [`aws-sdk-ec2`](https://crates.io/crates/aws-sdk-ec2), [`aws-sdk-s3`](https://crates.io/crates/aws-sdk-s3), [`aws-sdk-iam`](https://crates.io/crates/aws-sdk-iam), [`aws-sdk-sts`](https://crates.io/crates/aws-sdk-sts), [`aws-sdk-ssm`](https://crates.io/crates/aws-sdk-ssm), [`aws-sdk-acm`](https://crates.io/crates/aws-sdk-acm) | AWS 官方 Rust SDK |
| 非同步 Runtime | [`tokio`](https://crates.io/crates/tokio) | AWS SDK 所需 |
| 序列化 | [`serde`](https://crates.io/crates/serde) + [`serde_json`](https://crates.io/crates/serde_json) | JSON 處理 |
| 終端 UI | [`dialoguer`](https://crates.io/crates/dialoguer) | 互動式 prompt (確認、選擇) |
| 色彩輸出 | [`console`](https://crates.io/crates/console) | 終端色彩、樣式 (含 `NO_COLOR` 支援) |
| 進度條 | [`indicatif`](https://crates.io/crates/indicatif) | 操作進度顯示 |
| 錯誤處理 | [`anyhow`](https://crates.io/crates/anyhow) + [`thiserror`](https://crates.io/crates/thiserror) | 應用層 + 函式庫層錯誤 |
| 日誌 | [`tracing`](https://crates.io/crates/tracing) + [`tracing-subscriber`](https://crates.io/crates/tracing-subscriber) | 結構化日誌 (對應 `-v`/`-vv`) |
| 設定檔 | [`dotenvy`](https://crates.io/crates/dotenvy) | .env 檔案讀取 |
| 表格輸出 | [`tabled`](https://crates.io/crates/tabled) | 格式化表格 (list 指令) |
| TLS/憑證 | [`openssl`](https://crates.io/crates/openssl) 或 [`rcgen`](https://crates.io/crates/rcgen) | CSR 簽署、憑證驗證 |
| 日期時間 | [`chrono`](https://crates.io/crates/chrono) | 時間計算 (憑證有效期) |

### 6.2 `Cargo.toml` 範例

```toml
[package]
name = "nlvpn"
version = "0.1.0"
edition = "2021"
description = "AWS Client VPN management CLI"
license = "MIT"

[dependencies]
clap = { version = "4", features = ["derive", "env"] }
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
anyhow = "1"
thiserror = "2"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
dialoguer = "0.11"
console = "0.15"
indicatif = "0.17"
tabled = "0.17"
dotenvy = "0.15"
chrono = { version = "0.4", features = ["serde"] }

# AWS SDK
aws-config = "1"
aws-sdk-ec2 = "1"
aws-sdk-s3 = "1"
aws-sdk-iam = "1"
aws-sdk-sts = "1"
aws-sdk-ssm = "1"
aws-sdk-acm = "1"

[dev-dependencies]
assert_cmd = "2"
predicates = "3"
tempfile = "3"
```

---

## 7. 專案結構

```
cli/
├── Cargo.toml
├── Cargo.lock
├── src/
│   ├── main.rs                    # Entry point, CLI parsing
│   ├── cli/
│   │   ├── mod.rs                 # CLI 定義 (clap derive)
│   │   ├── global.rs              # 全域 flags 定義
│   │   ├── endpoint.rs            # endpoint subcommands
│   │   ├── user.rs                # user subcommands
│   │   ├── cert.rs                # cert subcommands
│   │   ├── service.rs             # service subcommands
│   │   ├── subnet.rs              # subnet subcommands
│   │   ├── infra.rs               # infra subcommands
│   │   ├── report.rs              # report subcommands
│   │   ├── admin.rs               # admin subcommands
│   │   └── config.rs              # config subcommands
│   │
│   ├── commands/                   # 指令實作
│   │   ├── mod.rs
│   │   ├── init.rs                # team member init flow
│   │   ├── setup.rs               # team member setup flow
│   │   ├── endpoint/
│   │   │   ├── mod.rs
│   │   │   ├── list.rs
│   │   │   ├── create.rs
│   │   │   ├── delete.rs
│   │   │   ├── status.rs
│   │   │   └── health.rs
│   │   ├── user/
│   │   │   ├── mod.rs
│   │   │   ├── add.rs
│   │   │   ├── remove.rs
│   │   │   ├── list.rs
│   │   │   ├── status.rs
│   │   │   └── offboard.rs
│   │   ├── cert/
│   │   │   ├── mod.rs
│   │   │   ├── sign.rs
│   │   │   ├── revoke.rs
│   │   │   ├── list.rs
│   │   │   └── status.rs
│   │   ├── service/
│   │   ├── subnet/
│   │   ├── infra/
│   │   ├── report/
│   │   ├── admin/
│   │   └── config/
│   │
│   ├── aws/                       # AWS 服務封裝
│   │   ├── mod.rs
│   │   ├── profile.rs             # Profile 管理 & 環境偵測
│   │   ├── ec2.rs                 # EC2/VPN API 封裝
│   │   ├── s3.rs                  # S3 操作
│   │   ├── iam.rs                 # IAM 操作
│   │   ├── sts.rs                 # STS 身份驗證
│   │   ├── ssm.rs                 # SSM Parameter Store
│   │   └── acm.rs                 # ACM 憑證管理
│   │
│   ├── cert/                      # 憑證處理
│   │   ├── mod.rs
│   │   ├── csr.rs                 # CSR 生成 & 簽署
│   │   ├── ca.rs                  # CA 操作
│   │   └── validation.rs          # 憑證驗證
│   │
│   ├── config/                    # 設定管理
│   │   ├── mod.rs
│   │   ├── env.rs                 # 環境設定 (.env 檔案)
│   │   ├── app.rs                 # 應用程式設定
│   │   └── validation.rs          # 設定驗證
│   │
│   ├── output/                    # 輸出格式化
│   │   ├── mod.rs
│   │   ├── table.rs               # 表格輸出
│   │   ├── json.rs                # JSON 輸出
│   │   └── progress.rs            # 進度顯示
│   │
│   ├── confirm/                   # 確認機制
│   │   ├── mod.rs
│   │   └── risk.rs                # 風險分級確認
│   │
│   └── error.rs                   # 錯誤類型定義
│
├── tests/                         # 整合測試
│   ├── cli_tests.rs
│   ├── user_tests.rs
│   └── cert_tests.rs
│
└── build.rs                       # Build script (version info)
```

---

## 8. 遷移策略

### 8.1 漸進式遷移 (推薦)

```
Phase 1: Rust CLI 與 Bash 腳本並存
         ├── 唯讀指令先遷移至 Rust
         └── 寫入操作仍使用 Bash

Phase 2: 核心寫入操作遷移
         ├── user add/remove 遷移至 Rust
         ├── cert sign 遷移至 Rust
         └── Bash 腳本加上 deprecation warning

Phase 3: 完整遷移
         ├── 所有指令遷移至 Rust
         ├── Bash 腳本改為 wrapper (呼叫 nlvpn)
         └── 遷移文件

Phase 4: Bash 腳本退役
         ├── 移除 Bash wrapper
         └── 僅保留 Rust CLI
```

### 8.2 向後相容

遷移期間提供 Bash wrapper 腳本：

```bash
#!/bin/bash
# admin-tools/manage_vpn_users.sh (wrapper)
echo "⚠️  This script is deprecated. Use 'nlvpn user $@' instead." >&2
exec nlvpn user "$@"
```

---

## 9. 安全性考量

### 9.1 Rust 帶來的安全改進

| 項目 | Bash 現況 | Rust 改進 |
|------|-----------|-----------|
| Shell injection | 變數展開風險 | 無 shell 層，直接 API 呼叫 |
| 密鑰處理 | 字串變數，可能洩漏至 log | `secrecy` crate，`zeroize` 記憶體清除 |
| 檔案權限 | `chmod 600` 手動設定 | 建立時即設定正確權限 |
| 輸入驗證 | regex + grep | 型別系統 + 驗證函式 |
| 錯誤處理 | `set -e` | `Result<T, E>` 完整錯誤鏈 |

### 9.2 Production 安全機制

```rust
/// 風險等級定義
enum RiskLevel {
    Low,        // 查詢操作，不需確認
    Medium,     // 一般寫入，簡單確認
    High,       // VPN 變更，需要明確確認
    Critical,   // Endpoint 刪除/離職，多重確認
}

/// Production 環境操作需要多重確認
fn confirm_production_operation(risk: RiskLevel, env: &Environment) -> Result<()> {
    if env.is_production() && risk >= RiskLevel::High {
        // 1. 顯示操作影響範圍
        // 2. 要求輸入 "PRODUCTION"
        // 3. Critical 等級追加要求輸入 "CONFIRM"
    }
    Ok(())
}
```

---

## 10. 發佈與分發

### 10.1 編譯目標

| 平台 | Target Triple | 優先級 |
|------|---------------|--------|
| macOS Apple Silicon | `aarch64-apple-darwin` | P0 (主要) |
| macOS Intel | `x86_64-apple-darwin` | P1 |
| Linux x86_64 | `x86_64-unknown-linux-musl` | P1 (CI/CD) |
| Linux ARM64 | `aarch64-unknown-linux-musl` | P2 |

### 10.2 分發方式

```bash
# 方式 1: Homebrew (推薦給 macOS 使用者)
brew tap newsleopard/tools
brew install nlvpn

# 方式 2: GitHub Releases
# 自動化 CI 編譯，產生各平台 binary

# 方式 3: cargo install (開發者)
cargo install nlvpn

# 方式 4: 直接下載
curl -fsSL https://github.com/newsleopard/nlvpn/releases/latest/download/nlvpn-$(uname -m)-apple-darwin -o nlvpn
chmod +x nlvpn
```

### 10.3 CI/CD (GitHub Actions)

```yaml
# 每次 tag push 自動編譯 & 發佈
on:
  push:
    tags: ['v*']

jobs:
  build:
    strategy:
      matrix:
        include:
          - target: aarch64-apple-darwin
            os: macos-latest
          - target: x86_64-apple-darwin
            os: macos-latest
          - target: x86_64-unknown-linux-musl
            os: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo build --release --target ${{ matrix.target }}
      - uses: softprops/action-gh-release@v2
        with:
          files: target/${{ matrix.target }}/release/nlvpn
```

---

## 附錄: 關鍵設計決策記錄

### ADR-001: CLI 名稱選擇 `nlvpn`

- **選項**: `nlvpn`, `vpnctl`, `vpn-admin`, `nl-vpn`
- **決定**: `nlvpn` — 簡短、包含組織標識 (nl = Newsleopard)、避免與系統工具衝突
- **理由**: 遵循業界慣例 (kubectl, awscli, gh)，名稱短且易記

### ADR-002: 使用 `clap` derive macro

- **決定**: 使用 `clap` 的 derive macro 而非 builder pattern
- **理由**: 程式碼更簡潔、型別安全、自動產生 help 文字

### ADR-003: 非同步 Runtime 使用 `tokio`

- **決定**: 使用 tokio 作為非同步 runtime
- **理由**: AWS SDK for Rust 要求 tokio；支援並行 API 呼叫提升效能

### ADR-004: 保留互動模式但預設 CLI 模式

- **決定**: 所有操作都能以 flag/argument 完成，但缺少必要參數時自動進入互動模式
- **理由**: 同時滿足自動化 (CI/CD) 和人工操作需求
