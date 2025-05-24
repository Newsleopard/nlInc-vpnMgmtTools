#!/usr/bin/env python3
"""
修復 readme.md 中的 Markdown 格式問題
"""

import re

def fix_markdown_formatting(content):
    """修復 Markdown 格式問題"""
    lines = content.split('\n')
    fixed_lines = []
    
    i = 0
    while i < len(lines):
        line = lines[i]
        
        # MD022: 標題前後需要空行
        if line.startswith('#') and i > 0 and lines[i-1].strip() != '':
            fixed_lines.append('')
        
        fixed_lines.append(line)
        
        # MD022: 標題後需要空行
        if line.startswith('#') and i < len(lines) - 1 and lines[i+1].strip() != '' and not lines[i+1].startswith('#'):
            fixed_lines.append('')
        
        # MD032: 列表前後需要空行
        if (line.startswith('- ') or line.startswith('* ') or re.match(r'^\d+\. ', line)):
            # 列表前需要空行
            if i > 0 and fixed_lines[-2].strip() != '' and not (fixed_lines[-2].startswith('- ') or fixed_lines[-2].startswith('* ') or re.match(r'^\d+\. ', fixed_lines[-2])):
                fixed_lines.insert(-1, '')
            
            # 找到列表結束位置
            j = i + 1
            while j < len(lines) and (lines[j].startswith('- ') or lines[j].startswith('* ') or re.match(r'^\d+\. ', lines[j]) or lines[j].strip() == ''):
                if lines[j].strip() != '':
                    fixed_lines.append(lines[j])
                j += 1
            
            # 列表後需要空行
            if j < len(lines) and lines[j].strip() != '':
                fixed_lines.append('')
            
            i = j - 1
        
        # MD031: 代碼塊前後需要空行
        elif line.startswith('```') or line.startswith('````'):
            # 代碼塊開始前需要空行
            if i > 0 and fixed_lines[-2].strip() != '':
                fixed_lines.insert(-1, '')
            
            # 找到代碼塊結束
            j = i + 1
            while j < len(lines) and not (lines[j].startswith('```') or lines[j].startswith('````')):
                fixed_lines.append(lines[j])
                j += 1
            
            if j < len(lines):
                fixed_lines.append(lines[j])  # 結束標記
                
                # 代碼塊後需要空行
                if j + 1 < len(lines) and lines[j + 1].strip() != '':
                    fixed_lines.append('')
            
            i = j
        
        # MD040: 代碼塊需要指定語言
        elif line == '```' or line == '````':
            # 如果是空的代碼塊標記，添加 bash 語言
            fixed_lines[-1] = line + 'bash'
        
        i += 1
    
    # MD047: 文件末尾需要單個換行符
    result = '\n'.join(fixed_lines)
    if not result.endswith('\n'):
        result += '\n'
    elif result.endswith('\n\n'):
        result = result.rstrip('\n') + '\n'
    
    return result

def main():
    readme_path = '/Users/ctyeh/Documents/NewsLeopard/nlm-codes/nlInc-vpnMgmtTools/readme.md'
    
    try:
        with open(readme_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        print("正在修復 Markdown 格式問題...")
        fixed_content = fix_markdown_formatting(content)
        
        with open(readme_path, 'w', encoding='utf-8') as f:
            f.write(fixed_content)
        
        print("✅ Markdown 格式修復完成")
        
    except Exception as e:
        print(f"❌ 修復過程中發生錯誤: {e}")

if __name__ == '__main__':
    main()
