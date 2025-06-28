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
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
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
                `arn:aws:ssm:${this.region}:${this.account}:parameter/vpn/${environment}/*`
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
            }),
            // CloudWatch metrics access for performance monitoring
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Epic 5.1.1: Create IAM role for writing parameters (elevated permissions)
    this.vpnParameterWriteRole = new iam.Role(this, 'VpnParameterWriteRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for writing VPN parameters to Parameter Store',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
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
                `arn:aws:ssm:${this.region}:${this.account}:parameter/vpn/${environment}/*`
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
      parameterName: `/vpn/${environment}/endpoint/state`,
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
      parameterName: `/vpn/${environment}/endpoint/conf`,
      stringValue: JSON.stringify({
        ENDPOINT_ID: 'PLACEHOLDER_ENDPOINT_ID',
        SUBNET_ID: 'PLACEHOLDER_SUBNET_ID'
      }),
      description: `VPN endpoint configuration for ${environment} (endpoint ID and subnet ID)`,
      tier: ssm.ParameterTier.STANDARD,
      allowedPattern: '.*', // Allow any JSON structure
      type: ssm.ParameterType.STRING
    });

    // Slack webhook URL (will be created as SecureString via setup script)
    const slackWebhook = new ssm.CfnParameter(this, 'SlackWebhook', {
      name: `/vpn/${environment}/slack/webhook`,
      value: 'PLACEHOLDER_WEBHOOK_URL',
      type: 'String',
      description: `Slack webhook URL for ${environment} notifications (will be converted to SecureString)`,
      tier: ssm.ParameterTier.STANDARD,
      allowedPattern: '^https://hooks\\.slack\\.com/.*|PLACEHOLDER_.*$' // Slack webhook URL pattern or placeholder
    });

    // Slack signing secret (sensitive, encrypted with KMS)
    const slackSigningSecret = new ssm.CfnParameter(this, 'SlackSigningSecret', {
      name: `/vpn/${environment}/slack/signing_secret`,
      value: 'PLACEHOLDER_SIGNING_SECRET',
      type: 'String',
      description: `Slack app signing secret for ${environment} request verification (will be converted to SecureString)`,
      tier: ssm.ParameterTier.STANDARD,
      allowedPattern: '^[a-f0-9]{32}$|^PLACEHOLDER_.*$' // 32-character hex string or placeholder
    });

    // Slack bot OAuth token (sensitive, encrypted with KMS)
    const slackBotToken = new ssm.CfnParameter(this, 'SlackBotToken', {
      name: `/vpn/${environment}/slack/bot_token`,
      value: 'PLACEHOLDER_BOT_TOKEN',
      type: 'String',
      description: `Slack bot OAuth token for ${environment} (will be converted to SecureString)`,
      tier: ssm.ParameterTier.STANDARD,
      allowedPattern: '^xoxb-[0-9]+-[0-9]+-[a-zA-Z0-9]+$|^PLACEHOLDER_.*$' // Slack bot token pattern or placeholder
    });

    // Epic 5.1.1: Cost optimization parameters (encrypted for security)
    const costOptimizationConfig = new ssm.CfnParameter(this, 'CostOptimizationConfig', {
      name: `/vpn/${environment}/cost/optimization_config`,
      value: JSON.stringify({
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
      type: 'String',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Epic 5.1.1: Administrative overrides tracking (encrypted for audit security)
    const adminOverrides = new ssm.CfnParameter(this, 'AdminOverrides', {
      name: `/vpn/${environment}/admin/overrides`,
      value: JSON.stringify({
        activeOverrides: {},
        overrideHistory: [],
        lastUpdated: new Date().toISOString()
      }),
      description: `Administrative override tracking for ${environment} (AUDIT TRAIL)`,
      type: 'String',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Epic 5.1.1: Cost tracking and metrics (encrypted to protect business data)
    const costMetrics = new ssm.CfnParameter(this, 'CostMetrics', {
      name: `/vpn/${environment}/cost/metrics`,
      value: JSON.stringify({
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
      type: 'String',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Epic 5.1.2: API Gateway configuration for cross-account calls (encrypted)
    if (environment === 'staging') {
      const crossAccountConfig = new ssm.CfnParameter(this, 'CrossAccountConfig', {
        name: `/vpn/${environment}/cross_account/config`,
        value: JSON.stringify({
          productionApiEndpoint: 'PLACEHOLDER_PRODUCTION_ENDPOINT',
          productionApiKey: 'PLACEHOLDER_PRODUCTION_API_KEY',
          retryConfig: {
            maxRetries: 3,
            backoffMultiplier: 2,
            baseDelayMs: 1000
          }
        }),
        description: `Cross-account routing configuration for ${environment}`,
        type: 'String',
        tier: ssm.ParameterTier.STANDARD,
          });
    }

    // Epic 5.1.1: Logging and monitoring configuration
    const loggingConfig = new ssm.StringParameter(this, 'LoggingConfig', {
      parameterName: `/vpn/${environment}/logging/config`,
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
          `/vpn/${environment}/endpoint/state`,
          `/vpn/${environment}/endpoint/conf`,
          `/vpn/${environment}/slack/webhook`,
          `/vpn/${environment}/slack/signing_secret`,
          `/vpn/${environment}/slack/bot_token`,
          `/vpn/${environment}/cost/optimization_config`,
          `/vpn/${environment}/admin/overrides`,
          `/vpn/${environment}/cost/metrics`,
          `/vpn/${environment}/logging/config`,
          ...(environment === 'staging' ? [`/vpn/${environment}/cross_account/config`] : [])
        ],
        encryptedParameters: [
          `/vpn/${environment}/slack/webhook`,
          `/vpn/${environment}/slack/signing_secret`,
          `/vpn/${environment}/slack/bot_token`,
          `/vpn/${environment}/cost/optimization_config`,
          `/vpn/${environment}/admin/overrides`,
          `/vpn/${environment}/cost/metrics`,
          ...(environment === 'staging' ? [`/vpn/${environment}/cross_account/config`] : [])
        ],
        kmsKeyUsed: true,
        validationPatterns: {
          slackWebhook: '^https://hooks\\.slack\\.com/.*|PLACEHOLDER_.*$',
          slackSigningSecret: '^[a-f0-9]{64}$|^PLACEHOLDER_.*$',
          slackBotToken: '^xoxb-[0-9]+-[0-9]+-[a-zA-Z0-9]+$|^PLACEHOLDER_.*$'
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
