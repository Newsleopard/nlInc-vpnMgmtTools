import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';
import { CloudWatchClient, PutMetricDataCommand, StandardUnit } from '@aws-sdk/client-cloudwatch';

// Import shared utilities from Lambda Layer
import { VpnCommandRequest, VpnCommandResponse, CrossAccountRequest } from '/opt/nodejs/types';
import * as vpnManager from '/opt/nodejs/vpnManager';
import * as stateStore from '/opt/nodejs/stateStore';
import * as slack from '/opt/nodejs/slack';
import { createLogger, extractLogContext, withPerformanceLogging } from '/opt/nodejs/logger';
import * as scheduleManager from '/opt/nodejs/scheduleManager';

const cloudwatch = new CloudWatchClient({});
const ENVIRONMENT = process.env.ENVIRONMENT || 'staging';

// Warming detection helper function
const isWarmingRequest = (event: any): boolean => {
  return event.source === 'aws.events' &&
         event['detail-type'] === 'Scheduled Event' &&
         event.detail?.warming === true;
};

// Auto-open detection helper function (for scheduled VPN opening)
const isAutoOpenRequest = (event: any): boolean => {
  return event.source === 'aws.events' &&
         event['detail-type'] === 'Scheduled Event' &&
         event.detail?.autoOpen === true;
};

// Auto-close detection helper function (for scheduled VPN closing - weekend/daily safety)
const isAutoCloseRequest = (event: any): boolean => {
  return event.source === 'aws.events' &&
         event['detail-type'] === 'Scheduled Event' &&
         event.detail?.autoClose === true;
};

export const handler = async (
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> => {
  // Handle warming requests
  if (isWarmingRequest(event)) {
    console.log('Warming request received - VPN control is now warm');
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: 'VPN control warmed successfully',
        functionName: context.functionName,
        timestamp: new Date().toISOString(),
        environment: ENVIRONMENT
      })
    };
  }

  // Handle scheduled auto-close requests (weekend/daily safety)
  if (isAutoCloseRequest(event)) {
    const closeReason = (event as any).detail?.reason || 'scheduled';
    console.log(`Auto-close request received for ${ENVIRONMENT} environment (reason: ${closeReason})`);

    try {
      // Check current status first
      const currentStatus = await vpnManager.fetchStatus();

      // Skip if already closed
      if (!currentStatus.associated) {
        console.log(`VPN ${ENVIRONMENT} is already closed, skipping auto-close`);
        return {
          statusCode: 200,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message: `VPN ${ENVIRONMENT} is already closed`,
            status: 'already_closed',
            timestamp: new Date().toISOString()
          })
        };
      }

      // Skip if currently disassociating (in-progress)
      if (currentStatus.associationState === 'disassociating') {
        console.log(`VPN ${ENVIRONMENT} is currently disassociating, skipping auto-close`);
        return {
          statusCode: 200,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message: `VPN ${ENVIRONMENT} is currently closing`,
            status: 'in_progress',
            timestamp: new Date().toISOString()
          })
        };
      }

      // Check if there are active connections - warn but still close for safety
      if (currentStatus.activeConnections > 0) {
        console.log(`VPN ${ENVIRONMENT} has ${currentStatus.activeConnections} active connections, proceeding with scheduled close`);

        // Send warning notification about active connections
        await slack.sendSlackNotification({
          text: `⚠️ VPN ${ENVIRONMENT} 排程關閉 (有連線中) | Scheduled close with active connections`,
          attachments: [{
            color: 'warning',
            fields: [
              { title: '🕤 Time | 時間', value: new Date().toLocaleString('zh-TW', { timeZone: 'Asia/Taipei' }), short: true },
              { title: '📍 Environment | 環境', value: ENVIRONMENT, short: true },
              { title: '👥 Active Connections | 連線數', value: currentStatus.activeConnections.toString(), short: true },
              { title: '📅 Reason | 原因', value: closeReason === 'weekend' ? 'Weekend auto-close | 週末自動關閉' : 'Daily safety close | 每日安全關閉', short: true },
              { title: '💡 Note | 提示', value: 'Connected users will be disconnected | 連線中的使用者將被中斷', short: false }
            ]
          }]
        });
      }

      // Close the VPN
      await vpnManager.disassociateSubnets();
      const newStatus = await vpnManager.fetchStatus();

      // Determine notification message based on reason
      const reasonText = closeReason === 'weekend'
        ? 'Weekend auto-close (Friday 8PM) | 週末自動關閉 (週五 8PM)'
        : 'Daily safety close (10PM) | 每日安全關閉 (10PM)';

      const reasonEmoji = closeReason === 'weekend' ? '🌙' : '🔒';

      // Send Slack notification
      await slack.sendSlackNotification({
        text: `${reasonEmoji} VPN ${ENVIRONMENT} 自動關閉 | Auto-closed`,
        attachments: [{
          color: '#36a64f',
          fields: [
            { title: '🕤 Time | 時間', value: new Date().toLocaleString('zh-TW', { timeZone: 'Asia/Taipei' }), short: true },
            { title: '📍 Environment | 環境', value: ENVIRONMENT, short: true },
            { title: '🤖 Trigger | 觸發', value: reasonText, short: false },
            { title: '💰 Cost Saving | 成本節省', value: 'Preventing unnecessary charges | 避免不必要的費用', short: false }
          ]
        }]
      });

      await publishMetric('ScheduledAutoCloseOperations', 1);

      console.log(`VPN ${ENVIRONMENT} auto-closed successfully (reason: ${closeReason})`);
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: `VPN ${ENVIRONMENT} auto-closed successfully`,
          status: 'closed',
          reason: closeReason,
          data: newStatus,
          timestamp: new Date().toISOString()
        })
      };
    } catch (error) {
      console.error(`Failed to auto-close VPN ${ENVIRONMENT}:`, error);

      // Send Slack error notification
      await slack.sendSlackNotification({
        text: `❌ VPN ${ENVIRONMENT} 自動關閉失敗 | Auto-close failed`,
        attachments: [{
          color: 'danger',
          fields: [
            { title: '🕤 Time | 時間', value: new Date().toISOString(), short: true },
            { title: '📍 Environment | 環境', value: ENVIRONMENT, short: true },
            { title: '📅 Reason | 原因', value: closeReason, short: true },
            { title: '❌ Error | 錯誤', value: error instanceof Error ? error.message : 'Unknown error', short: false }
          ]
        }]
      });

      return {
        statusCode: 500,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: `Failed to auto-close VPN ${ENVIRONMENT}`,
          error: error instanceof Error ? error.message : 'Unknown error',
          timestamp: new Date().toISOString()
        })
      };
    }
  }

  // Handle scheduled auto-open requests (weekday 10:00 AM)
  if (isAutoOpenRequest(event)) {
    console.log(`Auto-open request received for ${ENVIRONMENT} environment`);
    try {
      // Check if auto-open schedule is enabled (Requirements: 6.1, 6.4)
      const isAutoOpenScheduleEnabled = await scheduleManager.isAutoOpenEnabled(ENVIRONMENT);
      if (!isAutoOpenScheduleEnabled) {
        console.log(`Auto-open schedule is disabled for ${ENVIRONMENT}, skipping scheduled open`);
        
        // Send notification about skipped operation
        await slack.sendSlackNotification({
          text: `📅 VPN ${ENVIRONMENT} 自動開啟已跳過 | Auto-open skipped`,
          attachments: [{
            color: '#ffaa00',
            fields: [
              { title: '🕤 Time | 時間', value: new Date().toISOString(), short: true },
              { title: '📍 Environment | 環境', value: ENVIRONMENT, short: true },
              { title: '📅 Reason | 原因', value: 'Auto-open schedule disabled | 自動開啟排程已停用', short: false },
              { title: '🔧 Re-enable | 重新啟用', value: `/vpn schedule on ${ENVIRONMENT}`, short: false }
            ]
          }]
        });
        
        await publishMetric('ScheduleDisabledSkips', 1);
        
        return {
          statusCode: 200,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message: `Auto-open skipped for ${ENVIRONMENT} - schedule disabled`,
            status: 'schedule_disabled',
            timestamp: new Date().toISOString()
          })
        };
      }
      
      // Check current status first
      const currentStatus = await vpnManager.fetchStatus();

      // Skip if already open
      if (currentStatus.associated) {
        console.log(`VPN ${ENVIRONMENT} is already open, skipping auto-open`);
        return {
          statusCode: 200,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message: `VPN ${ENVIRONMENT} is already open`,
            status: 'already_open',
            timestamp: new Date().toISOString()
          })
        };
      }

      // Skip if currently associating (in-progress)
      if (currentStatus.associationState === 'associating') {
        console.log(`VPN ${ENVIRONMENT} is currently associating, skipping auto-open`);
        return {
          statusCode: 200,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message: `VPN ${ENVIRONMENT} is currently opening`,
            status: 'in_progress',
            timestamp: new Date().toISOString()
          })
        };
      }

      // Open the VPN
      await vpnManager.associateSubnets();
      const newStatus = await vpnManager.fetchStatus();

      // Send Slack notification
      await slack.sendSlackNotification({
        text: `🌅 VPN ${ENVIRONMENT} 自動開啟 | Auto-opened`,
        attachments: [{
          color: 'good',
          fields: [
            { title: '🕤 Time | 時間', value: new Date().toISOString(), short: true },
            { title: '📍 Environment | 環境', value: ENVIRONMENT, short: true },
            { title: '🤖 Trigger | 觸發', value: 'Scheduled auto-open (weekday 10:00 AM)', short: false }
          ]
        }]
      });

      console.log(`VPN ${ENVIRONMENT} auto-opened successfully`);
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: `VPN ${ENVIRONMENT} auto-opened successfully`,
          status: 'opened',
          data: newStatus,
          timestamp: new Date().toISOString()
        })
      };
    } catch (error) {
      console.error(`Failed to auto-open VPN ${ENVIRONMENT}:`, error);

      // Send Slack error notification
      await slack.sendSlackNotification({
        text: `❌ VPN ${ENVIRONMENT} 自動開啟失敗 | Auto-open failed`,
        attachments: [{
          color: 'danger',
          fields: [
            { title: '🕤 Time | 時間', value: new Date().toISOString(), short: true },
            { title: '📍 Environment | 環境', value: ENVIRONMENT, short: true },
            { title: '❌ Error | 錯誤', value: error instanceof Error ? error.message : 'Unknown error', short: false }
          ]
        }]
      });

      return {
        statusCode: 500,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: `Failed to auto-open VPN ${ENVIRONMENT}`,
          error: error instanceof Error ? error.message : 'Unknown error',
          timestamp: new Date().toISOString()
        })
      };
    }
  }

  // Initialize structured logger for Epic 4.1
  const logContext = extractLogContext(event, context, 'vpn-control');
  const logger = createLogger(logContext);
  
  logger.info('VPN Control Lambda invoked', {
    httpMethod: event.httpMethod,
    path: event.path,
    userAgent: event.headers?.['User-Agent'] || event.headers?.['user-agent'],
    sourceIP: event.requestContext?.identity?.sourceIp,
    correlationId: event.headers?.['X-Correlation-ID']
  });

  try {
    // Parse request body
    let requestBody: VpnCommandRequest | CrossAccountRequest;
    
    try {
      requestBody = JSON.parse(event.body || '{}');
    } catch (parseError) {
      console.error('Failed to parse request body:', parseError);
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          success: false,
          message: 'Failed to parse request body',
          error: 'Invalid JSON in request body'
        })
      };
    }

    // Extract command from request (handle both direct and cross-account requests)
    let command: VpnCommandRequest;
    
    if ('command' in requestBody) {
      // Cross-account request format
      command = requestBody.command;
      console.log(`Processing cross-account request from ${requestBody.sourceAccount}`);
    } else {
      // Direct request format
      command = requestBody as VpnCommandRequest;
    }

    console.log('Processing VPN command:', command);

    // Validate command
    if (!command.action || !command.environment) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          success: false,
          message: 'Request validation failed',
          error: 'Missing required fields: action and environment'
        })
      };
    }

    // Validate action (expanded for Epic 3.2)
    const validActions = ['open', 'close', 'check', 'admin-noclose', 'admin-autoclose', 'admin-cooldown', 'admin-force-close', 'cost-savings', 'cost-analysis', 'help'];
    if (!validActions.includes(command.action)) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          success: false,
          message: 'Invalid action specified',
          error: `Invalid action. Must be one of: ${validActions.join(', ')}`
        })
      };
    }

    // Validate environment matches deployment (skip for cost commands which use environment field for report type)
    const isCostCommand = command.action.startsWith('cost-');
    const validEnvironments = ['staging', 'production'];
    
    if (!isCostCommand && command.environment !== ENVIRONMENT) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          success: false,
          message: 'Environment validation failed',
          error: `Environment mismatch. This function handles ${ENVIRONMENT}, but received ${command.environment}`
        })
      };
    }

    // Validate VPN endpoint configuration (skip for check and cost commands)
    if (command.action !== 'check' && !isCostCommand) {
      const isValid = await vpnManager.validateEndpoint();
      if (!isValid) {
        const errorMsg = 'VPN endpoint validation failed. Please check configuration.';
        await slack.sendSlackAlert(errorMsg, ENVIRONMENT, 'critical');
        
        return {
          statusCode: 500,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
          },
          body: JSON.stringify({
            success: false,
            message: 'VPN endpoint validation failed',
            error: errorMsg
          })
        };
      }
    }

    // Execute the requested action
    let response: VpnCommandResponse;
    
    try {
      switch (command.action) {
        case 'open':
          await vpnManager.associateSubnets();
          await updateLastActivity();
          await recordManualActivity(); // Track manual operation for idle detection
          const openStatus = await vpnManager.fetchStatus();
          await publishMetric('VpnOpenOperations', 1);
          
          response = {
            success: true,
            message: `VPN ${ENVIRONMENT} environment opened successfully`,
            data: openStatus
          };
          
          // Send success notification
          await slack.sendSlackNotification(
            `✅ VPN ${ENVIRONMENT} opened by ${command.user}`
          );
          break;

        case 'close':
          await vpnManager.disassociateSubnets();
          await updateLastActivity();
          await recordManualActivity(); // Track manual operation for idle detection
          const closeStatus = await vpnManager.fetchStatus();
          await publishMetric('VpnCloseOperations', 1);
          
          response = {
            success: true,
            message: `VPN ${ENVIRONMENT} environment closed successfully`,
            data: closeStatus
          };
          
          // Send success notification
          await slack.sendSlackNotification(
            `🔴 VPN ${ENVIRONMENT} closed by ${command.user}`
          );
          break;

        case 'check':
          const status = await vpnManager.fetchStatus();
          
          response = {
            success: true,
            message: `VPN ${ENVIRONMENT} status retrieved successfully`,
            data: status
          };
          break;
          
        // Epic 3.2: Administrative commands
        case 'admin-noclose':
          response = await handleAdminNoClose(command);
          break;
          
        case 'admin-autoclose':
          response = await handleAdminAutoClose(command);
          break;
          
        case 'admin-cooldown':
          response = await handleCooldownStatus(command);
          break;
          
        case 'admin-force-close':
          response = await handleForceClose(command);
          break;
          
        // Epic 3.2: Cost analysis commands  
        case 'cost-savings':
          response = await handleCostSavings(command);
          break;
          
        case 'cost-analysis':
          response = await handleCostAnalysis(command);
          break;
          
        case 'help':
          // Help commands should be handled in Slack handler, not here
          response = {
            success: false,
            message: 'Help command should not reach VPN control',
            error: 'Help commands are handled at the Slack handler level'
          };
          break;

        default:
          throw new Error(`Unsupported action: ${command.action}`);
      }

      console.log('VPN operation completed successfully:', response);

    } catch (operationError) {
      console.error(`VPN ${command.action} operation failed:`, operationError);
      
      const errorMessage = operationError instanceof Error ? operationError.message : String(operationError);
      
      // Check if this is an intermediate state error (not a critical system failure)
      const isIntermediateStateError = errorMessage.includes('currently associating') || 
                                     errorMessage.includes('currently disassociating');
      
      if (isIntermediateStateError) {
        // Don't send critical alerts for expected intermediate state blocks
        console.log('Operation blocked due to intermediate state - this is expected behavior');
        await publishMetric('VpnOperationBlocked', 1);
      } else {
        // Send alert for actual operation failures
        await slack.sendSlackAlert(
          `VPN ${command.action} operation failed: ${errorMessage}`,
          ENVIRONMENT,
          'critical'
        );
        await publishMetric('VpnOperationErrors', 1);
      }
      
      response = {
        success: false,
        message: isIntermediateStateError ? 
          'VPN operation temporarily unavailable' : 
          `VPN ${command.action} operation failed`,
        error: errorMessage
      };
    }

    // Return response
    return {
      statusCode: response.success ? 200 : 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify(response)
    };

  } catch (error) {
    console.error('Unexpected error in VPN Control Lambda:', error);
    
    // Send critical alert
    const errorMessage = error instanceof Error ? error.message : String(error);
    await slack.sendSlackAlert(
      `Critical error in VPN Control Lambda: ${errorMessage}`,
      ENVIRONMENT,
      'critical'
    );
    
    await publishMetric('LambdaErrors', 1);

    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        success: false,
        message: 'Critical Lambda error occurred',
        error: 'Internal server error'
      })
    };
  }
};

// Helper function to update last activity timestamp
async function updateLastActivity(): Promise<void> {
  try {
    await vpnManager.updateLastActivity();
  } catch (error) {
    console.error('Failed to update last activity:', error);
    // Don't throw as this shouldn't break the main operation
  }
}

// Helper function to publish CloudWatch metrics
async function publishMetric(metricName: string, value: number): Promise<void> {
  try {
    await cloudwatch.send(new PutMetricDataCommand({
      Namespace: 'VPN/Automation',
      MetricData: [{
        MetricName: metricName,
        Value: value,
        Unit: StandardUnit.Count,
        Dimensions: [{
          Name: 'Environment',
          Value: ENVIRONMENT
        }],
        Timestamp: new Date()
      }]
    }));
    
    console.log(`Published metric ${metricName}: ${value}`);
  } catch (error) {
    console.error('Failed to publish metric:', error);
    // Don't throw as metric failure shouldn't break the main operation
  }
}

// Record manual activity timestamp for intelligent idle detection
async function recordManualActivity(): Promise<void> {
  try {
    const now = new Date().toISOString();
    await stateStore.writeParameter(`/vpn/automation/manual_activity/${ENVIRONMENT}`, now);
    console.log(`Recorded manual activity timestamp: ${now}`);
  } catch (error) {
    console.error('Failed to record manual activity timestamp:', error);
    // Don't throw as this shouldn't break the main operation
  }
}

// Epic 3.2: Handle administrative no-close command (disable auto-close)
async function handleAdminNoClose(command: VpnCommandRequest): Promise<VpnCommandResponse> {
  try {
    const expiryTime = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours
    const overrideValue = `enabled:expires:${expiryTime.toISOString()}`;
    
    await stateStore.writeParameter(`/vpn/automation/admin_override/${ENVIRONMENT}`, overrideValue);
    await publishMetric('AdminOverrideEnabled', 1);
    
    await slack.sendSlackNotification({
      text: "🛡️ Auto-Close Disabled",
      attachments: [{
        color: "warning",
        fields: [
          {
            title: `${ENVIRONMENT === 'production' ? '🚀' : '🔧'} Environment`,
            value: ENVIRONMENT,
            short: true
          },
          {
            title: "👤 Admin",
            value: command.user,
            short: true
          },
          {
            title: "⏰ Duration",
            value: "24 hours (auto-expires)",
            short: true
          },
          {
            title: "⏱️ Expires",
            value: expiryTime.toLocaleString(),
            short: true
          },
          {
            title: "🔧 Status",
            value: "Cost optimization suspended",
            short: true
          },
          {
            title: "📝 Note",
            value: `Use \`/vpn admin autoclose ${ENVIRONMENT}\` to re-enable auto-close`,
            short: false
          }
        ]
      }]
    });
    
    return {
      success: true,
      message: `Auto-close disabled for ${ENVIRONMENT} (expires in 24 hours)`
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      success: false,
      message: 'Disable auto-close operation failed',
      error: `Failed to disable auto-close: ${errorMessage}`
    };
  }
}

// Epic 3.2: Handle auto-close command (re-enable auto-close)
async function handleAdminAutoClose(command: VpnCommandRequest): Promise<VpnCommandResponse> {
  try {
    await stateStore.writeParameter(`/vpn/automation/admin_override/${ENVIRONMENT}`, '');
    await publishMetric('AdminOverrideCleared', 1);
    
    await slack.sendSlackNotification({
      text: "✅ Auto-Close Re-enabled",
      attachments: [{
        color: "good",
        fields: [
          {
            title: `${ENVIRONMENT === 'production' ? '🚀' : '🔧'} Environment`,
            value: ENVIRONMENT,
            short: true
          },
          {
            title: "👤 Admin",
            value: command.user,
            short: true
          },
          {
            title: "🔄 Status",
            value: "Cost optimization active",
            short: true
          },
          {
            title: "⏱️ Monitoring",
            value: "Idle detection resumed",
            short: true
          }
        ]
      }]
    });
    
    return {
      success: true,
      message: `Auto-close re-enabled for ${ENVIRONMENT}. Cost optimization resumed.`
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      success: false,
      message: 'Enable auto-close operation failed',
      error: `Failed to enable auto-close: ${errorMessage}`
    };
  }
}

// Epic 3.2: Handle cooldown status command
async function handleCooldownStatus(_command: VpnCommandRequest): Promise<VpnCommandResponse> {
  try {
    const cooldownParam = await stateStore.readParameter(`/vpn/automation/cooldown/${ENVIRONMENT}`);
    
    if (!cooldownParam) {
      return {
        success: true,
        message: `No cooldown active for ${ENVIRONMENT}`,
        data: { cooldownActive: false, remainingMinutes: 0 } as any
      };
    }
    
    const cooldownTime = new Date(cooldownParam);
    const now = new Date();
    const cooldownElapsed = (now.getTime() - cooldownTime.getTime()) / (1000 * 60);
    const cooldownMinutes = Number(process.env.COOLDOWN_MINUTES || 30);
    const remainingMinutes = Math.max(0, cooldownMinutes - cooldownElapsed);
    
    return {
      success: true,
      message: remainingMinutes > 0 
        ? `Cooldown active: ${Math.ceil(remainingMinutes)} minutes remaining`
        : `Cooldown expired (${Math.floor(cooldownElapsed)} minutes ago)`,
      data: {
        cooldownActive: remainingMinutes > 0,
        remainingMinutes: Math.ceil(remainingMinutes),
        cooldownStarted: cooldownTime.toISOString()
      } as any
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      success: false,
      message: 'Cooldown status check failed',
      error: `Failed to check cooldown status: ${errorMessage}`
    };
  }
}

// Epic 3.2: Handle force close command
async function handleForceClose(command: VpnCommandRequest): Promise<VpnCommandResponse> {
  try {
    await vpnManager.disassociateSubnets();
    await updateLastActivity();
    
    // Clear cooldown to allow immediate re-association if needed
    await stateStore.writeParameter(`/vpn/automation/cooldown/${ENVIRONMENT}`, '');
    
    const status = await vpnManager.fetchStatus();
    await publishMetric('AdminForceCloseOperations', 1);
    
    await slack.sendSlackNotification({
      text: "⚠️ Force Close Executed",
      attachments: [{
        color: "danger",
        fields: [
          {
            title: `${ENVIRONMENT === 'production' ? '🚀' : '🔧'} Environment`,
            value: ENVIRONMENT,
            short: true
          },
          {
            title: "👤 Admin",
            value: command.user,
            short: true
          },
          {
            title: "🔧 Action",
            value: "Bypassed all safety mechanisms",
            short: true
          },
          {
            title: "🔄 Cooldown",
            value: "Cleared for immediate re-association",
            short: true
          },
          {
            title: "⏱️ Timestamp",
            value: new Date().toLocaleString(),
            short: false
          }
        ]
      }]
    });
    
    return {
      success: true,
      message: `VPN ${ENVIRONMENT} force closed successfully`,
      data: status
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      success: false,
      message: 'Force close operation failed',
      error: `Failed to force close: ${errorMessage}`
    };
  }
}

// Epic 3.2: Handle cost savings report
async function handleCostSavings(_command: VpnCommandRequest): Promise<VpnCommandResponse> {
  try {
    // Get cumulative savings (waste time prevented)
    const cumulativeKey = `/vpn/cost_optimization/cumulative_savings/${ENVIRONMENT}`;
    let cumulativeSavings = 0;
    try {
      const cumulative = await stateStore.readParameter(cumulativeKey);
      cumulativeSavings = parseFloat(cumulative) || 0;
    } catch (error) {
      console.log('No cumulative savings data found');
    }
    
    // Get today's savings (waste time prevented today)
    const today = new Date().toISOString().split('T')[0];
    const dailyKey = `/vpn/cost_optimization/daily_savings/${ENVIRONMENT}/${today}`;
    let todaySavings = 0;
    try {
      const daily = await stateStore.readParameter(dailyKey);
      todaySavings = parseFloat(daily) || 0;
    } catch (error) {
      console.log('No daily savings data found for today');
    }
    
    // Get theoretical daily maximum savings (24/7 vs actual usage)
    const dailyMaxKey = `/vpn/cost_optimization/daily_max_savings/${ENVIRONMENT}/${today}`;
    let theoreticalDailySavings = 0;
    try {
      const dailyMax = await stateStore.readParameter(dailyMaxKey);
      theoreticalDailySavings = parseFloat(dailyMax) || 0;
    } catch (error) {
      console.log('No theoretical daily savings data found');
    }
    
    // Get current VPN status
    const status = await vpnManager.fetchStatus();
    const hourlyRate = 0.10; // Base rate per subnet per hour
    
    const report = {
      environment: ENVIRONMENT,
      cumulativeSavings: cumulativeSavings.toFixed(2),
      todaySavings: todaySavings.toFixed(2),
      theoreticalDailySavings: theoreticalDailySavings.toFixed(2),
      currentStatus: status.associated ? 'Running (accumulating cost)' : 'Stopped (saving money)',
      potentialHourlySavings: status.associated ? hourlyRate.toFixed(2) : '0.00',
      explanation: 'Savings = waste time prevented (VPN would run 24/7 without auto-system)',
      lastUpdated: new Date().toISOString()
    };
    
    return {
      success: true,
      message: `Cost savings report for ${ENVIRONMENT}`,
      data: report as any
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      success: false,
      message: 'Cost savings report generation failed',
      error: `Failed to generate cost savings report: ${errorMessage}`
    };
  }
}

// Epic 3.2: Handle cost analysis command
async function handleCostAnalysis(command: VpnCommandRequest): Promise<VpnCommandResponse> {
  try {
    const reportType = command.environment; // Using environment field for report type
    
    if (reportType === 'daily') {
      // Get last 7 days of savings
      const dailyReports = [];
      for (let i = 0; i < 7; i++) {
        const date = new Date();
        date.setDate(date.getDate() - i);
        const dateStr = date.toISOString().split('T')[0];
        
        try {
          const stagingKey = `/vpn/cost_optimization/daily_savings/staging/${dateStr}`;
          const productionKey = `/vpn/cost_optimization/daily_savings/production/${dateStr}`;
          
          const stagingSavings = await stateStore.readParameter(stagingKey).catch(() => '0');
          const productionSavings = await stateStore.readParameter(productionKey).catch(() => '0');
          
          dailyReports.push({
            date: dateStr,
            stagingSavings: parseFloat(stagingSavings) || 0,
            productionSavings: parseFloat(productionSavings) || 0,
            totalSavings: (parseFloat(stagingSavings) || 0) + (parseFloat(productionSavings) || 0)
          });
        } catch (error) {
          dailyReports.push({
            date: dateStr,
            stagingSavings: 0,
            productionSavings: 0,
            totalSavings: 0
          });
        }
      }
      
      return {
        success: true,
        message: 'Daily cost analysis (last 7 days)',
        data: { reportType: 'daily', data: dailyReports } as any
      };
    } else {
      // Cumulative report
      const stagingCumulative = await stateStore.readParameter('/vpn/cost_optimization/cumulative_savings/staging').catch(() => '0');
      const productionCumulative = await stateStore.readParameter('/vpn/cost_optimization/cumulative_savings/production').catch(() => '0');
      
      const analysis = {
        stagingTotal: parseFloat(stagingCumulative) || 0,
        productionTotal: parseFloat(productionCumulative) || 0,
        grandTotal: (parseFloat(stagingCumulative) || 0) + (parseFloat(productionCumulative) || 0),
        estimatedMonthlySavings: ((parseFloat(stagingCumulative) || 0) + (parseFloat(productionCumulative) || 0)) * 30,
        concept: 'Baseline: VPN runs 24/7 without auto-system. Savings = waste time prevented by auto-close.',
        dailyWasteWithout: '$2.40 per environment (24h × $0.10)',
        actualDailyWithAuto: '~$0.60 per environment (optimal usage)',
        lastUpdated: new Date().toISOString()
      };
      
      return {
        success: true,
        message: 'Cumulative cost analysis',
        data: { reportType: 'cumulative', data: analysis } as any
      };
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      success: false,
      message: 'Cost analysis generation failed',
      error: `Failed to generate cost analysis: ${errorMessage}`
    };
  }
}