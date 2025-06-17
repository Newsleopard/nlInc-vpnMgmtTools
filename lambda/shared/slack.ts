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
  const parts = text.split(/\s+/);
  
  if (parts.length < 2) {
    throw new Error('Invalid command format. Usage: /vpn <action> <environment>');
  }
  
  const action = parts[0].toLowerCase();
  const environment = parts[1].toLowerCase();
  
  // Validate action
  if (!['open', 'close', 'check'].includes(action)) {
    throw new Error('Invalid action. Must be: open, close, or check');
  }
  
  // Validate environment
  if (!['staging', 'production'].includes(environment)) {
    throw new Error('Invalid environment. Must be: staging or production');
  }
  
  return {
    action: action as 'open' | 'close' | 'check',
    environment: environment as 'staging' | 'production',
    user: slackCommand.user_name,
    requestId: generateRequestId()
  };
}

// Generate unique request ID for tracking
export function generateRequestId(): string {
  return `vpn-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

// Format VPN command response for Slack
export function formatSlackResponse(
  response: VpnCommandResponse,
  command: VpnCommandRequest
): any {
  const environmentEmoji = command.environment === 'production' ? '🔴' : '🟡';
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
  const environmentEmoji = environment === 'production' ? '🔴' : '🟡';
  
  const alertMessage = `${emoji} **VPN Automation Alert** ${environmentEmoji}\n` +
                      `**Environment:** ${environment}\n` +
                      `**Severity:** ${severity}\n` +
                      `**Message:** ${message}\n` +
                      `**Time:** ${new Date().toISOString()}`;
  
  await sendSlackNotification(alertMessage, '#vpn-alerts');
}