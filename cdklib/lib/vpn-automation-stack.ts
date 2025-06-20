import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as path from 'path';
import { Construct } from 'constructs';

export interface VpnAutomationStackProps extends cdk.StackProps {
  environment: string;
}

export class VpnAutomationStack extends cdk.Stack {
  public readonly apiGatewayUrl: cdk.CfnOutput;

  constructor(scope: Construct, id: string, props: VpnAutomationStackProps) {
    super(scope, id, props);

    const { environment } = props;

    // Create shared Lambda layer
    const sharedLayer = new lambda.LayerVersion(this, 'VpnSharedLayer', {
      code: lambda.Code.fromAsset(path.join(__dirname, '../../lambda/shared')),
      compatibleRuntimes: [lambda.Runtime.NODEJS_18_X],
      description: 'Shared utilities for VPN Cost Automation',
      layerVersionName: `vpn-shared-layer-${environment}`
    });

    // IAM role for slack-handler Lambda (minimal permissions)
    const slackHandlerRole = new iam.Role(this, 'SlackHandlerRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        ParameterStoreRead: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ssm:GetParameter'
              ],
              resources: [
                `arn:aws:ssm:${this.region}:${this.account}:parameter/vpn/slack/*`
              ]
            })
          ]
        }),
        LambdaInvoke: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'lambda:InvokeFunction'
              ],
              resources: [
                `arn:aws:lambda:${this.region}:${this.account}:function:VpnAutomationStack-${environment}-VpnControl*`
              ]
            })
          ]
        })
      }
    });

    // IAM role for vpn-control and vpn-monitor Lambdas
    const vpnControlRole = new iam.Role(this, 'VpnControlRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        VpnOperations: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ec2:DescribeClientVpnEndpoints',
                'ec2:DescribeClientVpnTargetNetworks',
                'ec2:DescribeClientVpnConnections',
                'ec2:DescribeClientVpnAuthorizationRules',
                'ec2:AssociateClientVpnTargetNetwork',
                'ec2:DisassociateClientVpnTargetNetwork'
              ],
              resources: ['*']
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ssm:GetParameter',
                'ssm:PutParameter'
              ],
              resources: [
                `arn:aws:ssm:${this.region}:${this.account}:parameter/vpn/*`
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData'
              ],
              resources: ['*'],
              conditions: {
                StringEquals: {
                  'cloudwatch:namespace': 'VPN/Automation'
                }
              }
            })
          ]
        })
      }
    });

    // Environment variables for Lambda functions
    const commonEnvironment = {
      IDLE_MINUTES: '60',
      ENVIRONMENT: environment,
      VPN_STATE_PREFIX: '/vpn/',
      SIGNING_SECRET_PARAM: '/vpn/slack/signing_secret',
      WEBHOOK_PARAM: '/vpn/slack/webhook',
      
      // Enhanced idle detection configuration
      COOLDOWN_MINUTES: '30',
      BUSINESS_HOURS_PROTECTION: 'true',
      BUSINESS_HOURS_TIMEZONE: 'UTC',
      
      // Production authorization (can be overridden via deployment)
      PRODUCTION_AUTHORIZED_USERS: process.env.PRODUCTION_AUTHORIZED_USERS || '*'
    };

    // slack-handler Lambda function
    const slackHandler = new lambda.Function(this, 'SlackHandler', {
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../../lambda/slack-handler')),
      layers: [sharedLayer],
      role: slackHandlerRole,
      timeout: cdk.Duration.seconds(3),
      environment: {
        ...commonEnvironment,
        // Production API endpoint will be set during deployment
        ...(environment === 'staging' && process.env.PRODUCTION_API_ENDPOINT ? {
          PRODUCTION_API_ENDPOINT: process.env.PRODUCTION_API_ENDPOINT,
          PRODUCTION_API_KEY: process.env.PRODUCTION_API_KEY || ''
        } : {})
      },
      description: `Slack command handler for ${environment} environment`
    });

    // vpn-control Lambda function
    const vpnControl = new lambda.Function(this, 'VpnControl', {
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../../lambda/vpn-control')),
      layers: [sharedLayer],
      role: vpnControlRole,
      timeout: cdk.Duration.seconds(30),
      environment: commonEnvironment,
      description: `VPN control function for ${environment} environment`
    });

    // vpn-monitor Lambda function (for scheduled monitoring)
    const vpnMonitor = new lambda.Function(this, 'VpnMonitor', {
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset(path.join(__dirname, '../../lambda/vpn-monitor')),
      layers: [sharedLayer],
      role: vpnControlRole, // Same role as vpn-control
      timeout: cdk.Duration.seconds(60),
      environment: commonEnvironment,
      description: `VPN monitoring function for ${environment} environment`
    });

    // API Gateway for Slack integration and cross-account calls
    const api = new apigateway.RestApi(this, 'VpnApi', {
      restApiName: `VPN Automation API (${environment})`,
      description: `API for VPN cost automation in ${environment} environment`,
      apiKeySourceType: apigateway.ApiKeySourceType.HEADER,
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key']
      }
    });

    // API Gateway integration for slack-handler
    const slackIntegration = new apigateway.LambdaIntegration(slackHandler, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' }
    });

    // API Gateway integration for vpn-control (for cross-account calls)
    const vpnControlIntegration = new apigateway.LambdaIntegration(vpnControl, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' }
    });

    // Slack endpoint (no API key required)
    api.root.addResource('slack').addMethod('POST', slackIntegration);

    // VPN control endpoint (API key required for cross-account security)
    const vpnResource = api.root.addResource('vpn');
    vpnResource.addMethod('POST', vpnControlIntegration, {
      apiKeyRequired: true
    });

    // Create API key for cross-account calls (only for production)
    let apiKey: apigateway.ApiKey | undefined;
    if (environment === 'production') {
      apiKey = new apigateway.ApiKey(this, 'CrossAccountApiKey', {
        apiKeyName: `vpn-automation-${environment}-key`,
        description: `API key for cross-account VPN automation calls to ${environment}`
      });

      // Create usage plan and associate with API key
      const usagePlan = new apigateway.UsagePlan(this, 'ApiUsagePlan', {
        name: `vpn-automation-${environment}-plan`,
        description: `Usage plan for VPN automation ${environment} API`,
        throttle: {
          rateLimit: 10,
          burstLimit: 20
        },
        quota: {
          limit: 1000,
          period: apigateway.Period.DAY
        }
      });

      usagePlan.addApiStage({
        stage: api.deploymentStage
      });

      usagePlan.addApiKey(apiKey);
    }

    // CloudWatch Events rule for scheduled monitoring (every 5 minutes)
    const monitoringRule = new events.Rule(this, 'VpnMonitoringRule', {
      schedule: events.Schedule.rate(cdk.Duration.minutes(5)),
      description: `Scheduled VPN monitoring for ${environment} environment`
    });

    // Add vpn-monitor as target for the rule
    monitoringRule.addTarget(new targets.LambdaFunction(vpnMonitor));

    // Grant CloudWatch Events permission to invoke the Lambda
    vpnMonitor.addPermission('AllowCloudWatchEventsInvoke', {
      principal: new iam.ServicePrincipal('events.amazonaws.com'),
      sourceArn: monitoringRule.ruleArn
    });

    // Create SSM parameters for initial setup (if they don't exist)
    new ssm.StringParameter(this, 'VpnEndpointState', {
      parameterName: '/vpn/endpoint/state',
      stringValue: JSON.stringify({
        associated: false,
        lastActivity: new Date().toISOString()
      }),
      description: 'VPN endpoint state (associated status and last activity)',
      tier: ssm.ParameterTier.STANDARD
    });

    // Create placeholder config parameter (needs to be updated with actual values)
    new ssm.StringParameter(this, 'VpnEndpointConfig', {
      parameterName: '/vpn/endpoint/conf',
      stringValue: JSON.stringify({
        ENDPOINT_ID: 'PLACEHOLDER_ENDPOINT_ID',
        SUBNET_ID: 'PLACEHOLDER_SUBNET_ID'
      }),
      description: 'VPN endpoint configuration (endpoint ID and subnet ID)',
      tier: ssm.ParameterTier.STANDARD
    });

    // Create placeholder parameters for Slack integration (to be updated manually)
    new ssm.StringParameter(this, 'SlackWebhookPlaceholder', {
      parameterName: '/vpn/slack/webhook',
      stringValue: 'PLACEHOLDER_WEBHOOK_URL',
      description: 'Slack webhook URL for notifications (SecureString recommended)',
      tier: ssm.ParameterTier.STANDARD
    });

    new ssm.StringParameter(this, 'SlackSigningSecretPlaceholder', {
      parameterName: '/vpn/slack/signing_secret',
      stringValue: 'PLACEHOLDER_SIGNING_SECRET',
      description: 'Slack app signing secret for request verification (SecureString recommended)',
      tier: ssm.ParameterTier.STANDARD
    });

    // Outputs
    this.apiGatewayUrl = new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: api.url,
      description: 'VPN Automation API Gateway URL',
      exportName: `VpnAutomationApiUrl-${environment}`
    });

    new cdk.CfnOutput(this, 'SlackEndpoint', {
      value: `${api.url}slack`,
      description: 'Slack webhook endpoint URL'
    });

    new cdk.CfnOutput(this, 'VpnControlEndpoint', {
      value: `${api.url}vpn`,
      description: 'VPN control endpoint URL (requires API key)'
    });

    if (apiKey) {
      new cdk.CfnOutput(this, 'ApiKeyId', {
        value: apiKey.keyId,
        description: 'API Key ID for cross-account calls'
      });
    }

    new cdk.CfnOutput(this, 'Environment', {
      value: environment,
      description: 'Deployment environment'
    });

    new cdk.CfnOutput(this, 'MonitoringSchedule', {
      value: 'Every 5 minutes',
      description: 'VPN monitoring schedule (CloudWatch Events)'
    });

    new cdk.CfnOutput(this, 'IdleThreshold', {
      value: `${commonEnvironment.IDLE_MINUTES} minutes`,
      description: 'VPN idle detection threshold'
    });

    new cdk.CfnOutput(this, 'CooldownPeriod', {
      value: `${commonEnvironment.COOLDOWN_MINUTES} minutes`,
      description: 'Anti-cycling cooldown period'
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Project', 'VpnCostAutomation');
    cdk.Tags.of(this).add('Component', 'Infrastructure');
    cdk.Tags.of(this).add('Phase', '1-Foundation');
  }
}