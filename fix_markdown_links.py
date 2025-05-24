#!/usr/bin/env python3
"""
修復 VPN 連接手冊的 Markdown 格式問題
"""

import re

def fix_markdown_links():
    file_path = "/Users/ctyeh/Documents/NewsLeopard/nlm-codes/nlInc-vpnMgmtTools/vpn_connection_manual.md"
    
    # 讀取文件
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 建立標題對應關係 - 實際標題到 URL friendly 錨點的映射
    title_mappings = {
        '前置作業檢查': '前置作業檢查',
        'AWS VPN Client 安裝與設定': 'aws-vpn-client-安裝與設定',
        'VPN 連接步驟': 'vpn-連接步驟',
        '連接驗證': '連接驗證',
        '日常使用指南': '日常使用指南',
        '環境切換操作': '環境切換操作',
        '故障排除': '故障排除',
        '安全最佳實踐': '安全最佳實踐',
        '常見問題 FAQ': '常見問題-faq',
        '緊急聯絡資訊': '緊急聯絡資訊'
    }
    
    # 修復目錄中的鏈接
    for title, anchor in title_mappings.items():
        # 查找目錄中的鏈接並替換
        pattern = rf'(\d+\.\s+\[{re.escape(title)}\]\(#)[^)]+(\))'
        replacement = rf'\1{anchor}\2'
        content = re.sub(pattern, replacement, content)
    
    # 修復有序列表問題 - 查找並修復 "2. **enhanced_env_selector.sh..." 的編號
    # 找到這個特定的列表項目並修復
    content = re.sub(
        r'2\. \*\*enhanced_env_selector\.sh - 互動式環境選擇器\*\*',
        '1. **enhanced_env_selector.sh - 互動式環境選擇器**',
        content
    )
    
    # 保存修復後的文件
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("✅ Markdown 格式修復完成！")
    print("修復內容：")
    print("- 目錄中的中文標題鏈接")
    print("- 有序列表編號問題")

if __name__ == "__main__":
    fix_markdown_links()
