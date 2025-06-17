// Test-specific version of vpn-monitor handler with relative imports
import { ScheduledEvent, Context } from 'aws-lambda';
import { CloudWatch } from 'aws-sdk';

// Import shared utilities using relative paths for tests
import { VpnState } from '../../shared/types';
import * as vpnManager from '../../shared/vpnManager';
import * as stateStore from '../../shared/stateStore';
import * as slack from '../../shared/slack';

const cloudwatch = new CloudWatch();

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

// Check if current time is during business hours (Monday-Friday, 9 AM - 6 PM UTC)
function isBusinessHours(): boolean {
  const now = new Date();
  const day = now.getUTCDay(); // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
  const hour = now.getUTCHours();
  
  // Monday (1) to Friday (5), 9 AM to 6 PM UTC
  return day >= 1 && day <= 5 && hour >= 9 && hour < 18;
}

// Calculate idle time in minutes
function calculateIdleTime(lastActivity: string): number {
  const lastActivityTime = new Date(lastActivity);
  const now = new Date();
  const diffMs = now.getTime() - lastActivityTime.getTime();
  return Math.floor(diffMs / (1000 * 60)); // Convert to minutes
}

export const handler = async (event: ScheduledEvent, context: Context): Promise<void> => {
  console.log(`VPN Monitor Lambda invoked in ${(process.env.ENVIRONMENT || 'staging')} environment`);
  console.log('Event:', JSON.stringify(event, null, 2));

  try {
    // Validate Parameter Store configuration
    const isValidConfig = await stateStore.validateParameterStore();
    if (!isValidConfig) {
      await slack.sendSlackAlert(
        'Parameter Store validation failed in VPN Monitor Lambda',
        (process.env.ENVIRONMENT || 'staging'),
        'critical'
      );
      return;
    }

    // Validate VPN endpoint
    const isValidEndpoint = await vpnManager.validateEndpoint();
    if (!isValidEndpoint) {
      await slack.sendSlackAlert(
        'VPN endpoint validation failed in Monitor Lambda',
        (process.env.ENVIRONMENT || 'staging'),
        'critical'
      );
      return;
    }

    // Get current VPN status
    const currentStatus = await vpnManager.fetchStatus();
    console.log('Current VPN status:', currentStatus);

    // Publish status metrics
    await publishMetric('VpnAssociationStatus', currentStatus.associated ? 1 : 0);
    await publishMetric('VpnActiveConnections', currentStatus.activeConnections);

    // If VPN is not associated, no action needed
    if (!currentStatus.associated) {
      console.log('VPN is not associated, no monitoring action needed');
      return;
    }

    // If there are active connections, no action needed
    if (currentStatus.activeConnections > 0) {
      console.log(`VPN has ${currentStatus.activeConnections} active connections, no action needed`);
      return;
    }

    // Check idle time
    const vpnState: VpnState = await stateStore.readState();
    const idleTimeMinutes = calculateIdleTime(vpnState.lastActivity);
    
    console.log(`VPN idle for ${idleTimeMinutes} minutes (threshold: ${(parseInt(process.env.IDLE_MINUTES || '60'))} minutes)`);
    
    // If not idle long enough, no action needed
    if (idleTimeMinutes < (parseInt(process.env.IDLE_MINUTES || '60'))) {
      console.log('VPN not idle long enough, no action needed');
      return;
    }

    // Check if it's business hours - avoid auto-disassociation during business hours
    if (isBusinessHours()) {
      console.log('Business hours detected, skipping auto-disassociation');
      await slack.sendSlackNotification(
        `⚠️ VPN ${(process.env.ENVIRONMENT || 'staging')} has been idle for ${idleTimeMinutes} minutes but auto-disassociation was skipped due to business hours`
      );
      return;
    }

    // Auto-disassociate the VPN
    console.log(`Auto-disassociating VPN after ${idleTimeMinutes} minutes of idle time`);
    
    try {
      await vpnManager.disassociateSubnets();
      await vpnManager.updateLastActivity();
      
      // Publish success metrics
      await publishMetric('IdleSubnetDisassociations', 1);
      
      // Send notification
      await slack.sendSlackNotification(
        `✅ VPN ${(process.env.ENVIRONMENT || 'staging')} was automatically disassociated after being idle for ${idleTimeMinutes} minutes`
      );
      
      console.log('Successfully auto-disassociated VPN subnets');
      
    } catch (disassociationError) {
      console.error('Failed to auto-disassociate VPN subnets:', disassociationError);
      
      const errorMessage = disassociationError instanceof Error ? disassociationError.message : String(disassociationError);
      await slack.sendSlackAlert(
        `Failed to auto-disassociate VPN ${(process.env.ENVIRONMENT || 'staging')} after ${idleTimeMinutes} minutes idle: ${errorMessage}`,
        (process.env.ENVIRONMENT || 'staging'),
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
      (process.env.ENVIRONMENT || 'staging'),
      'critical'
    );
    
    await publishMetric('MonitorLambdaErrors', 1);
  }
};