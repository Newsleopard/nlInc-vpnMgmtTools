#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { VpnAutomationStack } from '../lib/vpn-automation-stack';
import { SecureParameterManagementStack } from '../lib/secure-parameter-management-stack';

/**
 * Epic 5.1: Secure Parameter Management - Enhanced CDK App
 * 
 * This app deploys the VPN Cost Automation infrastructure with enhanced security:
 * 1. SecureParameterManagementStack - KMS-encrypted parameter storage
 * 2. VpnAutomationStack - Lambda functions and API Gateway (enhanced with secure parameters)
 */

const app = new cdk.App();

// Get environment from context or default to staging
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'staging';

// Epic 5.1.1: Deploy secure parameter management stack first
const secureParamStack = new SecureParameterManagementStack(app, `VpnSecureParameters-${environment}`, {
  environment,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: `VPN Cost Automation - Secure Parameter Management for ${environment}`,
  tags: {
    Project: 'VPN-Cost-Automation',
    Environment: environment,
    Epic: '5.1-Secure-Parameter-Management',
    Stack: 'SecureParameters'
  }
});

// Epic 5.1.2: Deploy main VPN automation stack with dependency on parameters
const vpnStack = new VpnAutomationStack(app, `VpnAutomation-${environment}`, {
  environment,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: `VPN Cost Automation - Main Application Stack for ${environment}`,
  tags: {
    Project: 'VPN-Cost-Automation',
    Environment: environment,
    Epic: 'Complete-Implementation',
    Stack: 'MainApplication'
  }
});

// Epic 5.1.1: Create dependency to ensure parameters are created first
vpnStack.addDependency(secureParamStack);

// Epic 5.1.2: Pass KMS key information to main stack
vpnStack.addEnvironment('VPN_PARAMETER_KMS_KEY_ID', secureParamStack.parameterKmsKey.keyId);
vpnStack.addEnvironment('VPN_PARAMETER_KMS_KEY_ARN', secureParamStack.parameterKmsKey.keyArn);

// Add cross-stack outputs for integration
new cdk.CfnOutput(secureParamStack, 'IntegrationInfo', {
  value: JSON.stringify({
    kmsKeyId: secureParamStack.parameterKmsKey.keyId,
    readRoleArn: secureParamStack.vpnParameterReadRole.roleArn,
    writeRoleArn: secureParamStack.vpnParameterWriteRole.roleArn,
    environment: environment,
    stackName: secureParamStack.stackName
  }),
  description: 'Integration information for VPN Automation main stack',
  exportName: `VpnSecureParametersInfo-${environment}`
});

// Epic 5.1.2: Output deployment summary
new cdk.CfnOutput(app.node, 'DeploymentSummary', {
  value: JSON.stringify({
    epic: '5.1-Secure-Parameter-Management',
    environment: environment,
    stacks: [
      `VpnSecureParameters-${environment}`,
      `VpnAutomation-${environment}`
    ],
    features: [
      'KMS-encrypted parameter storage',
      'Least-privilege IAM roles',
      'Parameter validation',
      'Configuration management',
      'Enhanced security monitoring'
    ],
    deploymentDate: new Date().toISOString()
  }),
  description: 'Epic 5.1 deployment summary and feature list'
});
