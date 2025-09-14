# Deployment Guide for DevOps

This guide provides DevOps engineers with comprehensive instructions for deploying, maintaining, and troubleshooting the AWS Client VPN management system.

## 🎯 Who This Guide Is For

- DevOps Engineers
- Infrastructure Engineers
- System Administrators
- Platform Engineers

## 📋 System Overview

### Architecture Components
- **Infrastructure**: AWS CDK v2 (TypeScript)
- **Runtime**: Node.js 20.x Lambda functions
- **API**: REST via API Gateway
- **Scheduling**: EventBridge (CloudWatch Events)
- **State**: SSM Parameter Store
- **Monitoring**: CloudWatch Logs/Metrics

### Dual-Environment Design
- **Staging**: Development and testing
- **Production**: Live operations
- Complete isolation between environments

## 🚀 Initial Deployment

### Prerequisites

#### 1. System Requirements
```bash
# Verify installations
node --version      # Required: v20.x+
npm --version       # Required: v10.x+
aws --version       # Required: v2.x
cdk --version       # Required: v2.x

# Install CDK if needed
npm install -g aws-cdk
```

#### 2. AWS Account Setup
```bash
# Configure AWS profiles
aws configure --profile staging
aws configure --profile production

# Verify credentials
aws sts get-caller-identity --profile staging
aws sts get-caller-identity --profile production
```

#### 3. Account Configuration

Edit environment configs:
```bash
# configs/staging/staging.env
AWS_ACCOUNT_ID="YOUR_STAGING_ACCOUNT_ID"
AWS_REGION="us-east-1"
ENV_AWS_PROFILE="staging"

# configs/production/production.env
AWS_ACCOUNT_ID="YOUR_PRODUCTION_ACCOUNT_ID"
AWS_REGION="us-east-1"
ENV_AWS_PROFILE="production"
```

### CDK Bootstrap

First-time setup for each account:
```bash
cd cdklib

# Bootstrap staging account
AWS_PROFILE=staging cdk bootstrap

# Bootstrap production account
AWS_PROFILE=production cdk bootstrap
```

### Deploy Infrastructure

#### Full Deployment
```bash
# Deploy both environments
./scripts/deploy.sh both --secure-parameters \
  --staging-profile staging \
  --production-profile production

# Check deployment status
./scripts/deploy.sh status
```

#### Single Environment
```bash
# Deploy staging only
./scripts/deploy.sh staging --secure-parameters

# Deploy production only
./scripts/deploy.sh production --secure-parameters
```

### Configure Slack Integration

#### 1. Create Slack App
- Go to https://api.slack.com/apps
- Create new app
- Add OAuth scopes: `chat:write`, `commands`, `incoming-webhook`

#### 2. Store Credentials in SSM
```bash
# Save Slack configuration
aws ssm put-parameter \
  --name "/vpn/slack/bot_token" \
  --value "xoxb-your-bot-token" \
  --type "SecureString" \
  --profile staging

aws ssm put-parameter \
  --name "/vpn/slack/signing_secret" \
  --value "your-signing-secret" \
  --type "SecureString" \
  --profile staging

aws ssm put-parameter \
  --name "/vpn/slack/webhook_url" \
  --value "https://hooks.slack.com/services/YOUR/WEBHOOK" \
  --type "SecureString" \
  --profile staging
```

#### 3. Configure Slash Command
- Command: `/vpn`
- Request URL: Your staging API Gateway URL (from deployment output)
- Method: POST

## 🔧 Lambda Development

### Project Structure
```
lambda/
├── slack-handler/     # Handles Slack commands
├── vpn-control/       # Executes VPN operations
├── vpn-monitor/       # Auto-shutdown monitoring
└── shared/            # Shared layer code
```

### Build Process

#### Manual Build
```bash
# Build individual function
cd lambda/slack-handler
./build.sh

# Build all functions
for dir in lambda/*/; do
  [ -f "$dir/build.sh" ] && (cd "$dir" && ./build.sh)
done
```

#### Deploy Changes
```bash
# Test in staging first
./scripts/deploy.sh staging

# Then deploy to production
./scripts/deploy.sh production
```

### Environment Variables

Lambda functions use these environment variables:

| Variable | Purpose | Example |
|----------|---------|---------|
| `ENVIRONMENT` | Environment identifier | staging/production |
| `APP_ENV` | Application environment | staging/production |
| `IDLE_MINUTES` | Auto-shutdown threshold | 54 |
| `LOG_LEVEL` | Logging verbosity | INFO/DEBUG |

## 📊 Monitoring and Logging

### CloudWatch Logs

#### View Real-time Logs
```bash
# Slack handler logs
aws logs tail /aws/lambda/vpn-slack-handler-staging \
  --follow --profile staging

# VPN control logs
aws logs tail /aws/lambda/vpn-control-staging \
  --follow --profile staging

# Monitor logs
aws logs tail /aws/lambda/vpn-monitor-staging \
  --follow --profile staging
```

#### Search for Errors
```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/vpn-control-production \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --profile production
```

### CloudWatch Metrics

Custom metrics tracked:
- `VPN/Automation/VpnOpenOperations`
- `VPN/Automation/VpnCloseOperations`
- `VPN/Automation/AutoCloseTriggered`
- `VPN/Automation/CostSaved`

#### Create Alarms
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "VPN-High-Error-Rate" \
  --alarm-description "Alert on high Lambda errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --profile production
```

### Lambda Warming System

The system includes automatic Lambda warming to eliminate cold starts:

#### Warming Schedule
- **Business hours** (9-18 weekdays): Every 3 minutes
- **Off hours** (18-9 weekdays): Every 15 minutes
- **Weekends**: Every 30 minutes

#### Monitor Warming
```bash
# Check warming rules
aws events list-rules --name-prefix "*Warming*" --profile staging

# View warming effectiveness
aws logs filter-log-events \
  --log-group-name /aws/lambda/vpn-slack-handler-staging \
  --filter-pattern "Warming request received" \
  --profile staging
```

## 🛠️ Maintenance Operations

### Update Lambda Code

1. **Modify code** in `lambda/*/index.ts`
2. **Build** the function
3. **Deploy** to staging
4. **Test** functionality
5. **Deploy** to production

```bash
# Complete update workflow
cd lambda/vpn-control
# Edit index.ts
./build.sh
cd ../..
./scripts/deploy.sh staging
# Test via Slack
./scripts/deploy.sh production
```

### Update Dependencies

```bash
# Update shared layer
cd lambda/shared
npm update
npm audit fix

# Update function dependencies
cd ../slack-handler
npm update
npm audit fix
```

### Configuration Updates

#### Update SSM Parameters
```bash
# Update configuration
aws ssm put-parameter \
  --name "/vpn/staging/cost/optimization_config" \
  --value '{"idleTimeoutMinutes":54}' \
  --type String \
  --overwrite \
  --profile staging
```

#### Update CDK Stack
```bash
cd cdklib
npm update aws-cdk-lib
cdk deploy --profile staging
```

## 🚨 Troubleshooting

### Common Issues

#### Lambda Timeout
**Symptoms**: Slack commands timeout

**Check**:
```bash
aws lambda get-function-configuration \
  --function-name vpn-slack-handler-staging \
  --query Timeout \
  --profile staging
```

**Fix**: Increase timeout in CDK configuration

#### Permission Errors
**Symptoms**: AccessDenied in logs

**Check**:
```bash
aws iam get-role-policy \
  --role-name VpnCostAutomationStack-staging-SlackHandlerRole \
  --policy-name DefaultPolicy \
  --profile staging
```

**Fix**: Update IAM policies in CDK

#### API Gateway 502 Error
**Symptoms**: Bad Gateway responses

**Check**:
1. Lambda function logs
2. API Gateway integration settings
3. Lambda function health

**Fix**:
```bash
# Redeploy API Gateway
./scripts/deploy.sh staging --force-update-api
```

### Emergency Procedures

#### Complete System Failure
1. **Notify stakeholders**
2. **Check AWS service health**
3. **Review CloudWatch logs**
4. **Redeploy if necessary**:
```bash
./scripts/deploy.sh both --secure-parameters --force
```

#### Rollback Deployment
```bash
# List previous deployments
aws cloudformation list-stack-resources \
  --stack-name VpnCostAutomationStack-staging \
  --profile staging

# Rollback to previous version
cdk deploy --rollback --profile staging
```

## 🔄 Disaster Recovery

### Backup Strategy

#### Automated Backups
```bash
#!/bin/bash
# backup.sh
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="backups/$DATE"
mkdir -p $BACKUP_DIR

# Backup SSM parameters
aws ssm get-parameters-by-path \
  --path "/vpn" \
  --recursive \
  --with-decryption \
  --profile production > $BACKUP_DIR/ssm-params.json

# Backup Lambda configurations
for func in vpn-slack-handler vpn-control vpn-monitor; do
  aws lambda get-function \
    --function-name $func-production \
    --profile production > $BACKUP_DIR/$func.json
done
```

### Recovery Procedures

#### Restore from Backup
```bash
# Restore SSM parameters
cat backup/ssm-params.json | jq -r '.Parameters[] |
  "aws ssm put-parameter --name \(.Name) --value \(.Value) --type \(.Type) --overwrite"' |
  bash

# Redeploy infrastructure
./scripts/deploy.sh production --secure-parameters
```

### RTO/RPO Targets

| Component | RTO | RPO |
|-----------|-----|-----|
| Lambda Functions | 5 min | 0 |
| API Gateway | 5 min | 0 |
| SSM Parameters | 10 min | 1 hour |
| VPN Endpoints | 30 min | N/A |

## 🚀 Performance Optimization

### Lambda Optimization

#### Memory Configuration
```typescript
// Optimal settings in CDK
const slackHandler = new lambda.Function(this, 'SlackHandler', {
  memorySize: 512,  // Balanced for I/O operations
  timeout: Duration.seconds(30),
  reservedConcurrentExecutions: 5
});
```

#### Code Optimization
- Initialize SDK clients outside handler
- Cache frequently accessed data
- Use connection pooling

### Cost Optimization

#### Monitor Costs
```bash
# Lambda invocation costs
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=vpn-slack-handler-staging \
  --start-time $(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum \
  --profile staging
```

#### Reduce Costs
- Adjust Lambda memory allocation
- Optimize warming frequency
- Set appropriate log retention

## 📋 Maintenance Checklist

### Daily
- [ ] Check CloudWatch error logs
- [ ] Verify auto-shutdown functioning
- [ ] Monitor Lambda errors

### Weekly
- [ ] Review Lambda performance metrics
- [ ] Check cost trends
- [ ] Update dependencies if needed

### Monthly
- [ ] Full system health check
- [ ] Security patches
- [ ] Documentation updates
- [ ] Backup verification

## 🆘 Support Resources

### Internal
- Slack: #devops channel
- Wiki: Infrastructure documentation
- Runbook: Emergency procedures

### External
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [GitHub Issues](https://github.com/your-org/vpn-toolkit/issues)

---

**For Admin Tasks:** See [Admin Guide](admin-guide.md)
**For Architecture:** See [Architecture Documentation](architecture.md)