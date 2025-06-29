# Contributing to AWS Client VPN Automation

We welcome contributions to the AWS Client VPN Automation project! This document provides guidelines for contributing.

## 🤝 How to Contribute

### Reporting Issues
- Use GitHub Issues to report bugs or request features
- Provide detailed information about your environment and the issue
- Include steps to reproduce the problem

### Submitting Changes
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests if applicable
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Development Setup
1. Clone the repository
2. Install dependencies: `npm install`
3. Set up your AWS credentials and profiles
4. Follow the setup instructions in the README.md

## 📋 Code Standards

### TypeScript/JavaScript
- Use TypeScript for all Lambda functions
- Follow existing code style and patterns
- Add proper error handling and logging
- Include JSDoc comments for functions

### Documentation
- Update README.md for significant changes
- Add or update relevant documentation in `/docs`
- Use clear, concise language
- Include examples where helpful

### Testing
- Add unit tests for new functionality
- Ensure existing tests pass
- Test in both staging and production-like environments

## 🔒 Security Guidelines

- Never commit secrets, keys, or credentials
- Use AWS SSM Parameter Store for sensitive configuration
- Follow AWS security best practices
- Report security issues privately via GitHub Security Advisories

## 📝 Pull Request Guidelines

### Before Submitting
- [ ] Code follows project style guidelines
- [ ] Tests pass locally
- [ ] Documentation is updated
- [ ] No sensitive information is included
- [ ] Changes are tested in a real AWS environment

### PR Description
- Clearly describe what the PR does
- Reference any related issues
- Include screenshots for UI changes
- List any breaking changes

## 🏗️ Architecture Guidelines

When contributing to the core architecture:
- Maintain separation between staging and production environments
- Follow the serverless-first approach
- Ensure cost optimization features remain intact
- Consider multi-region compatibility

## 💬 Community

- Be respectful and inclusive
- Help others learn and contribute
- Share knowledge and best practices
- Follow the project's code of conduct

## 📞 Getting Help

- Check existing documentation first
- Search existing issues
- Ask questions in GitHub Discussions
- Be specific about your environment and use case

Thank you for contributing to AWS Client VPN Automation! 🎉
