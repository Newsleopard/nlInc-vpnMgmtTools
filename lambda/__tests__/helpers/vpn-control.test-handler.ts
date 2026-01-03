// Test-specific version of vpn-control handler with relative imports
import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';
import { CloudWatch } from 'aws-sdk';

// Import shared utilities using relative paths for tests
import { VpnCommandRequest, VpnCommandResponse, CrossAccountRequest } from '../../shared/types';
import * as vpnManager from '../../shared/vpnManager';
import * as stateStore from '../../shared/stateStore';
import * as slack from '../../shared/slack';

const cloudwatch = new CloudWatch();
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

// MetricData interface for CloudWatch
interface MetricData {
  MetricName: string;
  Value: number;
  Unit: string;
  Timestamp?: Date;
  Dimensions?: { Name: string; Value: string }[];
}

// Publish CloudWatch metric
async function publishMetric(metricName: string, value: number, unit: string = 'Count'): Promise<void> {
  const metricData: MetricData = {
    MetricName: metricName,
    Value: value,
    Unit: unit,
    Timestamp: new Date(),
    Dimensions: [
      {
        Name: 'Environment',
        Value: (process.env.ENVIRONMENT || 'staging')
      }
    ]
  };

  try {
    await cloudwatch.putMetricData({
      Namespace: 'VPN/Automation',
      MetricData: [metricData]
    }).promise();
  } catch (error) {
    console.error('Failed to publish metric:', error);
  }
}

export const handler = async (event: APIGatewayProxyEvent, context: Context): Promise<APIGatewayProxyResult> => {
  console.log(`VPN Control Lambda invoked in ${ENVIRONMENT} environment`);
  console.log('Event:', JSON.stringify(event, null, 2));

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

  // Handle scheduled auto-open requests (weekday 9:30 AM)
  if (isAutoOpenRequest(event)) {
    console.log(`Auto-open request received for ${ENVIRONMENT} environment`);
    try {
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
            { title: '🤖 Trigger | 觸發', value: 'Scheduled auto-open (weekday 9:30 AM)', short: false }
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

  try {
    // Validate Parameter Store configuration
    const isValidConfig = await stateStore.validateParameterStore();
    if (!isValidConfig) {
      await slack.sendSlackAlert(
        'Parameter Store validation failed in VPN Control Lambda',
        (process.env.ENVIRONMENT || 'staging'),
        'critical'
      );
      
      return {
        statusCode: 500,
        body: JSON.stringify({
          success: false,
          message: '',
          error: 'Parameter Store validation failed'
        })
      };
    }

    // Validate VPN endpoint
    const isValidEndpoint = await vpnManager.validateEndpoint();
    if (!isValidEndpoint) {
      await slack.sendSlackAlert(
        'VPN endpoint validation failed in Control Lambda',
        (process.env.ENVIRONMENT || 'staging'),
        'critical'
      );
      
      return {
        statusCode: 500,
        body: JSON.stringify({
          success: false,
          message: '',
          error: 'VPN endpoint validation failed'
        })
      };
    }

    // Parse the request body
    let command: VpnCommandRequest;
    try {
      // Handle both direct requests and cross-account requests
      const body = JSON.parse(event.body || '{}');
      
      if (body.command && body.sourceAccount) {
        // Cross-account request format
        const crossAccountRequest = body as CrossAccountRequest;
        command = crossAccountRequest.command;
        console.log(`Processing cross-account request from ${crossAccountRequest.sourceAccount}`);
      } else {
        // Direct request format
        command = body as VpnCommandRequest;
      }
    } catch (parseError) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          success: false,
          message: '',
          error: 'Invalid JSON in request body'
        })
      };
    }

    // Validate required fields
    if (!command.action || !command.environment || !command.user) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          success: false,
          message: '',
          error: 'Missing required fields: action, environment, user'
        })
      };
    }

    // Validate action
    if (!['open', 'close', 'check'].includes(command.action)) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          success: false,
          message: '',
          error: `Invalid action: ${command.action}. Must be open, close, or check`
        })
      };
    }

    // Validate environment matches Lambda's environment
    if (command.environment !== (process.env.ENVIRONMENT || 'staging')) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          success: false,
          message: '',
          error: `Environment mismatch. Lambda is ${(process.env.ENVIRONMENT || 'staging')}, request is ${command.environment}`
        })
      };
    }

    console.log(`Processing ${command.action} command for ${command.environment} environment by user ${command.user}`);

    let response: VpnCommandResponse;
    
    try {
      // Execute the requested operation
      switch (command.action) {
        case 'open':
          await vpnManager.associateSubnets();
          await vpnManager.updateLastActivity();
          const openStatus = await vpnManager.fetchStatus();
          await publishMetric('VpnOpenOperations', 1);
          
          response = {
            success: true,
            message: `VPN ${command.environment} opened successfully`,
            data: openStatus
          };
          break;

        case 'close':
          await vpnManager.disassociateSubnets();
          await vpnManager.updateLastActivity();
          const closeStatus = await vpnManager.fetchStatus();
          await publishMetric('VpnCloseOperations', 1);
          
          response = {
            success: true,
            message: `VPN ${command.environment} closed successfully`,
            data: closeStatus
          };
          break;

        case 'check':
          const status = await vpnManager.fetchStatus();
          await publishMetric('VpnStatusChecks', 1);
          
          response = {
            success: true,
            message: `VPN ${command.environment} status retrieved`,
            data: status
          };
          break;

        default:
          throw new Error(`Unsupported action: ${command.action}`);
      }

      console.log(`Successfully completed ${command.action} operation:`, response);

    } catch (operationError) {
      console.error(`VPN ${command.action} operation failed:`, operationError);
      
      // Send alert for operation failure
      const errorMessage = operationError instanceof Error ? operationError.message : String(operationError);
      await slack.sendSlackAlert(
        `VPN ${command.action} operation failed: ${errorMessage}`,
        (process.env.ENVIRONMENT || 'staging'),
        'critical'
      );
      
      await publishMetric('VpnOperationErrors', 1);
      
      response = {
        success: false,
        message: '',
        error: `VPN ${command.action} failed: ${errorMessage}`
      };
    }

    // Return response
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(response)
    };

  } catch (error) {
    console.error('Unexpected error in VPN Control Lambda:', error);
    
    // Send critical alert
    const errorMessage = error instanceof Error ? error.message : String(error);
    await slack.sendSlackAlert(
      `Critical error in VPN Control Lambda: ${errorMessage}`,
      (process.env.ENVIRONMENT || 'staging'),
      'critical'
    );
    
    await publishMetric('LambdaErrors', 1);

    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        success: false,
        message: '',
        error: 'Internal server error'
      })
    };
  }
};