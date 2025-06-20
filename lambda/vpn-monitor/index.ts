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
const COOLDOWN_MINUTES = Number(process.env.COOLDOWN_MINUTES || 30);
const BUSINESS_HOURS_ENABLED = process.env.BUSINESS_HOURS_PROTECTION !== 'false';
const BUSINESS_HOURS_TIMEZONE = process.env.BUSINESS_HOURS_TIMEZONE || 'UTC';

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
      
      // Reset cooldown if VPN is actively being used
      await clearCooldownTimestamp();
      return;
    }

    // Check for recent manual activity (association/disassociation via Slack)
    if (await hasRecentManualActivity()) {
      console.log('Recent manual activity detected, skipping auto-disassociation');
      await publishMetric('ManualActivitySkips', 1);
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
    if (BUSINESS_HOURS_ENABLED && isBusinessHours()) {
      console.log('Skipping auto-disassociation during business hours');
      await slack.sendSlackNotification(
        `⚠️ VPN ${ENVIRONMENT} has been idle for ${idleTimeMinutes} minutes but auto-close is disabled during business hours (${BUSINESS_HOURS_TIMEZONE})`,
        `#vpn-${ENVIRONMENT}`
      );
      
      // Publish metric for business hours skips
      await publishMetric('BusinessHoursSkips', 1);
      return;
    }

    // Check cooldown period to prevent rapid cycling
    if (await isInCooldownPeriod()) {
      const remainingCooldown = await getRemainingCooldownMinutes();
      console.log(`Skipping auto-disassociation - still in cooldown period (${remainingCooldown} minutes remaining)`);
      await publishMetric('CooldownSkips', 1);
      return;
    }

    // Auto-disassociate subnets to save costs
    console.log(`Auto-disassociating VPN subnets after ${idleTimeMinutes} minutes of idle time`);
    
    try {
      await vpnManager.disassociateSubnets();
      
      // Record cooldown timestamp to prevent rapid cycling
      await recordCooldownTimestamp();
      
      // Publish auto-disassociation metric with additional context
      await publishMetric('IdleSubnetDisassociations', 1);
      await publishMetric('IdleMinutesWhenDisassociated', idleTimeMinutes);
      
      // Send Slack notification about automatic action
      const environmentEmoji = ENVIRONMENT === 'production' ? '🔴' : '🟡';
      const costSavingsMessage = calculateHourlyCostSavings();
      await slack.sendSlackNotification(
        `💰 VPN ${environmentEmoji} ${ENVIRONMENT} was idle for ${idleTimeMinutes} minutes. ` +
        `Subnets automatically disassociated to save costs (~$${costSavingsMessage}/hour saved). ` +
        `Use \`/vpn open ${ENVIRONMENT}\` to re-enable.`,
        `#vpn-${ENVIRONMENT}`
      );
      
      console.log('Successfully auto-disassociated VPN subnets with cooldown protection enabled');
      
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
  
  // If timezone is specified and not UTC, adjust for it
  let hour: number;
  let dayOfWeek: number;
  
  if (BUSINESS_HOURS_TIMEZONE === 'UTC') {
    hour = now.getUTCHours();
    dayOfWeek = now.getUTCDay();
  } else {
    // For simplicity, support common timezones with offset
    const timezoneOffsets: { [key: string]: number } = {
      'EST': -5, 'EDT': -4,  // US Eastern
      'PST': -8, 'PDT': -7,  // US Pacific  
      'CST': -6, 'CDT': -5,  // US Central
      'MST': -7, 'MDT': -6,  // US Mountain
      'GMT': 0, 'UTC': 0     // GMT/UTC
    };
    
    const offset = timezoneOffsets[BUSINESS_HOURS_TIMEZONE] || 0;
    const adjustedTime = new Date(now.getTime() + (offset * 60 * 60 * 1000));
    hour = adjustedTime.getUTCHours();
    dayOfWeek = adjustedTime.getUTCDay();
  }
  
  // Business hours: Monday-Friday, 9 AM - 6 PM in specified timezone
  const isWeekday = dayOfWeek >= 1 && dayOfWeek <= 5;
  const isBusinessHour = hour >= 9 && hour < 18;
  
  console.log(`Business hours check: ${BUSINESS_HOURS_TIMEZONE} time, hour=${hour}, day=${dayOfWeek}, weekday=${isWeekday}, business_hour=${isBusinessHour}`);
  
  return isWeekday && isBusinessHour;
}

// Check if we're in a cooldown period after recent auto-disassociation
async function isInCooldownPeriod(): Promise<boolean> {
  try {
    const cooldownParam = await stateStore.readParameter(`/vpn/automation/cooldown/${ENVIRONMENT}`);
    if (!cooldownParam) {
      return false;
    }
    
    const cooldownTime = new Date(cooldownParam);
    const now = new Date();
    const cooldownElapsed = (now.getTime() - cooldownTime.getTime()) / (1000 * 60); // minutes
    
    return cooldownElapsed < COOLDOWN_MINUTES;
  } catch (error) {
    console.log('No cooldown timestamp found, proceeding normally');
    return false;
  }
}

// Get remaining cooldown time in minutes
async function getRemainingCooldownMinutes(): Promise<number> {
  try {
    const cooldownParam = await stateStore.readParameter(`/vpn/automation/cooldown/${ENVIRONMENT}`);
    if (!cooldownParam) {
      return 0;
    }
    
    const cooldownTime = new Date(cooldownParam);
    const now = new Date();
    const cooldownElapsed = (now.getTime() - cooldownTime.getTime()) / (1000 * 60); // minutes
    
    return Math.max(0, COOLDOWN_MINUTES - cooldownElapsed);
  } catch (error) {
    return 0;
  }
}

// Record timestamp for cooldown period
async function recordCooldownTimestamp(): Promise<void> {
  try {
    const now = new Date().toISOString();
    await stateStore.writeParameter(`/vpn/automation/cooldown/${ENVIRONMENT}`, now);
    console.log(`Recorded cooldown timestamp: ${now}`);
  } catch (error) {
    console.error('Failed to record cooldown timestamp:', error);
    // Don't throw as this shouldn't break the main operation
  }
}

// Clear cooldown timestamp when VPN is actively being used
async function clearCooldownTimestamp(): Promise<void> {
  try {
    await stateStore.writeParameter(`/vpn/automation/cooldown/${ENVIRONMENT}`, '');
    console.log('Cleared cooldown timestamp due to active usage');
  } catch (error) {
    console.error('Failed to clear cooldown timestamp:', error);
  }
}

// Check if there has been recent manual activity (Slack commands)
async function hasRecentManualActivity(): Promise<boolean> {
  try {
    const manualActivityParam = await stateStore.readParameter(`/vpn/automation/manual_activity/${ENVIRONMENT}`);
    if (!manualActivityParam) {
      return false;
    }
    
    const manualActivityTime = new Date(manualActivityParam);
    const now = new Date();
    const timeSinceManualActivity = (now.getTime() - manualActivityTime.getTime()) / (1000 * 60); // minutes
    
    // Consider manual activity "recent" if it happened within the last 15 minutes
    const manualActivityGracePeriod = 15;
    return timeSinceManualActivity < manualActivityGracePeriod;
  } catch (error) {
    console.log('No manual activity timestamp found');
    return false;
  }
}

// Calculate estimated hourly cost savings from disassociation
function calculateHourlyCostSavings(): string {
  // AWS Client VPN charges per associated subnet per hour
  // Typical cost is around $0.10 per subnet association per hour
  // This is a rough estimate - actual costs may vary by region
  const costPerSubnetPerHour = 0.10;
  const estimatedSubnets = 1; // Could be enhanced to read actual subnet count
  
  const savings = (costPerSubnetPerHour * estimatedSubnets).toFixed(2);
  return savings;
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