#!/usr/bin/env python3
"""
修復 readme.md 中剩餘的 Markdown 格式問題
"""

import re

def fix_markdown_comprehensive(content):
    """全面修復 Markdown 格式問題"""
    lines = content.split('\n')
    fixed_lines = []
    i = 0
    
    while i < len(lines):
        line = lines[i]
        
        # 修復 MD022: 標題前後需要空行
        if line.startswith('#'):
            # 標題前需要空行
            if i > 0 and fixed_lines and fixed_lines[-1].strip() != '':
                fixed_lines.append('')
            
            fixed_lines.append(line)
            
            # 標題後需要空行 
            if i < len(lines) - 1 and lines[i+1].strip() != '' and not lines[i+1].startswith('#'):
                fixed_lines.append('')
        
        # 修復 MD032: 列表前後需要空行
        elif (line.startswith('- ') or line.startswith('* ') or re.match(r'^\d+\.', line) or line.startswith('- [')):
            # 列表前需要空行
            if i > 0 and fixed_lines and fixed_lines[-1].strip() != '' and not (fixed_lines[-1].startswith('- ') or fixed_lines[-1].startswith('* ') or re.match(r'^\d+\.', fixed_lines[-1]) or fixed_lines[-1].startswith('- [')):
                fixed_lines.append('')
            
            # 處理整個列表
            list_lines = []
            j = i
            while j < len(lines) and (lines[j].startswith('- ') or lines[j].startswith('* ') or re.match(r'^\d+\.', lines[j]) or lines[j].startswith('- [') or lines[j].strip() == ''):
                if lines[j].strip() != '':
                    list_lines.append(lines[j])
                j += 1
            
            fixed_lines.extend(list_lines)
            
            # 列表後需要空行
            if j < len(lines) and lines[j].strip() != '':
                fixed_lines.append('')
            
            i = j - 1
        
        # 修復 MD031: 代碼塊前後需要空行
        elif line.startswith('```') or line.startswith('````'):
            # 代碼塊前需要空行
            if i > 0 and fixed_lines and fixed_lines[-1].strip() != '':
                fixed_lines.append('')
            
            # MD040: 添加語言標識
            if line.strip() in ['```', '````']:
                line = line + 'bash'
            
            fixed_lines.append(line)
            
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
        
        else:
            fixed_lines.append(line)
        
        i += 1
    
    # MD047: 文件末尾需要單個換行符
    result = '\n'.join(fixed_lines)
    if not result.endswith('\n'):
        result += '\n'
    elif result.endswith('\n\n\n'):
        result = result.rstrip('\n') + '\n'
    
    return result

def main():
    readme_path = '/Users/ctyeh/Documents/NewsLeopard/nlm-codes/nlInc-vpnMgmtTools/readme.md'
    
    try:
        with open(readme_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        print("正在全面修復 Markdown 格式問題...")
        fixed_content = fix_markdown_comprehensive(content)
        
        # 進行額外的特定修復
        print("進行特定問題修復...")
        
        # 修復 JSON 代碼塊
        fixed_content = re.sub(r'```json\n\{\n', '```json\n{\n', fixed_content)
        
        # 修復空的代碼塊語言標識
        fixed_content = re.sub(r'```\n(?=[^`])', '```bash\n', fixed_content)
        fixed_content = re.sub(r'````\n(?=[^`])', '````bash\n', fixed_content)
        
        with open(readme_path, 'w', encoding='utf-8') as f:
            f.write(fixed_content)
        
        print("✅ 全面 Markdown 格式修復完成")
        
    except Exception as e:
        print(f"❌ 修復過程中發生錯誤: {e}")

if __name__ == '__main__':
    main()
