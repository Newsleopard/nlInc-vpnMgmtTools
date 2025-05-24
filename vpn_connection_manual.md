# 📖 AWS Client VPN 連接完整使用手冊

**版本：** 2.0  
**適用於：** macOS 使用者  
**更新日期：** 2024年12月  

---

## 📋 目錄

1. [概述](#概述)
2. [前置作業檢查](#前置作業檢查)
3. [AWS VPN Client 安裝與設定](#aws-vpn-client-安裝與設定)
4. [VPN 連接步驟](#vpn-連接步驟)
5. [連接驗證](#連接驗證)
6. [日常使用指南](#日常使用指南)
7. [故障排除](#故障排除)
8. [安全最佳實踐](#安全最佳實踐)
9. [常見問題 FAQ](#常見問題-faq)
10. [緊急聯絡資訊](#緊急聯絡資訊)

---

## 概述

本手冊將指導您如何在執行 `team_member_setup.sh` 腳本後，成功連接到公司的 AWS Client VPN。整個過程大約需要 10-15 分鐘完成。

### 💡 重要提醒
- VPN 僅用於訪問生產環境進行除錯和必要的工作
- 請在使用完畢後立即斷開連接
- 嚴禁分享您的 VPN 配置文件或憑證

---

## 前置作業檢查

### ✅ 步驟 1：確認腳本執行完成

執行完 `team_member_setup.sh` 後，您應該看到類似以下的成功訊息：

```
============================================
       AWS Client VPN 設置完成！      
============================================

連接說明：
1. 開啟 AWS VPN 客戶端 (在應用程式文件夾中)
2. 點擊「檔案」>「管理設定檔」
...
設置完成！祝您除錯順利！
```

### ✅ 步驟 2：檢查生成的文件

在您的專案目錄中應該包含以下文件：

```bash
專案目錄/
├── .user_vpn_config                    # ⚠️ 用戶配置（敏感）
├── user_vpn_setup.log                 # 設置日誌
├── user-certificates/                  # 🔒 證書目錄（高度敏感）
│   ├── ca.crt                         # CA 證書
│   ├── [您的用戶名].crt               # 您的個人證書
│   └── [您的用戶名].key               # 🔐 您的私鑰（極度敏感）
└── vpn-config/                         # VPN 配置檔案
    ├── client-config-base.ovpn        # 基礎配置
    └── [您的用戶名]-config.ovpn       # 🎯 您要使用的完整配置
```

### ✅ 步驟 3：驗證文件權限

檢查敏感文件的權限設置是否正確：

```bash
# 在終端機中執行以下命令：
ls -la .user_vpn_config
ls -la user-certificates/
ls -la vpn-config/[您的用戶名]-config.ovpn

# 正確的權限應該顯示：
# -rw-------  (600) - 僅所有者可讀寫
```

如果權限不正確，請執行：
```bash
chmod 600 .user_vpn_config
chmod 600 user-certificates/*
chmod 600 vpn-config/[您的用戶名]-config.ovpn
```

---

## AWS VPN Client 安裝與設定

### 📱 步驟 1：確認 AWS VPN Client 已安裝

1. **檢查應用程式是否存在**
   ```bash
   # 在終端機中執行：
   ls -la "/Applications/AWS VPN Client.app"
   ```

2. **如果應用程式存在**
   - 您應該看到類似：`drwxr-xr-x ... AWS VPN Client.app`
   - 跳到「步驟 2」

3. **如果應用程式不存在**
   - 檢查 Downloads 資料夾是否有安裝檔：
   ```bash
   ls -la ~/Downloads/AWS_VPN_Client.pkg
   ```
   - 如果存在，雙擊安裝檔進行安裝
   - 如果不存在，請聯繫 IT 管理員

### 📱 步驟 2：啟動 AWS VPN Client

1. **方法一：使用 Spotlight**
   - 按 `⌘ + 空格鍵` 開啟 Spotlight
   - 輸入 "AWS VPN Client"
   - 按 `Enter` 啟動

2. **方法二：使用 Finder**
   - 開啟 Finder
   - 點擊左側的「應用程式」
   - 找到並雙擊「AWS VPN Client」

3. **方法三：使用 Launchpad**
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

### 🔧 步驟 1：開啟設定檔管理

1. 在 AWS VPN Client 中，點擊選單列的：
   ```
   檔案 (File) → 管理設定檔 (Manage Profiles)
   ```
   
2. 或使用快捷鍵：`⌘ + ,`

3. 設定檔管理視窗將會開啟

### 🔧 步驟 2：添加新的設定檔

1. **點擊「添加設定檔」按鈕**
   - 位於設定檔管理視窗的左下角
   - 按鈕文字為「Add Profile」或「添加設定檔」

2. **選擇導入方式**
   - 選擇「從檔案導入」(Import from file)
   - 或「選擇檔案」(Choose file)

### 🔧 步驟 3：選擇配置檔案

1. **導航到您的專案目錄**
   - 在檔案選擇器中，找到您執行腳本的資料夾
   - 進入 `vpn-config/` 子資料夾

2. **選擇正確的配置檔案**
   - 檔案名稱格式：`[您的用戶名]-config.ovpn`
   - 例如：`john.doe-config.ovpn`
   - **⚠️ 重要：不要選擇 `client-config-base.ovpn`**

3. **確認並開啟**
   - 點擊「開啟」(Open) 按鈕

### 🔧 步驟 4：設定設定檔資訊

1. **輸入設定檔名稱**
   - 在「設定檔名稱」欄位中輸入：
   ```
   Production VPN - [您的姓名]
   ```
   - 例如：`Production VPN - John Doe`

2. **檢查配置資訊**
   - 確認顯示的伺服器位址正確
   - 確認沒有錯誤提示

3. **完成添加**
   - 點擊「添加設定檔」(Add Profile) 按鈕
   - 關閉設定檔管理視窗

### 🔧 步驟 5：連接到 VPN

1. **選擇設定檔**
   - 在 AWS VPN Client 主視窗中
   - 從下拉選單選擇您剛才添加的設定檔

2. **開始連接**
   - 點擊「連接」(Connect) 按鈕
   - 狀態指示器會變化：
     - 🔴 紅色：未連接
     - 🟡 黃色：正在連接...
     - 🟢 綠色：已連接

3. **等待連接完成**
   - 初次連接可能需要 30-60 秒
   - 請耐心等待，不要重複點擊

---

## 連接驗證

### ✅ 確認連接狀態

連接成功後，您應該看到：

1. **AWS VPN Client 顯示**
   ```
   狀態：已連接 (Connected)
   伺服器：[VPN伺服器地址]
   分配的 IP：172.16.x.x
   連接時間：00:01:23
   ```

2. **系統通知**
   - macOS 可能會顯示「VPN 已連接」的通知

### ✅ 網路連接測試

在終端機中執行以下測試：

1. **檢查 VPN 介面**
   ```bash
   ifconfig | grep -A 3 utun
   ```
   應該顯示類似：
   ```
   utun3: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1436
   inet 172.16.0.10 --> 172.16.0.10 netmask 0xffffff00
   ```

2. **檢查路由表**
   ```bash
   netstat -rn | grep utun
   ```

3. **測試內部資源訪問**
   ```bash
   # 請向 IT 管理員索取測試 IP 地址
   ping 10.0.1.10
   
   # 或測試內部服務
   curl -I http://internal-api.company.com
   ```

### ✅ DNS 解析測試

```bash
# 測試內部域名解析（如果有的話）
nslookup internal.company.com

# 檢查 DNS 設定
scutil --dns | grep nameserver
```

---

## 日常使用指南

### 🔄 正常連接流程

1. **開啟 AWS VPN Client**
2. **選擇您的設定檔**
3. **點擊連接**
4. **等待狀態變為綠色**
5. **開始工作**
6. **完成後立即斷開**

### 🔄 中斷連接

1. **方法一：正常中斷**
   - 在 AWS VPN Client 中點擊「中斷連接」(Disconnect)

2. **方法二：強制中斷**
   - 如果無法正常中斷，可以完全退出應用程式
   - `⌘ + Q` 或選單中的「退出」

3. **方法三：系統中斷**
   ```bash
   # 在終端機中執行（緊急情況）
   sudo pkill -f "AWS VPN Client"
   ```

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

### ❌ 問題 1：無法導入配置檔案

**症狀：**
- 選擇 .ovpn 檔案後出現錯誤
- 提示「無效的配置檔案」

**解決步驟：**

1. **檢查檔案完整性**
   ```bash
   ls -la vpn-config/[您的用戶名]-config.ovpn
   cat vpn-config/[您的用戶名]-config.ovpn | head -10
   ```

2. **檢查檔案內容**
   - 確保檔案包含 `<cert>` 和 `<key>` 區塊
   - 確保檔案末尾沒有多餘的空行

3. **重新生成配置**
   ```bash
   # 重新執行設置腳本
   ./team_member_setup.sh
   ```

4. **檢查權限**
   ```bash
   chmod 600 vpn-config/[您的用戶名]-config.ovpn
   ```

### ❌ 問題 2：連接失敗 - 認證錯誤

**症狀：**
- 狀態顯示「連接失敗」
- 錯誤訊息包含 "authentication failed" 或 "certificate"

**解決步驟：**

1. **檢查證書有效期**
   ```bash
   openssl x509 -in user-certificates/[您的用戶名].crt -noout -dates
   ```

2. **驗證證書匹配**
   ```bash
   # 檢查證書和私鑰是否匹配
   openssl x509 -noout -modulus -in user-certificates/[您的用戶名].crt | openssl md5
   openssl rsa -noout -modulus -in user-certificates/[您的用戶名].key | openssl md5
   # 兩個 MD5 值應該相同
   ```

3. **聯繫 IT 管理員**
   - 確認您的證書是否已正確導入到 AWS ACM
   - 確認您的用戶是否有權限訪問 VPN 端點

### ❌ 問題 3：連接成功但無法訪問內部資源

**症狀：**
- VPN 狀態顯示已連接
- 但無法 ping 到內部 IP 或訪問內部服務

**解決步驟：**

1. **檢查分配的 IP**
   ```bash
   ifconfig | grep -A 2 utun
   ```
   確認您獲得了正確的 VPN IP 段（通常是 172.16.x.x）

2. **檢查路由表**
   ```bash
   route -n get 10.0.0.0
   netstat -rn | grep utun
   ```

3. **測試 VPN 伺服器連接**
   ```bash
   # 嘗試 ping VPN 閘道
   route -n get default | grep gateway
   ```

4. **聯繫 IT 管理員檢查**
   - VPN 端點的授權規則
   - 目標資源的安全群組設定
   - 路由表配置

### ❌ 問題 4：DNS 解析問題

**症狀：**
- 無法解析內部域名
- 外部網站可以訪問但內部網站不行

**解決步驟：**

1. **檢查 DNS 設定**
   ```bash
   scutil --dns | grep nameserver
   ```

2. **刷新 DNS 快取**
   ```bash
   sudo dscacheutil -flushcache
   sudo killall -HUP mDNSResponder
   ```

3. **手動測試 DNS**
   ```bash
   # 使用指定 DNS 伺服器測試
   nslookup internal.company.com 8.8.8.8
   ```

4. **重新連接 VPN**
   - 中斷連接
   - 等待 10 秒
   - 重新連接

### ❌ 問題 5：連接速度慢

**症狀：**
- VPN 連接成功但網路速度明顯變慢
- 存取內部資源響應時間過長

**解決步驟：**

1. **檢查本地網路**
   ```bash
   # 測試本地網路速度
   ping 8.8.8.8
   ```

2. **測試 VPN 延遲**
   ```bash
   # ping VPN 閘道
   ping [VPN閘道IP]
   ```

3. **優化設定**
   - 關閉不必要的背景應用程式
   - 使用有線網路而非 Wi-Fi
   - 暫時關閉防毒軟體的即時掃描

4. **檢查 MTU 設定**
   ```bash
   # 測試最佳 MTU 大小
   ping -D -s 1464 8.8.8.8
   ```

### ❌ 問題 6：macOS 權限問題

**症狀：**
- 無法啟動 AWS VPN Client
- 出現權限相關錯誤

**解決步驟：**

1. **檢查應用程式權限**
   - 前往「系統偏好設定」>「安全性與隱私權」
   - 確認 AWS VPN Client 被允許

2. **重新安裝應用程式**
   ```bash
   # 卸載現有版本
   sudo rm -rf "/Applications/AWS VPN Client.app"
   
   # 重新安裝
   sudo installer -pkg ~/Downloads/AWS_VPN_Client.pkg -target /
   ```

3. **檢查系統版本相容性**
   - 確認您的 macOS 版本支援 AWS VPN Client
   - 最低要求：macOS 10.15 (Catalina)

---

## 安全最佳實踐

### 🔐 憑證和配置文件安全

1. **文件權限**
   ```bash
   # 定期檢查敏感文件權限
   find . -name "*.ovpn" -o -name "*.key" -o -name "*.crt" | xargs ls -la
   
   # 確保權限正確
   chmod 600 vpn-config/*.ovpn
   chmod 600 user-certificates/*.key
   chmod 600 user-certificates/*.crt
   ```

2. **文件備份**
   ```bash
   # 創建加密備份（可選）
   tar -czf vpn-backup-$(date +%Y%m%d).tar.gz user-certificates/ vpn-config/
   gpg --symmetric --cipher-algo AES256 vpn-backup-$(date +%Y%m%d).tar.gz
   rm vpn-backup-$(date +%Y%m%d).tar.gz
   ```

3. **絕對禁止的行為**
   - ❌ 不要通過電子郵件發送配置文件
   - ❌ 不要將文件上傳到雲端儲存（Dropbox、Google Drive 等）
   - ❌ 不要將文件提交到 Git 儲存庫
   - ❌ 不要在多台電腦上使用同一個配置文件
   - ❌ 不要分享您的用戶憑證給其他人

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
   ```

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

### ❓ Q1：我可以在多台電腦上使用同一個配置文件嗎？

**A1：** 不建議，也不安全。每台電腦都應該有獨立的憑證和配置。如果您需要在多台電腦上使用 VPN，請為每台電腦分別執行 `team_member_setup.sh`。

### ❓ Q2：VPN 連接會影響我訪問外部網站的速度嗎？

**A2：** 會有一定影響，因為：
- 流量需要經過 VPN 伺服器路由
- 加密/解密會增加延遲
- 建議只在需要訪問內部資源時連接

### ❓ Q3：我忘記了配置文件的位置，如何找到？

**A3：** 執行以下命令：
```bash
find ~ -name "*-config.ovpn" -type f 2>/dev/null
```

### ❓ Q4：可以同時連接多個 VPN 嗎？

**A4：** 技術上可能，但不建議，可能會導致：
- 路由衝突
- 連接不穩定
- 安全風險
建議一次只連接一個 VPN。

### ❓ Q5：如何更新過期的證書？

**A5：** 
1. 聯繫 IT 管理員確認證書狀態
2. 重新執行 `team_member_setup.sh`
3. 在 AWS VPN Client 中更新設定檔

### ❓ Q6：VPN 連接時是否會記錄我的活動？

**A6：** 是的，VPN 連接會被記錄，包括：
- 連接時間和持續時間
- 訪問的內部資源
- 流量統計
這些記錄用於安全監控和故障排除。

### ❓ Q7：我可以在個人時間使用公司 VPN 嗎？

**A7：** 請遵循公司的 IT 使用政策。通常 VPN 僅用於工作相關活動。

### ❓ Q8：如何檢查我的證書何時過期？

**A8：**
```bash
openssl x509 -in user-certificates/[您的用戶名].crt -noout -enddate
```

### ❓ Q9：VPN 斷開後我需要重新啟動應用程式嗎？

**A9：** 通常不需要。如果遇到連接問題，可以嘗試：
1. 先中斷連接
2. 等待 10 秒
3. 重新連接
如果仍有問題，再考慮重新啟動應用程式。

### ❓ Q10：我可以在虛擬機器中使用 VPN 嗎？

**A10：** 技術上可行，但可能需要額外的網路配置。建議在主機系統中直接使用 VPN。

**祝您使用順利！** 🎉