#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { VpnAutomationStack } from '../lib/vpn-automation-stack';

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
const stackName = `VpnAutomationStack-${environment}`;
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

// Create the stack
new VpnAutomationStack(app, stackName, {
  ...stackProps,
  environment: environment
});