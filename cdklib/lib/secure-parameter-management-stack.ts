import * as cdk from 'aws-cdk-lib';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export interface SecureParameterManagementStackProps extends cdk.StackProps {
  environment: string;
}

/**
 * Epic 5.1: Secure Parameter Management
 * 
 * This stack implements secure parameter storage with:
 * - KMS encryption for sensitive parameters
 * - SecureString parameter types for secrets
 * - Least-privilege IAM policies
 * - Parameter validation and configuration management
 */
export class SecureParameterManagementStack extends cdk.Stack {
  public readonly parameterKmsKey: kms.Key;
  public readonly vpnParameterReadRole: iam.Role;
  public readonly vpnParameterWriteRole: iam.Role;

  constructor(scope: Construct, id: string, props: SecureParameterManagementStackProps) {
    super(scope, id, props);

    const { environment } = props;

    // Epic 5.1.1: Create KMS key for parameter encryption
    this.parameterKmsKey = new kms.Key(this, 'VpnParameterKmsKey', {
      description: `VPN Cost Automation Parameter Store encryption key for ${environment}`,
      enableKeyRotation: true,
      alias: `vpn-parameter-store-${environment}`,
      policy: new iam.PolicyDocument({
        statements: [
          // Allow root account to manage the key
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*']
          }),
          // Allow AWS Systems Manager to use the key for parameter operations
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('ssm.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:DescribeKey',
              'kms:Encrypt',
              'kms:GenerateDataKey*',
              'kms:ReEncrypt*'
            ],
            resources: ['*']
          })
        ]
      })
    });

    // Epic 5.1.1: Create IAM role for reading parameters (minimal permissions)
    this.vpnParameterReadRole = new iam.Role(this, 'VpnParameterReadRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Minimal role for reading VPN parameters from Parameter Store',
      inlinePolicies: {
        VpnParameterRead: new iam.PolicyDocument({
          statements: [
            // Read access to VPN parameters only
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ssm:GetParameter',
                'ssm:GetParameters'
              ],
              resources: [
                `arn:aws:ssm:${this.region}:${this.account}:parameter/vpn/*`
              ]
            }),
            // KMS decrypt access for encrypted parameters
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt',
                'kms:DescribeKey'
              ],
              resources: [this.parameterKmsKey.keyArn],
              conditions: {
                StringEquals: {
                  'kms:ViaService': `ssm.${this.region}.amazonaws.com`
                }
              }
            })
          ]
        })
      }
    });

    // Epic 5.1.1: Create IAM role for writing parameters (elevated permissions)
    this.vpnParameterWriteRole = new iam.Role(this, 'VpnParameterWriteRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for writing VPN parameters to Parameter Store',
      inlinePolicies: {
        VpnParameterWrite: new iam.PolicyDocument({
          statements: [
            // Read and write access to VPN parameters
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ssm:GetParameter',
                'ssm:GetParameters',
                'ssm:PutParameter',
                'ssm:DeleteParameter'
              ],
              resources: [
                `arn:aws:ssm:${this.region}:${this.account}:parameter/vpn/*`
              ]
            }),
            // KMS encrypt/decrypt access for encrypted parameters
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt',
                'kms:DescribeKey',
                'kms:Encrypt',
                'kms:GenerateDataKey*',
                'kms:ReEncrypt*'
              ],
              resources: [this.parameterKmsKey.keyArn],
              conditions: {
                StringEquals: {
                  'kms:ViaService': `ssm.${this.region}.amazonaws.com`
                }
              }
            })
          ]
        })
      }
    });

    // Epic 5.1.1: Create secure parameters with KMS encryption
    
    // VPN endpoint state (non-sensitive, standard String)
    const vpnEndpointState = new ssm.StringParameter(this, 'VpnEndpointState', {
      parameterName: '/vpn/endpoint/state',
      stringValue: JSON.stringify({
        associated: false,
        lastActivity: new Date().toISOString()
      }),
      description: `VPN endpoint state for ${environment} (associated status and last activity)`,
      tier: ssm.ParameterTier.STANDARD,
      allowedPattern: '.*', // Allow any JSON structure
      type: ssm.ParameterType.STRING
    });

    // VPN endpoint configuration (non-sensitive, standard String)
    const vpnEndpointConfig = new ssm.StringParameter(this, 'VpnEndpointConfig', {
      parameterName: '/vpn/endpoint/conf',
      stringValue: JSON.stringify({
        ENDPOINT_ID: 'PLACEHOLDER_ENDPOINT_ID',
        SUBNET_ID: 'PLACEHOLDER_SUBNET_ID'
      }),
      description: `VPN endpoint configuration for ${environment} (endpoint ID and subnet ID)`,
      tier: ssm.ParameterTier.STANDARD,
      allowedPattern: '.*', // Allow any JSON structure
      type: ssm.ParameterType.STRING
    });

    // Slack webhook URL (sensitive, encrypted with KMS)
    const slackWebhook = new ssm.StringParameter(this, 'SlackWebhook', {
      parameterName: '/vpn/slack/webhook',
      stringValue: 'PLACEHOLDER_WEBHOOK_URL',
      description: `Slack webhook URL for ${environment} notifications (ENCRYPTED)`,
      tier: ssm.ParameterTier.STANDARD,
      type: ssm.ParameterType.SECURE_STRING,
      keyId: this.parameterKmsKey,
      allowedPattern: '^https://hooks\\.slack\\.com/.*|PLACEHOLDER_.*$' // Slack webhook URL pattern or placeholder
    });

    // Slack signing secret (sensitive, encrypted with KMS)
    const slackSigningSecret = new ssm.StringParameter(this, 'SlackSigningSecret', {
      parameterName: '/vpn/slack/signing_secret',
      stringValue: 'PLACEHOLDER_SIGNING_SECRET',
      description: `Slack app signing secret for ${environment} request verification (ENCRYPTED)`,
      tier: ssm.ParameterTier.STANDARD,
      type: ssm.ParameterType.SECURE_STRING,
      keyId: this.parameterKmsKey,
      allowedPattern: '^[a-f0-9]{64}$|^PLACEHOLDER_.*$' // 64-character hex string or placeholder
    });

    // Epic 5.1.1: Cost optimization parameters (encrypted for security)
    const costOptimizationConfig = new ssm.StringParameter(this, 'CostOptimizationConfig', {
      parameterName: '/vpn/cost/optimization_config',
      stringValue: JSON.stringify({
        idleTimeoutMinutes: 60,
        cooldownMinutes: 30,
        businessHoursProtection: true,
        businessHoursTimezone: 'UTC',
        businessHoursStart: '09:00',
        businessHoursEnd: '18:00',
        regionalPricingEnabled: true,
        cumulativeSavingsTracking: true
      }),
      description: `Cost optimization configuration for ${environment}`,
      tier: ssm.ParameterTier.STANDARD,
      type: ssm.ParameterType.SECURE_STRING,
      keyId: this.parameterKmsKey
    });

    // Epic 5.1.1: Administrative overrides tracking (encrypted for audit security)
    const adminOverrides = new ssm.StringParameter(this, 'AdminOverrides', {
      parameterName: '/vpn/admin/overrides',
      stringValue: JSON.stringify({
        activeOverrides: {},
        overrideHistory: [],
        lastUpdated: new Date().toISOString()
      }),
      description: `Administrative override tracking for ${environment} (AUDIT TRAIL)`,
      tier: ssm.ParameterTier.STANDARD,
      type: ssm.ParameterType.SECURE_STRING,
      keyId: this.parameterKmsKey
    });

    // Epic 5.1.1: Cost tracking and metrics (encrypted to protect business data)
    const costMetrics = new ssm.StringParameter(this, 'CostMetrics', {
      parameterName: '/vpn/cost/metrics',
      stringValue: JSON.stringify({
        totalSavings: 0,
        monthlyStats: {},
        lastCalculated: new Date().toISOString(),
        regionPricing: {
          'us-east-1': 0.05,
          'us-west-2': 0.05,
          'eu-west-1': 0.05,
          'ap-southeast-1': 0.05
        }
      }),
      description: `Cost tracking metrics for ${environment} (BUSINESS DATA)`,
      tier: ssm.ParameterTier.STANDARD,
      type: ssm.ParameterType.SECURE_STRING,
      keyId: this.parameterKmsKey
    });

    // Epic 5.1.2: API Gateway configuration for cross-account calls (encrypted)
    if (environment === 'staging') {
      const crossAccountConfig = new ssm.StringParameter(this, 'CrossAccountConfig', {
        parameterName: '/vpn/cross_account/config',
        stringValue: JSON.stringify({
          productionApiEndpoint: 'PLACEHOLDER_PRODUCTION_ENDPOINT',
          productionApiKey: 'PLACEHOLDER_PRODUCTION_API_KEY',
          retryConfig: {
            maxRetries: 3,
            backoffMultiplier: 2,
            baseDelayMs: 1000
          }
        }),
        description: `Cross-account routing configuration for ${environment}`,
        tier: ssm.ParameterTier.STANDARD,
        type: ssm.ParameterType.SECURE_STRING,
        keyId: this.parameterKmsKey
      });
    }

    // Epic 5.1.1: Logging and monitoring configuration
    const loggingConfig = new ssm.StringParameter(this, 'LoggingConfig', {
      parameterName: '/vpn/logging/config',
      stringValue: JSON.stringify({
        logLevel: 'INFO',
        structuredLogging: true,
        auditLogging: true,
        performanceMonitoring: true,
        securityLogging: true,
        logRetentionDays: 30,
        metricsNamespace: 'VPN/Automation',
        enableCloudWatchInsights: true
      }),
      description: `Logging and monitoring configuration for ${environment}`,
      tier: ssm.ParameterTier.STANDARD,
      type: ssm.ParameterType.STRING
    });

    // Create CloudFormation outputs
    new cdk.CfnOutput(this, 'ParameterKmsKeyId', {
      value: this.parameterKmsKey.keyId,
      description: 'KMS Key ID for VPN parameter encryption',
      exportName: `VpnParameterKmsKey-${environment}`
    });

    new cdk.CfnOutput(this, 'ParameterKmsKeyArn', {
      value: this.parameterKmsKey.keyArn,
      description: 'KMS Key ARN for VPN parameter encryption',
      exportName: `VpnParameterKmsKeyArn-${environment}`
    });

    new cdk.CfnOutput(this, 'VpnParameterReadRoleArn', {
      value: this.vpnParameterReadRole.roleArn,
      description: 'IAM Role ARN for reading VPN parameters',
      exportName: `VpnParameterReadRole-${environment}`
    });

    new cdk.CfnOutput(this, 'VpnParameterWriteRoleArn', {
      value: this.vpnParameterWriteRole.roleArn,
      description: 'IAM Role ARN for writing VPN parameters',
      exportName: `VpnParameterWriteRole-${environment}`
    });

    // Epic 5.1.2: Parameter validation summary output
    new cdk.CfnOutput(this, 'ParameterValidationSummary', {
      value: JSON.stringify({
        parametersCreated: [
          '/vpn/endpoint/state',
          '/vpn/endpoint/conf',
          '/vpn/slack/webhook',
          '/vpn/slack/signing_secret',
          '/vpn/cost/optimization_config',
          '/vpn/admin/overrides',
          '/vpn/cost/metrics',
          '/vpn/logging/config',
          ...(environment === 'staging' ? ['/vpn/cross_account/config'] : [])
        ],
        encryptedParameters: [
          '/vpn/slack/webhook',
          '/vpn/slack/signing_secret',
          '/vpn/cost/optimization_config',
          '/vpn/admin/overrides',
          '/vpn/cost/metrics',
          ...(environment === 'staging' ? ['/vpn/cross_account/config'] : [])
        ],
        kmsKeyUsed: true,
        validationPatterns: {
          slackWebhook: '^https://hooks\\.slack\\.com/.*|PLACEHOLDER_.*$',
          slackSigningSecret: '^[a-f0-9]{64}$|^PLACEHOLDER_.*$'
        }
      }),
      description: 'Parameter validation and security summary'
    });

    // Add tags for cost tracking and compliance
    cdk.Tags.of(this).add('Project', 'VPN-Cost-Automation');
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Epic', '5.1-Secure-Parameter-Management');
    cdk.Tags.of(this).add('SecurityLevel', 'High');
    cdk.Tags.of(this).add('Compliance', 'Required');
  }
}
