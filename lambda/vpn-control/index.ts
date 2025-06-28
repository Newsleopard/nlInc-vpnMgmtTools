import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';
import { CloudWatchClient, PutMetricDataCommand, StandardUnit } from '@aws-sdk/client-cloudwatch';

// Import shared utilities from Lambda Layer
import { VpnCommandRequest, VpnCommandResponse, CrossAccountRequest } from '/opt/nodejs/types';
import * as vpnManager from '/opt/nodejs/vpnManager';
import * as stateStore from '/opt/nodejs/stateStore';
import * as slack from '/opt/nodejs/slack';
import { createLogger, extractLogContext, withPerformanceLogging } from '/opt/nodejs/logger';

const cloudwatch = new CloudWatchClient({});
const ENVIRONMENT = process.env.ENVIRONMENT || 'staging';

export const handler = async (
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> => {
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
    const validActions = ['open', 'close', 'check', 'admin-override', 'admin-clear-override', 'admin-cooldown', 'admin-force-close', 'cost-savings', 'cost-analysis'];
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

    // Validate environment matches deployment
    if (command.environment !== ENVIRONMENT) {
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

    // Validate VPN endpoint configuration (skip for check command)
    if (command.action !== 'check') {
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
        case 'admin-override':
          response = await handleAdminOverride(command);
          break;
          
        case 'admin-clear-override':
          response = await handleClearOverride(command);
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

        default:
          throw new Error(`Unsupported action: ${command.action}`);
      }

      console.log('VPN operation completed successfully:', response);

    } catch (operationError) {
      console.error(`VPN ${command.action} operation failed:`, operationError);
      
      // Send alert for operation failure
      const errorMessage = operationError instanceof Error ? operationError.message : String(operationError);
      await slack.sendSlackAlert(
        `VPN ${command.action} operation failed: ${errorMessage}`,
        ENVIRONMENT,
        'critical'
      );
      
      await publishMetric('VpnOperationErrors', 1);
      
      response = {
        success: false,
        message: `VPN ${command.action} operation failed`,
        error: `VPN ${command.action} failed: ${errorMessage}`
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

// Epic 3.2: Handle administrative override command
async function handleAdminOverride(command: VpnCommandRequest): Promise<VpnCommandResponse> {
  try {
    const expiryTime = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours
    const overrideValue = `enabled:expires:${expiryTime.toISOString()}`;
    
    await stateStore.writeParameter(`/vpn/automation/admin_override/${ENVIRONMENT}`, overrideValue);
    await publishMetric('AdminOverrideEnabled', 1);
    
    await slack.sendSlackNotification(
      `🛑 **Administrative Override Enabled** ${ENVIRONMENT === 'production' ? '🔴' : '🟡'}\n` +
      `👤 **Admin**: ${command.user}\n` +
      `⏰ **Duration**: 24 hours\n` +
      `⏱️ **Expires**: ${expiryTime.toLocaleString()}\n` +
      `🚫 **Effect**: Auto-close disabled\n` +
      `📝 **Note**: Use \`/vpn admin clear-override ${ENVIRONMENT}\` to re-enable`
    );
    
    return {
      success: true,
      message: `Administrative override enabled for ${ENVIRONMENT} (expires in 24 hours)`
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      success: false,
      message: 'Admin override operation failed',
      error: `Failed to enable admin override: ${errorMessage}`
    };
  }
}

// Epic 3.2: Handle clear override command
async function handleClearOverride(command: VpnCommandRequest): Promise<VpnCommandResponse> {
  try {
    await stateStore.writeParameter(`/vpn/automation/admin_override/${ENVIRONMENT}`, '');
    await publishMetric('AdminOverrideCleared', 1);
    
    await slack.sendSlackNotification(
      `✅ **Administrative Override Cleared** ${ENVIRONMENT === 'production' ? '🔴' : '🟡'}\n` +
      `👤 **Admin**: ${command.user}\n` +
      `🔄 **Effect**: Auto-close re-enabled\n` +
      `⏱️ **Monitoring**: Idle detection resumed`
    );
    
    return {
      success: true,
      message: `Administrative override cleared for ${ENVIRONMENT}. Auto-close re-enabled.`
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      success: false,
      message: 'Clear override operation failed',
      error: `Failed to clear admin override: ${errorMessage}`
    };
  }
}

// Epic 3.2: Handle cooldown status command
async function handleCooldownStatus(command: VpnCommandRequest): Promise<VpnCommandResponse> {
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
    
    await slack.sendSlackNotification(
      `⚠️ **Force Close Executed** ${ENVIRONMENT === 'production' ? '🔴' : '🟡'}\n` +
      `👤 **Admin**: ${command.user}\n` +
      `🔧 **Action**: Bypassed all safety mechanisms\n` +
      `🔄 **Cooldown**: Cleared for immediate re-association\n` +
      `⏱️ **Timestamp**: ${new Date().toLocaleString()}`
    );
    
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
async function handleCostSavings(command: VpnCommandRequest): Promise<VpnCommandResponse> {
  try {
    // Get cumulative savings
    const cumulativeKey = `/vpn/cost_optimization/cumulative_savings/${ENVIRONMENT}`;
    let cumulativeSavings = 0;
    try {
      const cumulative = await stateStore.readParameter(cumulativeKey);
      cumulativeSavings = parseFloat(cumulative) || 0;
    } catch (error) {
      console.log('No cumulative savings data found');
    }
    
    // Get today's savings
    const today = new Date().toISOString().split('T')[0];
    const dailyKey = `/vpn/cost_optimization/daily_savings/${ENVIRONMENT}/${today}`;
    let todaySavings = 0;
    try {
      const daily = await stateStore.readParameter(dailyKey);
      todaySavings = parseFloat(daily) || 0;
    } catch (error) {
      console.log('No daily savings data found for today');
    }
    
    // Get current VPN status for potential savings
    const status = await vpnManager.fetchStatus();
    const hourlyRate = 0.10; // Base rate per subnet per hour
    
    const report = {
      environment: ENVIRONMENT,
      cumulativeSavings: cumulativeSavings.toFixed(2),
      todaySavings: todaySavings.toFixed(2),
      currentStatus: status.associated ? 'Running' : 'Stopped',
      potentialHourlySavings: status.associated ? hourlyRate.toFixed(2) : '0.00',
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