import { ScheduledEvent, Context } from 'aws-lambda';
import { CloudWatchClient, PutMetricDataCommand, StandardUnit } from '@aws-sdk/client-cloudwatch';

// Import shared utilities from Lambda Layer
import * as vpnManager from '/opt/nodejs/vpnManager';
import * as stateStore from '/opt/nodejs/stateStore';
import * as slack from '/opt/nodejs/slack';
import { createLogger } from '/opt/nodejs/logger';
import * as scheduleManager from '/opt/nodejs/scheduleManager';
import { VpnConnectionDetail, WeekendNotificationState } from '/opt/nodejs/types';

const cloudwatch = new CloudWatchClient({});

const IDLE_MINUTES = Number(process.env.IDLE_MINUTES || 30);
const ENVIRONMENT = process.env.ENVIRONMENT || 'staging';
const COOLDOWN_MINUTES = Number(process.env.COOLDOWN_MINUTES || 30);
const BUSINESS_HOURS_ENABLED = process.env.BUSINESS_HOURS_PROTECTION !== 'false';
const BUSINESS_HOURS_TIMEZONE = process.env.BUSINESS_HOURS_TIMEZONE || 'UTC';
// Idle threshold for soft-close: only close if connection has been idle for this many minutes
const SOFT_CLOSE_IDLE_THRESHOLD_MINUTES = Number(process.env.SOFT_CLOSE_IDLE_THRESHOLD_MINUTES || 60);

// Weekend notification constants for long-running connection alerts
const WEEKEND_NOTIFICATION_FIRST_HOURS = 3;      // First notification after 3 hours
const WEEKEND_NOTIFICATION_INTERVAL_HOURS = 1;   // Repeat notifications every 1 hour
const CONNECTION_COST_PER_HOUR = 0.05;           // AWS Client VPN connection cost per hour

// Soft-close notification frequency: notify on every Nth retry attempt (reduces noise)
const SOFT_CLOSE_NOTIFICATION_FREQUENCY = 2;     // Notify on odd attempts (1, 3, 5...)

// Timezone offset mapping for business hours calculations (UTC offset in hours)
const TIMEZONE_OFFSETS: { [key: string]: number } = {
  'EST': -5, 'EDT': -4,    // US Eastern
  'PST': -8, 'PDT': -7,    // US Pacific
  'CST': -6, 'CDT': -5,    // US Central
  'MST': -7, 'MDT': -6,    // US Mountain
  'GMT': 0, 'UTC': 0,      // GMT/UTC
  'Asia/Taipei': 8,        // Taiwan Standard Time (UTC+8)
  'TST': 8, 'Taiwan': 8    // Alternative Taiwan timezone names
};

/**
 * Get adjusted time components based on configured timezone
 * @returns Object with hour, minute, and dayOfWeek in the configured timezone
 */
function getAdjustedTimeComponents(): { hour: number; minute: number; dayOfWeek: number } {
  const now = new Date();

  if (BUSINESS_HOURS_TIMEZONE === 'UTC') {
    return {
      hour: now.getUTCHours(),
      minute: now.getUTCMinutes(),
      dayOfWeek: now.getUTCDay()
    };
  }

  const offset = TIMEZONE_OFFSETS[BUSINESS_HOURS_TIMEZONE] || 0;
  const adjustedTime = new Date(now.getTime() + (offset * 60 * 60 * 1000));

  return {
    hour: adjustedTime.getUTCHours(),
    minute: adjustedTime.getUTCMinutes(),
    dayOfWeek: adjustedTime.getUTCDay()
  };
}

/**
 * Get environment-specific styling for Slack notifications
 * Returns consistent formatting: red/uppercase for production, blue/normal for staging
 */
function getEnvironmentStyle(): {
  emoji: string;
  name: string;
  color: string;
  titleSuffix: string;
} {
  const isProduction = ENVIRONMENT === 'production';
  const emoji = isProduction ? '🚀' : '🔧';
  const name = isProduction ? 'PRODUCTION' : 'Staging';
  const color = isProduction ? '#d93025' : '#1a73e8';  // Red for production, blue for staging
  const titleSuffix = `${emoji} ${name}`;

  return { emoji, name, color, titleSuffix };
}

// Warming detection helper function
const isWarmingRequest = (event: any): boolean => {
  return event.source === 'aws.events' && 
         event['detail-type'] === 'Scheduled Event' &&
         event.detail?.warming === true;
};

export const handler = async (
  event: ScheduledEvent,
  context: Context
): Promise<void> => {
  // Handle warming requests
  if (isWarmingRequest(event)) {
    console.log('Warming request received - VPN monitor is now warm');
    return;
  }

  // Check for pending close retry (soft close mechanism)
  const pendingCloseResult = await checkAndHandlePendingClose();
  if (pendingCloseResult.handled) {
    console.log('Pending close handled:', pendingCloseResult.status);
    return;
  }

  // Initialize structured logger for Epic 4.1
  const logger = createLogger({
    requestId: context.awsRequestId,
    environment: ENVIRONMENT,
    functionName: 'vpn-monitor',
    correlationId: event.id
  });
  
  logger.info('VPN Monitor Lambda triggered', {
    idleThreshold: IDLE_MINUTES,
    cooldownMinutes: COOLDOWN_MINUTES,
    businessHoursEnabled: BUSINESS_HOURS_ENABLED,
    timezone: BUSINESS_HOURS_TIMEZONE,
    eventTime: event.time,
    eventSource: event.source
  });

  try {
    // Validate Parameter Store configuration
    const isValid = await stateStore.validateParameterStore();

    if (!isValid) {
      // Check if deployment is in progress - suppress alerts during deployment
      const isDeploying = await stateStore.isDeploymentInProgress();

      if (isDeploying) {
        logger.warn('Parameter Store validation failed during deployment - suppressing alert', {
          environment: ENVIRONMENT,
          validationStep: 'parameter_store',
          deploymentMode: true
        });
        return;
      }

      logger.critical('Parameter Store validation failed - some required parameters are missing', null, {
        environment: ENVIRONMENT,
        validationStep: 'parameter_store'
      });

      await slack.sendSlackAlert(
        'VPN 監控系統偵測到設定參數異常，請檢查系統配置是否正確',
        ENVIRONMENT,
        'critical'
      );
      return;
    }

    logger.debug('Parameter Store validation successful');

    // Validate VPN endpoint exists and is accessible
    const endpointValid = await vpnManager.validateEndpoint();

    if (!endpointValid) {
      // Check if deployment is in progress - suppress alerts during deployment
      const isDeploying = await stateStore.isDeploymentInProgress();

      if (isDeploying) {
        logger.warn('VPN endpoint validation failed during deployment - suppressing alert', {
          environment: ENVIRONMENT,
          validationStep: 'vpn_endpoint',
          deploymentMode: true
        });
        return;
      }

      logger.critical('VPN endpoint validation failed', null, {
        environment: ENVIRONMENT,
        validationStep: 'vpn_endpoint'
      });

      await slack.sendSlackAlert(
        'VPN Monitor: VPN endpoint validation failed. Please check endpoint configuration.',
        ENVIRONMENT,
        'critical'
      );
      return;
    }
    
    logger.debug('VPN endpoint validation successful');

    // Fetch current VPN status
    const status = await vpnManager.fetchStatus();
    const state = await stateStore.readState();

    logger.info('Current VPN status', {
      associated: status.associated,
      associationState: status.associationState,
      activeConnections: status.activeConnections,
      trafficStatus: status.trafficSummary?.status,
      trafficIngressDelta: status.trafficSummary?.ingressDelta,
      trafficEgressDelta: status.trafficSummary?.egressDelta,
      trafficIdleMinutes: status.trafficSummary?.idleMinutes,
      lastActivity: status.lastActivity,
      endpointId: status.endpointId,
      subnetId: status.subnetId
    });

    logger.audit('VPN status check', 'vpn_status', 'success', {
      associated: status.associated,
      activeConnections: status.activeConnections,
      trafficStatus: status.trafficSummary?.status,
      lastActivity: status.lastActivity,
      endpointId: status.endpointId
    });

    // Check for pending association completion
    const associationResult = await checkAndNotifyAssociationCompletion(status);
    if (associationResult.notified) {
      logger.info('Association completion notification sent', {
        startedBy: associationResult.startedBy,
        duration: associationResult.duration
      });
    }

    // Check for pending disassociation completion
    const disassociationResult = await checkAndNotifyDisassociationCompletion(status);
    if (disassociationResult.notified) {
      logger.info('Disassociation completion notification sent', {
        startedBy: disassociationResult.startedBy,
        duration: disassociationResult.duration
      });
    }

    // Publish current status metrics
    await publishStatusMetrics(status);

    // Check if VPN is associated and potentially idle
    if (!status.associated) {
      logger.info('VPN is already disassociated, no action needed', {
        monitoringCycle: 'completed',
        action: 'none_required'
      });
      return;
    }

    // Check if there are active connections with actual traffic
    if (status.activeConnections > 0) {
      // Warn if trafficSummary is missing - indicates a potential issue with traffic monitoring
      if (!status.trafficSummary) {
        logger.warn('Missing traffic summary with active connections - treating as unknown', {
          activeConnections: status.activeConnections,
          fallbackBehavior: 'treating_as_active'
        });
      }
      const trafficStatus = status.trafficSummary?.status || 'active';
      const hasActiveTraffic = trafficStatus === 'active';

      if (hasActiveTraffic) {
        logger.info('VPN has active connections with traffic', {
          activeConnections: status.activeConnections,
          trafficStatus,
          ingressDelta: status.trafficSummary?.ingressDelta || 0,
          egressDelta: status.trafficSummary?.egressDelta || 0,
          action: 'maintaining_activity'
        });

        // Update last activity since there's actual traffic
        await vpnManager.updateLastActivity();

        // Reset cooldown if VPN is actively being used
        await clearCooldownTimestamp();

        // Weekend notification check for long-running connections
        // This runs on weekends to alert about connections active 3+ hours for cost awareness
        if (status.activeConnectionDetails) {
          try {
            await checkAndSendWeekendNotifications(status.activeConnectionDetails);
          } catch (notificationError) {
            console.error('Failed to process weekend notifications:', notificationError);
            // Don't throw - this shouldn't block the main monitoring flow
          }
        }

        return;
      } else {
        // Connections exist but no traffic - potential stale connections
        // Note: idleMinutes represents wall clock time since last traffic was observed
        // This is calculated from the traffic snapshot timestamp, not accumulated across Lambda invocations
        const idleMinutes = status.trafficSummary?.idleMinutes || 0;
        logger.info('VPN has connections but no recent traffic (potential stale)', {
          activeConnections: status.activeConnections,
          trafficStatus,
          trafficIdleMinutes: idleMinutes,
          softCloseThreshold: SOFT_CLOSE_IDLE_THRESHOLD_MINUTES,
          willTriggerClose: idleMinutes >= SOFT_CLOSE_IDLE_THRESHOLD_MINUTES,
          action: 'checking_idle_timeout'
        });

        // Publish traffic idle metric
        await publishMetric('VpnTrafficIdleMinutes', idleMinutes);

        // Don't return - continue to idle check below
        // This allows stale connections to be detected and VPN to auto-close
        // after SOFT_CLOSE_IDLE_THRESHOLD_MINUTES of inactivity
      }
    }

    // Weekend notification check for long-running connections
    // This runs on weekends to alert about connections active 3+ hours for cost awareness
    // Note: This does NOT block auto-close - it's purely informational
    if (status.associated && status.activeConnections > 0 && status.activeConnectionDetails) {
      try {
        await checkAndSendWeekendNotifications(status.activeConnectionDetails);
      } catch (notificationError) {
        console.error('Failed to process weekend notifications:', notificationError);
        // Don't throw - this shouldn't block the main monitoring flow
      }
    }

    // Check if auto-close schedule is enabled (Requirements: 6.1, 6.2, 6.3)
    const isAutoCloseScheduleEnabled = await scheduleManager.isAutoCloseEnabled(ENVIRONMENT);
    if (!isAutoCloseScheduleEnabled) {
      logger.info('Auto-close schedule is disabled, skipping idle check', {
        environment: ENVIRONMENT,
        reason: 'schedule_disabled'
      });
      // No Slack notification - just log and return silently to avoid spam
      await publishMetric('ScheduleDisabledSkips', 1);
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

    // Check for administrative override
    if (await hasAdministrativeOverride()) {
      console.log('Skipping auto-disassociation due to administrative override');
      const envStyle = getEnvironmentStyle();

      await slack.sendSlackNotification({
        text: `🛑 Administrative Override Active - ${envStyle.titleSuffix}`,
        attachments: [{
          color: envStyle.color,
          fields: [
            {
              title: `${envStyle.emoji} Environment`,
              value: envStyle.name,
              short: true
            },
            {
              title: "🚫 Status",
              value: "Auto-disassociation disabled",
              short: true
            },
            {
              title: "🔧 To Re-enable",
              value: `/vpn admin clear-override ${ENVIRONMENT}`,
              short: false
            }
          ]
        }]
      });

      await publishMetric('AdministrativeOverrideSkips', 1);
      return;
    }
    
    // Check business hours constraint (enhanced safety mechanism)
    if (BUSINESS_HOURS_ENABLED && isBusinessHours()) {
      console.log('Skipping auto-disassociation during business hours');

      // Check if we already notified about business hours today (once per day)
      const today = new Date().toISOString().split('T')[0]; // "2026-01-07"
      const alreadyNotifiedToday = await hasBusinessHoursNotificationToday(today);

      if (alreadyNotifiedToday) {
        console.log('Business hours protection active, notification already sent today');
        await publishMetric('BusinessHoursSkips', 1);
        return;
      }

      // Enhanced business hours notification with cost impact
      const costProjection = await calculateCostSavings(idleTimeMinutes);
      const envStyle = getEnvironmentStyle();
      const currentTime = new Date().toLocaleTimeString('zh-TW', { timeZone: BUSINESS_HOURS_TIMEZONE });

      await slack.sendSlackNotification({
        text: `⏰ Business Hours Protection - ${envStyle.titleSuffix}`,
        attachments: [{
          color: envStyle.color,
          fields: [
            {
              title: `${envStyle.emoji} Environment`,
              value: envStyle.name,
              short: true
            },
            {
              title: "🕒 Current Time",
              value: `${currentTime} (${BUSINESS_HOURS_TIMEZONE})`,
              short: true
            },
            {
              title: "⏱️ Idle Duration",
              value: `${idleTimeMinutes} minutes (threshold: ${IDLE_MINUTES}min)`,
              short: true
            },
            {
              title: "💰 Waste Being Accumulated",
              value: `$${costProjection.hourly}/hour\n_Would save ~$${costProjection.total} if closed now_`,
              short: true
            },
            {
              title: "🛡️ Protection Status",
              value: "Auto-close disabled",
              short: true
            },
            {
              title: "📝 Note",
              value: `Auto-close at 5 PM or manual: \`/vpn close ${ENVIRONMENT}\``,
              short: false
            }
          ]
        }]
      });

      // Record that we sent the notification today (once per day deduplication)
      await recordBusinessHoursNotification(today);

      // Publish metric for business hours skips with cost impact
      await publishMetric('BusinessHoursSkips', 1);
      await publishMetric('BusinessHoursSkipCostImpact', parseFloat(costProjection.hourly));
      return;
    }

    // Check enhanced cooldown period to prevent rapid cycling
    if (await isInCooldownPeriod()) {
      const remainingCooldown = await getRemainingCooldownMinutes();
      console.log(`Skipping auto-disassociation - still in cooldown period (${remainingCooldown} minutes remaining)`);

      // Enhanced cooldown notification with context
      const envStyle = getEnvironmentStyle();

      await slack.sendSlackNotification({
        text: `⏳ Cooldown Protection Active - ${envStyle.titleSuffix}`,
        attachments: [{
          color: envStyle.color,
          fields: [
            {
              title: `${envStyle.emoji} Environment`,
              value: envStyle.name,
              short: true
            },
            {
              title: "⏱️ Time Remaining",
              value: `${Math.ceil(remainingCooldown)} minutes`,
              short: true
            },
            {
              title: "🔄 Purpose",
              value: "Prevents rapid cycling",
              short: true
            },
            {
              title: "📈 Current Idle",
              value: `${idleTimeMinutes} minutes`,
              short: true
            },
            {
              title: "💡 Manual Override",
              value: `/vpn close ${ENVIRONMENT} for immediate shutdown`,
              short: false
            }
          ]
        }]
      });

      await publishMetric('CooldownSkips', 1);
      await publishMetric('CooldownRemainingMinutes', remainingCooldown);
      return;
    }

    // Auto-disassociate subnets to save costs
    console.log(`Auto-disassociating VPN subnets after ${idleTimeMinutes} minutes of idle time`);
    
    try {
      await vpnManager.disassociateSubnets();
      
      // Record cooldown timestamp to prevent rapid cycling
      await recordCooldownTimestamp();
      
      // Calculate detailed cost savings
      const costSavings = await calculateCostSavings(idleTimeMinutes);
      
      // Publish enhanced auto-disassociation metrics
      await publishMetric('IdleSubnetDisassociations', 1);
      await publishMetric('IdleMinutesWhenDisassociated', idleTimeMinutes);
      await publishMetric('AutoDisassociationTriggerCount', 1);
      
      // Track cumulative savings
      await trackCumulativeSavings(costSavings);
      
      // Publish cost savings metrics
      await publishCostSavingsMetrics(costSavings, idleTimeMinutes);
      
      // Send enhanced bilingual Slack notification about automatic action
      const envStyle = getEnvironmentStyle();

      // Create bilingual message with beautiful formatting using attachments
      await slack.sendSlackNotification({
        text: `💰 Auto VPN Cost Optimization - ${envStyle.titleSuffix}`,
        attachments: [{
          color: envStyle.color,
          fields: [
            {
              title: `${envStyle.emoji} Environment`,
              value: envStyle.name,
              short: true
            },
            {
              title: "📊 Idle Duration",
              value: `${idleTimeMinutes} minutes (threshold: ${IDLE_MINUTES}min)`,
              short: true
            },
            {
              title: "💵 Waste Prevented",
              value: `~$${costSavings.total} saved\n_${costSavings.details.wasteTimePrevented}h of 24/7 waste prevented_`,
              short: true
            },
            {
              title: "🔧 Action Taken",
              value: "Subnets auto-disassociated",
              short: true
            },
            {
              title: "📱 Re-enable",
              value: `/vpn open ${ENVIRONMENT}`,
              short: true
            },
            {
              title: "⏰ Cooldown Period",
              value: `${COOLDOWN_MINUTES} minutes (prevents rapid cycling)`,
              short: true
            }
          ],
          footer: "VPN Automation System",
          ts: Math.floor(Date.now() / 1000)
        }]
      });
      
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
  const { hour, minute, dayOfWeek } = getAdjustedTimeComponents();

  // Business hours: Monday-Friday, 10:00 AM - 5:00 PM in specified timezone
  const isWeekday = dayOfWeek >= 1 && dayOfWeek <= 5;

  // Check if after 10:00 AM: hour >= 10
  const isAfterStart = hour >= 10;

  // Check if before 5:00 PM: hour < 17
  const isBeforeEnd = hour < 17;

  const isBusinessHour = isAfterStart && isBeforeEnd;

  console.log(`Business hours check: ${BUSINESS_HOURS_TIMEZONE} time, hour=${hour}, minute=${minute}, day=${dayOfWeek}, weekday=${isWeekday}, business_hour=${isBusinessHour}`);

  return isWeekday && isBusinessHour;
}

/**
 * Check if current time is during the weekend (Saturday or Sunday)
 * Uses shared timezone handling via getAdjustedTimeComponents()
 */
function isWeekend(): boolean {
  const { dayOfWeek } = getAdjustedTimeComponents();

  // 0 = Sunday, 6 = Saturday
  const isWeekendDay = dayOfWeek === 0 || dayOfWeek === 6;
  console.log(`Weekend check: ${BUSINESS_HOURS_TIMEZONE} time, day=${dayOfWeek}, isWeekend=${isWeekendDay}`);

  return isWeekendDay;
}

/**
 * Calculate connection duration in hours
 * @param establishedTime - When the connection was established
 * @returns Duration in hours (floating point)
 */
function getConnectionDurationHours(establishedTime: Date | string): number {
  const established = establishedTime instanceof Date
    ? establishedTime
    : new Date(establishedTime);

  if (isNaN(established.getTime())) {
    return 0;
  }

  const now = new Date();
  const durationMs = now.getTime() - established.getTime();
  return durationMs / (1000 * 60 * 60); // Convert to hours
}

// Check if we're in a cooldown period after recent auto-disassociation
async function isInCooldownPeriod(): Promise<boolean> {
  try {
    const cooldownParam = await stateStore.readParameter(`/vpn/${ENVIRONMENT}/automation/cooldown`);
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
    const cooldownParam = await stateStore.readParameter(`/vpn/${ENVIRONMENT}/automation/cooldown`);
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
    await stateStore.writeParameter(`/vpn/${ENVIRONMENT}/automation/cooldown`, now);
    console.log(`Recorded cooldown timestamp: ${now}`);
  } catch (error) {
    console.error('Failed to record cooldown timestamp:', error);
    // Don't throw as this shouldn't break the main operation
  }
}

// Clear cooldown timestamp when VPN is actively being used
async function clearCooldownTimestamp(): Promise<void> {
  try {
    await stateStore.writeParameter(`/vpn/${ENVIRONMENT}/automation/cooldown`, '');
    console.log('Cleared cooldown timestamp due to active usage');
  } catch (error) {
    console.error('Failed to clear cooldown timestamp:', error);
  }
}

// Check if there has been recent manual activity (Slack commands)
async function hasRecentManualActivity(): Promise<boolean> {
  try {
    const manualActivityParam = await stateStore.readParameter(`/vpn/${ENVIRONMENT}/automation/manual_activity`);
    if (!manualActivityParam) {
      return false;
    }
    
    const manualActivityTime = new Date(manualActivityParam);
    const now = new Date();
    const timeSinceManualActivity = (now.getTime() - manualActivityTime.getTime()) / (1000 * 60); // minutes
    
    // Consider manual activity "recent" if it happened within the last 15 minutes
    const manualActivityGracePeriod = 15;
    const isRecent = timeSinceManualActivity < manualActivityGracePeriod;
    
    if (isRecent) {
      console.log(`Recent manual activity detected: ${timeSinceManualActivity.toFixed(1)} minutes ago`);

      // Enhanced manual activity notification
      const envStyle = getEnvironmentStyle();

      await slack.sendSlackNotification({
        text: `👤 Manual Activity Detected - ${envStyle.titleSuffix}`,
        attachments: [{
          color: envStyle.color,
          fields: [
            {
              title: `${envStyle.emoji} Environment`,
              value: envStyle.name,
              short: true
            },
            {
              title: "🕰️ Last Activity",
              value: `${timeSinceManualActivity.toFixed(1)} minutes ago`,
              short: true
            },
            {
              title: "⏱️ Grace Period",
              value: `${manualActivityGracePeriod} minutes`,
              short: true
            },
            {
              title: "🔒 Protection Status",
              value: "Auto-close temporarily disabled",
              short: true
            },
            {
              title: "📝 Note",
              value: "Auto-monitoring will resume after grace period",
              short: false
            }
          ]
        }]
      });
    }
    
    return isRecent;
  } catch (error) {
    console.log('No manual activity timestamp found');
    return false;
  }
}

// Check for administrative override to disable auto-disassociation
async function hasAdministrativeOverride(): Promise<boolean> {
  try {
    const overrideParam = await stateStore.readParameter(`/vpn/${ENVIRONMENT}/automation/admin_override`);
    if (!overrideParam) {
      return false;
    }
    
    // Check if override is still valid (has expiration)
    if (overrideParam.includes('expires:')) {
      const expiryMatch = overrideParam.match(/expires:(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})/);
      if (expiryMatch) {
        const expiryTime = new Date(expiryMatch[1]);
        const now = new Date();
        
        if (now > expiryTime) {
          console.log('Administrative override has expired, clearing it');
          await stateStore.writeParameter(`/vpn/${ENVIRONMENT}/automation/admin_override`, '');
          return false;
        }
      }
    }
    
    return overrideParam === 'enabled' || overrideParam.startsWith('enabled:');
  } catch (error) {
    console.log('No administrative override found');
    return false;
  }
}

// True cost savings calculation based on preventing 24/7 waste with AWS hourly billing
async function calculateCostSavings(idleTimeMinutes: number): Promise<{ hourly: string; total: string; details: any }> {
  try {
    // AWS Client VPN pricing varies by region and includes multiple components
    const regionalPricing: { [key: string]: { subnetAssociation: number; endpointHour: number } } = {
      'us-east-1': { subnetAssociation: 0.10, endpointHour: 0.05 },
      'us-west-2': { subnetAssociation: 0.10, endpointHour: 0.05 },
      'eu-west-1': { subnetAssociation: 0.12, endpointHour: 0.06 },
      'ap-southeast-1': { subnetAssociation: 0.15, endpointHour: 0.07 },
      'default': { subnetAssociation: 0.10, endpointHour: 0.05 }
    };
    
    const region = process.env.AWS_REGION || 'default';
    const pricing = regionalPricing[region] || regionalPricing['default'];
    
    // Try to get actual subnet count from VPN configuration
    let subnetCount = 1; // Default fallback
    try {
      const config = await stateStore.readConfig();
      // If SUBNET_ID contains comma-separated values, count them
      if (config.SUBNET_ID && config.SUBNET_ID.includes(',')) {
        subnetCount = config.SUBNET_ID.split(',').length;
      }
    } catch (error) {
      console.log('Could not determine subnet count, using default of 1');
    }
    
    // Calculate hourly cost (only subnet association is saved when VPN closes)
    const hourlySubnetCost = pricing.subnetAssociation * subnetCount;
    
    // Key insight: Without auto-cost system, VPN would run 24/7 due to human forgetfulness
    // With auto-cost system, VPN runs for idle time then auto-closes
    // AWS bills partial hours as full hours, so we need to account for that
    
    const idleHours = idleTimeMinutes / 60;
    const billedIdleHours = Math.ceil(idleHours); // AWS rounds up partial hours
    
    // Calculate the waste time prevented
    // This represents the time from auto-close until next expected usage
    // Conservative estimate: VPN would stay on until next business period
    const currentHour = new Date().getHours();
    let estimatedWasteHours = 0;
    
    // Estimate waste time based on time of day
    if (currentHour >= 18 || currentHour < 9) {
      // Evening/night closure - would waste until next morning
      estimatedWasteHours = currentHour >= 18 ? (24 - currentHour + 9) : (9 - currentHour);
    } else {
      // Daytime closure - conservative estimate of 4 hours until next usage
      estimatedWasteHours = 4;
    }
    
    // True savings = Waste time prevented × hourly cost
    // This is the cost we would have paid without the auto-system
    const totalSavingsForPeriod = estimatedWasteHours * hourlySubnetCost;
    
    const details = {
      region,
      subnetCount,
      idleTimeMinutes,
      idleHours: idleHours.toFixed(2),
      billedIdleHours,
      estimatedWasteHours,
      costPerSubnetPerHour: pricing.subnetAssociation,
      actualCostPaid: billedIdleHours * hourlySubnetCost,
      wasteTimePrevented: estimatedWasteHours,
      savingsExplanation: `Prevented ${estimatedWasteHours}h of waste (VPN would run 24/7 without auto-system)`
    };
    
    return {
      hourly: hourlySubnetCost.toFixed(2),
      total: totalSavingsForPeriod.toFixed(2),
      details
    };
  } catch (error) {
    console.error('Error calculating cost savings:', error);
    // Fallback to simple calculation - assume 8 hours of waste prevented
    const simpleSavings = (0.10 * 1 * 8).toFixed(2); // 8 hours of waste prevented
    return {
      hourly: '0.10',
      total: simpleSavings,
      details: { 
        error: 'Calculation failed, using fallback estimate',
        explanation: 'Estimated 8 hours of waste prevented'
      }
    };
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

// Helper function to publish comprehensive status metrics
async function publishStatusMetrics(status: any): Promise<void> {
  const metrics = [
    {
      MetricName: 'VpnAssociationStatus',
      Value: status.associated ? 1 : 0,
      Unit: StandardUnit.None
    },
    {
      MetricName: 'VpnActiveConnections',
      Value: status.activeConnections,
      Unit: StandardUnit.Count
    },
    {
      MetricName: 'VpnUptimeMinutes',
      Value: status.associated ? 5 : 0, // 5-minute intervals when running
      Unit: StandardUnit.Count
    },
    {
      MetricName: 'VpnDowntimeMinutes',
      Value: !status.associated ? 5 : 0, // 5-minute intervals when stopped
      Unit: StandardUnit.Count
    }
  ];

  try {
    await cloudwatch.send(new PutMetricDataCommand({
      Namespace: 'VPN/Automation',
      MetricData: metrics.map(metric => ({
        ...metric,
        Dimensions: [{
          Name: 'Environment',
          Value: ENVIRONMENT
        }],
        Timestamp: new Date()
      }))
    }));
    
    console.log('Published status metrics:', metrics.map(m => `${m.MetricName}: ${m.Value}`));
  } catch (error) {
    console.error('Failed to publish status metrics:', error);
  }
}

// Publish detailed cost savings metrics for analysis
async function publishCostSavingsMetrics(costSavings: any, idleMinutes: number): Promise<void> {
  const metrics = [
    {
      MetricName: 'CostSavingsPerHour',
      Value: parseFloat(costSavings.hourly),
      Unit: StandardUnit.Count // Represents dollars
    },
    {
      MetricName: 'CostSavingsTotal',
      Value: parseFloat(costSavings.total),
      Unit: StandardUnit.Count // Represents dollars
    },
    {
      MetricName: 'IdleTimeBeforeDisassociation',
      Value: idleMinutes,
      Unit: StandardUnit.Count // Minutes
    },
    {
      MetricName: 'SubnetCount',
      Value: costSavings.details.subnetCount || 1,
      Unit: StandardUnit.Count
    }
  ];

  try {
    await cloudwatch.send(new PutMetricDataCommand({
      Namespace: 'VPN/CostOptimization',
      MetricData: metrics.map(metric => ({
        ...metric,
        Dimensions: [
          {
            Name: 'Environment',
            Value: ENVIRONMENT
          },
          {
            Name: 'Region',
            Value: costSavings.details.region || 'unknown'
          }
        ],
        Timestamp: new Date()
      }))
    }));
    
    console.log('Published cost savings metrics:', metrics.map(m => `${m.MetricName}: ${m.Value}`));
  } catch (error) {
    console.error('Failed to publish cost savings metrics:', error);
  }
}

// Track cumulative cost savings over time
async function trackCumulativeSavings(costSavings: any): Promise<void> {
  try {
    // Read existing cumulative savings
    const cumulativeKey = `/vpn/cost_optimization/cumulative_savings/${ENVIRONMENT}`;
    let cumulativeSavings = 0;
    
    try {
      const existing = await stateStore.readParameter(cumulativeKey);
      cumulativeSavings = parseFloat(existing) || 0;
    } catch (error) {
      console.log('No existing cumulative savings found, starting fresh');
    }
    
    // Add current savings
    cumulativeSavings += parseFloat(costSavings.total);
    
    // Store updated cumulative savings
    await stateStore.writeParameter(cumulativeKey, cumulativeSavings.toString());
    
    // Publish cumulative savings metric
    await cloudwatch.send(new PutMetricDataCommand({
      Namespace: 'VPN/CostOptimization',
      MetricData: [{
        MetricName: 'CumulativeSavings',
        Value: cumulativeSavings,
        Unit: StandardUnit.Count,
        Dimensions: [{
          Name: 'Environment',
          Value: ENVIRONMENT
        }],
        Timestamp: new Date()
      }]
    }));
    
    console.log(`Updated cumulative savings: $${cumulativeSavings.toFixed(2)}`);
    
    // Track daily savings for reporting
    await trackDailySavings(parseFloat(costSavings.total));
    
  } catch (error) {
    console.error('Failed to track cumulative savings:', error);
  }
}

// Track daily savings for reporting and trending
async function trackDailySavings(savingsAmount: number): Promise<void> {
  try {
    const today = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
    const dailyKey = `/vpn/cost_optimization/daily_savings/${ENVIRONMENT}/${today}`;
    
    let dailySavings = 0;
    try {
      const existing = await stateStore.readParameter(dailyKey);
      dailySavings = parseFloat(existing) || 0;
    } catch (error) {
      console.log(`No existing daily savings found for ${today}`);
    }
    
    dailySavings += savingsAmount;
    await stateStore.writeParameter(dailyKey, dailySavings.toString());
    
    // Publish daily savings metric
    await cloudwatch.send(new PutMetricDataCommand({
      Namespace: 'VPN/CostOptimization',
      MetricData: [{
        MetricName: 'DailySavings',
        Value: dailySavings,
        Unit: StandardUnit.Count,
        Dimensions: [
          {
            Name: 'Environment',
            Value: ENVIRONMENT
          },
          {
            Name: 'Date',
            Value: today
          }
        ],
        Timestamp: new Date()
      }]
    }));
    
    console.log(`Updated daily savings for ${today}: $${dailySavings.toFixed(2)} (waste time prevented)`);
    
    // Also calculate and store the theoretical daily maximum savings
    // This represents what we would save if VPN ran 24/7 vs optimal usage
    await calculateAndStoreDailyMaxSavings(today);
    
  } catch (error) {
    console.error('Failed to track daily savings:', error);
  }
}

// Calculate theoretical daily maximum savings (24/7 cost vs actual usage)
async function calculateAndStoreDailyMaxSavings(dateStr: string): Promise<void> {
  try {
    // Get all VPN runtime periods for today from state tracking
    const runtimeKey = `/vpn/runtime_tracking/${ENVIRONMENT}/${dateStr}`;
    let totalRuntimeHours = 0;

    try {
      const runtimeData = await stateStore.readParameter(runtimeKey);
      const runtime = JSON.parse(runtimeData);
      totalRuntimeHours = runtime.totalHours || 0;
    } catch (error) {
      // If no runtime data, estimate based on current closure
      // This is a fallback - ideally we'd track all start/stop events
      console.log('No runtime tracking data found, using estimation');
      return;
    }

    // Calculate theoretical maximum daily savings
    const pricing = 0.10; // Default US pricing
    const subnetCount = 1; // Default

    const maxDailyCost = 24 * pricing * subnetCount; // 24/7 cost
    const actualDailyCost = Math.ceil(totalRuntimeHours) * pricing * subnetCount; // AWS hourly billing
    const theoreticalMaxSavings = maxDailyCost - actualDailyCost;

    // Store theoretical max savings for reporting
    const maxSavingsKey = `/vpn/cost_optimization/daily_max_savings/${ENVIRONMENT}/${dateStr}`;
    await stateStore.writeParameter(maxSavingsKey, theoreticalMaxSavings.toString());

    console.log(`Theoretical max daily savings for ${dateStr}: $${theoreticalMaxSavings.toFixed(2)} (24h cost: $${maxDailyCost} - actual: $${actualDailyCost})`);

  } catch (error) {
    console.error('Failed to calculate daily max savings:', error);
  }
}

// Check for pending association completion and send notification
async function checkAndNotifyAssociationCompletion(status: any): Promise<{ notified: boolean; startedBy?: string; duration?: string }> {
  try {
    const pendingParam = await stateStore.readParameter(`/vpn/${ENVIRONMENT}/automation/pending_association`);

    if (!pendingParam) {
      return { notified: false };
    }

    const pending = JSON.parse(pendingParam);
    const startedAt = new Date(pending.startedAt);
    const now = new Date();
    const durationMs = now.getTime() - startedAt.getTime();
    const durationMinutes = Math.round(durationMs / (1000 * 60));

    // Check if association is now complete
    if (status.associationState === 'associated') {
      // Clear pending association
      await stateStore.deleteParameter(`/vpn/${ENVIRONMENT}/automation/pending_association`);

      // Send success notification
      const envStyle = getEnvironmentStyle();

      await slack.sendSlackNotification({
        text: `✅ VPN Ready for Connections - ${envStyle.titleSuffix}`,
        attachments: [{
          color: envStyle.color,
          fields: [
            { title: `${envStyle.emoji} Environment`, value: envStyle.name, short: true },
            { title: '⏱️ Association Time', value: `${durationMinutes} minute${durationMinutes !== 1 ? 's' : ''}`, short: true },
            { title: '👤 Started By', value: pending.startedBy || 'unknown', short: true },
            { title: '✅ Status', value: 'Ready for connections', short: true }
          ]
        }]
      });

      await publishMetric('VpnAssociationCompleted', 1);
      await publishMetric('VpnAssociationDurationMinutes', durationMinutes);

      return { notified: true, startedBy: pending.startedBy, duration: `${durationMinutes}m` };
    }

    // Check if association failed
    if (status.associationState === 'failed' || status.associationState === 'disassociated') {
      // Clear pending association
      await stateStore.deleteParameter(`/vpn/${ENVIRONMENT}/automation/pending_association`);

      // Send failure notification
      const envStyle = getEnvironmentStyle();

      await slack.sendSlackNotification({
        text: `❌ VPN Association Failed - ${envStyle.titleSuffix}`,
        attachments: [{
          color: envStyle.color,
          fields: [
            { title: `${envStyle.emoji} Environment`, value: envStyle.name, short: true },
            { title: 'State', value: status.associationState || 'unknown', short: true },
            { title: 'Started By', value: pending.startedBy || 'unknown', short: true },
            { title: 'Recommendation', value: 'Try `/vpn open` again', short: false }
          ]
        }]
      });

      await publishMetric('VpnAssociationFailed', 1);

      return { notified: true, startedBy: pending.startedBy, duration: `${durationMinutes}m` };
    }

    // Still associating - check for timeout (15 minutes max)
    if (durationMinutes > 15) {
      // Clear pending association due to timeout
      await stateStore.deleteParameter(`/vpn/${ENVIRONMENT}/automation/pending_association`);

      const envStyle = getEnvironmentStyle();

      await slack.sendSlackNotification({
        text: `⚠️ VPN Association Timed Out - ${envStyle.titleSuffix}`,
        attachments: [{
          color: envStyle.color,
          fields: [
            { title: `${envStyle.emoji} Environment`, value: envStyle.name, short: true },
            { title: 'Current State', value: status.associationState || 'unknown', short: true },
            { title: 'Duration', value: `${durationMinutes} minutes`, short: true },
            { title: '⚠️ Action Required', value: 'Please check status manually with `/vpn check` or AWS Console. No further automatic notifications will be sent.', short: false }
          ]
        }]
      });

      await publishMetric('VpnAssociationTimeout', 1);

      return { notified: true, startedBy: pending.startedBy, duration: `${durationMinutes}m` };
    }

    // Still in progress, not yet timed out - send progress notification
    console.log(`VPN association still in progress: ${status.associationState} (${durationMinutes}m elapsed)`);

    const envStyle = getEnvironmentStyle();
    await slack.sendSlackNotification({
      text: `⏳ VPN Still Associating - ${envStyle.titleSuffix}`,
      attachments: [{
        color: envStyle.color,
        fields: [
          { title: `${envStyle.emoji} Environment`, value: envStyle.name, short: true },
          { title: '🔄 Status', value: 'Associating...', short: true },
          { title: '⏱️ Elapsed Time', value: `${durationMinutes} minute${durationMinutes !== 1 ? 's' : ''}`, short: true },
          { title: '👤 Started By', value: pending.startedBy || 'unknown', short: true }
        ]
      }]
    });

    return { notified: true };

  } catch (error) {
    // No pending association or error reading parameter
    console.log('No pending association found or error:', error);
    return { notified: false };
  }
}

// Check for pending disassociation completion and send notification
async function checkAndNotifyDisassociationCompletion(status: any): Promise<{ notified: boolean; startedBy?: string; duration?: string }> {
  try {
    const pendingParam = await stateStore.readParameter(`/vpn/${ENVIRONMENT}/automation/pending_disassociation`);

    if (!pendingParam) {
      return { notified: false };
    }

    const pending = JSON.parse(pendingParam);
    const startedAt = new Date(pending.startedAt);
    const now = new Date();
    const durationMs = now.getTime() - startedAt.getTime();
    const durationMinutes = Math.round(durationMs / (1000 * 60));

    // Check if disassociation is now complete
    // NOTE: Only check associationState, not status.associated, because associated may
    // become false before the state transitions to 'disassociated', causing premature detection
    if (status.associationState === 'disassociated') {
      // Clear pending disassociation
      await stateStore.deleteParameter(`/vpn/${ENVIRONMENT}/automation/pending_disassociation`);

      // Send success notification
      const envStyle = getEnvironmentStyle();

      await slack.sendSlackNotification({
        text: `🔴 VPN Is Now Closed - ${envStyle.titleSuffix}`,
        attachments: [{
          color: envStyle.color,
          fields: [
            { title: `${envStyle.emoji} Environment`, value: envStyle.name, short: true },
            { title: '⏱️ Disassociation Time', value: `${durationMinutes} minute${durationMinutes !== 1 ? 's' : ''}`, short: true },
            { title: '👤 Closed By', value: pending.startedBy || 'unknown', short: true },
            { title: '🔴 Status', value: 'VPN is now closed', short: true }
          ]
        }]
      });

      await publishMetric('VpnDisassociationCompleted', 1);
      await publishMetric('VpnDisassociationDurationMinutes', durationMinutes);

      return { notified: true, startedBy: pending.startedBy, duration: `${durationMinutes}m` };
    }

    // Check if disassociation failed (went back to associated somehow)
    if (status.associationState === 'associated') {
      // Clear pending disassociation
      await stateStore.deleteParameter(`/vpn/${ENVIRONMENT}/automation/pending_disassociation`);

      // Send failure notification
      const envStyle = getEnvironmentStyle();

      await slack.sendSlackNotification({
        text: `⚠️ VPN Disassociation Cancelled - ${envStyle.titleSuffix}`,
        attachments: [{
          color: envStyle.color,
          fields: [
            { title: `${envStyle.emoji} Environment`, value: envStyle.name, short: true },
            { title: 'State', value: 'Still associated', short: true },
            { title: 'Started By', value: pending.startedBy || 'unknown', short: true },
            { title: 'Note', value: 'VPN remains open', short: false }
          ]
        }]
      });

      return { notified: true, startedBy: pending.startedBy, duration: `${durationMinutes}m` };
    }

    // Still disassociating - check for timeout (15 minutes max)
    if (durationMinutes > 15) {
      // Clear pending disassociation due to timeout
      await stateStore.deleteParameter(`/vpn/${ENVIRONMENT}/automation/pending_disassociation`);

      const envStyle = getEnvironmentStyle();

      await slack.sendSlackNotification({
        text: `⚠️ VPN Disassociation Timed Out - ${envStyle.titleSuffix}`,
        attachments: [{
          color: envStyle.color,
          fields: [
            { title: `${envStyle.emoji} Environment`, value: envStyle.name, short: true },
            { title: 'Current State', value: status.associationState || 'unknown', short: true },
            { title: 'Duration', value: `${durationMinutes} minutes`, short: true },
            { title: '⚠️ Action Required', value: 'Please check status manually with `/vpn check` or AWS Console. No further automatic notifications will be sent.', short: false }
          ]
        }]
      });

      await publishMetric('VpnDisassociationTimeout', 1);

      return { notified: true, startedBy: pending.startedBy, duration: `${durationMinutes}m` };
    }

    // Still in progress, not yet timed out - send progress notification
    console.log(`VPN disassociation still in progress: ${status.associationState} (${durationMinutes}m elapsed)`);

    const envStyle = getEnvironmentStyle();
    await slack.sendSlackNotification({
      text: `⏳ VPN Still Disassociating - ${envStyle.titleSuffix}`,
      attachments: [{
        color: envStyle.color,
        fields: [
          { title: `${envStyle.emoji} Environment`, value: envStyle.name, short: true },
          { title: '🔄 Status', value: 'Disassociating...', short: true },
          { title: '⏱️ Elapsed Time', value: `${durationMinutes} minute${durationMinutes !== 1 ? 's' : ''}`, short: true },
          { title: '👤 Started By', value: pending.startedBy || 'unknown', short: true }
        ]
      }]
    });

    return { notified: true };

  } catch (error) {
    // No pending disassociation or error reading parameter
    console.log('No pending disassociation found or error:', error);
    return { notified: false };
  }
}

// Check for and handle pending close retries (soft close mechanism)
async function checkAndHandlePendingClose(): Promise<{ handled: boolean; status: string }> {
  const RETRY_DELAY_MINUTES = 30;

  try {
    // Check for pending close in SSM
    const pendingCloseParam = await stateStore.readParameter(`/vpn/${ENVIRONMENT}/automation/pending_close`);

    if (!pendingCloseParam) {
      return { handled: false, status: 'no_pending_close' };
    }

    const pendingClose = JSON.parse(pendingCloseParam);
    const retryTime = new Date(pendingClose.retryTime);
    const now = new Date();

    // Check if it's time to retry
    if (now < retryTime) {
      const remainingMinutes = Math.ceil((retryTime.getTime() - now.getTime()) / (1000 * 60));
      console.log(`Pending close scheduled for ${pendingClose.retryTime}, ${remainingMinutes} minutes remaining`);
      return { handled: false, status: `pending_retry_in_${remainingMinutes}_minutes` };
    }

    console.log(`Processing pending close retry for ${ENVIRONMENT} (attempt #${pendingClose.attempts}, reason: ${pendingClose.reason})`);

    // Fetch current VPN status
    const status = await vpnManager.fetchStatus();

    // If already closed, clear pending close and return
    if (!status.associated) {
      console.log('VPN is already closed, clearing pending close');
      await stateStore.deleteParameter(`/vpn/${ENVIRONMENT}/automation/pending_close`);
      return { handled: true, status: 'already_closed' };
    }

    // Check for active connections with traffic status
    if (status.activeConnections > 0) {
      const connectionDetails = status.activeConnectionDetails || [];
      const usernames = connectionDetails.map(c => c.username).join(', ') || 'unknown';

      // Check traffic status - only delay if connections have actual traffic or haven't been idle long enough
      const hasActiveTraffic = status.trafficSummary?.status === 'active';
      const idleMinutes = status.trafficSummary?.idleMinutes || 0;
      const shouldDelayClose = hasActiveTraffic || idleMinutes < SOFT_CLOSE_IDLE_THRESHOLD_MINUTES;

      if (shouldDelayClose) {
        const nextRetryTime = new Date(now.getTime() + RETRY_DELAY_MINUTES * 60 * 1000);
        const nextRetryTimeStr = nextRetryTime.toLocaleString('zh-TW', { timeZone: 'Asia/Taipei' });
        const trafficStatusStr = hasActiveTraffic ? 'active' : `idle (${idleMinutes}min)`;

        console.log(`VPN has ${status.activeConnections} connections (${usernames}), traffic: ${trafficStatusStr}, scheduling next retry at ${nextRetryTimeStr}`);

        // Schedule next retry
        const newPendingClose = {
          retryTime: nextRetryTime.toISOString(),
          reason: pendingClose.reason,
          attempts: pendingClose.attempts + 1,
          scheduledAt: pendingClose.scheduledAt // Keep original scheduled time
        };

        await stateStore.writeParameter(
          `/vpn/${ENVIRONMENT}/automation/pending_close`,
          JSON.stringify(newPendingClose)
        );

        // Send Slack notification only on odd retry attempts (1, 3, 5...)
        // to reduce notification noise while still keeping users informed
        if (pendingClose.attempts % SOFT_CLOSE_NOTIFICATION_FREQUENCY === 1) {
          const noteMessage = hasActiveTraffic
            ? 'Respecting active connections with recent traffic'
            : `Connections idle for ${idleMinutes}min (will auto-close at ${SOFT_CLOSE_IDLE_THRESHOLD_MINUTES}min of inactivity)`;

          const envStyle = getEnvironmentStyle();

          await slack.sendSlackNotification({
            text: `⏳ VPN Close Delayed - ${envStyle.titleSuffix}`,
            attachments: [{
              color: envStyle.color,
              fields: [
                { title: `${envStyle.emoji} Environment`, value: envStyle.name, short: true },
                { title: '👥 Connections', value: status.activeConnections.toString(), short: true },
                { title: '👤 Users', value: usernames, short: true },
                { title: '📊 Traffic Status', value: trafficStatusStr, short: true },
                { title: '🔄 Retry Attempt', value: `#${pendingClose.attempts}`, short: true },
                { title: '⏰ Next Check', value: nextRetryTimeStr, short: true },
                { title: '📅 Reason', value: pendingClose.reason === 'weekend' ? 'Weekend close' : 'Scheduled close', short: true },
                { title: '💡 Note', value: noteMessage, short: false }
              ]
            }]
          });
        }

        await publishMetric('SoftCloseRetryDelayed', 1);
        return { handled: true, status: 'delayed_again' };
      } else {
        // Connections exist but have been idle for 60+ minutes - proceed with close
        console.log(`Connections idle for ${idleMinutes}min (threshold: ${SOFT_CLOSE_IDLE_THRESHOLD_MINUTES}min), proceeding with soft close`);
        // Fall through to close logic below
      }
    }

    // Capture info about idle connections before close (if any)
    const connectionDetails = status.activeConnectionDetails || [];
    const idleUsernames = connectionDetails.map(c => c.username).join(', ') || '';
    const idleMinutes = status.trafficSummary?.idleMinutes || 0;
    const hadIdleConnections = status.activeConnections > 0 && idleMinutes >= SOFT_CLOSE_IDLE_THRESHOLD_MINUTES;

    // Proceed with close
    const closeReason = hadIdleConnections
      ? `Closing ${status.activeConnections} idle connection(s) after ${idleMinutes}min of inactivity`
      : 'No active connections';
    console.log(`${closeReason}, proceeding with soft close (attempt #${pendingClose.attempts})`);

    try {
      await vpnManager.disassociateSubnets();

      // Clear pending close
      await stateStore.deleteParameter(`/vpn/${ENVIRONMENT}/automation/pending_close`);

      // Send success notification
      const closeTimeStr = new Date().toLocaleString('zh-TW', { timeZone: 'Asia/Taipei' });
      const envStyle = getEnvironmentStyle();

      // Build notification fields
      const notificationFields = [
        { title: `${envStyle.emoji} Environment`, value: envStyle.name, short: true },
        { title: '🕤 Time', value: closeTimeStr, short: true },
        { title: '🔄 Retry Attempts', value: pendingClose.attempts.toString(), short: true },
        { title: '📅 Original Reason', value: pendingClose.reason === 'weekend' ? 'Weekend close' : 'Scheduled close', short: true }
      ];

      // Add idle connection info if applicable
      if (hadIdleConnections) {
        notificationFields.push(
          { title: '👤 Users Disconnected', value: idleUsernames, short: true },
          { title: '⏱️ Idle Duration', value: `${idleMinutes}min (threshold: ${SOFT_CLOSE_IDLE_THRESHOLD_MINUTES}min)`, short: true }
        );
      }

      notificationFields.push(
        { title: '💰 Cost Saving', value: 'Preventing unnecessary charges', short: false },
        { title: '💡 Note', value: hadIdleConnections
          ? `Closed idle connections after ${SOFT_CLOSE_IDLE_THRESHOLD_MINUTES}+ minutes of inactivity`
          : 'Closed after all connections ended', short: false }
      );

      await slack.sendSlackNotification({
        text: `🌙 VPN Soft Close Completed - ${envStyle.titleSuffix}`,
        attachments: [{
          color: envStyle.color,
          fields: notificationFields
        }]
      });

      await publishMetric('SoftCloseCompleted', 1);
      if (hadIdleConnections) {
        await publishMetric('SoftCloseIdleConnectionsClosed', status.activeConnections);
      }
      return { handled: true, status: hadIdleConnections ? 'closed_idle_connections' : 'closed_successfully' };

    } catch (closeError) {
      console.error('Failed to close VPN during soft close retry:', closeError);

      // Send error notification
      const envStyle = getEnvironmentStyle();

      await slack.sendSlackNotification({
        text: `❌ VPN Soft Close Failed - ${envStyle.titleSuffix}`,
        attachments: [{
          color: envStyle.color,
          fields: [
            { title: `${envStyle.emoji} Environment`, value: envStyle.name, short: true },
            { title: '🕤 Time', value: new Date().toISOString(), short: true },
            { title: '🔄 Retry Attempt', value: pendingClose.attempts.toString(), short: true },
            { title: '❌ Error', value: closeError instanceof Error ? closeError.message : 'Unknown error', short: false }
          ]
        }]
      });

      await publishMetric('SoftCloseErrors', 1);
      return { handled: true, status: 'close_failed' };
    }

  } catch (error) {
    console.error('Error checking pending close:', error);
    return { handled: false, status: 'error' };
  }
}

// Check if business hours notification was already sent today (once per day deduplication)
async function hasBusinessHoursNotificationToday(today: string): Promise<boolean> {
  try {
    const lastNotified = await stateStore.readParameter(
      `/vpn/${ENVIRONMENT}/automation/notification/business_hours_notified`
    );
    return lastNotified === today;
  } catch {
    return false;
  }
}

// Record that business hours notification was sent today
async function recordBusinessHoursNotification(today: string): Promise<void> {
  try {
    await stateStore.writeParameter(
      `/vpn/${ENVIRONMENT}/automation/notification/business_hours_notified`,
      today
    );
    console.log(`Recorded business hours notification for ${today}`);
  } catch (error) {
    console.error('Failed to record business hours notification:', error);
  }
}

// ============================================================================
// Weekend Active Connection Notification Functions
// ============================================================================

/**
 * Read weekend notification state from SSM
 */
async function readWeekendNotificationState(): Promise<WeekendNotificationState> {
  try {
    const stateJson = await stateStore.readParameter(
      `/vpn/${ENVIRONMENT}/automation/notification/weekend_connection_state`
    );

    if (stateJson) {
      try {
        return JSON.parse(stateJson);
      } catch (parseError) {
        console.error('Failed to parse weekend notification state, resetting:', parseError);
        await publishMetric('WeekendStateParseErrors', 1);
        // Fall through to return default state
      }
    }
  } catch (error) {
    console.log('No existing weekend notification state found, creating new');
  }

  return {
    connections: {},
    lastUpdated: new Date().toISOString()
  };
}

/**
 * Write weekend notification state to SSM
 */
async function writeWeekendNotificationState(state: WeekendNotificationState): Promise<void> {
  try {
    state.lastUpdated = new Date().toISOString();
    await stateStore.writeParameter(
      `/vpn/${ENVIRONMENT}/automation/notification/weekend_connection_state`,
      JSON.stringify(state)
    );
    console.log('Updated weekend notification state');
  } catch (error) {
    console.error('Failed to write weekend notification state:', error);
  }
}

/**
 * Format bytes to human-readable string
 */
function formatBytes(bytes: number): string {
  if (bytes <= 0) return '0 B';  // Guard against zero and negative values
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  const value = bytes / Math.pow(k, i);
  return `${value.toFixed(value >= 100 ? 0 : value >= 10 ? 1 : 2)} ${sizes[i]}`;
}

/**
 * Send Slack notification for a long-running weekend connection
 */
async function sendWeekendConnectionNotification(
  connection: VpnConnectionDetail,
  durationHours: number,
  notificationCount: number
): Promise<void> {
  // Use centralized environment styling
  const envStyle = getEnvironmentStyle();

  // Calculate estimated cost for this connection's duration
  const estimatedCost = (durationHours * CONNECTION_COST_PER_HOUR).toFixed(2);

  // Format duration
  const hours = Math.floor(durationHours);
  const minutes = Math.floor((durationHours - hours) * 60);
  const durationStr = minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;

  // Get current time in configured timezone
  const currentTime = new Date().toLocaleString('zh-TW', { timeZone: BUSINESS_HOURS_TIMEZONE });

  // Build notification title with environment
  const notificationTitle = notificationCount === 1
    ? `📅 Weekend VPN Connection Alert - ${envStyle.titleSuffix}`
    : `📅 Weekend VPN Connection Alert #${notificationCount} - ${envStyle.titleSuffix}`;

  await slack.sendSlackNotification({
    text: notificationTitle,
    attachments: [{
      color: envStyle.color,
      fields: [
        {
          title: `${envStyle.emoji} Environment`,
          value: envStyle.name,
          short: true
        },
        {
          title: '👤 User',
          value: connection.username,
          short: true
        },
        {
          title: '⏱️ Connection Duration',
          value: durationStr,
          short: true
        },
        {
          title: '📊 Total Traffic',
          value: `↓ ${formatBytes(connection.egressBytes)}  ↑ ${formatBytes(connection.ingressBytes)}`,
          short: true
        },
        {
          title: '💰 Estimated Connection Cost',
          value: `$${estimatedCost} ($${CONNECTION_COST_PER_HOUR.toFixed(2)}/hour)`,
          short: true
        },
        {
          title: '🕐 Current Time',
          value: `${currentTime} (${BUSINESS_HOURS_TIMEZONE})`,
          short: true
        },
        {
          title: '💡 Cost Awareness',
          value: 'This connection has been active for 3+ hours on a weekend. Please disconnect if not actively using the VPN to save costs.',
          short: false
        }
      ],
      footer: 'VPN Weekend Cost Awareness System',
      ts: Math.floor(Date.now() / 1000)
    }]
  });

  console.log(`Sent weekend connection notification #${notificationCount} for ${connection.username} (${durationStr}, $${estimatedCost})`);
}

/**
 * Check and send weekend notifications for long-running connections
 *
 * Logic:
 * 1. Only runs on weekends (Saturday/Sunday)
 * 2. First notification: After connection has been active 3+ hours
 * 3. Repeat notifications: Every 1 hour after first notification
 * 4. Cleanup: Remove entries for closed connections
 */
async function checkAndSendWeekendNotifications(
  connections: VpnConnectionDetail[]
): Promise<void> {
  // Only run on weekends
  if (!isWeekend()) {
    return;
  }

  const now = new Date();
  const nowIso = now.toISOString();

  // Read current notification state
  const notificationState = await readWeekendNotificationState();
  let stateModified = false;

  // Get current active connection IDs for cleanup
  const activeConnectionIds = new Set(connections.map(c => c.connectionId));

  // Cleanup: Remove entries for connections that no longer exist
  for (const connectionId of Object.keys(notificationState.connections)) {
    if (!activeConnectionIds.has(connectionId)) {
      console.log(`Removing weekend notification tracking for closed connection: ${connectionId}`);
      delete notificationState.connections[connectionId];
      stateModified = true;
    }
  }

  // Process each active connection
  for (const connection of connections) {
    const durationHours = getConnectionDurationHours(connection.establishedTime);
    const existingEntry = notificationState.connections[connection.connectionId];

    // Check if connection qualifies for notification
    if (durationHours < WEEKEND_NOTIFICATION_FIRST_HOURS) {
      // Connection not old enough yet - skip
      continue;
    }

    let shouldNotify = false;
    let notificationCount = 1;

    if (!existingEntry) {
      // First time seeing this long-running connection - send first notification
      shouldNotify = true;
      notificationState.connections[connection.connectionId] = {
        username: connection.username,
        firstNotificationTime: nowIso,
        lastNotificationTime: nowIso,
        notificationCount: 1
      };
      stateModified = true;

      console.log(`Weekend notification: First alert for ${connection.username} (${durationHours.toFixed(1)}h)`);
    } else {
      // Check if enough time has passed since last notification
      const lastNotification = new Date(existingEntry.lastNotificationTime);
      const hoursSinceLastNotification = (now.getTime() - lastNotification.getTime()) / (1000 * 60 * 60);

      if (hoursSinceLastNotification >= WEEKEND_NOTIFICATION_INTERVAL_HOURS) {
        shouldNotify = true;
        existingEntry.lastNotificationTime = nowIso;
        existingEntry.notificationCount++;
        notificationCount = existingEntry.notificationCount;
        stateModified = true;

        console.log(`Weekend notification: Repeat alert #${notificationCount} for ${connection.username} (${durationHours.toFixed(1)}h)`);
      }
    }

    if (shouldNotify) {
      try {
        await sendWeekendConnectionNotification(connection, durationHours, notificationCount);
        await publishMetric('WeekendConnectionNotifications', 1);
      } catch (notifyError) {
        console.error(`Failed to send weekend notification for ${connection.username}:`, notifyError);
      }
    }
  }

  // Save state if modified
  if (stateModified) {
    await writeWeekendNotificationState(notificationState);
  }
}
