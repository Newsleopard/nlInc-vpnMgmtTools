import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as path from 'path';
import { Construct } from 'constructs';
import { SecureParameterManagementStack } from './secure-parameter-management-stack';

export interface VpnAutomationStackProps extends cdk.StackProps {
  environment: string;
  secureParameterStack?: SecureParameterManagementStack;
}

export class VpnAutomationStack extends cdk.Stack {
  public readonly apiGatewayUrl: cdk.CfnOutput;

  constructor(scope: Construct, id: string, props: VpnAutomationStackProps) {
    super(scope, id, props);

    const { environment, secureParameterStack } = props;
    
    // Get current AWS account and region
    const region = cdk.Stack.of(this).region;
    const account = cdk.Stack.of(this).account;

    // Create shared Lambda layer (v2.1 - fixed VPN Monitor logic)
    const sharedLayer = new lambda.LayerVersion(this, 'VpnSharedLayer', {
      code: lambda.Code.fromAsset(path.resolve(__dirname, '../../lambda/shared/layer-package')),
      compatibleRuntimes: [lambda.Runtime.NODEJS_20_X],
      description: 'Shared utilities for VPN Cost Automation',
      layerVersionName: `vpn-shared-layer-${environment}`
    });

    // Epic 5.1: Use secure parameter management roles if available
    const slackHandlerRole = secureParameterStack?.vpnParameterReadRole || new iam.Role(this, 'SlackHandlerRole', {
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
                `arn:aws:ssm:${region}:${account}:parameter/vpn/*`
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt'
              ],
              resources: [
                secureParameterStack?.parameterKmsKey.keyArn || `arn:aws:kms:${region}:${account}:key/*`
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
                `arn:aws:lambda:${region}:${account}:function:VpnAutomation-${environment}-*`
              ]
            })
          ]
        }),
        CrossAccountMetrics: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData'
              ],
              resources: ['*'],
              conditions: {
                StringEquals: {
                  'cloudwatch:namespace': [
                    'VPN/CrossAccount', 
                    'VPN/Automation', 
                    'VPN/Logging'  // Epic 4.1: Enhanced logging metrics
                  ]
                }
              }
            })
          ]
        })
      }
    });

    // Epic 5.1: Use secure parameter management roles if available  
    const vpnControlRole = secureParameterStack?.vpnParameterWriteRole || new iam.Role(this, 'VpnControlRole', {
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
                `arn:aws:ssm:${region}:${account}:parameter/vpn/*`
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
                  'cloudwatch:namespace': [
                    'VPN/Automation', 
                    'VPN/CostOptimization',
                    'VPN/Logging'  // Epic 4.1: Enhanced logging metrics
                  ]
                }
              }
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt'
              ],
              resources: [
                secureParameterStack?.parameterKmsKey.keyArn || `arn:aws:kms:${region}:${account}:key/*`
              ]
            })
          ]
        })
      }
    });

    // Epic 5.1: Environment variables for Lambda functions with secure parameter management
    const commonEnvironment = {
      IDLE_MINUTES: '54',
      ENVIRONMENT: environment,
      VPN_STATE_PREFIX: `/vpn/${environment}/`,
      SIGNING_SECRET_PARAM: `/vpn/${environment}/slack/signing_secret`,
      WEBHOOK_PARAM: `/vpn/${environment}/slack/webhook`,
      BOT_TOKEN_PARAM: `/vpn/${environment}/slack/bot_token`,
      
      // Epic 5.1: Secure parameter management configuration
      SECURE_PARAMETER_ENABLED: 'true',
      KMS_KEY_ID: secureParameterStack?.parameterKmsKey.keyId || '',
      VPN_PARAMETER_KMS_KEY_ID: secureParameterStack?.parameterKmsKey.keyId || '', // Add missing KMS key ID
      PARAMETER_VALIDATION_ENABLED: 'true',
      
      // Enhanced idle detection configuration
      COOLDOWN_MINUTES: '30',
      BUSINESS_HOURS_PROTECTION: 'false',
      BUSINESS_HOURS_TIMEZONE: 'Asia/Taipei',
      
      // Epic 3.2: Authorization configuration
      PRODUCTION_AUTHORIZED_USERS: '*',
      ADMIN_AUTHORIZED_USERS: '',
      
      // Epic 3.2: Cost optimization configuration
      COST_TRACKING_ENABLED: 'true',
      REGIONAL_PRICING_ENABLED: 'true',
      CUMULATIVE_SAVINGS_TRACKING: 'true',
      
      // Epic 3.2: Enhanced notification settings
      ENHANCED_NOTIFICATIONS: 'true',
      COST_ALERTS_CHANNEL: '#vpn-costs',
      ADMIN_ALERTS_CHANNEL: '#vpn-alerts',
      
      // Epic 4.1: Comprehensive logging configuration
      LOG_LEVEL: 'INFO',
      STRUCTURED_LOGGING: 'true',
      AUDIT_LOGGING: 'true',
      PERFORMANCE_MONITORING: 'true',
      SECURITY_LOGGING: 'true',
      LOG_RETENTION_DAYS: '30',
      VERBOSE_LOGGING: 'false'
    };

    // vpn-control Lambda function (define first so we can reference its name)
    const vpnControl = new lambda.Function(this, 'VpnControl', {
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset(path.resolve(__dirname, '../../lambda/vpn-control/dist')),
      layers: [sharedLayer],
      role: vpnControlRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256, // Optimized for performance
      environment: commonEnvironment,
      description: `VPN control function for ${environment} environment`
    });

    // slack-handler Lambda function
    const slackHandler = new lambda.Function(this, 'SlackHandler', {
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset(path.resolve(__dirname, '../../lambda/slack-handler/dist')),
      layers: [sharedLayer],
      role: slackHandlerRole,
      timeout: cdk.Duration.seconds(15), // Reduced timeout for Slack's 3-second requirement
      memorySize: 256, // Optimized for performance to avoid Slack timeouts
      environment: {
        ...commonEnvironment,
        VPN_CONTROL_FUNCTION_NAME: vpnControl.functionName,
        // Production API endpoint will be set during deployment
        ...(environment === 'staging' ? {
          PRODUCTION_API_ENDPOINT: '',
          PRODUCTION_API_KEY: ''
        } : {})
      },
      description: `Slack command handler for ${environment} environment`
    });

    // vpn-monitor Lambda function (for scheduled monitoring)
    // VPN Monitor needs write access to disassociate idle connections
    const vpnMonitorRole = secureParameterStack?.vpnParameterWriteRole || vpnControlRole;
    
    const vpnMonitor = new lambda.Function(this, 'VpnMonitor', {
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromAsset(path.resolve(__dirname, '../../lambda/vpn-monitor/dist')),
      layers: [sharedLayer],
      role: vpnMonitorRole, // Use write role for VPN management operations
      timeout: cdk.Duration.seconds(60),
      memorySize: 256, // Optimized for performance
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
      apiKeyRequired: true,
      requestValidatorOptions: {
        requestValidatorName: 'vpn-request-validator',
        validateRequestBody: true,
        validateRequestParameters: false
      },
      methodResponses: [
        {
          statusCode: '200',
          responseModels: {
            'application/json': apigateway.Model.EMPTY_MODEL
          }
        },
        {
          statusCode: '400',
          responseModels: {
            'application/json': apigateway.Model.ERROR_MODEL
          }
        },
        {
          statusCode: '500',
          responseModels: {
            'application/json': apigateway.Model.ERROR_MODEL
          }
        }
      ]
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
          rateLimit: 20, // Increased for better cross-account performance
          burstLimit: 50
        },
        quota: {
          limit: 2000, // Increased daily quota
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

    // Lambda Warming Infrastructure
    // Business hours warming rule (9 AM - 6 PM Taiwan time, Mon-Fri)
    const businessHoursWarmingRule = new events.Rule(this, 'BusinessHoursWarmingRule', {
      schedule: events.Schedule.expression('rate(3 minutes)'),
      description: `Business hours Lambda warming for ${environment} environment`,
      enabled: true
    });

    // Off-hours warming rule (6 PM - 9 AM Taiwan time, Mon-Fri)
    const offHoursWarmingRule = new events.Rule(this, 'OffHoursWarmingRule', {
      schedule: events.Schedule.expression('rate(15 minutes)'),
      description: `Off-hours Lambda warming for ${environment} environment`,
      enabled: true
    });

    // Weekend warming rule (Sat-Sun, all day)
    const weekendWarmingRule = new events.Rule(this, 'WeekendWarmingRule', {
      schedule: events.Schedule.expression('rate(30 minutes)'),
      description: `Weekend Lambda warming for ${environment} environment`,
      enabled: true
    });

    // Warming event payload
    const warmingEventPayload = {
      source: 'aws.events',
      'detail-type': 'Scheduled Event',
      detail: {
        warming: true,
        environment: environment,
        timestamp: '{{aws.events.scheduled-time}}'
      }
    };

    // Add all Lambda functions as targets for each warming rule
    const lambdaFunctions = [slackHandler, vpnControl, vpnMonitor];

    lambdaFunctions.forEach((lambdaFunction, index) => {
      // Business hours warming
      businessHoursWarmingRule.addTarget(new targets.LambdaFunction(lambdaFunction, {
        event: events.RuleTargetInput.fromObject(warmingEventPayload)
      }));
      
      // Off-hours warming
      offHoursWarmingRule.addTarget(new targets.LambdaFunction(lambdaFunction, {
        event: events.RuleTargetInput.fromObject(warmingEventPayload)
      }));
      
      // Weekend warming
      weekendWarmingRule.addTarget(new targets.LambdaFunction(lambdaFunction, {
        event: events.RuleTargetInput.fromObject(warmingEventPayload)
      }));
      
      // Grant CloudWatch Events permission to invoke each Lambda for warming
      lambdaFunction.addPermission(`AllowBusinessHoursWarmingInvoke${index}`, {
        principal: new iam.ServicePrincipal('events.amazonaws.com'),
        sourceArn: businessHoursWarmingRule.ruleArn
      });
      
      lambdaFunction.addPermission(`AllowOffHoursWarmingInvoke${index}`, {
        principal: new iam.ServicePrincipal('events.amazonaws.com'),
        sourceArn: offHoursWarmingRule.ruleArn
      });
      
      lambdaFunction.addPermission(`AllowWeekendWarmingInvoke${index}`, {
        principal: new iam.ServicePrincipal('events.amazonaws.com'),
        sourceArn: weekendWarmingRule.ruleArn
      });
    });

    // Epic 4.1: Enhanced CloudWatch log groups with custom retention
    const slackHandlerLogGroup = new logs.LogGroup(this, 'SlackHandlerLogGroup', {
      logGroupName: `/aws/lambda/${slackHandler.functionName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    const vpnControlLogGroup = new logs.LogGroup(this, 'VpnControlLogGroup', {
      logGroupName: `/aws/lambda/${vpnControl.functionName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    const vpnMonitorLogGroup = new logs.LogGroup(this, 'VpnMonitorLogGroup', {
      logGroupName: `/aws/lambda/${vpnMonitor.functionName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Epic 4.1: CloudWatch Dashboard for comprehensive monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'VpnAutomationDashboard', {
      dashboardName: `VPN-Automation-${environment}`,
      periodOverride: cloudwatch.PeriodOverride.AUTO
    });

    // Add Lambda metrics widgets
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Invocations',
        left: [
          slackHandler.metricInvocations(),
          vpnControl.metricInvocations(),
          vpnMonitor.metricInvocations()
        ],
        period: cdk.Duration.minutes(5)
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Errors',
        left: [
          slackHandler.metricErrors(),
          vpnControl.metricErrors(),
          vpnMonitor.metricErrors()
        ],
        period: cdk.Duration.minutes(5)
      })
    );

    // Add Lambda warming metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Warming Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Lambda',
            metricName: 'Invocations',
            dimensionsMap: { FunctionName: slackHandler.functionName },
            label: 'Slack Handler Invocations'
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Lambda',
            metricName: 'Invocations',
            dimensionsMap: { FunctionName: vpnControl.functionName },
            label: 'VPN Control Invocations'
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Lambda',
            metricName: 'Invocations',
            dimensionsMap: { FunctionName: vpnMonitor.functionName },
            label: 'VPN Monitor Invocations'
          })
        ],
        period: cdk.Duration.minutes(5)
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Cold Start Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Lambda',
            metricName: 'Duration',
            dimensionsMap: { FunctionName: slackHandler.functionName },
            statistic: 'Maximum',
            label: 'Slack Handler Max Duration'
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Lambda',
            metricName: 'Duration',
            dimensionsMap: { FunctionName: vpnControl.functionName },
            statistic: 'Maximum',
            label: 'VPN Control Max Duration'
          })
        ],
        period: cdk.Duration.minutes(5)
      })
    );

    // Add VPN automation metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'VPN Operations',
        left: [
          new cloudwatch.Metric({
            namespace: 'VPN/Automation',
            metricName: 'VpnAssociationStatus',
            dimensionsMap: { Environment: environment }
          }),
          new cloudwatch.Metric({
            namespace: 'VPN/Automation',
            metricName: 'VpnActiveConnections',
            dimensionsMap: { Environment: environment }
          })
        ],
        period: cdk.Duration.minutes(5)
      }),
      new cloudwatch.GraphWidget({
        title: 'Cost Optimization Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'VPN/CostOptimization',
            metricName: 'CostSavingsPerHour',
            dimensionsMap: { Environment: environment }
          }),
          new cloudwatch.Metric({
            namespace: 'VPN/CostOptimization',
            metricName: 'CumulativeSavings',
            dimensionsMap: { Environment: environment }
          })
        ],
        period: cdk.Duration.hours(1)
      })
    );

    // Epic 4.1: Logging and audit metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Logging Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'VPN/Logging',
            metricName: 'ERRORErrors',
            dimensionsMap: { Environment: environment }
          }),
          new cloudwatch.Metric({
            namespace: 'VPN/Logging',
            metricName: 'CRITICALErrors',
            dimensionsMap: { Environment: environment }
          }),
          new cloudwatch.Metric({
            namespace: 'VPN/Logging',
            metricName: 'CriticalErrorCount'
          })
        ],
        period: cdk.Duration.minutes(5)
      }),
      new cloudwatch.GraphWidget({
        title: 'Cross-Account Operations',
        left: [
          new cloudwatch.Metric({
            namespace: 'VPN/CrossAccount',
            metricName: 'CrossAccountSuccess',
            dimensionsMap: { SourceEnvironment: environment }
          }),
          new cloudwatch.Metric({
            namespace: 'VPN/CrossAccount',
            metricName: 'CrossAccountFailure',
            dimensionsMap: { SourceEnvironment: environment }
          })
        ],
        period: cdk.Duration.minutes(5)
      }),
      new cloudwatch.GraphWidget({
        title: 'Security & Performance Monitoring',
        left: [
          new cloudwatch.Metric({
            namespace: 'VPN/Security',
            metricName: 'SecurityEventCount'
          })
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'VPN/Performance',
            metricName: 'SlowOperationCount'
          })
        ],
        period: cdk.Duration.minutes(5)
      })
    );

    // Epic 4.1: CloudWatch Alarms for critical errors
    const criticalErrorAlarm = new cloudwatch.Alarm(this, 'CriticalErrorAlarm', {
      alarmName: `VPN-${environment}-CriticalErrors`,
      alarmDescription: `Critical errors in VPN automation ${environment}`,
      metric: new cloudwatch.Metric({
        namespace: 'VPN/Logging',
        metricName: 'CRITICALErrors',
        dimensionsMap: { Environment: environment },
        statistic: 'Sum'
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    const functionErrorAlarm = new cloudwatch.Alarm(this, 'FunctionErrorAlarm', {
      alarmName: `VPN-${environment}-FunctionErrors`,
      alarmDescription: `Lambda function errors in VPN automation ${environment}`,
      metric: new cloudwatch.MathExpression({
        expression: 'm1 + m2 + m3',
        usingMetrics: {
          m1: slackHandler.metricErrors(),
          m2: vpnControl.metricErrors(),
          m3: vpnMonitor.metricErrors()
        }
      }),
      threshold: 3,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
    });

    // Epic 4.1: Log Stream for centralized error monitoring
    const errorLogStream = new logs.LogStream(this, 'ErrorLogStream', {
      logGroup: slackHandlerLogGroup,
      logStreamName: `error-stream-${environment}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Epic 4.1: Metric filters for advanced log monitoring
    const criticalErrorFilter = new logs.MetricFilter(this, 'CriticalErrorFilter', {
      logGroup: slackHandlerLogGroup,
      filterPattern: logs.FilterPattern.stringValue('$.level', '=', 'CRITICAL'),
      metricNamespace: 'VPN/Logging',
      metricName: 'CriticalErrorCount',
      metricValue: '1',
      defaultValue: 0
    });

    const securityEventFilter = new logs.MetricFilter(this, 'SecurityEventFilter', {
      logGroup: slackHandlerLogGroup,
      filterPattern: logs.FilterPattern.exists('$.metadata.securityEvent'),
      metricNamespace: 'VPN/Security',
      metricName: 'SecurityEventCount',
      metricValue: '1',
      defaultValue: 0
    });

    const performanceThresholdFilter = new logs.MetricFilter(this, 'PerformanceThresholdFilter', {
      logGroup: vpnControlLogGroup,
      filterPattern: logs.FilterPattern.numberValue('$.performance.duration', '>', 5000), // >5 seconds
      metricNamespace: 'VPN/Performance',
      metricName: 'SlowOperationCount',
      metricValue: '1',
      defaultValue: 0
    });

    // Epic 4.1: Additional CloudWatch alarms for logging metrics
    const securityEventAlarm = new cloudwatch.Alarm(this, 'SecurityEventAlarm', {
      alarmName: `VPN-${environment}-SecurityEvents`,
      alarmDescription: `High-risk security events detected in ${environment}`,
      metric: new cloudwatch.Metric({
        namespace: 'VPN/Security',
        metricName: 'SecurityEventCount',
        statistic: 'Sum'
      }),
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    const performanceAlarm = new cloudwatch.Alarm(this, 'PerformanceAlarm', {
      alarmName: `VPN-${environment}-SlowOperations`,
      alarmDescription: `Slow VPN operations detected in ${environment}`,
      metric: new cloudwatch.Metric({
        namespace: 'VPN/Performance',
        metricName: 'SlowOperationCount',
        statistic: 'Sum'
      }),
      threshold: 3,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Note: All SSM parameters are now created by the VpnSecureParameters stack
    // to avoid duplication and enable Epic 5.1 secure parameter management

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

    // Epic 4.1: Additional outputs for logging infrastructure
    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${region}.console.aws.amazon.com/cloudwatch/home?region=${region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for VPN Automation monitoring'
    });

    new cdk.CfnOutput(this, 'LogGroupNames', {
      value: JSON.stringify({
        slackHandler: slackHandlerLogGroup.logGroupName,
        vpnControl: vpnControlLogGroup.logGroupName,
        vpnMonitor: vpnMonitorLogGroup.logGroupName
      }),
      description: 'CloudWatch Log Group names for all Lambda functions'
    });

    // Epic 4.1: CloudWatch Log Insights queries for common troubleshooting
    new cdk.CfnOutput(this, 'LogInsightsQueries', {
      value: JSON.stringify({
        errors: 'fields @timestamp, level, message, context.correlationId | filter level = "ERROR" or level = "CRITICAL" | sort @timestamp desc',
        auditTrail: 'fields @timestamp, audit.operation, audit.resource, audit.outcome, context.userId | filter ispresent(audit) | sort @timestamp desc',
        performance: 'fields @timestamp, message, performance.duration, context.functionName | filter performance.duration > 1000 | sort performance.duration desc',
        crossAccount: 'fields @timestamp, message, metadata | filter message like /cross.account/ | sort @timestamp desc'
      }),
      description: 'Pre-built CloudWatch Log Insights queries for troubleshooting'
    });

    // Lambda Warming Configuration Outputs
    new cdk.CfnOutput(this, 'LambdaWarmingStrategy', {
      value: JSON.stringify({
        businessHours: '3 minutes (9 AM - 6 PM Taiwan)',
        offHours: '15 minutes (6 PM - 9 AM Taiwan)',
        weekend: '30 minutes (Sat-Sun all day)',
        estimatedMonthlyCost: '$8-12'
      }),
      description: 'Lambda warming configuration and schedule'
    });

    new cdk.CfnOutput(this, 'WarmingRuleArns', {
      value: JSON.stringify({
        businessHours: businessHoursWarmingRule.ruleArn,
        offHours: offHoursWarmingRule.ruleArn,
        weekend: weekendWarmingRule.ruleArn
      }),
      description: 'CloudWatch Events rule ARNs for Lambda warming'
    });

    new cdk.CfnOutput(this, 'VpnControlEndpoint', {
      value: `${api.url}vpn`,
      description: 'VPN control endpoint URL (requires API key)'
    });

    // Epic 4.1: Add comprehensive tagging for resource management
    cdk.Tags.of(this).add('Project', 'VPN-Cost-Automation');
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Epic', 'Epic-4.1-Comprehensive-Logging');
    cdk.Tags.of(this).add('CreatedBy', 'CDK');
    cdk.Tags.of(this).add('Purpose', 'Cost-Optimization-and-Logging');
    cdk.Tags.of(this).add('LoggingEnabled', 'true');
    cdk.Tags.of(this).add('MonitoringEnabled', 'true');

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

    new cdk.CfnOutput(this, 'CrossAccountRouting', {
      value: environment === 'staging' ? 'Enabled (routes to production)' : 'N/A (production endpoint)',
      description: 'Cross-account routing capability'
    });

    new cdk.CfnOutput(this, 'ApiGatewayThrottling', {
      value: environment === 'production' ? 'Enabled (20 req/sec, 50 burst)' : 'N/A',
      description: 'API Gateway rate limiting configuration'
    });

    new cdk.CfnOutput(this, 'CostOptimizationFeatures', {
      value: 'Enhanced cost tracking, regional pricing, cumulative savings, admin overrides',
      description: 'Epic 3.2 cost optimization features enabled'
    });

    new cdk.CfnOutput(this, 'AdminCommands', {
      value: 'override, clear-override, cooldown, force-close, cost-savings, cost-analysis',
      description: 'Available administrative commands'
    });

    new cdk.CfnOutput(this, 'CostMetricsNamespace', {
      value: 'VPN/CostOptimization',
      description: 'CloudWatch namespace for cost optimization metrics'
    });

    // Add tags to all resources (Updated for Epic 3.2)
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Project', 'VpnCostAutomation');
    cdk.Tags.of(this).add('Component', 'Infrastructure');
    cdk.Tags.of(this).add('Phase', '2-Enhanced-Features');
    cdk.Tags.of(this).add('Epic', '3.2-Automatic-Cost-Saving-Actions');
    cdk.Tags.of(this).add('CostOptimization', 'enabled');
    cdk.Tags.of(this).add('AutomationLevel', 'advanced');
  }
}