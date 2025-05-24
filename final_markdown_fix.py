#!/usr/bin/env python3
"""
最終修復 readme.md 中所有 Markdown 格式問題
"""

import re
import os

def fix_all_markdown_issues(file_path):
    """修復所有 Markdown 格式問題"""
    print(f"🔧 開始修復 {file_path}...")
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 修復所有問題
    lines = content.split('\n')
    fixed_lines = []
    
    i = 0
    while i < len(lines):
        current_line = lines[i]
        
        # 處理代碼塊 - MD031 和 MD040
        if current_line.strip() in ['```', '````']:
            # 代碼塊前需要空行
            if fixed_lines and fixed_lines[-1].strip() != '':
                fixed_lines.append('')
            
            # 添加語言標識 (MD040)
            fixed_lines.append(current_line.strip() + 'bash')
            
            # 處理代碼塊內容
            i += 1
            while i < len(lines) and not (lines[i].startswith('```') or lines[i].startswith('````')):
                fixed_lines.append(lines[i])
                i += 1
            
            # 添加結束標記
            if i < len(lines):
                fixed_lines.append(lines[i])
                
                # 代碼塊後需要空行
                if i + 1 < len(lines) and lines[i + 1].strip() != '':
                    fixed_lines.append('')
        
        # 處理標題 - MD022
        elif current_line.startswith('#'):
            # 標題前需要空行
            if fixed_lines and fixed_lines[-1].strip() != '':
                fixed_lines.append('')
            
            fixed_lines.append(current_line)
            
            # 標題後需要空行
            if i + 1 < len(lines) and lines[i + 1].strip() != '' and not lines[i + 1].startswith('#'):
                fixed_lines.append('')
        
        # 處理列表 - MD032
        elif (current_line.strip().startswith('- ') or 
              current_line.strip().startswith('* ') or 
              re.match(r'^\d+\.', current_line.strip()) or
              current_line.strip().startswith('- [')):
            
            # 列表前需要空行
            if (fixed_lines and fixed_lines[-1].strip() != '' and 
                not (fixed_lines[-1].strip().startswith('- ') or 
                     fixed_lines[-1].strip().startswith('* ') or
                     re.match(r'^\d+\.', fixed_lines[-1].strip()) or
                     fixed_lines[-1].strip().startswith('- ['))):
                fixed_lines.append('')
            
            # 收集整個列表
            list_items = []
            j = i
            while j < len(lines):
                line = lines[j]
                if (line.strip().startswith('- ') or 
                    line.strip().startswith('* ') or 
                    re.match(r'^\d+\.', line.strip()) or
                    line.strip().startswith('- [')):
                    list_items.append(line)
                    j += 1
                elif line.strip() == '':
                    j += 1
                    break
                else:
                    break
            
            fixed_lines.extend(list_items)
            
            # 列表後需要空行
            if j < len(lines) and lines[j].strip() != '':
                fixed_lines.append('')
            
            i = j - 1
        
        else:
            fixed_lines.append(current_line)
        
        i += 1
    
    # MD047: 確保文件末尾只有一個換行符
    result = '\n'.join(fixed_lines)
    if not result.endswith('\n'):
        result += '\n'
    elif result.count('\n') > 1 and result.endswith('\n\n'):
        result = result.rstrip('\n') + '\n'
    
    # 寫回文件
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(result)
    
    print(f"✅ {file_path} 修復完成！")

if __name__ == '__main__':
    readme_path = '/Users/ctyeh/Documents/NewsLeopard/nlm-codes/nlInc-vpnMgmtTools/readme.md'
    
    if os.path.exists(readme_path):
        fix_all_markdown_issues(readme_path)
    else:
        print(f"❌ 文件不存在: {readme_path}")
