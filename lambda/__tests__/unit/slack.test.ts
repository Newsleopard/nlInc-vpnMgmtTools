import * as crypto from 'crypto';
import { resetAllMocks } from '../../__mocks__/aws-sdk';

// Import after mocks are set up
import * as slack from '../../shared/slack';
import { SlackCommand, VpnCommandRequest, VpnCommandResponse } from '../../shared/types';

describe('slack', () => {
  beforeEach(() => {
    resetAllMocks();
  });

  describe('verifySlackSignature', () => {
    const mockSigningSecret = 'test_signing_secret';
    const mockBody = 'token=test&text=check+staging';
    const mockTimestamp = Math.floor(Date.now() / 1000).toString();

    it('should verify valid Slack signature', () => {
      const baseString = `v0:${mockTimestamp}:${mockBody}`;
      const signature = 'v0=' + crypto
        .createHmac('sha256', mockSigningSecret)
        .update(baseString)
        .digest('hex');

      const result = slack.verifySlackSignature(mockBody, signature, mockTimestamp, mockSigningSecret);

      expect(result).toBe(true);
    });

    it('should reject invalid signature', () => {
      const invalidSignature = 'v0=invalid_signature';

      const result = slack.verifySlackSignature(mockBody, invalidSignature, mockTimestamp, mockSigningSecret);

      expect(result).toBe(false);
    });

    it('should reject timestamp too old (replay attack protection)', () => {
      const oldTimestamp = (Math.floor(Date.now() / 1000) - 400).toString(); // 400 seconds ago
      const baseString = `v0:${oldTimestamp}:${mockBody}`;
      const signature = 'v0=' + crypto
        .createHmac('sha256', mockSigningSecret)
        .update(baseString)
        .digest('hex');

      const result = slack.verifySlackSignature(mockBody, signature, oldTimestamp, mockSigningSecret);

      expect(result).toBe(false);
    });

    it('should handle verification errors gracefully', () => {
      const result = slack.verifySlackSignature(mockBody, '', '', '');

      expect(result).toBe(false);
    });
  });

  describe('parseSlackCommand', () => {
    const mockSlackCommand: SlackCommand = {
      token: 'test_token',
      team_id: 'T123456',
      team_domain: 'test-team',
      channel_id: 'C123456',
      channel_name: 'general',
      user_id: 'U123456',
      user_name: 'testuser',
      command: '/vpn',
      text: 'open staging',
      response_url: 'https://hooks.slack.com/commands/123',
      trigger_id: 'trigger123'
    };

    it('should parse valid VPN command', () => {
      const result = slack.parseSlackCommand(mockSlackCommand);

      expect(result).toEqual({
        action: 'open',
        environment: 'staging',
        user: 'testuser',
        requestId: expect.stringMatching(/^vpn-\d+-[a-z0-9]{9}$/)
      });
    });

    it('should parse close production command', () => {
      const command = { ...mockSlackCommand, text: 'close production' };
      const result = slack.parseSlackCommand(command);

      expect(result.action).toBe('close');
      expect(result.environment).toBe('production');
    });

    it('should parse check command', () => {
      const command = { ...mockSlackCommand, text: 'check staging' };
      const result = slack.parseSlackCommand(command);

      expect(result.action).toBe('check');
      expect(result.environment).toBe('staging');
    });

    it('should throw error for insufficient arguments', () => {
      const command = { ...mockSlackCommand, text: 'open' };

      expect(() => slack.parseSlackCommand(command)).toThrow('Invalid command format. Usage: /vpn <action> <environment>');
    });

    it('should throw error for invalid action', () => {
      const command = { ...mockSlackCommand, text: 'invalid staging' };

      expect(() => slack.parseSlackCommand(command)).toThrow('Invalid action. Must be: open, close, or check');
    });

    it('should throw error for invalid environment', () => {
      const command = { ...mockSlackCommand, text: 'open invalid' };

      expect(() => slack.parseSlackCommand(command)).toThrow('Invalid environment. Must be: staging or production');
    });

    it('should handle empty text', () => {
      const command = { ...mockSlackCommand, text: '' };

      expect(() => slack.parseSlackCommand(command)).toThrow('Invalid command format. Usage: /vpn <action> <environment>');
    });

    it('should be case insensitive', () => {
      const command = { ...mockSlackCommand, text: 'OPEN STAGING' };
      const result = slack.parseSlackCommand(command);

      expect(result.action).toBe('open');
      expect(result.environment).toBe('staging');
    });
  });

  describe('generateRequestId', () => {
    it('should generate unique request IDs', () => {
      const id1 = slack.generateRequestId();
      const id2 = slack.generateRequestId();

      expect(id1).toMatch(/^vpn-\d+-[a-z0-9]{9}$/);
      expect(id2).toMatch(/^vpn-\d+-[a-z0-9]{9}$/);
      expect(id1).not.toBe(id2);
    });
  });

  describe('formatSlackResponse', () => {
    const mockCommand: VpnCommandRequest = {
      action: 'open',
      environment: 'staging',
      user: 'testuser',
      requestId: 'vpn-123-abc'
    };

    it('should format successful open response', () => {
      const response: VpnCommandResponse = {
        success: true,
        message: 'VPN opened successfully',
        data: {
          associated: true,
          activeConnections: 2,
          lastActivity: new Date('2025-06-17T10:00:00.000Z'),
          endpointId: 'cvpn-endpoint-123',
          subnetId: 'subnet-123'
        }
      };

      const result = slack.formatSlackResponse(response, mockCommand);

      expect(result).toEqual({
        response_type: 'in_channel',
        text: '🟢 VPN open completed for 🟡 Staging',
        attachments: [{
          color: 'good',
          fields: [
            { title: 'Status', value: '🟢 Opened', short: true },
            { title: 'Active Connections', value: '2', short: true },
            { title: 'Last Activity', value: 'Just now', short: true }
          ],
          footer: 'Request ID: vpn-123-abc',
          ts: expect.any(Number)
        }]
      });
    });

    it('should format successful close response', () => {
      const command = { ...mockCommand, action: 'close' as const };
      const response: VpnCommandResponse = {
        success: true,
        message: 'VPN closed successfully',
        data: {
          associated: false,
          activeConnections: 0,
          lastActivity: new Date('2025-06-17T09:30:00.000Z'),
          endpointId: 'cvpn-endpoint-123',
          subnetId: 'subnet-123'
        }
      };

      const result = slack.formatSlackResponse(response, command);

      expect(result.text).toBe('🔴 VPN close completed for 🟡 Staging');
      expect(result.attachments[0].fields[0].value).toBe('🔴 Closed');
    });

    it('should format check response with idle time', () => {
      const command = { ...mockCommand, action: 'check' as const };
      const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);
      
      const response: VpnCommandResponse = {
        success: true,
        message: 'VPN status retrieved',
        data: {
          associated: true,
          activeConnections: 1,
          lastActivity: thirtyMinutesAgo,
          endpointId: 'cvpn-endpoint-123',
          subnetId: 'subnet-123'
        }
      };

      const result = slack.formatSlackResponse(response, command);

      expect(result.attachments[0].fields).toContainEqual({
        title: 'Last Activity',
        value: '30 minutes ago',
        short: true
      });
    });

    it('should format production environment with correct emoji', () => {
      const command = { ...mockCommand, environment: 'production' as const };
      const response: VpnCommandResponse = {
        success: true,
        message: 'VPN opened successfully'
      };

      const result = slack.formatSlackResponse(response, command);

      expect(result.text).toBe('🟢 VPN open completed for 🔴 Production');
    });

    it('should format error response', () => {
      const response: VpnCommandResponse = {
        success: false,
        message: '',
        error: 'VPN endpoint not found'
      };

      const result = slack.formatSlackResponse(response, mockCommand);

      expect(result).toEqual({
        response_type: 'ephemeral',
        text: '❌ VPN open failed for 🟡 Staging',
        attachments: [{
          color: 'danger',
          fields: [{
            title: 'Error',
            value: 'VPN endpoint not found',
            short: false
          }]
        }]
      });
    });

    it('should handle response without data', () => {
      const response: VpnCommandResponse = {
        success: true,
        message: 'Operation completed'
      };

      const result = slack.formatSlackResponse(response, mockCommand);

      expect(result.attachments[0].fields).toHaveLength(1);
      expect(result.attachments[0].fields[0]).toEqual({
        title: 'Status',
        value: '🟢 Opened',
        short: true
      });
    });
  });

  describe('sendSlackNotification', () => {
    beforeEach(() => {
      // Mock fetch globally
      global.fetch = jest.fn();
    });

    afterEach(() => {
      jest.restoreAllMocks();
    });

    it('should send notification to default channel', async () => {
      (global.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        status: 200
      });

      // Mock stateStore.readSlackWebhook
      const mockStateStore = require('../../shared/stateStore');
      jest.spyOn(mockStateStore, 'readSlackWebhook').mockResolvedValue('https://hooks.slack.com/test');

      await slack.sendSlackNotification('Test message');

      expect(global.fetch).toHaveBeenCalledWith(
        'https://hooks.slack.com/test',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            text: 'Test message',
            channel: '#vpn-automation',
            username: 'VPN Automation',
            icon_emoji: ':robot_face:'
          })
        }
      );
    });

    it('should handle webhook errors gracefully', async () => {
      (global.fetch as jest.Mock).mockResolvedValue({
        ok: false,
        status: 404,
        statusText: 'Not Found'
      });

      const mockStateStore = require('../../shared/stateStore');
      jest.spyOn(mockStateStore, 'readSlackWebhook').mockResolvedValue('https://hooks.slack.com/test');

      // Should not throw error
      await expect(slack.sendSlackNotification('Test message')).resolves.toBeUndefined();
    });
  });

  describe('sendSlackAlert', () => {
    beforeEach(() => {
      global.fetch = jest.fn();
    });

    afterEach(() => {
      jest.restoreAllMocks();
    });

    it('should format alert message correctly', async () => {
      (global.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        status: 200
      });

      const mockStateStore = require('../../shared/stateStore');
      jest.spyOn(mockStateStore, 'readSlackWebhook').mockResolvedValue('https://hooks.slack.com/test');

      await slack.sendSlackAlert('Test alert', 'staging', 'critical');

      expect(global.fetch).toHaveBeenCalledWith(
        'https://hooks.slack.com/test',
        expect.objectContaining({
          body: expect.stringContaining('🚨 **VPN Automation Alert** 🟡')
        })
      );
    });

    it('should use warning emoji for warning severity', async () => {
      (global.fetch as jest.Mock).mockResolvedValue({
        ok: true,
        status: 200
      });

      const mockStateStore = require('../../shared/stateStore');
      jest.spyOn(mockStateStore, 'readSlackWebhook').mockResolvedValue('https://hooks.slack.com/test');

      await slack.sendSlackAlert('Test warning', 'production', 'warning');

      expect(global.fetch).toHaveBeenCalledWith(
        'https://hooks.slack.com/test',
        expect.objectContaining({
          body: expect.stringContaining('⚠️ **VPN Automation Alert** 🔴')
        })
      );
    });
  });
});