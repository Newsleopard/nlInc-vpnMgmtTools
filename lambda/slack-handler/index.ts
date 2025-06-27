import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';
import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';
import { CloudWatchClient, PutMetricDataCommand, StandardUnit } from '@aws-sdk/client-cloudwatch';
import * as querystring from 'querystring';

// Import shared utilities from Lambda Layer
import { SlackCommand, VpnCommandRequest, VpnCommandResponse, CrossAccountRequest } from '/opt/types';
import * as slack from '/opt/slack';
import * as stateStore from '/opt/stateStore';
import { createLogger, extractLogContext, withPerformanceLogging } from '/opt/logger';

const lambda = new LambdaClient({});
const cloudwatch = new CloudWatchClient({});
const ENVIRONMENT = process.env.ENVIRONMENT || 'staging';

export const handler = async (
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> => {
  // Initialize structured logger with Epic 4.1 enhancements
  const logContext = extractLogContext(event, context, 'slack-handler');
  const logger = createLogger(logContext);
  
  logger.info('Slack Handler Lambda invoked', {
    httpMethod: event.httpMethod,
    userAgent: event.headers['User-Agent'] || event.headers['user-agent'],
    sourceIP: event.requestContext?.identity?.sourceIp,
    path: event.path,
    stage: event.requestContext?.stage
  });

  try {
    // Verify this is a POST request
    if (event.httpMethod !== 'POST') {
      logger.security('Invalid HTTP method attempted', 'low', {
        authenticationMethod: 'none',
        riskScore: 1
      }, {
        method: event.httpMethod,
        path: event.path,
        sourceIP: event.requestContext?.identity?.sourceIp
      });
      
      return {
        statusCode: 405,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Method not allowed' })
      };
    }

    // Parse Slack request body (URL-encoded)
    const body = event.body || '';
    const slackData = querystring.parse(body) as any;
    
    // Verify Slack signature for security
    const signature = event.headers['X-Slack-Signature'] || event.headers['x-slack-signature'] || '';
    const timestamp = event.headers['X-Slack-Request-Timestamp'] || event.headers['x-slack-request-timestamp'] || '';
    
    try {
      const signingSecret = await withPerformanceLogging(
        'readSlackSigningSecret',
        stateStore.readSlackSigningSecret,
        logger
      )();
      
      const isValidSignature = slack.verifySlackSignature(body, signature, timestamp, signingSecret);
      
      if (!isValidSignature) {
        logger.security('Invalid Slack signature detected', 'high', {
          authenticationMethod: 'slack_signature',
          riskScore: 8
        }, {
          sourceIP: event.requestContext?.identity?.sourceIp,
          userAgent: event.headers['User-Agent'],
          signaturePresent: !!signature,
          timestampPresent: !!timestamp
        });
        
        return {
          statusCode: 401,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ error: 'Unauthorized' })
        };
      }
      
      logger.debug('Slack signature verification successful', {
        timestampAge: Math.abs(Date.now() / 1000 - parseInt(timestamp))
      });
      
    } catch (signatureError) {
      logger.error('Failed to verify Slack signature', signatureError, {
        hasSignature: !!signature,
        hasTimestamp: !!timestamp,
        bodyLength: body.length
      });
      
      return {
        statusCode: 500,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Authentication configuration error' })
      };
    }

    // Parse Slack command
    const slackCommand: SlackCommand = {
      token: slackData.token,
      team_id: slackData.team_id,
      team_domain: slackData.team_domain,
      channel_id: slackData.channel_id,
      channel_name: slackData.channel_name,
      user_id: slackData.user_id,
      user_name: slackData.user_name,
      command: slackData.command,
      text: slackData.text || '',
      response_url: slackData.response_url,
      trigger_id: slackData.trigger_id
    };

    // Update logger context with user information
    logger.updateContext({ 
      userId: slackCommand.user_name,
      sessionId: slackCommand.trigger_id 
    });
    
    logger.info('Received Slack command', {
      command: slackCommand.command,
      text: slackCommand.text,
      user: slackCommand.user_name,
      channel: slackCommand.channel_name,
      teamId: slackCommand.team_id,
      teamDomain: slackCommand.team_domain
    });

    // Parse VPN command from Slack text
    let vpnCommand: VpnCommandRequest;
    try {
      vpnCommand = withPerformanceLogging(
        'parseSlackCommand',
        slack.parseSlackCommand,
        logger
      )(slackCommand);
      
      logger.audit('Command parsed', 'slack_command', 'success', {
        command: vpnCommand.action,
        environment: vpnCommand.environment,
        user: vpnCommand.user,
        requestId: vpnCommand.requestId,
        originalText: slackCommand.text
      });
      
    } catch (parseError) {
      logger.warn('Failed to parse VPN command', {
        error: parseError.message,
        originalText: slackCommand.text,
        user: slackCommand.user_name,
        channel: slackCommand.channel_name
      });
      
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          response_type: 'ephemeral',
          text: '❌ Invalid command format',
          attachments: [{
            color: 'danger',
            fields: [{
              title: 'Error',
              value: parseError.message,
              short: false
            }, {
              title: 'Usage',
              value: '`/vpn <action> <environment>`\n' +
                     'Actions: `open`, `close`, `check`\n' +
                     'Environments: `staging`, `production`\n\n' +
                     'Examples:\n' +
                     '• `/vpn open staging`\n' +
                     '• `/vpn close production`\n' +
                     '• `/vpn check staging`',
              short: false
            }]
          }]
        })
      };
    }

    logger.info('Parsed VPN command', {
      action: vpnCommand.action,
      environment: vpnCommand.environment,
      requestId: vpnCommand.requestId,
      isLocalEnvironment: vpnCommand.environment === ENVIRONMENT
    });

    // Route command based on environment
    let response: VpnCommandResponse;
    
    if (vpnCommand.environment === ENVIRONMENT) {
      // Local command - invoke vpn-control Lambda directly
      logger.info('Processing local command', {
        targetEnvironment: ENVIRONMENT,
        routingType: 'local_lambda'
      });
      
      response = await withPerformanceLogging(
        'invokeLocalVpnControl',
        invokeLocalVpnControl,
        logger
      )(vpnCommand, logger);
      
    } else {
      // Cross-account command - call production API Gateway via HTTPS
      logger.info('Processing cross-account command', {
        sourceEnvironment: ENVIRONMENT,
        targetEnvironment: vpnCommand.environment,
        routingType: 'cross_account_api'
      });
      
      response = await withPerformanceLogging(
        'invokeProductionViaAPIGateway',
        invokeProductionViaAPIGateway,
        logger
      )(vpnCommand, logger);
    }

    // Format response for Slack
    const slackResponse = slack.formatSlackResponse(response, vpnCommand);
    
    logger.audit('VPN operation completed', 'vpn_command', response.success ? 'success' : 'failure', {
      command: vpnCommand.action,
      environment: vpnCommand.environment,
      user: vpnCommand.user,
      requestId: vpnCommand.requestId,
      success: response.success,
      error: response.error,
      responseData: response.data ? {
        associated: response.data.associated,
        activeConnections: response.data.activeConnections
      } : undefined
    });
    
    logger.info('Sending Slack response', {
      responseType: slackResponse.response_type,
      hasAttachments: !!slackResponse.attachments,
      success: response.success
    });
    
    return {
      statusCode: 200,
      headers: { 
        'Content-Type': 'application/json',
        'X-Correlation-ID': logger.getCorrelationId()
      },
      body: JSON.stringify(slackResponse)
    };

  } catch (error) {
    logger.critical('Unexpected error in Slack Handler Lambda', error, {
      httpMethod: event.httpMethod,
      path: event.path,
      userAgent: event.headers['User-Agent']
    });
    
    // Send alert about handler failure
    await slack.sendSlackAlert(
      `Slack Handler Lambda error: ${error.message}`,
      ENVIRONMENT,
      'critical'
    );

    return {
      statusCode: 200,
      headers: { 
        'Content-Type': 'application/json',
        'X-Correlation-ID': logger.getCorrelationId()
      },
      body: JSON.stringify({
        response_type: 'ephemeral',
        text: '❌ Internal error processing VPN command',
        attachments: [{
          color: 'danger',
          fields: [{
            title: 'Error',
            value: 'An unexpected error occurred. The development team has been notified.',
            short: false
          }, {
            title: 'Request ID',
            value: logger.getCorrelationId(),
            short: true
          }]
        }]
      })
    };
  }
};

// Invoke local vpn-control Lambda function
async function invokeLocalVpnControl(command: VpnCommandRequest, logger: any): Promise<VpnCommandResponse> {
  const childLogger = logger.child({ operation: 'invokeLocalVpnControl' });
  
  try {
    childLogger.info('Invoking local vpn-control Lambda', {
      functionName: `VpnAutomationStack-${ENVIRONMENT}-VpnControl`,
      command: command.action,
      environment: command.environment
    });
    
    const invocationStart = Date.now();
    
    const result = await lambda.send(new InvokeCommand({
      FunctionName: `VpnAutomationStack-${ENVIRONMENT}-VpnControl`,
      InvocationType: 'RequestResponse',
      Payload: JSON.stringify({
        httpMethod: 'POST',
        body: JSON.stringify(command),
        headers: { 
          'Content-Type': 'application/json',
          'X-Correlation-ID': logger.getCorrelationId()
        }
      })
    }));

    const invocationTime = Date.now() - invocationStart;
    
    childLogger.performance('Lambda invocation completed', {
      duration: invocationTime,
      apiCalls: 1
    }, {
      functionName: `VpnAutomationStack-${ENVIRONMENT}-VpnControl`,
      payloadSize: result.Payload ? result.Payload.toString().length : 0
    });

    if (!result.Payload) {
      throw new Error('No response from vpn-control Lambda');
    }

    const lambdaResponse = JSON.parse(result.Payload.toString());
    
    childLogger.debug('Lambda response received', {
      statusCode: lambdaResponse.statusCode,
      hasBody: !!lambdaResponse.body,
      logResult: result.LogResult ? 'present' : 'absent'
    });
    
    if (lambdaResponse.statusCode !== 200) {
      const errorResponse = JSON.parse(lambdaResponse.body);
      throw new Error(errorResponse.error || 'VPN operation failed');
    }

    const response = JSON.parse(lambdaResponse.body);
    
    childLogger.audit('Local VPN operation', 'lambda_invocation', response.success ? 'success' : 'failure', {
      command: command.action,
      environment: command.environment,
      requestId: command.requestId,
      duration: invocationTime,
      success: response.success
    });

    return response;
    
  } catch (error) {
    childLogger.error('Failed to invoke local vpn-control', error, {
      command: command.action,
      environment: command.environment,
      functionName: `VpnAutomationStack-${ENVIRONMENT}-VpnControl`
    });
    
    return {
      success: false,
      message: 'Local VPN operation failed',
      error: `Local VPN operation failed: ${error.message}`
    };
  }
}

// Invoke production API Gateway via HTTPS for cross-account calls with enhanced retry logic
async function invokeProductionViaAPIGateway(command: VpnCommandRequest, logger: any): Promise<VpnCommandResponse> {
  const childLogger = logger.child({ operation: 'invokeProductionViaAPIGateway' });
  const maxRetries = 3;
  const baseRetryDelay = 1000; // 1 second base delay
  const maxRetryDelay = 10000; // 10 second max delay
  
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const productionAPIEndpoint = process.env.PRODUCTION_API_ENDPOINT;
      const apiKey = process.env.PRODUCTION_API_KEY || '';
      
      if (!productionAPIEndpoint) {
        throw new Error('Production API endpoint not configured');
      }

      childLogger.info(`Calling production API Gateway (attempt ${attempt}/${maxRetries})`, {
        endpoint: productionAPIEndpoint?.substring(0, 50) + '...',
        action: command.action,
        environment: command.environment,
        user: command.user,
        attempt: attempt,
        maxRetries: maxRetries
      });
      
      const requestBody: CrossAccountRequest = {
        command: command,
        requestId: command.requestId,
        sourceAccount: 'staging',
        crossAccountMetadata: {
          requestTimestamp: new Date().toISOString(),
          sourceEnvironment: ENVIRONMENT,
          routingAttempt: attempt,
          userAgent: 'VPN-Automation-Slack-Handler/1.0'
        }
      };

      childLogger.debug('Preparing cross-account request', {
        targetEndpoint: productionAPIEndpoint,
        requestId: command.requestId,
        correlationId: logger.getCorrelationId(),
        payloadSize: JSON.stringify(requestBody).length
      });

      // Add timeout to fetch request
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 30000); // 30 second timeout
      const requestStart = Date.now();
      
      try {
        const response = await fetch(productionAPIEndpoint, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': apiKey,
            'User-Agent': 'VPN-Automation-Slack-Handler/1.0',
            'X-Correlation-ID': logger.getCorrelationId()
          },
          body: JSON.stringify(requestBody),
          signal: controller.signal
        });

        clearTimeout(timeoutId);
        const requestTime = Date.now() - requestStart;

        childLogger.performance('Cross-account API call completed', {
          duration: requestTime,
          networkLatency: requestTime,
          apiCalls: 1
        }, {
          statusCode: response.status,
          attempt: attempt,
          endpoint: productionAPIEndpoint?.substring(0, 50) + '...'
        });

        if (!response.ok) {
          const errorText = await response.text();
          throw new Error(`Production API error: ${response.status} ${response.statusText} - ${errorText}`);
        }

        const result = await response.json() as VpnCommandResponse;
        
        childLogger.info('Production API response received', {
          success: result.success,
          hasData: !!result.data,
          requestId: command.requestId,
          responseTime: requestTime,
          attempt: attempt
        });
        
        // Add success metrics for cross-account calls
        if (result.success) {
          childLogger.audit('Cross-account operation completed successfully', 'cross_account_routing', 'success', {
            action: command.action,
            environment: command.environment,
            attempt: attempt,
            requestId: command.requestId,
            totalAttempts: attempt,
            sourceEnvironment: ENVIRONMENT,
            responseTime: requestTime
          });
          
          // Publish cross-account success metric
          await publishCrossAccountMetric('CrossAccountSuccess', 1, command.environment);
        } else {
          childLogger.warn('Cross-account operation returned failure', {
            action: command.action,
            environment: command.environment,
            error: result.error,
            attempt: attempt
          });
        }
        
        return result;
        
      } catch (fetchError) {
        clearTimeout(timeoutId);
        const requestTime = Date.now() - requestStart;
        
        if (fetchError.name === 'AbortError') {
          childLogger.warn('Cross-account request timeout', {
            attempt: attempt,
            timeout: 30000,
            requestTime: requestTime
          });
          throw new Error('Request timeout - production API did not respond within 30 seconds');
        }
        throw fetchError;
      }
      
    } catch (error) {
      childLogger.error(`Cross-account attempt ${attempt} failed`, error, {
        attempt: attempt,
        maxRetries: maxRetries,
        action: command.action,
        environment: command.environment
      });
      
      // If this is the last attempt or a configuration error, don't retry
      if (attempt === maxRetries || error.message.includes('not configured')) {
        // Publish failure metric
        await publishCrossAccountMetric('CrossAccountFailure', 1, command.environment);
        
        // Send alert for persistent cross-account failures
        if (attempt === maxRetries) {
          await slack.sendSlackAlert(
            `Cross-account routing failed after ${maxRetries} attempts: ${error.message}`,
            ENVIRONMENT,
            'critical'
          );
        }
        
        return {
          success: false,
          message: 'Cross-account VPN operation failed',
          error: `Cross-account VPN operation failed after ${attempt} attempts: ${error.message}`
        };
      }
      
      // Wait before retrying with exponential backoff
      if (attempt < maxRetries) {
        const delay = Math.min(baseRetryDelay * Math.pow(2, attempt - 1), maxRetryDelay);
        console.log(`Retrying in ${delay}ms... (attempt ${attempt + 1}/${maxRetries})`);
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }
  
  // This should never be reached, but just in case
  return {
    success: false,
    message: 'Cross-account VPN operation failed',
    error: 'Cross-account VPN operation failed: Maximum retries exceeded'
  };
}

// Publish cross-account routing metrics
async function publishCrossAccountMetric(
  metricName: string, 
  value: number, 
  targetEnvironment: string
): Promise<void> {
  try {
    await cloudwatch.send(new PutMetricDataCommand({
      Namespace: 'VPN/CrossAccount',
      MetricData: [{
        MetricName: metricName,
        Value: value,
        Unit: StandardUnit.Count,
        Dimensions: [
          {
            Name: 'SourceEnvironment',
            Value: ENVIRONMENT
          },
          {
            Name: 'TargetEnvironment', 
            Value: targetEnvironment
          }
        ],
        Timestamp: new Date()
      }]
    }));
    
    console.log(`Published cross-account metric ${metricName}: ${value}`);
  } catch (error) {
    console.error('Failed to publish cross-account metric:', error);
    // Don't throw as metric failure shouldn't break the main operation
  }
}