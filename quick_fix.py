#!/usr/bin/env python3
"""
快速修復 readme.md 中所有空的代碼塊
"""

import re

def fix_empty_code_blocks():
    file_path = '/Users/ctyeh/Documents/NewsLeopard/nlm-codes/nlInc-vpnMgmtTools/readme.md'
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 修復空的代碼塊，添加語言標識
    # 替換獨立的 ``` 行為 ```bash
    content = re.sub(r'^```$', '```bash', content, flags=re.MULTILINE)
    
    # 修復列表前後空行問題 (MD032)
    lines = content.split('\n')
    fixed_lines = []
    
    for i, line in enumerate(lines):
        # 檢查是否是列表項
        if (line.strip().startswith('- ') or 
            line.strip().startswith('* ') or 
            re.match(r'^\d+\.', line.strip())):
            
            # 如果前一行不是空行且不是列表項，添加空行
            if (i > 0 and 
                fixed_lines and 
                fixed_lines[-1].strip() != '' and 
                not (fixed_lines[-1].strip().startswith('- ') or 
                     fixed_lines[-1].strip().startswith('* ') or 
                     re.match(r'^\d+\.', fixed_lines[-1].strip()))):
                fixed_lines.append('')
        
        fixed_lines.append(line)
        
        # 檢查是否是列表項結束，需要添加空行
        if (line.strip().startswith('- ') or 
            line.strip().startswith('* ') or 
            re.match(r'^\d+\.', line.strip())):
            
            # 如果下一行不是空行且不是列表項，添加空行
            if (i + 1 < len(lines) and 
                lines[i + 1].strip() != '' and 
                not (lines[i + 1].strip().startswith('- ') or 
                     lines[i + 1].strip().startswith('* ') or 
                     re.match(r'^\d+\.', lines[i + 1].strip())) and
                not lines[i + 1].startswith('#')):
                fixed_lines.append('')
    
    # 修復標題前後空行問題 (MD022)
    final_lines = []
    for i, line in enumerate(fixed_lines):
        if line.startswith('#'):
            # 標題前添加空行
            if i > 0 and final_lines and final_lines[-1].strip() != '':
                final_lines.append('')
            
            final_lines.append(line)
            
            # 標題後添加空行
            if (i + 1 < len(fixed_lines) and 
                fixed_lines[i + 1].strip() != '' and 
                not fixed_lines[i + 1].startswith('#')):
                final_lines.append('')
        else:
            final_lines.append(line)
    
    # 確保文件以單個換行符結尾 (MD047)
    result = '\n'.join(final_lines)
    if not result.endswith('\n'):
        result += '\n'
    elif result.endswith('\n\n\n'):
        result = result.rstrip('\n') + '\n'
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(result)
    
    print("✅ 所有空的代碼塊已修復為 bash 語言標識")
    print("✅ 列表和標題的空行問題已修復")
    print("✅ 文件結尾格式已修復")

if __name__ == '__main__':
    fix_empty_code_blocks()
