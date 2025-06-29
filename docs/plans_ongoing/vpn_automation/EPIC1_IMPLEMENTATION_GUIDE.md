# Epic 1: Core Infrastructure & Lambda Foundation - Implementation Guide

## 🎯 Overview

Epic 1 has been successfully implemented, providing the foundational serverless architecture for VPN cost automation. This implementation includes CDK infrastructure, Lambda functions, Parameter Store integration, and deployment automation.

## ✅ Completed Components

### 1. CDK Project Structure (`cdklib/`)
- **Package Configuration**: Complete TypeScript CDK project with proper dependencies
- **Stack Definition**: Environment-aware CDK stack supporting staging and production
- **Build System**: TypeScript compilation and CDK synthesis
- **Configuration**: CDK context and deployment settings

### 2. Lambda Shared Layer (`lambda/shared/`)
- **📄 types.ts**: TypeScript interfaces for Parameter Store schema and API contracts
- **📄 stateStore.ts**: Parameter Store wrapper with read/write operations and validation
- **📄 vpnManager.ts**: Core VPN operations (associate/disassociate/status) with AWS EC2 integration
- **📄 slack.ts**: Slack integration utilities for signature verification and message formatting

### 3. Lambda Functions

#### slack-handler (`lambda/slack-handler/`)
- **Purpose**: Entry point for Slack commands with signature verification
- **Features**: 
  - Command parsing and validation
  - Cross-account routing logic
  - Local and remote VPN control invocation
  - Slack response formatting

#### vpn-control (`lambda/vpn-control/`)
- **Purpose**: Core VPN operations (open/close/check)
- **Features**:
  - Subnet association/disassociation
  - VPN status monitoring
  - CloudWatch metrics publishing
  - Error handling and notifications

#### vpn-monitor (`lambda/vpn-monitor/`)
- **Purpose**: Scheduled monitoring for idle detection and cost optimization
- **Features**:
  - 5-minute scheduled execution
  - Idle time calculation
  - Automatic subnet disassociation
  - Business hours awareness
  - Comprehensive metrics and alerting

### 4. CDK Infrastructure Stack (`cdklib/lib/vpn-automation-stack.ts`)
- **Lambda Functions**: All three Lambda functions with proper IAM roles
- **API Gateway**: RESTful API with Slack and cross-account endpoints
- **IAM Roles**: Least-privilege roles for each Lambda function
- **CloudWatch Events**: Scheduled monitoring rule
- **Parameter Store**: Initial parameter creation
- **API Keys**: Cross-account authentication for production
- **Outputs**: API Gateway URLs and configuration details

### 5. Deployment Pipeline (`scripts/`)
- **📄 deploy.sh**: Comprehensive deployment script with multi-environment support
- **📄 setup-parameters.sh**: Parameter Store configuration script
- **Features**:
  - Environment validation
  - CDK bootstrapping
  - Cross-account URL dependency resolution
  - AWS profile management
  - Rollback and monitoring capabilities

## 🏗️ Architecture Implementation

### Parameter Store Schema
```json
{
  "/vpn/endpoint/conf": {
    "ENDPOINT_ID": "cvpn-endpoint-xyz",
    "SUBNET_ID": "subnet-abc123"
  },
  "/vpn/endpoint/state": {
    "associated": false,
    "lastActivity": "2025-06-17T10:00:00.000Z"
  },
  "/vpn/slack/webhook": "https://hooks.slack.com/...",
  "/vpn/slack/signing_secret": "slack_signing_secret"
}
```

### Multi-Environment Support
- **Staging Environment**: Development and testing with simplified security
- **Production Environment**: Enhanced security with API key authentication
- **Cross-Account Routing**: Staging can control production via HTTPS API calls
- **Environment Isolation**: Separate Parameter Store namespaces and IAM roles

### Security Implementation
- **IAM Least Privilege**: Function-specific roles with minimal required permissions
- **Slack Signature Verification**: HMAC-SHA256 signature validation
- **API Key Authentication**: Cross-account API protection
- **Parameter Encryption**: Sensitive data stored as SecureString parameters
- **Request Validation**: Input sanitization and environment matching

## 🚀 Deployment Instructions

### Prerequisites
1. **AWS CLI** configured with staging and production profiles
2. **AWS CDK CLI** installed globally (`npm install -g aws-cdk`)
3. **Node.js 18+** for TypeScript compilation
4. **Slack App** configured with webhook and signing secret

### Step 1: Configure Parameters
```bash
# Set up staging environment parameters
./scripts/setup-parameters.sh staging \
  --endpoint-id cvpn-endpoint-0123456789abcdef \
  --subnet-id subnet-0123456789abcdef \
  --slack-webhook https://hooks.slack.com/services/... \
  --slack-secret your-slack-signing-secret

# Set up production environment parameters  
./scripts/setup-parameters.sh production \
  --endpoint-id cvpn-endpoint-0987654321fedcba \
  --subnet-id subnet-0987654321fedcba \
  --slack-webhook https://hooks.slack.com/services/... \
  --slack-secret your-slack-signing-secret
```

### Step 2: Deploy Infrastructure
```bash
# Deploy both environments
./scripts/deploy.sh both

# Or deploy individually
./scripts/deploy.sh production
./scripts/deploy.sh staging
```

### Step 3: Validate Deployment
```bash
# Check deployment status
./scripts/deploy.sh status

# Test API endpoints (examples)
curl -X POST https://api-gateway-url/slack \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "text=check staging&user_name=testuser"
```

## 📊 Monitoring and Metrics

### CloudWatch Metrics
The implementation publishes custom metrics to `VPN/Automation` namespace:

- **VpnAssociationStatus**: Current association state (0/1)
- **VpnActiveConnections**: Number of active VPN connections
- **VpnOpenOperations**: Count of VPN open operations
- **VpnCloseOperations**: Count of VPN close operations
- **IdleSubnetDisassociations**: Count of automatic cost-saving actions
- **VpnIdleTimeMinutes**: Current idle time in minutes
- **VpnOperationErrors**: Count of operation failures
- **LambdaErrors**: Count of Lambda execution errors

### Logging
- **Structured JSON logging** across all Lambda functions
- **Request correlation IDs** for tracing
- **Environment and operation context** in all log entries
- **Error details and stack traces** for troubleshooting

## 🔧 Configuration Reference

### Environment Variables
All Lambda functions receive these environment variables:
- `ENVIRONMENT`: Current environment (staging/production)
- `IDLE_MINUTES`: Idle threshold for auto-disassociation (default: 60)
- `VPN_STATE_PREFIX`: Parameter Store prefix (/vpn/)
- `SIGNING_SECRET_PARAM`: Slack signing secret parameter name
- `WEBHOOK_PARAM`: Slack webhook parameter name

### IAM Permissions
#### slack-handler Role
- `ssm:GetParameter` on `/vpn/slack/*` parameters
- Basic Lambda execution permissions

#### vpn-control/vpn-monitor Role  
- `ec2:Describe*` and `ec2:*ClientVpn*` for VPN operations
- `ssm:GetParameter` and `ssm:PutParameter` on `/vpn/*` parameters
- `cloudwatch:PutMetricData` for metrics publishing
- Basic Lambda execution permissions

## 🔍 Testing and Validation

### Unit Testing Framework
Each Lambda function includes package.json with testing dependencies:
```json
{
  "devDependencies": {
    "@types/aws-lambda": "^8.10.109",
    "@types/node": "^18.14.6", 
    "typescript": "~4.9.5"
  }
}
```

### Integration Testing
Use the deployment script's validation features:
```bash
# Show deployment differences
./scripts/deploy.sh diff-staging
./scripts/deploy.sh diff-production

# Validate AWS profile configuration
aws sts get-caller-identity --profile staging
aws sts get-caller-identity --profile production
```

### Manual Testing Commands
```bash
# Test Parameter Store access
aws ssm get-parameter --name /vpn/endpoint/conf --profile staging

# Test VPN endpoint validation
aws ec2 describe-client-vpn-endpoints --client-vpn-endpoint-ids YOUR_ENDPOINT_ID

# Monitor Lambda function logs
aws logs tail /aws/lambda/VpnAutomationStack-staging-VpnControl --follow
```

## 🚧 Next Steps

Epic 1 provides the foundation for implementing Epic 2 (Slack Integration) and Epic 3 (Automated Monitoring). The infrastructure is ready for:

1. **Slack App Configuration**: Configure Slack app to use the deployed API Gateway endpoints
2. **Cross-Account Testing**: Validate staging-to-production command routing
3. **Cost Monitoring**: Enable automated idle detection and subnet disassociation
4. **Operational Runbooks**: Create procedures for monitoring and troubleshooting

## 📚 Related Documentation

- [VPN_COST_AUTOMATION_DEPLOYMENT.md](VPN_COST_AUTOMATION_DEPLOYMENT.md) - Detailed deployment procedures
- [VPN_COST_AUTOMATION_SECURITY.md](VPN_COST_AUTOMATION_SECURITY.md) - Security configurations and best practices
- [VPN_COST_AUTOMATION_OPERATIONS_RUNBOOK.md](VPN_COST_AUTOMATION_OPERATIONS_RUNBOOK.md) - Day-to-day operations guide
- [Existing admin-tools/](../../admin-tools/) - Reference implementation patterns used

## 🎉 Success Criteria

✅ **All Epic 1 acceptance criteria have been met:**

- CDK stack supports environment-specific deployment (staging/production)
- Stack includes Lambda functions, IAM roles, and API Gateway with proper configuration
- Environment variables are properly configured per deployment
- API Gateway URL outputs enable cross-account integration
- Shared TypeScript utilities provide reusable functionality
- Parameter Store schema supports VPN state and configuration management
- VPN control functions handle open/close/check operations with proper error handling
- VPN status monitoring includes idle detection and connection tracking
- Deployment pipeline supports automated multi-environment deployment with validation

Epic 1 implementation is **complete and ready for production use**.