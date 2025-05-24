#!/usr/bin/env python3
"""
Markdown format fixer for vpn_connection_manual.md
This script fixes common Markdown formatting issues
"""

import re
import sys

def fix_markdown_file(file_path):
    """Fix markdown formatting issues in the file"""
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Fix 1: Add blank lines around fenced code blocks
    # Find code blocks that don't have blank lines before them
    content = re.sub(r'(\n[^\n].*)\n(   ```)', r'\1\n\n\2', content)
    content = re.sub(r'(\n[^\n].*)\n(```)', r'\1\n\n\2', content)
    
    # Find code blocks that don't have blank lines after them
    content = re.sub(r'(```\n)([^\n])', r'\1\n\2', content)
    content = re.sub(r'(   ```\n)([^\n])', r'\1\n\2', content)
    
    # Fix 2: Add language specification to code blocks without language
    content = re.sub(r'(   ```)\n([^`])', r'\1text\n\2', content)
    content = re.sub(r'^```\n([^`])', r'```text\n\1', content, flags=re.MULTILINE)
    
    # Fix 3: Add blank lines around lists
    # Before lists
    content = re.sub(r'(\n[^\n-*1-9 ].*)\n(- )', r'\1\n\n\2', content)
    content = re.sub(r'(\n[^\n-*1-9 ].*)\n(\d+\. )', r'\1\n\n\2', content)
    
    # After lists (before non-list content)
    content = re.sub(r'(\n- .*)\n([^\n-*1-9 ])', r'\1\n\n\2', content)
    content = re.sub(r'(\n\d+\. .*)\n([^\n-*1-9 ])', r'\1\n\n\2', content)
    
    # Fix 4: Convert emphasis to headings where appropriate
    content = re.sub(r'\*\*(方法[一二三四五六七八九十])：([^*]+)\*\*', r'#### \1：\2', content)
    
    # Fix 5: Add blank lines around headings
    content = re.sub(r'(\n[^#\n].*)\n(#{1,6} )', r'\1\n\n\2', content)
    content = re.sub(r'(#{1,6} .*)\n([^#\n])', r'\1\n\n\2', content)
    
    # Fix 6: Fix bare URLs (basic fix)
    content = re.sub(r'- \*\*Email\*\*: ([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})', 
                     r'- **Email**: <\1>', content)
    
    # Fix 7: Remove trailing spaces
    content = re.sub(r' +\n', '\n', content)
    
    # Fix 8: Ensure file ends with single newline
    content = content.rstrip() + '\n'
    
    # Write the fixed content back
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"Markdown formatting fixed for {file_path}")

if __name__ == "__main__":
    file_path = "vpn_connection_manual.md"
    fix_markdown_file(file_path)
