---
name: Setup Help
about: Get help with initial setup and configuration
title: '[SETUP] '
labels: setup, question
assignees: ''
---

## ⚠️ Project Status Notice
This is a **reference implementation** and is not actively maintained. Community members may help answer questions, but there's no guarantee of response.

## Setup Issue Type
- [ ] Account ID replacement
- [ ] AWS profile configuration
- [ ] Slack integration setup
- [ ] Deployment issues
- [ ] Permission problems
- [ ] Other setup issue

## What You're Trying to Do
<!-- Describe what you're trying to set up -->

## What's Not Working
<!-- Describe the specific error or issue -->

## Your Environment
- AWS Region: 
- Number of AWS accounts: 
- macOS version:
- Node.js version:

## Configuration Details
**Have you completed these steps?**
- [ ] Replaced `YOUR_STAGING_ACCOUNT_ID` with actual account ID
- [ ] Replaced `YOUR_PRODUCTION_ACCOUNT_ID` with actual account ID  
- [ ] Configured AWS profiles
- [ ] Set up Slack app and tokens
- [ ] Updated environment configuration files

## Error Messages
<!-- Paste any error messages you're seeing -->

## Additional Context
<!-- Any other context about your setup -->

---
**💡 Quick Fixes:**
- **Account ID issues**: Check [維護部署手冊 - 新用戶快速設置](../../docs/maintenance-deployment-manual.md#新用戶快速設置) for complete list of placeholders to replace
- **Permission errors**: Ensure your AWS user has VPN, Lambda, and S3 permissions
- **Slack errors**: Verify tokens are stored in SSM Parameter Store correctly
