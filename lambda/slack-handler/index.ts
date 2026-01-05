import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';
import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';
import { CloudWatchClient, PutMetricDataCommand, StandardUnit } from '@aws-sdk/client-cloudwatch';
import * as querystring from 'querystring';

// Import shared utilities from Lambda Layer
import { SlackCommand, VpnCommandRequest, VpnCommandResponse, CrossAccountRequest, ScheduleStatusData } from '/opt/nodejs/types';
import * as slack from '/opt/nodejs/slack';
import * as stateStore from '/opt/nodejs/stateStore';
import { createLogger, extractLogContext, withPerformanceLogging } from '/opt/nodejs/logger';
import * as scheduleManager from '/opt/nodejs/scheduleManager';

const lambda = new LambdaClient({});
const cloudwatch = new CloudWatchClient({});
const ENVIRONMENT = process.env.ENVIRONMENT || 'staging';

// Warming detection helper function
const isWarmingRequest = (event: any): boolean => {
  return event.source === 'aws.events' && 
         event['detail-type'] === 'Scheduled Event' &&
         event.detail?.warming === true;
};

export const handler = async (
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> => {
  // Handle warming requests
  if (isWarmingRequest(event)) {
    console.log('Warming request received - Slack handler is now warm');
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: 'Slack handler warmed successfully',
        functionName: context.functionName,
        timestamp: new Date().toISOString(),
        environment: ENVIRONMENT
      })
    };
  }

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
      
      // Security: Only log metadata, never secret values
      logger.debug('Slack signing secret loaded', {
        hasValue: !!signingSecret,
        lengthValid: signingSecret.length > 0
      });

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
        
        // Security: Never expose signature details in response
        return {
          statusCode: 200,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            response_type: 'ephemeral',
            text: '❌ Invalid Slack signature. Please contact your administrator if this persists.'
          })
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
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          response_type: 'ephemeral',
          text: '❌ Authentication configuration error. Please contact your administrator.'
        })
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

    // Handle help commands immediately
    if (vpnCommand.action === 'help') {
      logger.info('Returning help message', {
        user: vpnCommand.user,
        requestId: vpnCommand.requestId
      });
      
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: vpnCommand.helpMessage || JSON.stringify({
          response_type: 'ephemeral',
          text: 'Help information not available'
        })
      };
    }

    // Handle schedule help command immediately
    if (vpnCommand.action === 'schedule-help') {
      logger.info('Returning schedule help message', {
        user: vpnCommand.user,
        requestId: vpnCommand.requestId
      });
      
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: vpnCommand.helpMessage || JSON.stringify({
          response_type: 'ephemeral',
          text: 'Schedule help information not available'
        })
      };
    }

    // Handle schedule commands synchronously (quick operations)
    // Requirements: 1.1, 2.1, 3.1, 4.1, 4.2, 4.3, 4.4
    if (vpnCommand.action.startsWith('schedule-')) {
      logger.info('Processing schedule command synchronously', {
        action: vpnCommand.action,
        environment: vpnCommand.environment,
        user: vpnCommand.user,
        duration: vpnCommand.duration
      });
      
      const scheduleResponse = await handleScheduleCommand(vpnCommand, logger);
      
      logger.audit('Schedule command completed', 'schedule_command', scheduleResponse.success ? 'success' : 'failure', {
        command: vpnCommand.action,
        environment: vpnCommand.environment,
        user: vpnCommand.user,
        requestId: vpnCommand.requestId,
        success: scheduleResponse.success,
        error: scheduleResponse.error
      });
      
      return {
        statusCode: 200,
        headers: { 
          'Content-Type': 'application/json',
          'X-Correlation-ID': logger.getCorrelationId()
        },
        body: JSON.stringify(scheduleResponse.slackResponse)
      };
    }

    // For potentially long-running operations (open/close), invoke asynchronously
    const isLongRunningOperation = ['open', 'close', 'start', 'stop', 'enable', 'disable', 'on', 'off'].includes(vpnCommand.action);

    if (isLongRunningOperation) {
      // NOTE: Pre-validation for intermediate states was removed because it caused
      // Slack operation_timeout errors. The synchronous status check took too long
      // (especially for cross-account calls). vpn-control now handles intermediate
      // state detection and will send appropriate error notifications via Slack.

      logger.info('Processing long-running operation asynchronously', {
        action: vpnCommand.action,
        environment: vpnCommand.environment
      });

      // Invoke vpn-control asynchronously - returns immediately
      // vpn-control handles all Slack notifications (⏳ started, then vpn-monitor sends ✅ ready)
      // Using InvocationType: 'Event' for async invocation (NOT in-process fire-and-forget)
      try {
        const isLocalCommand = vpnCommand.environment === ENVIRONMENT;

        if (isLocalCommand) {
          await invokeVpnControlAsync(vpnCommand, logger);
        } else {
          // Cross-account: invoke production API Gateway
          await invokeProductionAsync(vpnCommand, logger);
        }

        logger.info('Async invocation queued, returning immediate response', {
          action: vpnCommand.action,
          environment: vpnCommand.environment,
          isLocalCommand
        });

      } catch (invocationError) {
        logger.error('Failed to queue async invocation', invocationError, {
          action: vpnCommand.action,
          environment: vpnCommand.environment
        });

        // Return error to user if we can't even queue the request
        return {
          statusCode: 200,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            response_type: 'ephemeral',
            text: `❌ Failed to start VPN ${vpnCommand.action} operation`,
            attachments: [{
              color: 'danger',
              fields: [{
                title: 'Error',
                value: invocationError.message,
                short: false
              }]
            }]
          })
        };
      }

      // Return immediate acknowledgment to Slack (within 3 seconds)
      // No duplicate message - vpn-control will send notifications
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          response_type: 'in_channel',
          text: `🔄 Processing VPN ${vpnCommand.action} for ${vpnCommand.environment}...`
        })
      };
    }

    // For quick operations (check/status), process synchronously
    logger.info('Processing quick operation synchronously', {
      action: vpnCommand.action,
      environment: vpnCommand.environment
    });

    // Route command based on environment
    let response: VpnCommandResponse;
    
    // Cost commands always execute locally since they aggregate data from both environments
    const isCostCommand = vpnCommand.action.startsWith('cost-');
    const isLocalCommand = vpnCommand.environment === ENVIRONMENT || isCostCommand;
    
    if (isLocalCommand) {
      // Local command - invoke vpn-control Lambda directly
      logger.info('Processing local command', {
        targetEnvironment: isCostCommand ? 'local_aggregated' : ENVIRONMENT,
        routingType: 'local_lambda',
        isCostCommand: isCostCommand
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
  
  const vpnControlFunctionName = process.env.VPN_CONTROL_FUNCTION_NAME || `VpnAutomationStack-${ENVIRONMENT}-VpnControl`;
  
  try {
    childLogger.info('Invoking local vpn-control Lambda', {
      functionName: vpnControlFunctionName,
      command: command.action,
      environment: command.environment
    });
    
    const invocationStart = Date.now();
    
    const result = await lambda.send(new InvokeCommand({
      FunctionName: vpnControlFunctionName,
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
      functionName: vpnControlFunctionName,
      payloadSize: result.Payload ? result.Payload.toString().length : 0
    });

    if (!result.Payload) {
      throw new Error('No response from vpn-control Lambda');
    }

    // Convert Uint8Array to string properly
    const payloadString = new TextDecoder().decode(result.Payload);
    childLogger.debug('Raw Lambda response payload', {
      payloadLength: payloadString.length,
      payloadStart: payloadString.substring(0, 100),
      payloadEnd: payloadString.substring(Math.max(0, payloadString.length - 100))
    });
    
    const lambdaResponse = JSON.parse(payloadString);
    
    childLogger.debug('Lambda response received', {
      statusCode: lambdaResponse.statusCode,
      hasBody: !!lambdaResponse.body,
      bodyLength: lambdaResponse.body ? lambdaResponse.body.length : 0,
      bodyStart: lambdaResponse.body ? lambdaResponse.body.substring(0, 50) : 'no body',
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
      functionName: vpnControlFunctionName
    });
    
    return {
      success: false,
      message: 'Local VPN operation failed',
      error: `Local VPN operation failed: ${error.message}`
    };
  }
}

/**
 * Invoke vpn-control Lambda asynchronously (fire-and-forget via Lambda service)
 * Uses InvocationType: 'Event' which queues the invocation and returns immediately.
 * This is NOT the same as in-process fire-and-forget (which doesn't work in Lambda).
 * AWS queues the invocation in a separate execution context.
 */
async function invokeVpnControlAsync(command: VpnCommandRequest, logger: any): Promise<void> {
  const childLogger = logger.child({ operation: 'invokeVpnControlAsync' });

  const vpnControlFunctionName = process.env.VPN_CONTROL_FUNCTION_NAME ||
    `VpnAutomationStack-${ENVIRONMENT}-VpnControl`;

  childLogger.info('Invoking vpn-control asynchronously', {
    functionName: vpnControlFunctionName,
    action: command.action,
    environment: command.environment,
    requestId: command.requestId
  });

  try {
    await lambda.send(new InvokeCommand({
      FunctionName: vpnControlFunctionName,
      InvocationType: 'Event',  // Async - queues invocation, returns immediately
      Payload: JSON.stringify({
        httpMethod: 'POST',
        body: JSON.stringify(command),
        headers: {
          'Content-Type': 'application/json',
          'X-Correlation-ID': logger.getCorrelationId()
        }
      })
    }));

    childLogger.info('Async invocation queued successfully', {
      functionName: vpnControlFunctionName,
      action: command.action,
      environment: command.environment
    });

  } catch (error) {
    childLogger.error('Failed to invoke vpn-control asynchronously', error, {
      functionName: vpnControlFunctionName,
      action: command.action,
      environment: command.environment
    });
    throw error;
  }
}

/**
 * Invoke production vpn-control via API Gateway asynchronously
 * For cross-account operations, we need to call the production API Gateway
 */
async function invokeProductionAsync(command: VpnCommandRequest, logger: any): Promise<void> {
  const childLogger = logger.child({ operation: 'invokeProductionAsync' });

  let productionAPIEndpoint = process.env.PRODUCTION_API_ENDPOINT;
  let apiKey = process.env.PRODUCTION_API_KEY || '';

  // If environment variables are not set, try to read from parameter store
  if (!productionAPIEndpoint) {
    try {
      const crossAccountConfig = await stateStore.readParameter('/vpn/staging/cross_account/config');
      if (crossAccountConfig) {
        const config = JSON.parse(crossAccountConfig);
        productionAPIEndpoint = config.productionApiEndpoint;
        apiKey = config.productionApiKey || '';
      }
    } catch (paramError) {
      childLogger.warn('Failed to read cross-account configuration', {
        error: paramError.message
      });
    }
  }

  if (!productionAPIEndpoint) {
    throw new Error('Production API endpoint not configured');
  }

  childLogger.info('Invoking production API asynchronously', {
    endpoint: productionAPIEndpoint?.substring(0, 50) + '...',
    action: command.action,
    environment: command.environment
  });

  const requestBody: CrossAccountRequest = {
    command: command,
    requestId: command.requestId,
    sourceAccount: 'staging',
    crossAccountMetadata: {
      requestTimestamp: new Date().toISOString(),
      sourceEnvironment: ENVIRONMENT,
      routingAttempt: 1,
      userAgent: 'VPN-Automation-Slack-Handler/1.0'
    }
  };

  // Fire-and-forget: 2 second timeout
  // We don't need to wait for production to fully process - just confirm the request was received
  // Slack times out after 3 seconds, so we must return quickly
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 2000);

  try {
    await fetch(productionAPIEndpoint, {
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
    childLogger.info('Cross-account request sent successfully', {
      action: command.action,
      environment: command.environment
    });

  } catch (error: any) {
    clearTimeout(timeoutId);

    // Timeout is expected and acceptable - request was likely sent
    // The production Lambda will handle processing and send its own Slack notifications
    if (error.name === 'AbortError') {
      childLogger.info('Cross-account request sent (timeout expected, production will process)', {
        action: command.action,
        environment: command.environment
      });
      return; // Don't throw - this is expected behavior
    }

    // Only throw for actual errors (network failures, etc.)
    childLogger.error('Failed to invoke production API asynchronously', error, {
      action: command.action,
      environment: command.environment
    });
    throw error;
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
      let productionAPIEndpoint = process.env.PRODUCTION_API_ENDPOINT;
      let apiKey = process.env.PRODUCTION_API_KEY || '';
      
      // If environment variables are not set, try to read from parameter store
      if (!productionAPIEndpoint) {
        try {
          const crossAccountConfig = await stateStore.readParameter('/vpn/staging/cross_account/config');
          if (crossAccountConfig) {
            const config = JSON.parse(crossAccountConfig);
            productionAPIEndpoint = config.productionApiEndpoint;
            apiKey = config.productionApiKey || '';
            childLogger.info('Loaded cross-account configuration from parameter store', {
              hasEndpoint: !!productionAPIEndpoint,
              hasApiKey: !!apiKey
            });
          }
        } catch (paramError) {
          childLogger.warn('Failed to read cross-account configuration from parameter store', {
            error: paramError.message
          });
        }
      }
      
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
      // VPN operations (open/close) can take 1-3 minutes, so use longer timeout
      const timeoutMs = ['open', 'close'].includes(command.action) ? 240000 : 30000; // 4 minutes for VPN ops, 30s for others
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
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
            timeout: timeoutMs,
            requestTime: requestTime
          });
          throw new Error(`Request timeout - production API did not respond within ${timeoutMs/1000} seconds`);
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

/**
 * Handle schedule commands for auto-schedule management
 * 
 * Requirements: 1.1, 2.1, 3.1, 4.1, 4.2, 4.3, 4.4
 * 
 * @param command - VPN command request with schedule action
 * @param logger - Logger instance
 * @returns Object with success status and formatted Slack response
 */
async function handleScheduleCommand(
  command: VpnCommandRequest,
  logger: any
): Promise<{ success: boolean; error?: string; slackResponse: any }> {
  const childLogger = logger.child({ operation: 'handleScheduleCommand' });
  
  try {
    childLogger.info('Processing schedule command', {
      action: command.action,
      environment: command.environment,
      user: command.user,
      duration: command.duration
    });

    let scheduleState: scheduleManager.ScheduleState;
    let statusData: ScheduleStatusData | undefined;
    let response: VpnCommandResponse;

    switch (command.action) {
      case 'schedule-on':
        // Enable both auto-open and auto-close schedules
        // Requirements: 1.1, 1.2, 1.3
        scheduleState = await scheduleManager.enableSchedule(
          command.environment,
          'both',
          command.user
        );
        
        response = {
          success: true,
          message: `Auto-scheduling enabled for ${command.environment}`
        };
        
        childLogger.info('Schedule enabled', {
          environment: command.environment,
          autoOpenEnabled: scheduleState.autoOpen.enabled,
          autoCloseEnabled: scheduleState.autoClose.enabled
        });
        break;

      case 'schedule-off':
        // Disable both auto-open and auto-close schedules
        // Requirements: 2.1, 2.2, 2.3, 2.4, 2.5
        scheduleState = await scheduleManager.disableSchedule(
          command.environment,
          'both',
          command.user,
          command.duration
        );
        
        response = {
          success: true,
          message: command.duration 
            ? `Auto-scheduling disabled for ${command.environment} for ${command.duration}`
            : `Auto-scheduling disabled for ${command.environment} indefinitely`
        };
        
        childLogger.info('Schedule disabled', {
          environment: command.environment,
          duration: command.duration,
          autoOpenEnabled: scheduleState.autoOpen.enabled,
          autoCloseEnabled: scheduleState.autoClose.enabled,
          expiresAt: scheduleState.autoOpen.expiresAt
        });
        break;

      case 'schedule-check':
        // Get schedule status
        // Requirements: 3.1, 3.2, 3.3, 3.4, 3.5
        statusData = await scheduleManager.getScheduleStatus(command.environment);
        
        response = {
          success: true,
          message: `Schedule status for ${command.environment}`
        };
        
        childLogger.info('Schedule status retrieved', {
          environment: command.environment,
          autoOpenEnabled: statusData.autoOpen.enabled,
          autoCloseEnabled: statusData.autoClose.enabled
        });
        break;

      case 'schedule-open-on':
        // Enable only auto-open schedule
        // Requirements: 4.1, 4.5
        scheduleState = await scheduleManager.enableSchedule(
          command.environment,
          'autoOpen',
          command.user
        );
        
        response = {
          success: true,
          message: `Auto-open schedule enabled for ${command.environment}`
        };
        
        childLogger.info('Auto-open schedule enabled', {
          environment: command.environment,
          autoOpenEnabled: scheduleState.autoOpen.enabled
        });
        break;

      case 'schedule-open-off':
        // Disable only auto-open schedule
        // Requirements: 4.2, 4.5
        scheduleState = await scheduleManager.disableSchedule(
          command.environment,
          'autoOpen',
          command.user,
          command.duration
        );
        
        response = {
          success: true,
          message: command.duration
            ? `Auto-open schedule disabled for ${command.environment} for ${command.duration}`
            : `Auto-open schedule disabled for ${command.environment} indefinitely`
        };
        
        childLogger.info('Auto-open schedule disabled', {
          environment: command.environment,
          duration: command.duration,
          autoOpenEnabled: scheduleState.autoOpen.enabled
        });
        break;

      case 'schedule-close-on':
        // Enable only auto-close schedule
        // Requirements: 4.3, 4.5
        scheduleState = await scheduleManager.enableSchedule(
          command.environment,
          'autoClose',
          command.user
        );
        
        response = {
          success: true,
          message: `Auto-close schedule enabled for ${command.environment}`
        };
        
        childLogger.info('Auto-close schedule enabled', {
          environment: command.environment,
          autoCloseEnabled: scheduleState.autoClose.enabled
        });
        break;

      case 'schedule-close-off':
        // Disable only auto-close schedule
        // Requirements: 4.4, 4.5
        scheduleState = await scheduleManager.disableSchedule(
          command.environment,
          'autoClose',
          command.user,
          command.duration
        );
        
        response = {
          success: true,
          message: command.duration
            ? `Auto-close schedule disabled for ${command.environment} for ${command.duration}`
            : `Auto-close schedule disabled for ${command.environment} indefinitely`
        };
        
        childLogger.info('Auto-close schedule disabled', {
          environment: command.environment,
          duration: command.duration,
          autoCloseEnabled: scheduleState.autoClose.enabled
        });
        break;

      default:
        response = {
          success: false,
          message: 'Unknown schedule command',
          error: `Unknown schedule action: ${command.action}`
        };
    }

    // Publish success metric
    await publishScheduleCommandMetric('ScheduleCommandExecuted', 1, command.environment, {
      Action: command.action,
      Success: 'true'
    });

    // Format the response for Slack
    const slackResponse = slack.formatScheduleResponse(response, command, statusData);

    return {
      success: response.success,
      error: response.error,
      slackResponse
    };

  } catch (error: any) {
    childLogger.error('Schedule command failed', {
      action: command.action,
      environment: command.environment,
      error: error.message
    });

    // Publish failure metric
    await publishScheduleCommandMetric('ScheduleCommandExecuted', 1, command.environment, {
      Action: command.action,
      Success: 'false'
    });

    const errorResponse: VpnCommandResponse = {
      success: false,
      message: 'Schedule command failed',
      error: error.message
    };

    const slackResponse = slack.formatScheduleResponse(errorResponse, command);

    return {
      success: false,
      error: error.message,
      slackResponse
    };
  }
}

/**
 * Publish schedule command metrics to CloudWatch
 */
async function publishScheduleCommandMetric(
  metricName: string,
  value: number,
  environment: string,
  dimensions: { [key: string]: string }
): Promise<void> {
  try {
    await cloudwatch.send(new PutMetricDataCommand({
      Namespace: 'VPN/Schedule',
      MetricData: [{
        MetricName: metricName,
        Value: value,
        Unit: StandardUnit.Count,
        Dimensions: [
          { Name: 'Environment', Value: environment },
          ...Object.entries(dimensions).map(([k, v]) => ({ Name: k, Value: v }))
        ],
        Timestamp: new Date()
      }]
    }));
  } catch (error) {
    // Don't throw - metric failure shouldn't break the main operation
    console.warn('Failed to publish schedule command metric:', error);
  }
}
