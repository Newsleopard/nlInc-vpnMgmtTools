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
    throw new Error(getHelpMessage());
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
  if (!['open', 'close', 'check', 'admin', 'savings', 'costs'].includes(action)) {
    throw new Error(`Invalid action "${parts[0]}". Must be: open, close, check, admin, savings, or costs\n\n` + getHelpMessage());
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
  return `**VPN Automation Commands:**

**Basic Usage:** \`/vpn <action> <environment>\`

**Core Actions:**
• \`open\` (aliases: start, enable, on) - Associate VPN subnets
• \`close\` (aliases: stop, disable, off) - Disassociate VPN subnets  
• \`check\` (aliases: status, state, info) - Check VPN status

**Cost Optimization (Epic 3.2):**
• \`/vpn savings <environment>\` - Show cost savings report
• \`/vpn costs daily\` - Show daily cost analysis
• \`/vpn costs cumulative\` - Show total savings

**Administrative Controls:**
• \`/vpn admin override <env>\` - Disable auto-close (24h)
• \`/vpn admin clear-override <env>\` - Re-enable auto-close
• \`/vpn admin cooldown <env>\` - Check cooldown status
• \`/vpn admin force-close <env>\` - Bypass safety mechanisms

**Environments:**
• \`staging\` (aliases: stage, dev) - Staging environment 🟡
• \`production\` (aliases: prod) - Production environment 🔴

**Examples:**
• \`/vpn open staging\` - Open staging VPN
• \`/vpn savings production\` - View production cost savings
• \`/vpn admin override staging\` - Disable auto-close for 24h
• \`/vpn costs daily\` - Daily cost breakdown

**Auto-Cost Optimization:**
- Idle VPNs auto-close after 60 minutes (configurable)
- Business hours protection (9 AM - 6 PM)
- 30-minute cooldown prevents rapid cycling
- Manual activity detection (15-min grace period)
- Real-time cost savings tracking (~$0.10/hour per subnet)`;
}

// Check if user is authorized for production operations
function isAuthorizedForProduction(username: string): boolean {
  // This could be enhanced to check against Parameter Store or external auth service
  const authorizedUsers = (process.env.PRODUCTION_AUTHORIZED_USERS || '').split(',');
  return authorizedUsers.includes(username) || authorizedUsers.includes('*');
}

// Generate unique request ID for tracking
export function generateRequestId(): string {
  return `vpn-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

// Parse administrative commands for Epic 3.2
function parseAdminCommand(slackCommand: SlackCommand, parts: string[]): VpnCommandRequest {
  const adminAction = parts[1].toLowerCase();
  const environment = parts[2]?.toLowerCase();
  
  // Validate admin permissions
  if (!isAuthorizedForAdmin(slackCommand.user_name)) {
    throw new Error(`❌ Access denied: User "${slackCommand.user_name}" is not authorized for administrative commands.\n\nContact your system administrator.`);
  }
  
  // Validate environment for admin commands
  if (!['staging', 'production'].includes(environment)) {
    throw new Error(`Invalid environment "${environment}". Must be: staging or production`);
  }
  
  // Map admin actions to standard format
  const adminActionMap: { [key: string]: string } = {
    'override': 'admin-override',
    'clear-override': 'admin-clear-override',
    'cooldown': 'admin-cooldown',
    'force-close': 'admin-force-close'
  };
  
  const mappedAction = adminActionMap[adminAction];
  if (!mappedAction) {
    throw new Error(`Invalid admin action "${adminAction}". Must be: override, clear-override, cooldown, or force-close`);
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
    case 'admin-override':
    case 'admin-clear-override':
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
        text: `💰 Cost Savings Report - ${savingsData.environment}`,
        attachments: [{
          color: 'good',
          fields: [
            {
              title: 'Today\'s Savings',
              value: `$${savingsData.todaySavings}`,
              short: true
            },
            {
              title: 'Total Savings',
              value: `$${savingsData.cumulativeSavings}`,
              short: true
            },
            {
              title: 'Current Status',
              value: savingsData.currentStatus,
              short: true
            },
            {
              title: 'Potential Hourly Savings',
              value: `$${savingsData.potentialHourlySavings}/hour`,
              short: true
            }
          ],
          footer: `Last updated: ${new Date(savingsData.lastUpdated).toLocaleString()}`
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
    return {
      response_type: 'ephemeral',
      text: `❌ VPN ${command.action} failed for ${environmentEmoji} ${environmentName}`,
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
  
  let statusEmoji = '⚪';
  let statusText = 'Unknown';
  
  if (command.action === 'check' && response.data) {
    statusEmoji = response.data.associated ? '🟢' : '🔴';
    statusText = response.data.associated ? 'Open' : 'Closed';
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
    text: `${statusEmoji} VPN ${command.action} completed for ${environmentEmoji} ${environmentName}`,
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
  message: string,
  channel?: string
): Promise<void> {
  try {
    const webhookUrl = await stateStore.readSlackWebhook();
    
    const payload = {
      text: message,
      channel: channel || '#vpn-automation',
      username: 'VPN Automation',
      icon_emoji: ':robot_face:'
    };
    
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
  
  // Convert UTC time to Taiwan timezone (UTC+8)
  const taiwanTime = new Date(new Date().getTime() + (8 * 60 * 60 * 1000));
  const formattedTime = taiwanTime.toLocaleString('zh-TW', {
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
  
  const alertMessage = `${emoji} **VPN 系統警報** ${environmentEmoji}\n` +
                      `**環境：** ${environmentName} (${environment})\n` +
                      `**嚴重程度：** ${severityName}\n` +
                      `**訊息：** ${userFriendlyMessage}\n` +
                      `**時間：** ${formattedTime} (台灣時間)`;
  
  await sendSlackNotification(alertMessage, '#vpn-alerts');
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