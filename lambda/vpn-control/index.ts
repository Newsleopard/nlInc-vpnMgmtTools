import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';
import { CloudWatch } from 'aws-sdk';

// Import shared utilities from Lambda Layer
import { VpnCommandRequest, VpnCommandResponse, CrossAccountRequest } from '/opt/types';
import * as vpnManager from '/opt/vpnManager';
import * as stateStore from '/opt/stateStore';
import * as slack from '/opt/slack';

const cloudwatch = new CloudWatch();
const ENVIRONMENT = process.env.ENVIRONMENT || 'staging';

export const handler = async (
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> => {
  console.log('VPN Control Lambda invoked', { 
    requestId: context.awsRequestId,
    environment: ENVIRONMENT,
    httpMethod: event.httpMethod,
    path: event.path
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
          error: 'Missing required fields: action and environment'
        })
      };
    }

    // Validate action
    if (!['open', 'close', 'check'].includes(command.action)) {
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          success: false,
          error: 'Invalid action. Must be: open, close, or check'
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
          error: `Environment mismatch. This function handles ${ENVIRONMENT}, but received ${command.environment}`
        })
      };
    }

    // Validate VPN endpoint configuration
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
          error: errorMsg
        })
      };
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
            `✅ VPN ${ENVIRONMENT} opened by ${command.user}`,
            `#vpn-${ENVIRONMENT}`
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
            `🔴 VPN ${ENVIRONMENT} closed by ${command.user}`,
            `#vpn-${ENVIRONMENT}`
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
        message: '',
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
    await cloudwatch.putMetricData({
      Namespace: 'VPN/Automation',
      MetricData: [{
        MetricName: metricName,
        Value: value,
        Unit: 'Count',
        Dimensions: [{
          Name: 'Environment',
          Value: ENVIRONMENT
        }],
        Timestamp: new Date()
      }]
    }).promise();
    
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