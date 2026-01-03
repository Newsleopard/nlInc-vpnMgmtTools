import { ScheduledEvent, Context } from 'aws-lambda';
import { CloudWatchClient, PutMetricDataCommand, StandardUnit } from '@aws-sdk/client-cloudwatch';

// Import shared utilities from Lambda Layer
import * as vpnManager from '/opt/nodejs/vpnManager';
import * as stateStore from '/opt/nodejs/stateStore';
import * as slack from '/opt/nodejs/slack';
import { createLogger } from '/opt/nodejs/logger';
import * as scheduleManager from '/opt/nodejs/scheduleManager';

const cloudwatch = new CloudWatchClient({});

const IDLE_MINUTES = Number(process.env.IDLE_MINUTES || 54);
const ENVIRONMENT = process.env.ENVIRONMENT || 'staging';
const COOLDOWN_MINUTES = Number(process.env.COOLDOWN_MINUTES || 30);
const BUSINESS_HOURS_ENABLED = process.env.BUSINESS_HOURS_PROTECTION !== 'false';
const BUSINESS_HOURS_TIMEZONE = process.env.BUSINESS_HOURS_TIMEZONE || 'UTC';

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
      activeConnections: status.activeConnections,
      lastActivity: status.lastActivity,
      endpointId: status.endpointId,
      subnetId: status.subnetId
    });
    
    logger.audit('VPN status check', 'vpn_status', 'success', {
      associated: status.associated,
      activeConnections: status.activeConnections,
      lastActivity: status.lastActivity,
      endpointId: status.endpointId
    });

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

    // Check if there are active connections
    if (status.activeConnections > 0) {
      logger.info('VPN has active connections, not idle', {
        activeConnections: status.activeConnections,
        action: 'maintaining_activity'
      });
      
      // Update last activity since there are active connections
      await vpnManager.updateLastActivity();
      
      // Reset cooldown if VPN is actively being used
      await clearCooldownTimestamp();
      return;
    }

    // Check if auto-close schedule is enabled (Requirements: 6.1, 6.2, 6.3)
    const isAutoCloseScheduleEnabled = await scheduleManager.isAutoCloseEnabled(ENVIRONMENT);
    if (!isAutoCloseScheduleEnabled) {
      logger.info('Auto-close schedule is disabled, skipping idle check', {
        environment: ENVIRONMENT,
        reason: 'schedule_disabled'
      });
      
      // Send notification about skipped operation
      const environmentEmoji = ENVIRONMENT === 'production' ? '🚀' : '🔧';
      const environmentName = ENVIRONMENT === 'production' ? 'Production' : 'Staging';
      
      await slack.sendSlackNotification({
        text: "📅 Auto-Close Schedule Disabled | 自動關閉排程已停用",
        attachments: [{
          color: "#ffaa00",
          fields: [
            {
              title: `${environmentEmoji} Environment | 環境`,
              value: environmentName,
              short: true
            },
            {
              title: "🔒 Status | 狀態",
              value: "Auto-close disabled | 自動關閉已停用",
              short: true
            },
            {
              title: "📝 Note | 注意",
              value: "Idle monitoring skipped due to schedule settings | 因排程設定跳過閒置監控",
              short: false
            },
            {
              title: "🔧 Re-enable | 重新啟用",
              value: `/vpn schedule on ${ENVIRONMENT}`,
              short: false
            }
          ]
        }]
      });
      
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
      const environmentEmoji = ENVIRONMENT === 'production' ? '🚀' : '🔧';
      const environmentName = ENVIRONMENT === 'production' ? 'Production' : 'Staging';
      
      await slack.sendSlackNotification({
        text: "🛑 Administrative Override Active | 管理員覆蓋已啟用",
        attachments: [{
          color: "warning",
          fields: [
            {
              title: `${environmentEmoji} Environment | 環境`,
              value: environmentName,
              short: true
            },
            {
              title: "🚫 Status | 狀態",
              value: "Auto-disassociation disabled | 自動斷開已停用",
              short: true
            },
            {
              title: "🔧 To Re-enable | 重新啟用",
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
      
      // Enhanced business hours notification with cost impact
      const costProjection = await calculateCostSavings(idleTimeMinutes);
      const environmentEmoji = ENVIRONMENT === 'production' ? '🚀' : '🔧';
      const environmentName = ENVIRONMENT === 'production' ? 'Production' : 'Staging';
      const currentTime = new Date().toLocaleTimeString();
      
      await slack.sendSlackNotification({
        text: "⏰ Business Hours Protection | 營業時間保護",
        attachments: [{
          color: "good",
          fields: [
            {
              title: `${environmentEmoji} Environment | 環境`,
              value: environmentName,
              short: true
            },
            {
              title: "🕒 Current Time | 目前時間",
              value: `${currentTime} (${BUSINESS_HOURS_TIMEZONE})`,
              short: true
            },
            {
              title: "⏱️ Idle Duration | 閒置時間",
              value: `${idleTimeMinutes} minutes | 分鐘\n_threshold: ${IDLE_MINUTES}min | 閾值: ${IDLE_MINUTES}分鐘_`,
              short: true
            },
            {
              title: "💰 Waste Being Accumulated | 正在累積浪費",
              value: `$${costProjection.hourly}/hour | 每小時\n_Would save ~$${costProjection.total} if closed now | 如現在關閉可節省約$${costProjection.total}_`,
              short: true
            },
            {
              title: "🛡️ Protection Status | 保護狀態",
              value: "Auto-close disabled | 自動關閉已停用",
              short: true
            },
            {
              title: "📝 Note | 注意",
              value: `Auto-close at 5 PM or manual: \`/vpn close ${ENVIRONMENT}\` | 5PM自動關閉或手動操作`,
              short: false
            }
          ]
        }]
      });
      
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
      const environmentEmoji = ENVIRONMENT === 'production' ? '🚀' : '🔧';
      const environmentName = ENVIRONMENT === 'production' ? 'Production' : 'Staging';
      
      await slack.sendSlackNotification({
        text: "⏳ Cooldown Protection Active | 冷卻保護啟用中",
        attachments: [{
          color: "#ffaa00",
          fields: [
            {
              title: `${environmentEmoji} Environment | 環境`,
              value: environmentName,
              short: true
            },
            {
              title: "⏱️ Time Remaining | 剩餘時間",
              value: `${Math.ceil(remainingCooldown)} minutes | 分鐘`,
              short: true
            },
            {
              title: "🔄 Purpose | 目的",
              value: "Prevents rapid cycling | 防止快速循環",
              short: true
            },
            {
              title: "📈 Current Idle | 目前閒置",
              value: `${idleTimeMinutes} minutes | 分鐘`,
              short: true
            },
            {
              title: "💡 Manual Override | 手動覆蓋",
              value: `/vpn close ${ENVIRONMENT} for immediate shutdown | 立即關閉`,
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
      const environmentEmoji = ENVIRONMENT === 'production' ? '🚀' : '🔧';
      const environmentName = ENVIRONMENT === 'production' ? 'Production' : 'Staging';
      
      // Create bilingual message with beautiful formatting using attachments
      await slack.sendSlackNotification({
        text: "💰 Auto VPN Cost Optimization | 自動 VPN 成本優化",
        attachments: [{
          color: "good",
          fields: [
            {
              title: `${environmentEmoji} Environment | 環境`,
              value: environmentName,
              short: true
            },
            {
              title: "📊 Idle Duration | 閒置時間",
              value: `${idleTimeMinutes} minutes | 分鐘\n_threshold: ${IDLE_MINUTES}min | 閾值: ${IDLE_MINUTES}分鐘_`,
              short: true
            },
            {
              title: "💵 Waste Prevented | 避免浪費",
              value: `~$${costSavings.total} saved | 節省\n_${costSavings.details.wasteTimePrevented}h of 24/7 waste prevented | 避免${costSavings.details.wasteTimePrevented}小時全天候浪費_`,
              short: true
            },
            {
              title: "🔧 Action Taken | 執行動作",
              value: "Subnets auto-disassociated | 子網路已自動取消關聯",
              short: true
            },
            {
              title: "📱 Re-enable | 重新啟用",
              value: `/vpn open ${ENVIRONMENT}`,
              short: true
            },
            {
              title: "⏰ Cooldown Period | 冷卻期",
              value: `${COOLDOWN_MINUTES} minutes | 分鐘\n_prevents rapid cycling | 防止快速循環_`,
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
  const now = new Date();

  // If timezone is specified and not UTC, adjust for it
  let hour: number;
  let minute: number;
  let dayOfWeek: number;

  if (BUSINESS_HOURS_TIMEZONE === 'UTC') {
    hour = now.getUTCHours();
    minute = now.getUTCMinutes();
    dayOfWeek = now.getUTCDay();
  } else {
    // For simplicity, support common timezones with offset
    const timezoneOffsets: { [key: string]: number } = {
      'EST': -5, 'EDT': -4,  // US Eastern
      'PST': -8, 'PDT': -7,  // US Pacific
      'CST': -6, 'CDT': -5,  // US Central
      'MST': -7, 'MDT': -6,  // US Mountain
      'GMT': 0, 'UTC': 0,    // GMT/UTC
      'Asia/Taipei': 8,      // Taiwan Standard Time (UTC+8)
      'TST': 8, 'Taiwan': 8  // Alternative Taiwan timezone names
    };

    const offset = timezoneOffsets[BUSINESS_HOURS_TIMEZONE] || 0;
    const adjustedTime = new Date(now.getTime() + (offset * 60 * 60 * 1000));
    hour = adjustedTime.getUTCHours();
    minute = adjustedTime.getUTCMinutes();
    dayOfWeek = adjustedTime.getUTCDay();
  }

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
    const isRecent = timeSinceManualActivity < manualActivityGracePeriod;
    
    if (isRecent) {
      console.log(`Recent manual activity detected: ${timeSinceManualActivity.toFixed(1)} minutes ago`);
      
      // Enhanced manual activity notification
      const environmentEmoji = ENVIRONMENT === 'production' ? '🚀' : '🔧';
      const environmentName = ENVIRONMENT === 'production' ? 'Production' : 'Staging';
      
      await slack.sendSlackNotification({
        text: "👤 Manual Activity Detected | 檢測到手動活動",
        attachments: [{
          color: "#36a64f",
          fields: [
            {
              title: `${environmentEmoji} Environment | 環境`,
              value: environmentName,
              short: true
            },
            {
              title: "🕰️ Last Activity | 最後活動",
              value: `${timeSinceManualActivity.toFixed(1)} minutes ago | 分鐘前`,
              short: true
            },
            {
              title: "⏱️ Grace Period | 寬限期",
              value: `${manualActivityGracePeriod} minutes | 分鐘`,
              short: true
            },
            {
              title: "🔒 Protection Status | 保護狀態",
              value: "Auto-close temporarily disabled | 自動關閉暫時停用",
              short: true
            },
            {
              title: "📝 Note | 注意",
              value: "Auto-monitoring will resume after grace period | 寬限期後將恢復自動監控",
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
    const overrideParam = await stateStore.readParameter(`/vpn/automation/admin_override/${ENVIRONMENT}`);
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
          await stateStore.writeParameter(`/vpn/automation/admin_override/${ENVIRONMENT}`, '');
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