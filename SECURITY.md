# Security Policy

## Supported Versions

We actively support the following versions with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 3.x.x   | :white_check_mark: |
| 2.x.x   | :x:                |
| 1.x.x   | :x:                |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability, please follow these steps:

### For Security Issues
1. **DO NOT** create a public GitHub issue
2. Use GitHub's Security Advisories feature to report privately
3. Or email security concerns to the maintainers
4. Include detailed information about the vulnerability

### What to Include
- Description of the vulnerability
- Steps to reproduce the issue
- Potential impact assessment
- Suggested fix (if you have one)

### Response Timeline
- **Initial Response**: Within 48 hours
- **Status Update**: Within 7 days
- **Fix Timeline**: Varies based on severity

## Security Best Practices

### For Users
- Never commit AWS credentials or secrets to version control
- Use IAM roles with minimal required permissions
- Regularly rotate access keys and certificates
- Enable CloudTrail logging for audit purposes
- Use encrypted S3 buckets for certificate exchange

### For Contributors
- Follow secure coding practices
- Use AWS SSM Parameter Store for sensitive configuration
- Implement proper input validation
- Add security-focused tests
- Review code for potential security issues

## Security Features

This project includes several security features:
- **No Hardcoded Secrets**: All sensitive data stored in AWS SSM
- **KMS Encryption**: Sensitive parameters encrypted at rest
- **IAM Best Practices**: Minimal permission policies
- **Certificate Management**: Secure certificate exchange via S3
- **Audit Logging**: Comprehensive CloudWatch and CloudTrail integration
- **Environment Isolation**: Complete separation between staging and production

## Vulnerability Disclosure

We follow responsible disclosure practices:
1. Security researchers report vulnerabilities privately
2. We work together to understand and fix the issue
3. We coordinate public disclosure after fixes are available
4. We acknowledge security researchers (with permission)

## Security Updates

Security updates will be:
- Released as soon as possible after verification
- Documented in release notes with severity levels
- Communicated through GitHub Security Advisories
- Tagged with appropriate version numbers

Thank you for helping keep AWS Client VPN Automation secure!
