import * as crypto from 'crypto';
import { SlackCommand, VpnCommandRequest, VpnCommandResponse } from './types';
import * as stateStore from './stateStore';

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
    
    // Debug logging (remove in production)
    console.log('Slack signature verification:', {
      receivedSignature: signature,
      expectedSignature: expectedSignature,
      timestamp: timestamp,
      bodyLength: body.length,
      signingSecretLength: signingSecret.length,
      match: signature === expectedSignature,
      baseString: baseString.substring(0, 100) + '...',
      bodyPreview: body.substring(0, 100) + '...'
    });
    
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
    throw new Error(`Invalid action "${parts[0]}". Must be: open, close, check, admin, savings, costs, or help\n\n` + getHelpMessage());
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
            value: '• `/vpn open staging` - Open staging VPN\n• `/vpn savings production` - View production cost savings\n• `/vpn admin noclose staging` - Disable auto-close for 24h\n• `/vpn costs daily` - Daily cost breakdown',
            short: true
          }
        ]
      },
      {
        color: '#764FA5',
        title: '🤖 Auto-Cost Optimization',
        text: '• 🌅 Auto-open weekdays 9:30 AM Taiwan time\n• Client auto-disconnects after 100 minutes idle (traffic-based)\n• Business hours protection (9:30 AM - 5:30 PM) - no auto-close\n• After 5:30 PM: auto-close ~154 min after last activity\n• 30-minute cooldown prevents rapid cycling',
        footer: 'VPN Automation System'
      }
    ]
  };
  
  return JSON.stringify(helpResponse);
}

// Check if user is authorized for production operations
function isAuthorizedForProduction(username: string): boolean {
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

// Check if user is authorized for administrative commands
function isAuthorizedForAdmin(username: string): boolean {
  const adminUsers = (process.env.ADMIN_AUTHORIZED_USERS || '').split(',');
  return adminUsers.includes(username) || adminUsers.includes('*') || isAuthorizedForProduction(username);
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
        statusText = 'VPN subnets are currently associating | VPN 子網路正在關聯中';
        instructionText = actionAttempted === 'open' ? 
          'Please wait for association to complete | 請等待關聯完成' :
          'Wait for association to finish, then try closing | 等待關聯完成後再嘗試關閉';
      } else if (isDisassociating) {
        statusText = 'VPN subnets are currently disassociating | VPN 子網路正在取消關聯中';
        instructionText = actionAttempted === 'close' ? 
          'Please wait for disassociation to complete | 請等待取消關聯完成' :
          'Wait for disassociation to finish, then try opening | 等待取消關聯完成後再嘗試開啟';
      }
      
      return {
        response_type: 'ephemeral',
        text: `🟡 VPN Operation In Progress | VPN 操作進行中`,
        attachments: [{
          color: 'warning',
          fields: [
            {
              title: `${environmentEmoji} Environment | 環境`,
              value: environmentName,
              short: true
            },
            {
              title: '📊 Current Status | 目前狀態',
              value: statusText,
              short: true
            },
            {
              title: '⏳ Action Required | 所需動作',
              value: instructionText,
              short: false
            },
            {
              title: '💡 Tip | 提示',
              value: `Use \`/vpn check ${command.environment}\` to monitor progress | 使用 \`/vpn check ${command.environment}\` 監控進度`,
              short: false
            }
          ],
          footer: 'VPN Automation System | VPN 自動化系統'
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
  const environmentName = environment === 'production' ? '正式環境' : '測試環境';
  const severityName = severity === 'critical' ? '緊急' : '警告';
  
  await sendSlackNotification({
    text: `${emoji} VPN 系統警報 ${environmentEmoji}`,
    attachments: [{
      color: severity === 'critical' ? 'danger' : 'warning',
      fields: [
        {
          title: '環境 Environment',
          value: `${environmentName} (${environment})`,
          short: true
        },
        {
          title: '嚴重程度 Severity',
          value: severityName,
          short: true
        },
        {
          title: '訊息 Message',
          value: userFriendlyMessage,
          short: false
        },
        {
          title: '時間 Time',
          value: `${formattedTime} (台灣時間)`,
          short: true
        }
      ],
      footer: 'VPN System Alert | VPN 系統警報',
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
      '🔧 VPN 監控系統偵測到設定參數異常，請檢查系統配置是否正確',
    
    'VPN endpoint validation failed': 
      '🔗 VPN 端點連線驗證失敗，請檢查網路連線狀態',
    
    'Failed to send Slack notification': 
      '📢 Slack 通知發送失敗，請檢查 Slack 整合設定',
    
    'Cross-account VPN operation failed': 
      '🔄 跨帳戶 VPN 操作失敗，請檢查跨帳戶權限設定',
    
    'VPN endpoint not configured': 
      '⚙️ VPN 端點尚未設定，請先完成 VPN 端點配置',
    
    'Unauthorized operation': 
      '🔐 權限不足，請檢查 AWS IAM 權限設定',
    
    'Request validation failed': 
      '📝 請求格式驗證失敗，請檢查輸入參數',
    
    'VPN connection timeout': 
      '⏱️ VPN 連線逾時，請檢查網路狀況或稍後再試',
    
    'Certificate validation failed': 
      '📜 憑證驗證失敗，請檢查 VPN 憑證是否有效'
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