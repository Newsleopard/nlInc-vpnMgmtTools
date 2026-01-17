import * as crypto from 'crypto';
import { SlackCommand, VpnCommandRequest, VpnCommandResponse, ScheduleStatusData, VpnConnectionDetail } from './types';
import * as stateStore from './stateStore';

// Helper function to format bytes into human-readable format
function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  const value = bytes / Math.pow(k, i);
  return `${value.toFixed(value >= 100 ? 0 : value >= 10 ? 1 : 2)} ${sizes[i]}`;
}

// Helper function to format connection duration
// Handles both Date objects and ISO string representations
function formatDuration(establishedTime: Date | string): string {
  const now = new Date();
  // Handle both Date objects and ISO strings (from JSON serialization)
  const established = establishedTime instanceof Date
    ? establishedTime
    : new Date(establishedTime);

  // Validate the date is valid
  if (isNaN(established.getTime())) {
    return 'unknown';
  }

  const diffMs = now.getTime() - established.getTime();
  const diffMinutes = Math.floor(diffMs / (1000 * 60));

  if (diffMinutes < 0) {
    return '0m'; // Future date protection
  }
  if (diffMinutes < 60) {
    return `${diffMinutes}m`;
  }
  const hours = Math.floor(diffMinutes / 60);
  const minutes = diffMinutes % 60;
  return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
}

// Verify Slack request signature for security
export function verifySlackSignature(
  body: string,
  signature: string,
  timestamp: string,
  signingSecret: string
): boolean {
  try {
    // Check timestamp to prevent replay attacks (5 minutes tolerance)
    const currentTime = Math.floor(Date.now() / 1000);
    const requestTime = parseInt(timestamp);
    
    if (Math.abs(currentTime - requestTime) > 300) {
      console.error('Request timestamp is too old');
      return false;
    }
    
    // Create signature base string
    const baseString = `v0:${timestamp}:${body}`;
    
    // Calculate expected signature
    const expectedSignature = 'v0=' + crypto
      .createHmac('sha256', signingSecret)
      .update(baseString)
      .digest('hex');
    
    // Security: Only log verification result, never expose signature values
    // Compare signatures using timing-safe comparison
    return crypto.timingSafeEqual(
      Buffer.from(signature),
      Buffer.from(expectedSignature)
    );
    
  } catch (error) {
    console.error('Failed to verify Slack signature:', error);
    return false;
  }
}

// Parse Slack slash command into VPN command request
export function parseSlackCommand(slackCommand: SlackCommand): VpnCommandRequest {
  const text = slackCommand.text.trim();
  
  // Handle help commands
  if (!text || text === 'help' || text === '--help' || text === '-h') {
    return {
      action: 'help' as any,
      environment: 'staging' as any, // Default environment for help
      user: slackCommand.user_name,
      requestId: generateRequestId(),
      helpMessage: getHelpMessage()
    };
  }
  
  const parts = text.split(/\s+/);
  
  // Handle schedule commands (Requirements: 1.1, 2.1, 2.2, 3.1, 4.1, 4.2, 4.3, 4.4)
  if (parts[0].toLowerCase() === 'schedule') {
    return parseScheduleCommand(slackCommand, parts);
  }
  
  // Handle administrative commands for Epic 3.2
  if (parts[0].toLowerCase() === 'admin' && parts.length >= 3) {
    return parseAdminCommand(slackCommand, parts);
  }
  
  // Handle cost and savings commands
  if (parts[0].toLowerCase() === 'savings' || parts[0].toLowerCase() === 'costs') {
    return parseCostCommand(slackCommand, parts);
  }
  
  if (parts.length < 2) {
    throw new Error('Invalid command format. Usage: /vpn <action> <environment>\n\n' + getHelpMessage());
  }
  
  let action = parts[0].toLowerCase();
  let environment = parts[1].toLowerCase();
  
  // Support action aliases
  if (action === 'start' || action === 'enable' || action === 'on') {
    action = 'open';
  } else if (action === 'stop' || action === 'disable' || action === 'off') {
    action = 'close';
  } else if (action === 'status' || action === 'state' || action === 'info') {
    action = 'check';
  }
  
  // Support environment aliases
  if (environment === 'prod' || environment === 'production-env') {
    environment = 'production';
  } else if (environment === 'stage' || environment === 'staging-env' || environment === 'dev') {
    environment = 'staging';
  }
  
  // Validate action (expanded for Epic 3.2)
  if (!['open', 'close', 'check', 'admin', 'savings', 'costs', 'help'].includes(action)) {
    throw new Error(`Invalid action "${parts[0]}". Must be: open, close, check, admin, savings, costs, schedule, or help\n\n` + getHelpMessage());
  }
  
  // Validate environment
  if (!['staging', 'production'].includes(environment)) {
    throw new Error(`Invalid environment "${parts[1]}". Must be: staging or production\n\n` + getHelpMessage());
  }
  
  // Validate permissions for production
  if (environment === 'production' && !isAuthorizedForProduction(slackCommand.user_name)) {
    throw new Error(`❌ Access denied: User "${slackCommand.user_name}" is not authorized for production VPN operations.\n\nContact your administrator to request production access.`);
  }
  
  return {
    action: action as 'open' | 'close' | 'check',
    environment: environment as 'staging' | 'production',
    user: slackCommand.user_name,
    requestId: generateRequestId()
  };
}

// Get help message for VPN commands
function getHelpMessage(): string {
  const helpResponse = {
    response_type: 'ephemeral',
    text: '📚 VPN Automation Help',
    attachments: [
      {
        color: 'good',
        title: '🚀 Basic Usage',
        text: '`/vpn <action> <environment>`',
        fields: [
          {
            title: '📋 Core Actions',
            value: '• `open` (aliases: start, enable, on) - Associate VPN subnets\n• `close` (aliases: stop, disable, off) - Disassociate VPN subnets\n• `check` (aliases: status, state, info) - Check VPN status',
            short: false
          }
        ]
      },
      {
        color: '#17a2b8',
        title: '📅 Schedule Management',
        fields: [
          {
            title: 'Schedule Commands',
            value: '• `/vpn schedule on <env>` - Enable auto-scheduling\n• `/vpn schedule off <env> [duration]` - Disable scheduling\n• `/vpn schedule check <env>` - Check schedule status\n• `/vpn schedule help` - Detailed schedule help',
            short: false
          }
        ]
      },
      {
        color: '#ffaa00',
        title: '💰 Cost Optimization Commands',
        fields: [
          {
            title: 'Cost Reports',
            value: '• `/vpn savings <environment>` - Show cost savings report\n• `/vpn costs daily` - Show daily cost analysis\n• `/vpn costs cumulative` - Show total savings',
            short: false
          }
        ]
      },
      {
        color: 'danger',
        title: '⚙️ Administrative Controls',
        fields: [
          {
            title: 'Admin Commands',
            value: '• `/vpn admin noclose <env>` - Disable auto-close (24h)\n• `/vpn admin autoclose <env>` - Re-enable auto-close\n• `/vpn admin cooldown <env>` - Check cooldown status\n• `/vpn admin force-close <env>` - Bypass safety mechanisms',
            short: false
          }
        ]
      },
      {
        color: '#36a64f',
        title: '🌍 Environments',
        fields: [
          {
            title: 'Available Environments',
            value: '• `staging` (aliases: stage, dev) - Staging environment 🔧\n• `production` (aliases: prod) - Production environment 🚀',
            short: true
          },
          {
            title: '📝 Examples',
            value: '• `/vpn open staging` - Open staging VPN\n• `/vpn schedule check production` - Check production schedule\n• `/vpn admin noclose staging` - Disable auto-close for 24h\n• `/vpn costs daily` - Daily cost breakdown',
            short: true
          }
        ]
      },
      {
        color: '#764FA5',
        title: '🤖 Auto-Cost Optimization',
        text: '• 🌅 Auto-open weekdays 10:00 AM Taiwan time\n• 🌙 Weekend soft-close Friday 8:00 PM\n  ↳ Respects active connections (retries every 30 min)\n• Business hours protection (10:00 AM - 5:00 PM)\n• Client auto-disconnects after 100 min idle\n• 30-minute cooldown prevents rapid cycling',
        footer: 'VPN Automation System'
      }
    ]
  };
  
  return JSON.stringify(helpResponse);
}

/**
 * Get detailed help message for schedule commands
 * 
 * Requirements: 7.2, 7.3, 7.4
 */
export function getScheduleHelpMessage(): string {
  const helpResponse = {
    response_type: 'ephemeral',
    text: '📅 VPN Schedule Management Help',
    attachments: [
      {
        color: 'good',
        title: '🔄 Basic Schedule Commands',
        fields: [
          {
            title: 'Enable All Schedules',
            value: '`/vpn schedule on <environment>`\nEnable both auto-open and auto-close',
            short: false
          },
          {
            title: 'Disable All Schedules',
            value: '`/vpn schedule off <environment> [duration]`\nDisable both schedules, optionally for a duration',
            short: false
          },
          {
            title: 'Check Schedule Status',
            value: '`/vpn schedule check <environment>`\nView current schedule configuration',
            short: false
          }
        ]
      },
      {
        color: '#ffaa00',
        title: '🎯 Granular Schedule Control',
        fields: [
          {
            title: 'Auto-Open Control',
            value: '`/vpn schedule open on <env>` - Enable auto-open\n`/vpn schedule open off <env>` - Disable auto-open',
            short: false
          },
          {
            title: 'Auto-Close Control',
            value: '`/vpn schedule close on <env>` - Enable auto-close\n`/vpn schedule close off <env>` - Disable auto-close',
            short: false
          }
        ]
      },
      {
        color: '#36a64f',
        title: '⏱️ Duration Format',
        fields: [
          {
            title: 'Supported Formats',
            value: '• `Nm` - Minutes (e.g., 30m)\n• `Nh` - Hours (e.g., 2h, 24h)\n• `Nd` - Days (e.g., 7d)',
            short: true
          },
          {
            title: 'Examples',
            value: '• `/vpn schedule off staging 2h`\n• `/vpn schedule close off prod 24h`\n• `/vpn schedule off production 7d`',
            short: true
          }
        ]
      },
      {
        color: '#764FA5',
        title: '📋 Schedule Configuration',
        text: '• 🌅 Auto-open: Weekdays 10:00 AM\n• 🌙 Weekend soft-close: Friday 8:00 PM\n  ↳ Respects active connections\n  ↳ Retries every 30 min\n• 🛡️ Business hours: 10:00 AM - 5:00 PM\n• ⏱️ Client idle: 100 minutes',
        footer: 'VPN Schedule Management'
      }
    ]
  };
  
  return JSON.stringify(helpResponse);
}

/**
 * Format schedule command response for Slack
 * 
 * Requirements: 1.3, 2.5, 3.2, 3.3, 3.4, 3.5, 3.6
 * 
 * @param response - VPN command response
 * @param command - Original VPN command request
 * @param statusData - Optional schedule status data for check commands
 * @returns Formatted Slack response object
 */
export function formatScheduleResponse(
  response: VpnCommandResponse,
  command: VpnCommandRequest,
  statusData?: ScheduleStatusData
): any {
  const environmentEmoji = command.environment === 'production' ? '🚀' : '🔧';
  const environmentName = command.environment.charAt(0).toUpperCase() + command.environment.slice(1);
  const environmentNameChinese = command.environment === 'production' ? '正式環境' : '測試環境';
  
  // Handle errors
  if (!response.success) {
    return {
      response_type: 'ephemeral',
      text: `❌ Schedule command failed`,
      attachments: [{
        color: 'danger',
        fields: [
          {
            title: 'Error',
            value: response.error || 'Unknown error occurred',
            short: false
          },
          {
            title: 'Usage',
            value: '`/vpn schedule <on|off|check> <environment>`',
            short: false
          }
        ]
      }]
    };
  }
  
  // Handle different schedule command types
  switch (command.action) {
    case 'schedule-on':
      return formatScheduleEnableResponse(command, environmentEmoji, environmentName, environmentNameChinese);
    
    case 'schedule-off':
      return formatScheduleDisableResponse(command, environmentEmoji, environmentName, environmentNameChinese);
    
    case 'schedule-check':
      return formatScheduleStatusResponse(command, statusData, environmentEmoji, environmentName, environmentNameChinese);
    
    case 'schedule-open-on':
    case 'schedule-open-off':
      return formatGranularScheduleResponse(command, 'auto-open', environmentEmoji, environmentName, environmentNameChinese);
    
    case 'schedule-close-on':
    case 'schedule-close-off':
      return formatGranularScheduleResponse(command, 'auto-close', environmentEmoji, environmentName, environmentNameChinese);
    
    case 'schedule-help':
      return JSON.parse(getScheduleHelpMessage());
    
    default:
      return {
        response_type: 'ephemeral',
        text: `✅ ${response.message}`,
        attachments: [{
          color: 'good',
          fields: [{
            title: 'Response',
            value: response.message,
            short: false
          }]
        }]
      };
  }
}

/**
 * Format enable schedule response
 */
function formatScheduleEnableResponse(
  command: VpnCommandRequest,
  environmentEmoji: string,
  environmentName: string,
  environmentNameChinese: string
): any {
  return {
    response_type: 'in_channel',
    text: `✅ Schedule Enabled`,
    attachments: [{
      color: 'good',
      fields: [
        {
          title: `${environmentEmoji} Environment`,
          value: environmentName,
          short: true
        },
        {
          title: '📅 Status',
          value: 'All schedules enabled',
          short: true
        },
        {
          title: '🔄 Auto-Open',
          value: '✅ Enabled',
          short: true
        },
        {
          title: '🔒 Auto-Close',
          value: '✅ Enabled',
          short: true
        },
        {
          title: '👤 Modified By',
          value: command.user,
          short: true
        },
        {
          title: '🕐 Time',
          value: new Date().toLocaleString('zh-TW', { timeZone: 'Asia/Taipei' }),
          short: true
        }
      ],
      footer: 'VPN Schedule Management'
    }]
  };
}

/**
 * Format disable schedule response
 */
function formatScheduleDisableResponse(
  command: VpnCommandRequest,
  environmentEmoji: string,
  environmentName: string,
  environmentNameChinese: string
): any {
  const fields: any[] = [
    {
      title: `${environmentEmoji} Environment`,
      value: environmentName,
      short: true
    },
    {
      title: '📅 Status',
      value: 'All schedules disabled',
      short: true
    },
    {
      title: '🔄 Auto-Open',
      value: '❌ Disabled',
      short: true
    },
    {
      title: '🔒 Auto-Close',
      value: '❌ Disabled',
      short: true
    }
  ];

  // Add duration info if provided
  if (command.duration) {
    fields.push({
      title: '⏱️ Duration',
      value: command.duration,
      short: true
    });
    fields.push({
      title: '🔔 Auto Re-enable',
      value: 'Yes, after duration expires',
      short: true
    });
  } else {
    fields.push({
      title: '⏱️ Duration',
      value: 'Indefinite',
      short: true
    });
    fields.push({
      title: '🔔 Auto Re-enable',
      value: 'No, manual re-enable required',
      short: true
    });
  }

  fields.push({
    title: '👤 Modified By',
    value: command.user,
    short: true
  });

  fields.push({
    title: '🕐 Time',
    value: new Date().toLocaleString('zh-TW', { timeZone: 'Asia/Taipei' }),
    short: true
  });

  return {
    response_type: 'in_channel',
    text: `⏸️ Schedule Disabled`,
    attachments: [{
      color: 'warning',
      fields,
      footer: 'VPN Schedule Management'
    }]
  };
}

/**
 * Format schedule status check response
 * 
 * Requirements: 3.2, 3.3, 3.4, 3.5
 */
function formatScheduleStatusResponse(
  command: VpnCommandRequest,
  statusData: ScheduleStatusData | undefined,
  environmentEmoji: string,
  environmentName: string,
  environmentNameChinese: string
): any {
  if (!statusData) {
    return {
      response_type: 'ephemeral',
      text: `❌ Failed to retrieve schedule status`,
      attachments: [{
        color: 'danger',
        fields: [{
          title: 'Error',
          value: 'Schedule status data not available',
          short: false
        }]
      }]
    };
  }

  const autoOpenStatus = statusData.autoOpen.enabled ? '✅ Enabled' : '❌ Disabled';
  const autoCloseStatus = statusData.autoClose.enabled ? '✅ Enabled' : '❌ Disabled';

  const fields: any[] = [
    {
      title: `${environmentEmoji} Environment`,
      value: environmentName,
      short: true
    },
    {
      title: '🔄 Auto-Open',
      value: autoOpenStatus,
      short: true
    }
  ];

  // Add next scheduled time if auto-open is enabled
  if (statusData.autoOpen.enabled && statusData.autoOpen.nextScheduledTime) {
    const nextTime = new Date(statusData.autoOpen.nextScheduledTime);
    fields.push({
      title: '📅 Next Open',
      value: nextTime.toLocaleString('zh-TW', { timeZone: 'Asia/Taipei' }),
      short: true
    });
  }

  // Add disabled until time if auto-open is disabled with expiration
  if (!statusData.autoOpen.enabled && statusData.autoOpen.disabledUntil) {
    fields.push({
      title: '⏱️ Auto-Open Re-enables In',
      value: statusData.autoOpen.disabledUntil,
      short: true
    });
  }

  fields.push({
    title: '🔒 Auto-Close',
    value: autoCloseStatus,
    short: true
  });

  fields.push({
    title: '⏰ Idle Timeout',
    value: `${statusData.autoClose.idleTimeoutMinutes} minutes`,
    short: true
  });

  // Add disabled until time if auto-close is disabled with expiration
  if (!statusData.autoClose.enabled && statusData.autoClose.disabledUntil) {
    fields.push({
      title: '⏱️ Auto-Close Re-enables In',
      value: statusData.autoClose.disabledUntil,
      short: true
    });
  }

  // Business hours protection
  fields.push({
    title: '🛡️ Business Hours Protection',
    value: statusData.businessHoursProtection.enabled
      ? `✅ ${statusData.businessHoursProtection.start} - ${statusData.businessHoursProtection.end} (${statusData.businessHoursProtection.timezone})`
      : '❌ Disabled',
    short: false
  });

  // Last modified info
  fields.push({
    title: '👤 Last Modified By',
    value: statusData.modifiedBy,
    short: true
  });

  fields.push({
    title: '🕐 Last Modified',
    value: new Date(statusData.lastModified).toLocaleString('zh-TW', { timeZone: 'Asia/Taipei' }),
    short: true
  });

  return {
    response_type: 'ephemeral',
    text: `📊 Schedule Status`,
    attachments: [{
      color: 'good',
      fields,
      footer: 'VPN Schedule Management'
    }]
  };
}

/**
 * Format granular schedule command response (open/close on/off)
 */
function formatGranularScheduleResponse(
  command: VpnCommandRequest,
  scheduleType: string,
  environmentEmoji: string,
  environmentName: string,
  environmentNameChinese: string
): any {
  const isEnable = command.action.endsWith('-on');
  const scheduleTypeName = scheduleType === 'auto-open' ? 'Auto-Open' : 'Auto-Close';
  const statusEmoji = isEnable ? '✅' : '❌';
  const statusText = isEnable ? 'Enabled' : 'Disabled';

  const fields: any[] = [
    {
      title: `${environmentEmoji} Environment`,
      value: environmentName,
      short: true
    },
    {
      title: `🎯 Schedule Type`,
      value: scheduleTypeName,
      short: true
    },
    {
      title: '📅 Status',
      value: `${statusEmoji} ${statusText}`,
      short: true
    }
  ];

  // Add duration info if disabling with duration
  if (!isEnable && command.duration) {
    fields.push({
      title: '⏱️ Duration',
      value: command.duration,
      short: true
    });
  }

  fields.push({
    title: '👤 Modified By',
    value: command.user,
    short: true
  });

  fields.push({
    title: '🕐 Time',
    value: new Date().toLocaleString('zh-TW', { timeZone: 'Asia/Taipei' }),
    short: true
  });

  const headerText = isEnable
    ? `✅ ${scheduleTypeName} Enabled`
    : `⏸️ ${scheduleTypeName} Disabled`;

  return {
    response_type: 'in_channel',
    text: headerText,
    attachments: [{
      color: isEnable ? 'good' : 'warning',
      fields,
      footer: 'VPN Schedule Management'
    }]
  };
}

// Check if user is authorized for production operations
export function isAuthorizedForProduction(username: string): boolean {
  // This could be enhanced to check against Parameter Store or external auth service
  const authorizedUsers = (process.env.PRODUCTION_AUTHORIZED_USERS || '').split(',');
  return authorizedUsers.includes(username) || authorizedUsers.includes('*');
}

// Generate unique request ID for tracking
export function generateRequestId(): string {
  return `vpn-${Date.now()}-${Math.random().toString(36).substring(2, 11)}`;
}

// Parse administrative commands for Epic 3.2
function parseAdminCommand(slackCommand: SlackCommand, parts: string[]): VpnCommandRequest {
  const adminAction = parts[1].toLowerCase();
  let environment = parts[2]?.toLowerCase();
  
  // Validate admin permissions
  if (!isAuthorizedForAdmin(slackCommand.user_name)) {
    throw new Error(`❌ Access denied: User "${slackCommand.user_name}" is not authorized for administrative commands.\n\nContact your system administrator.`);
  }
  
  // Support environment aliases for admin commands
  if (environment === 'prod' || environment === 'production-env') {
    environment = 'production';
  } else if (environment === 'stage' || environment === 'staging-env' || environment === 'dev') {
    environment = 'staging';
  }
  
  // Validate environment for admin commands
  if (!['staging', 'production'].includes(environment)) {
    throw new Error(`Invalid environment "${environment}". Must be: staging or production`);
  }
  
  // Map admin actions to standard format
  const adminActionMap: { [key: string]: string } = {
    'noclose': 'admin-noclose',
    'autoclose': 'admin-autoclose',
    // Legacy commands for backward compatibility
    'override': 'admin-noclose',
    'clear-override': 'admin-autoclose',
    'cooldown': 'admin-cooldown',
    'force-close': 'admin-force-close'
  };
  
  const mappedAction = adminActionMap[adminAction];
  if (!mappedAction) {
    throw new Error(`Invalid admin action "${adminAction}". Must be: noclose, autoclose, cooldown, or force-close`);
  }
  
  return {
    action: mappedAction as any,
    environment: environment as 'staging' | 'production',
    user: slackCommand.user_name,
    requestId: generateRequestId()
  };
}

// Parse cost analysis commands for Epic 3.2
function parseCostCommand(slackCommand: SlackCommand, parts: string[]): VpnCommandRequest {
  const costAction = parts[0].toLowerCase();
  const reportType = parts[1]?.toLowerCase() || 'summary';
  
  // Map cost actions to standard format
  const costActionMap: { [key: string]: string } = {
    'savings': 'cost-savings',
    'costs': 'cost-analysis'
  };
  
  const mappedAction = costActionMap[costAction];
  
  return {
    action: mappedAction as any,
    environment: reportType as any, // Using environment field for report type
    user: slackCommand.user_name,
    requestId: generateRequestId()
  };
}

/**
 * Parse schedule commands for auto-schedule management
 * 
 * Supported formats:
 * - /vpn schedule on <environment>
 * - /vpn schedule off <environment> [duration]
 * - /vpn schedule check <environment>
 * - /vpn schedule open on|off <environment>
 * - /vpn schedule close on|off <environment>
 * - /vpn schedule help
 * 
 * Requirements: 1.1, 2.1, 2.2, 3.1, 4.1, 4.2, 4.3, 4.4
 */
export function parseScheduleCommand(slackCommand: SlackCommand, parts: string[]): VpnCommandRequest {
  // parts[0] is 'schedule'
  const subCommand = parts[1]?.toLowerCase();
  
  // Handle schedule help
  if (!subCommand || subCommand === 'help' || subCommand === '--help' || subCommand === '-h') {
    return {
      action: 'schedule-help',
      environment: 'staging',
      user: slackCommand.user_name,
      requestId: generateRequestId(),
      helpMessage: getScheduleHelpMessage()
    };
  }
  
  // Handle granular schedule commands: /vpn schedule open|close on|off <environment>
  if (subCommand === 'open' || subCommand === 'close') {
    return parseGranularScheduleCommand(slackCommand, parts, subCommand);
  }
  
  // Handle basic schedule commands: /vpn schedule on|off|check <environment>
  if (['on', 'off', 'check'].includes(subCommand)) {
    return parseBasicScheduleCommand(slackCommand, parts, subCommand);
  }
  
  throw new Error(
    `Invalid schedule action "${subCommand}". Use: on, off, check, open, close, or help\n\n` +
    getScheduleHelpMessage()
  );
}

/**
 * Parse basic schedule commands: on, off, check
 */
function parseBasicScheduleCommand(
  slackCommand: SlackCommand, 
  parts: string[], 
  subCommand: string
): VpnCommandRequest {
  let environment = parts[2]?.toLowerCase();
  const duration = parts[3]; // Optional duration for 'off' command
  
  // Validate environment is provided
  if (!environment) {
    throw new Error(
      `Environment required. Usage: /vpn schedule ${subCommand} <environment>\n\n` +
      getScheduleHelpMessage()
    );
  }
  
  // Support environment aliases
  environment = normalizeEnvironment(environment);
  
  // Validate environment
  if (!['staging', 'production'].includes(environment)) {
    throw new Error(
      `Invalid environment "${parts[2]}". Must be: staging or production\n\n` +
      getScheduleHelpMessage()
    );
  }
  
  // Check authorization for schedule commands (Requirements: 1.4, 2.6)
  if (!isAuthorizedForSchedule(slackCommand.user_name, environment)) {
    throw new Error(
      `❌ Access denied: User "${slackCommand.user_name}" is not authorized for ${environment} schedule management.\n\n` +
      `Contact your administrator to request schedule management access.`
    );
  }
  
  // Validate duration format if provided for 'off' command
  if (subCommand === 'off' && duration) {
    if (!isValidDurationFormat(duration)) {
      throw new Error(
        `Invalid duration format "${duration}". Use: Nh (hours), Nd (days), Nm (minutes).\n` +
        `Examples: 2h, 24h, 7d, 30m`
      );
    }
  }
  
  // Map to action type
  const actionMap: { [key: string]: string } = {
    'on': 'schedule-on',
    'off': 'schedule-off',
    'check': 'schedule-check'
  };
  
  return {
    action: actionMap[subCommand] as any,
    environment: environment as 'staging' | 'production',
    user: slackCommand.user_name,
    requestId: generateRequestId(),
    duration: subCommand === 'off' ? duration : undefined
  };
}

/**
 * Parse granular schedule commands: open on/off, close on/off
 */
function parseGranularScheduleCommand(
  slackCommand: SlackCommand, 
  parts: string[], 
  scheduleType: string
): VpnCommandRequest {
  const onOff = parts[2]?.toLowerCase();
  let environment = parts[3]?.toLowerCase();
  const duration = parts[4]; // Optional duration for 'off' command
  
  // Validate on/off is provided
  if (!onOff || !['on', 'off'].includes(onOff)) {
    throw new Error(
      `Invalid command. Usage: /vpn schedule ${scheduleType} <on|off> <environment>\n\n` +
      getScheduleHelpMessage()
    );
  }
  
  // Validate environment is provided
  if (!environment) {
    throw new Error(
      `Environment required. Usage: /vpn schedule ${scheduleType} ${onOff} <environment>\n\n` +
      getScheduleHelpMessage()
    );
  }
  
  // Support environment aliases
  environment = normalizeEnvironment(environment);
  
  // Validate environment
  if (!['staging', 'production'].includes(environment)) {
    throw new Error(
      `Invalid environment "${parts[3]}". Must be: staging or production\n\n` +
      getScheduleHelpMessage()
    );
  }
  
  // Check authorization for schedule commands (Requirements: 1.4, 2.6)
  if (!isAuthorizedForSchedule(slackCommand.user_name, environment)) {
    throw new Error(
      `❌ Access denied: User "${slackCommand.user_name}" is not authorized for ${environment} schedule management.\n\n` +
      `Contact your administrator to request schedule management access.`
    );
  }
  
  // Validate duration format if provided for 'off' command
  if (onOff === 'off' && duration) {
    if (!isValidDurationFormat(duration)) {
      throw new Error(
        `Invalid duration format "${duration}". Use: Nh (hours), Nd (days), Nm (minutes).\n` +
        `Examples: 2h, 24h, 7d, 30m`
      );
    }
  }
  
  // Map to action type: schedule-open-on, schedule-open-off, schedule-close-on, schedule-close-off
  const action = `schedule-${scheduleType}-${onOff}`;
  
  return {
    action: action as any,
    environment: environment as 'staging' | 'production',
    user: slackCommand.user_name,
    requestId: generateRequestId(),
    duration: onOff === 'off' ? duration : undefined
  };
}

/**
 * Normalize environment aliases to standard names
 */
function normalizeEnvironment(environment: string): string {
  if (environment === 'prod' || environment === 'production-env') {
    return 'production';
  }
  if (environment === 'stage' || environment === 'staging-env' || environment === 'dev') {
    return 'staging';
  }
  return environment;
}

/**
 * Validate duration format
 * Valid formats: Nh (hours), Nd (days), Nm (minutes)
 * Examples: 2h, 24h, 7d, 30m
 */
function isValidDurationFormat(duration: string): boolean {
  if (!duration || typeof duration !== 'string') {
    return false;
  }
  const trimmed = duration.trim().toLowerCase();
  const match = trimmed.match(/^(\d+)([hdm])$/);
  if (!match) {
    return false;
  }
  const value = parseInt(match[1], 10);
  return value > 0 && !isNaN(value);
}

// Check if user is authorized for administrative commands
function isAuthorizedForAdmin(username: string): boolean {
  const adminUsers = (process.env.ADMIN_AUTHORIZED_USERS || '').split(',');
  return adminUsers.includes(username) || adminUsers.includes('*') || isAuthorizedForProduction(username);
}

/**
 * Check if user is authorized for schedule management commands
 *
 * Authorization rules (Requirements: 1.4, 2.6):
 * - Admin users: Full access to all environments
 * - Production: Only users explicitly in PRODUCTION_SCHEDULE_USERS or PRODUCTION_AUTHORIZED_USERS
 * - Staging: Only users explicitly in STAGING_SCHEDULE_USERS or with admin access
 *
 * Security: No automatic cross-environment privilege escalation
 * Security: Wildcard (*) is NOT supported for schedule commands
 *
 * @param username - Slack username
 * @param environment - Target environment
 * @returns true if authorized
 */
export function isAuthorizedForSchedule(username: string, environment: string): boolean {
  // Validate inputs to prevent injection
  if (!username || typeof username !== 'string' || username.length > 100) {
    console.warn('Invalid username provided for schedule authorization check');
    return false;
  }

  const sanitizedUsername = username.trim().toLowerCase();
  const sanitizedEnvironment = environment?.toLowerCase();

  if (!['staging', 'production'].includes(sanitizedEnvironment)) {
    console.warn('Invalid environment for schedule authorization', { environment });
    return false;
  }

  // Admin users have full access to all environments
  if (isAuthorizedForAdmin(sanitizedUsername)) {
    console.log('Schedule authorization granted', {
      username: sanitizedUsername,
      environment: sanitizedEnvironment,
      reason: 'admin_user'
    });
    return true;
  }

  // Environment-specific authorization (NO automatic cross-environment access)
  const envAuthKey = sanitizedEnvironment === 'production'
    ? 'PRODUCTION_SCHEDULE_USERS'
    : 'STAGING_SCHEDULE_USERS';

  const authorizedUsers = (process.env[envAuthKey] || '')
    .split(',')
    .map(u => u.trim().toLowerCase())
    .filter(u => u.length > 0 && u !== '*'); // Security: Reject wildcard

  // Check if user is in environment-specific list
  if (authorizedUsers.includes(sanitizedUsername)) {
    console.log('Schedule authorization granted', {
      username: sanitizedUsername,
      environment: sanitizedEnvironment,
      reason: 'environment_specific_user_list'
    });
    return true;
  }

  // For production, also check PRODUCTION_AUTHORIZED_USERS (VPN operation users)
  if (sanitizedEnvironment === 'production') {
    const prodAuthUsers = (process.env.PRODUCTION_AUTHORIZED_USERS || '')
      .split(',')
      .map(u => u.trim().toLowerCase())
      .filter(u => u.length > 0 && u !== '*'); // Security: Reject wildcard

    if (prodAuthUsers.includes(sanitizedUsername)) {
      console.log('Schedule authorization granted', {
        username: sanitizedUsername,
        environment: sanitizedEnvironment,
        reason: 'production_authorized_user'
      });
      return true;
    }
  }

  console.log('Schedule authorization denied', {
    username: sanitizedUsername,
    environment: sanitizedEnvironment,
    reason: 'not_in_authorized_list'
  });
  return false;
}

// Enhanced Slack response formatting for Epic 3.2 commands
function formatEnhancedSlackResponse(response: VpnCommandResponse, command: VpnCommandRequest): any {
  if (!response.success) {
    return {
      response_type: 'ephemeral',
      text: `❌ ${command.action} failed`,
      attachments: [{
        color: 'danger',
        fields: [{
          title: 'Error',
          value: response.error || 'Unknown error occurred',
          short: false
        }]
      }]
    };
  }
  
  // Format different command types
  switch (command.action) {
    case 'admin-noclose':
    case 'admin-autoclose':
    case 'admin-force-close':
      return {
        response_type: 'ephemeral',
        text: `✅ ${response.message}`,
        attachments: [{
          color: 'warning',
          fields: [{
            title: 'Administrative Action',
            value: `Command: \`${command.action}\`\nUser: ${command.user}\nTimestamp: ${new Date().toLocaleString()}`,
            short: false
          }]
        }]
      };
      
    case 'admin-cooldown':
      const cooldownData = response.data as any;
      return {
        response_type: 'ephemeral',
        text: `🕰️ Cooldown Status`,
        attachments: [{
          color: cooldownData.cooldownActive ? 'warning' : 'good',
          fields: [
            {
              title: 'Status',
              value: cooldownData.cooldownActive ? '⏳ Active' : '✅ Inactive',
              short: true
            },
            {
              title: 'Remaining Time',
              value: cooldownData.cooldownActive ? `${cooldownData.remainingMinutes} minutes` : 'N/A',
              short: true
            },
            {
              title: 'Details',
              value: response.message,
              short: false
            }
          ]
        }]
      };
      
    case 'cost-savings':
      const savingsData = response.data as any;
      return {
        response_type: 'in_channel',
        text: `💰 Waste Prevention Report - ${savingsData.environment}`,
        attachments: [{
          color: 'good',
          fields: [
            {
              title: 'Today\'s Waste Prevented',
              value: `$${savingsData.todaySavings}`,
              short: true
            },
            {
              title: 'Total Waste Prevented',
              value: `$${savingsData.cumulativeSavings}`,
              short: true
            },
            {
              title: 'Theoretical Daily Savings',
              value: `$${savingsData.theoreticalDailySavings || '0.00'}`,
              short: true
            },
            {
              title: 'Current Status',
              value: savingsData.currentStatus,
              short: true
            },
            {
              title: 'Hourly Waste Rate',
              value: `$${savingsData.potentialHourlySavings}/hour`,
              short: true
            },
            {
              title: 'Concept',
              value: 'Without auto-system: VPN runs 24/7\nWith auto-system: VPN closes when idle\nSavings = Prevented waste time',
              short: false
            }
          ],
          footer: `${savingsData.explanation} | ${new Date(savingsData.lastUpdated).toLocaleString()}`
        }]
      };
      
    case 'cost-analysis':
      const analysisData = response.data as any;
      if (analysisData.reportType === 'daily') {
        const dailyData = analysisData.data.slice(0, 5); // Show last 5 days
        const fields = dailyData.map((day: any) => ({
          title: day.date,
          value: `Staging: $${day.stagingSavings.toFixed(2)}\nProduction: $${day.productionSavings.toFixed(2)}\nTotal: $${day.totalSavings.toFixed(2)}`,
          short: true
        }));
        
        return {
          response_type: 'in_channel',
          text: `📊 Daily Cost Analysis (Last 5 Days)`,
          attachments: [{
            color: 'good',
            fields: fields
          }]
        };
      } else {
        const cumData = analysisData.data;
        return {
          response_type: 'in_channel',
          text: `📊 Cumulative Cost Analysis`,
          attachments: [{
            color: 'good',
            fields: [
              {
                title: 'Staging Total',
                value: `$${cumData.stagingTotal.toFixed(2)}`,
                short: true
              },
              {
                title: 'Production Total',
                value: `$${cumData.productionTotal.toFixed(2)}`,
                short: true
              },
              {
                title: 'Grand Total',
                value: `$${cumData.grandTotal.toFixed(2)}`,
                short: true
              },
              {
                title: 'Est. Monthly Rate',
                value: `$${cumData.estimatedMonthlySavings.toFixed(2)}`,
                short: true
              }
            ],
            footer: `Updated: ${new Date(cumData.lastUpdated).toLocaleString()}`
          }]
        };
      }
      
    default:
      return {
        response_type: 'ephemeral',
        text: `✅ ${response.message}`,
        attachments: [{
          color: 'good',
          fields: [{
            title: 'Response',
            value: response.message,
            short: false
          }]
        }]
      };
  }
}

// Enhanced format VPN command response for Slack (Epic 3.2)
export function formatSlackResponse(
  response: VpnCommandResponse,
  command: VpnCommandRequest
): any {
  // Handle Epic 3.2 administrative and cost commands
  if (command.action.startsWith('admin-') || command.action.startsWith('cost-')) {
    return formatEnhancedSlackResponse(response, command);
  }
  
  const environmentEmoji = command.environment === 'production' ? '🚀' : '🔧';
  const environmentName = command.environment.charAt(0).toUpperCase() + command.environment.slice(1);
  
  if (!response.success) {
    // Check if this is an intermediate state error
    const errorMessage = response.error || 'Unknown error occurred';
    const isIntermediateStateError = errorMessage.includes('currently associating') || 
                                   errorMessage.includes('currently disassociating');
    
    if (isIntermediateStateError) {
      // Special handling for intermediate state errors with bilingual support
      const isAssociating = errorMessage.includes('currently associating');
      const isDisassociating = errorMessage.includes('currently disassociating');
      const actionAttempted = command.action === 'open' ? 'open' : 'close';
      
      let statusText = '';
      let instructionText = '';
      
      if (isAssociating) {
        statusText = 'VPN subnets are currently associating';
        instructionText = actionAttempted === 'open' ?
          'Please wait for association to complete' :
          'Wait for association to finish, then try closing';
      } else if (isDisassociating) {
        statusText = 'VPN subnets are currently disassociating';
        instructionText = actionAttempted === 'close' ?
          'Please wait for disassociation to complete' :
          'Wait for disassociation to finish, then try opening';
      }

      return {
        response_type: 'ephemeral',
        text: `🟡 VPN Operation In Progress`,
        attachments: [{
          color: 'warning',
          fields: [
            {
              title: `${environmentEmoji} Environment`,
              value: environmentName,
              short: true
            },
            {
              title: '📊 Current Status',
              value: statusText,
              short: true
            },
            {
              title: '⏳ Action Required',
              value: instructionText,
              short: false
            },
            {
              title: '💡 Tip',
              value: `Use \`/vpn check ${command.environment}\` to monitor progress`,
              short: false
            }
          ],
          footer: 'VPN Automation System'
        }]
      };
    } else {
      // Regular error formatting for actual failures
      return {
        response_type: 'ephemeral',
        text: `❌ VPN ${command.action} failed for ${environmentEmoji} ${environmentName}`,
        attachments: [{
          color: 'danger',
          fields: [{
            title: 'Error',
            value: errorMessage,
            short: false
          }]
        }]
      };
    }
  }
  
  let statusEmoji = '⚪';
  let statusText = 'Unknown';
  
  if (command.action === 'check' && response.data) {
    // Handle different association states
    if (response.data.associationState) {
      switch (response.data.associationState) {
        case 'associated':
          statusEmoji = '🟢';
          statusText = 'Open';
          break;
        case 'associating':
          statusEmoji = '🟡';
          statusText = 'Associating...';
          break;
        case 'disassociating':
          statusEmoji = '🟡';
          statusText = 'Disassociating...';
          break;
        case 'disassociated':
          statusEmoji = '🔴';
          statusText = 'Closed';
          break;
        case 'failed':
          statusEmoji = '❌';
          statusText = 'Failed';
          break;
        default:
          statusEmoji = '⚪';
          statusText = 'Unknown';
      }
    } else {
      // Fallback to boolean check
      statusEmoji = response.data.associated ? '🟢' : '🔴';
      statusText = response.data.associated ? 'Open' : 'Closed';
    }
  } else if (command.action === 'open') {
    statusEmoji = '🟢';
    statusText = 'Opened';
  } else if (command.action === 'close') {
    statusEmoji = '🔴';
    statusText = 'Closed';
  }
  
  const fields: any[] = [{
    title: 'Status',
    value: `${statusEmoji} ${statusText}`,
    short: true
  }];
  
  if (response.data) {
    fields.push({
      title: 'Active Connections',
      value: response.data.activeConnections.toString(),
      short: true
    });

    // Add traffic status for check command
    if (command.action === 'check' && response.data.trafficSummary) {
      const traffic = response.data.trafficSummary;
      let trafficStatusText = '';
      let trafficEmoji = '⚪';

      if (traffic.status === 'active') {
        trafficEmoji = '🟢';
        const delta = traffic.ingressDelta + traffic.egressDelta;
        trafficStatusText = delta > 0
          ? `Active (+${formatBytes(delta)} recent)`
          : 'Active';
      } else if (traffic.status === 'idle') {
        trafficEmoji = '⚠️';
        trafficStatusText = traffic.idleMinutes
          ? `Idle (no traffic in ${traffic.idleMinutes}m)`
          : 'Idle';
      } else {
        trafficEmoji = '⚪';
        trafficStatusText = 'No connections';
      }

      fields.push({
        title: 'Traffic Status',
        value: `${trafficEmoji} ${trafficStatusText}`,
        short: true
      });

      // Show total traffic if there are connections
      if (response.data.activeConnections > 0) {
        fields.push({
          title: 'Total Traffic',
          value: `↓ ${formatBytes(traffic.totalEgressBytes)}  ↑ ${formatBytes(traffic.totalIngressBytes)}`,
          short: true
        });
      }
    }

    // Add per-user breakdown for check command with active connections
    if (command.action === 'check' && response.data.activeConnectionDetails && response.data.activeConnectionDetails.length > 0) {
      const connections = response.data.activeConnectionDetails;
      const userLines = connections.map((conn: VpnConnectionDetail) => {
        // formatDuration now handles both Date objects and ISO strings
        const duration = formatDuration(conn.establishedTime);
        const traffic = `↓ ${formatBytes(conn.egressBytes)}  ↑ ${formatBytes(conn.ingressBytes)}`;
        const statusTag = conn.trafficStatus === 'idle'
          ? `[Idle ${conn.idleMinutes || 0}m]`
          : '[Active]';
        return `• ${conn.username} (${conn.clientIp}) - ${duration}\n   ${traffic}  ${statusTag}`;
      }).join('\n');

      fields.push({
        title: 'Connected Users',
        value: userLines,
        short: false
      });
    }

    // Add association state details for intermediate states
    if (response.data.associationState &&
        ['associating', 'disassociating', 'failed'].includes(response.data.associationState)) {
      fields.push({
        title: 'Association State',
        value: response.data.associationState.charAt(0).toUpperCase() + response.data.associationState.slice(1),
        short: true
      });
    }

    if (response.data.lastActivity) {
      const lastActivity = new Date(response.data.lastActivity);
      const timeDiff = Date.now() - lastActivity.getTime();
      const minutesAgo = Math.floor(timeDiff / (1000 * 60));

      fields.push({
        title: 'Last Activity',
        value: minutesAgo < 1 ? 'Just now' : `${minutesAgo} minutes ago`,
        short: true
      });
    }
  }
  
  return {
    response_type: 'in_channel',
    text: `📶 VPN ${command.action} completed for ${environmentEmoji} ${environmentName}`,
    attachments: [{
      color: response.success ? 'good' : 'danger',
      fields: fields,
      footer: `Request ID: ${command.requestId}`,
      ts: Math.floor(Date.now() / 1000)
    }]
  };
}

// Send notification to Slack webhook
export async function sendSlackNotification(
  message: string | object
): Promise<void> {
  try {
    const webhookUrl = await stateStore.readSlackWebhook();
    
    const payload = typeof message === 'string' ? { text: message } : message;
    
    const response = await fetch(webhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });
    
    if (!response.ok) {
      throw new Error(`Slack webhook request failed: ${response.status} ${response.statusText}`);
    }
    
    console.log('Successfully sent Slack notification');
    
  } catch (error) {
    console.error('Failed to send Slack notification:', error);
    // Don't throw here as notification failure shouldn't break the main operation
  }
}

// Send alert to dedicated alerts channel
export async function sendSlackAlert(
  message: string,
  environment: string,
  severity: 'warning' | 'critical' = 'warning'
): Promise<void> {
  const emoji = severity === 'critical' ? '🚨' : '⚠️';
  const environmentEmoji = environment === 'production' ? '🚀' : '🔧';
  
  // Convert UTC time to Taiwan timezone (UTC+8) - use proper timezone conversion
  const formattedTime = new Date().toLocaleString('zh-TW', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    timeZone: 'Asia/Taipei'
  });
  
  // Make message more user-friendly
  const userFriendlyMessage = makeMessageUserFriendly(message);
  const environmentName = environment === 'production' ? 'Production' : 'Staging';
  const severityName = severity === 'critical' ? 'Critical' : 'Warning';

  await sendSlackNotification({
    text: `${emoji} VPN System Alert ${environmentEmoji}`,
    attachments: [{
      color: severity === 'critical' ? 'danger' : 'warning',
      fields: [
        {
          title: 'Environment',
          value: `${environmentName} (${environment})`,
          short: true
        },
        {
          title: 'Severity',
          value: severityName,
          short: true
        },
        {
          title: 'Message',
          value: userFriendlyMessage,
          short: false
        },
        {
          title: 'Time',
          value: `${formattedTime} (Asia/Taipei)`,
          short: true
        }
      ],
      footer: 'VPN System Alert',
      ts: Math.floor(Date.now() / 1000)
    }]
  });
}

/**
 * Convert technical error messages to user-friendly messages
 */
function makeMessageUserFriendly(message: string): string {
  const friendlyMessages: { [key: string]: string } = {
    'VPN Monitor: Parameter Store validation failed. Please check configuration.':
      '🔧 VPN monitoring system detected configuration parameter error. Please check system configuration.',

    'VPN endpoint validation failed':
      '🔗 VPN endpoint connection verification failed. Please check network status.',

    'Failed to send Slack notification':
      '📢 Slack notification failed. Please check Slack integration settings.',

    'Cross-account VPN operation failed':
      '🔄 Cross-account VPN operation failed. Please check cross-account permissions.',

    'VPN endpoint not configured':
      '⚙️ VPN endpoint not configured. Please complete VPN endpoint setup first.',

    'Unauthorized operation':
      '🔐 Permission denied. Please check AWS IAM permissions.',

    'Request validation failed':
      '📝 Request validation failed. Please check input parameters.',

    'VPN connection timeout':
      '⏱️ VPN connection timeout. Please check network status or try again later.',

    'Certificate validation failed':
      '📜 Certificate validation failed. Please check if VPN certificate is valid.'
  };
  
  // Check for exact matches first
  if (friendlyMessages[message]) {
    return friendlyMessages[message];
  }
  
  // Check for partial matches
  for (const [technical, friendly] of Object.entries(friendlyMessages)) {
    if (message.includes(technical) || technical.includes(message.split(':')[0])) {
      return friendly;
    }
  }
  
  // If no match found, return original message with some formatting
  return `🔍 ${message}`;
}