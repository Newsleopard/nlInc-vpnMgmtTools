import { ScheduledEvent, Context } from 'aws-lambda';
import { CloudWatch } from 'aws-sdk';

// Import shared utilities from Lambda Layer
import { VpnState } from '/opt/types';
import * as vpnManager from '/opt/vpnManager';
import * as stateStore from '/opt/stateStore';
import * as slack from '/opt/slack';

const cloudwatch = new CloudWatch();

const IDLE_MINUTES = Number(process.env.IDLE_MINUTES || 60);
const ENVIRONMENT = process.env.ENVIRONMENT || 'staging';

export const handler = async (
  event: ScheduledEvent,
  context: Context
): Promise<void> => {
  console.log('VPN Monitor Lambda triggered', {
    requestId: context.awsRequestId,
    environment: ENVIRONMENT,
    idleThreshold: IDLE_MINUTES,
    eventTime: event.time
  });

  try {
    // Validate Parameter Store configuration
    const isValid = await stateStore.validateParameterStore();
    if (!isValid) {
      console.error('Parameter Store validation failed - some required parameters are missing');
      await slack.sendSlackAlert(
        'VPN Monitor: Parameter Store validation failed. Please check configuration.',
        ENVIRONMENT,
        'critical'
      );
      return;
    }

    // Validate VPN endpoint exists and is accessible
    const endpointValid = await vpnManager.validateEndpoint();
    if (!endpointValid) {
      console.error('VPN endpoint validation failed');
      await slack.sendSlackAlert(
        'VPN Monitor: VPN endpoint validation failed. Please check endpoint configuration.',
        ENVIRONMENT,
        'critical'
      );
      return;
    }

    // Fetch current VPN status
    const status = await vpnManager.fetchStatus();
    const state = await stateStore.readState();
    
    console.log('Current VPN status:', {
      associated: status.associated,
      activeConnections: status.activeConnections,
      lastActivity: status.lastActivity,
      endpointId: status.endpointId
    });

    // Publish current status metrics
    await publishStatusMetrics(status);

    // Check if VPN is associated and potentially idle
    if (!status.associated) {
      console.log('VPN is already disassociated, no action needed');
      return;
    }

    // Check if there are active connections
    if (status.activeConnections > 0) {
      console.log(`VPN has ${status.activeConnections} active connections, not idle`);
      
      // Update last activity since there are active connections
      await vpnManager.updateLastActivity();
      return;
    }

    // Calculate idle time
    const lastActivityTime = new Date(state.lastActivity);
    const currentTime = new Date();
    const idleTimeMs = currentTime.getTime() - lastActivityTime.getTime();
    const idleTimeMinutes = Math.floor(idleTimeMs / (1000 * 60));

    console.log(`VPN has been idle for ${idleTimeMinutes} minutes (threshold: ${IDLE_MINUTES})`);

    // Publish idle time metric
    await publishMetric('VpnIdleTimeMinutes', idleTimeMinutes);

    // Check if idle time exceeds threshold
    if (idleTimeMinutes < IDLE_MINUTES) {
      console.log('VPN is idle but has not exceeded threshold yet');
      return;
    }

    // Check business hours constraint (optional safety mechanism)
    if (isBusinessHours()) {
      console.log('Skipping auto-disassociation during business hours');
      await slack.sendSlackNotification(
        `⚠️ VPN ${ENVIRONMENT} has been idle for ${idleTimeMinutes} minutes but auto-close is disabled during business hours`,
        `#vpn-${ENVIRONMENT}`
      );
      return;
    }

    // Auto-disassociate subnets to save costs
    console.log(`Auto-disassociating VPN subnets after ${idleTimeMinutes} minutes of idle time`);
    
    try {
      await vpnManager.disassociateSubnets();
      
      // Publish auto-disassociation metric
      await publishMetric('IdleSubnetDisassociations', 1);
      
      // Send Slack notification about automatic action
      const environmentEmoji = ENVIRONMENT === 'production' ? '🔴' : '🟡';
      await slack.sendSlackNotification(
        `⚠️ VPN ${environmentEmoji} ${ENVIRONMENT} was idle for ${idleTimeMinutes} minutes. ` +
        `Subnets automatically disassociated to save costs. ` +
        `Use \`/vpn open ${ENVIRONMENT}\` to re-enable.`,
        `#vpn-${ENVIRONMENT}`
      );
      
      console.log('Successfully auto-disassociated VPN subnets');
      
    } catch (disassociationError) {
      console.error('Failed to auto-disassociate VPN subnets:', disassociationError);
      
      const errorMessage = disassociationError instanceof Error ? disassociationError.message : String(disassociationError);
      await slack.sendSlackAlert(
        `Failed to auto-disassociate VPN ${ENVIRONMENT} after ${idleTimeMinutes} minutes idle: ${errorMessage}`,
        ENVIRONMENT,
        'critical'
      );
      
      await publishMetric('AutoDisassociationErrors', 1);
    }

  } catch (error) {
    console.error('Error in VPN Monitor Lambda:', error);
    
    // Send critical alert for monitor failures
    const errorMessage = error instanceof Error ? error.message : String(error);
    await slack.sendSlackAlert(
      `VPN Monitor Lambda error: ${errorMessage}`,
      ENVIRONMENT,
      'critical'
    );
    
    await publishMetric('MonitorLambdaErrors', 1);
  }
};

// Helper function to check if current time is during business hours
function isBusinessHours(): boolean {
  const now = new Date();
  const hour = now.getUTCHours(); // Use UTC for consistency
  const dayOfWeek = now.getUTCDay(); // 0 = Sunday, 6 = Saturday
  
  // Business hours: Monday-Friday, 9 AM - 6 PM UTC
  // Adjust timezone as needed for your organization
  const isWeekday = dayOfWeek >= 1 && dayOfWeek <= 5;
  const isBusinessHour = hour >= 9 && hour < 18;
  
  return isWeekday && isBusinessHour;
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

// Helper function to publish comprehensive status metrics
async function publishStatusMetrics(status: any): Promise<void> {
  const metrics = [
    {
      MetricName: 'VpnAssociationStatus',
      Value: status.associated ? 1 : 0,
      Unit: 'None'
    },
    {
      MetricName: 'VpnActiveConnections',
      Value: status.activeConnections,
      Unit: 'Count'
    }
  ];

  try {
    await cloudwatch.putMetricData({
      Namespace: 'VPN/Automation',
      MetricData: metrics.map(metric => ({
        ...metric,
        Dimensions: [{
          Name: 'Environment',
          Value: ENVIRONMENT
        }],
        Timestamp: new Date()
      }))
    }).promise();
    
    console.log('Published status metrics:', metrics.map(m => `${m.MetricName}: ${m.Value}`));
  } catch (error) {
    console.error('Failed to publish status metrics:', error);
  }
}