#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { VpnAutomationStack } from '../lib/vpn-automation-stack';
import { SecureParameterManagementStack } from '../lib/secure-parameter-management-stack';

const app = new cdk.App();

// Get environment from environment variable
const environment = process.env.ENVIRONMENT || 'staging';
const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION || 'us-east-1';

// Validate required environment variables
if (!account) {
  throw new Error('CDK_DEFAULT_ACCOUNT environment variable is required');
}

// Environment-specific configuration
const stackName = `VpnAutomation-${environment}`;
const stackProps: cdk.StackProps = {
  env: {
    account: account,
    region: region,
  },
  description: `VPN Cost Automation Stack for ${environment} environment`,
  tags: {
    Environment: environment,
    Project: 'VpnCostAutomation',
    ManagedBy: 'CDK'
  }
};

// Create the secure parameter management stack first
const secureParameterStackName = `VpnSecureParameters-${environment}`;
const secureParameterStack = new SecureParameterManagementStack(app, secureParameterStackName, {
  ...stackProps,
  environment: environment
});

// Create the main VPN automation stack with secure parameter stack reference
new VpnAutomationStack(app, stackName, {
  ...stackProps,
  environment: environment,
  secureParameterStack: secureParameterStack
});