#!/usr/bin/env python3
"""
Comprehensive Markdown format fixer for vpn_connection_manual.md
This script fixes all common Markdown formatting issues
"""

import re

def fix_markdown_comprehensive(file_path):
    """Comprehensive fix for markdown formatting issues"""
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Store the original for comparison
    original_content = content
    
    # Fix 1: Convert bold text to headings where appropriate  
    content = re.sub(r'\*\*(方法[一二三四五六七八九十])：([^*\n]+)\*\*', r'#### \1：\2', content)
    
    # Fix 2: Add language to code blocks without language
    # First, fix simple code blocks
    content = re.sub(r'^```\n([^`])', r'```text\n\1', content, flags=re.MULTILINE)
    content = re.sub(r'^   ```\n([^`])', r'   ```text\n\1', content, flags=re.MULTILINE)
    
    # Fix 3: Add blank lines around headings
    # Before headings
    content = re.sub(r'(\n[^#\n].*)\n(#{1,6} )', r'\1\n\n\2', content)
    # After headings
    content = re.sub(r'(#{1,6} .*)\n([^#\n])', r'\1\n\n\2', content)
    
    # Fix 4: Add blank lines around fenced code blocks
    # Before code blocks (with proper indentation handling)
    content = re.sub(r'(\n[^\n].*)\n(   ```[a-z]*\n)', r'\1\n\n\2', content)
    content = re.sub(r'(\n[^\n].*)\n(```[a-z]*\n)', r'\1\n\n\2', content)
    
    # After code blocks
    content = re.sub(r'(```\n)([^\n])', r'\1\n\2', content)
    content = re.sub(r'(   ```\n)([^\n])', r'\1\n\2', content)
    
    # Fix 5: Add blank lines around lists
    # Split content into lines for more precise list handling
    lines = content.split('\n')
    fixed_lines = []
    
    for i, line in enumerate(lines):
        # Add line to result
        fixed_lines.append(line)
        
        # Check if current line is not a list item and next line is a list item
        if (i < len(lines) - 1 and 
            not re.match(r'^[\s]*[-*]|\d+\.', line) and 
            line.strip() != '' and
            re.match(r'^[\s]*[-*]|\d+\.', lines[i + 1])):
            fixed_lines.append('')  # Add blank line before list
        
        # Check if current line is a list item and next line is not a list item
        if (i < len(lines) - 1 and 
            re.match(r'^[\s]*[-*]|\d+\.', line) and 
            not re.match(r'^[\s]*[-*]|\d+\.', lines[i + 1]) and
            lines[i + 1].strip() != ''):
            fixed_lines.append('')  # Add blank line after list
    
    content = '\n'.join(fixed_lines)
    
    # Fix 6: Fix bare URLs by wrapping in angle brackets
    content = re.sub(r'(\*\*Email\*\*: )([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})', 
                     r'\1<\2>', content)
    
    # Fix 7: Fix ordered list numbering issues
    # This is complex, but let's try to fix the most obvious cases
    content = re.sub(r'^3\. \*\*方法三：系統中斷\*\*', r'3. **方法三：系統中斷**', content, flags=re.MULTILINE)
    content = re.sub(r'^4\. \*\*日誌檔案\*\*', r'1. **日誌檔案**', content, flags=re.MULTILINE)
    
    # Fix 8: Remove trailing spaces
    content = re.sub(r' +\n', '\n', content)
    
    # Fix 9: Remove excessive blank lines (more than 2 consecutive)
    content = re.sub(r'\n{3,}', '\n\n', content)
    
    # Fix 10: Ensure file ends with single newline
    content = content.rstrip() + '\n'
    
    # Write the fixed content back
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"Comprehensive markdown formatting completed for {file_path}")
    print(f"Original length: {len(original_content)} characters")
    print(f"Fixed length: {len(content)} characters")

if __name__ == "__main__":
    file_path = "vpn_connection_manual.md"
    fix_markdown_comprehensive(file_path)
