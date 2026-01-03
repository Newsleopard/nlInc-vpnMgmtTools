/**
 * Integration Tests for Schedule Commands
 * 
 * Tests the schedule command parsing and response formatting
 * through the shared slack module.
 * 
 * Requirements: 1.1, 1.4, 2.1, 3.1
 */

import { 
  parseSlackCommand, 
  formatScheduleResponse, 
  isAuthorizedForSchedule,
  getScheduleHelpMessage
} from '../../shared/slack';
import { SlackCommand, VpnCommandRequest, VpnCommandResponse, ScheduleStatusData } from '../../shared/types';

describe('Schedule Commands Integration Tests', () => {
  // Helper to create a mock Slack command
  const createSlackCommand = (text: string, userName: string = 'testuser'): SlackCommand => ({
    token: 'test_token',
    team_id: 'T123456',
    team_domain: 'test-team',
    channel_id: 'C123456',
    channel_name: 'general',
    user_id: 'U123456',
    user_name: userName,
    command: '/vpn',
    text,
    response_url: 'https://hooks.slack.com/commands/123',
    trigger_id: 'trigger123'
  });

  beforeEach(() => {
    // Set up environment variables for authorization
    process.env.PRODUCTION_AUTHORIZED_USERS = 'admin,testuser';
    process.env.ADMIN_AUTHORIZED_USERS = 'admin';
    process.env.SCHEDULE_AUTHORIZED_USERS = 'admin,testuser';
  });

  describe('Schedule Enable Command (schedule-on)', () => {
    it('should parse schedule on staging command correctly', () => {
      const slackCommand = createSlackCommand('schedule on staging');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-on');
      expect(result.environment).toBe('staging');
      expect(result.user).toBe('testuser');
      expect(result.requestId).toBeDefined();
    });

    it('should parse schedule on production command correctly', () => {
      const slackCommand = createSlackCommand('schedule on production', 'admin');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-on');
      expect(result.environment).toBe('production');
      expect(result.user).toBe('admin');
    });

    it('should support environment alias prod', () => {
      const slackCommand = createSlackCommand('schedule on prod');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-on');
      expect(result.environment).toBe('production');
    });
  });

  describe('Schedule Disable Command (schedule-off)', () => {
    it('should parse schedule off staging command correctly', () => {
      const slackCommand = createSlackCommand('schedule off staging');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-off');
      expect(result.environment).toBe('staging');
      expect(result.duration).toBeUndefined();
    });

    it('should parse schedule off with duration correctly', () => {
      const slackCommand = createSlackCommand('schedule off staging 2h');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-off');
      expect(result.environment).toBe('staging');
      expect(result.duration).toBe('2h');
    });

    it('should parse schedule off with day duration correctly', () => {
      const slackCommand = createSlackCommand('schedule off production 7d');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-off');
      expect(result.environment).toBe('production');
      expect(result.duration).toBe('7d');
    });

    it('should reject invalid duration format', () => {
      const slackCommand = createSlackCommand('schedule off staging invalid');
      
      expect(() => parseSlackCommand(slackCommand)).toThrow('Invalid duration format');
    });
  });

  describe('Schedule Check Command (schedule-check)', () => {
    it('should parse schedule check staging command correctly', () => {
      const slackCommand = createSlackCommand('schedule check staging');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-check');
      expect(result.environment).toBe('staging');
    });

    it('should parse schedule check production command correctly', () => {
      const slackCommand = createSlackCommand('schedule check production');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-check');
      expect(result.environment).toBe('production');
    });
  });

  describe('Granular Schedule Commands', () => {
    it('should parse schedule open on command correctly', () => {
      const slackCommand = createSlackCommand('schedule open on staging');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-open-on');
      expect(result.environment).toBe('staging');
    });

    it('should parse schedule open off command correctly', () => {
      const slackCommand = createSlackCommand('schedule open off staging');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-open-off');
      expect(result.environment).toBe('staging');
    });

    it('should parse schedule close on command correctly', () => {
      const slackCommand = createSlackCommand('schedule close on staging');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-close-on');
      expect(result.environment).toBe('staging');
    });

    it('should parse schedule close off command correctly', () => {
      const slackCommand = createSlackCommand('schedule close off staging');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-close-off');
      expect(result.environment).toBe('staging');
    });

    it('should parse schedule close off with duration correctly', () => {
      const slackCommand = createSlackCommand('schedule close off staging 24h');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-close-off');
      expect(result.environment).toBe('staging');
      expect(result.duration).toBe('24h');
    });
  });

  describe('Schedule Help Command', () => {
    it('should parse schedule help command correctly', () => {
      const slackCommand = createSlackCommand('schedule help');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-help');
      expect(result.helpMessage).toBeDefined();
    });

    it('should parse schedule without arguments as help', () => {
      const slackCommand = createSlackCommand('schedule');
      const result = parseSlackCommand(slackCommand);

      expect(result.action).toBe('schedule-help');
    });

    it('should return detailed help message', () => {
      const helpMessage = getScheduleHelpMessage();
      const parsed = JSON.parse(helpMessage);

      expect(parsed.text).toContain('Schedule Management');
      expect(parsed.attachments).toBeDefined();
      expect(parsed.attachments.length).toBeGreaterThan(0);
    });
  });

  describe('Authorization Enforcement', () => {
    it('should authorize admin user for production', () => {
      const isAuthorized = isAuthorizedForSchedule('admin', 'production');
      expect(isAuthorized).toBe(true);
    });

    it('should authorize testuser for staging', () => {
      const isAuthorized = isAuthorizedForSchedule('testuser', 'staging');
      expect(isAuthorized).toBe(true);
    });

    it('should deny unauthorized user for production', () => {
      // Clear authorized users to test denial
      process.env.PRODUCTION_AUTHORIZED_USERS = 'admin';
      process.env.ADMIN_AUTHORIZED_USERS = 'admin';
      process.env.SCHEDULE_AUTHORIZED_USERS = '';
      
      const isAuthorized = isAuthorizedForSchedule('unauthorized_user', 'production');
      expect(isAuthorized).toBe(false);
    });

    it('should throw error when unauthorized user tries schedule command on production', () => {
      process.env.PRODUCTION_AUTHORIZED_USERS = 'admin';
      process.env.ADMIN_AUTHORIZED_USERS = 'admin';
      process.env.SCHEDULE_AUTHORIZED_USERS = '';
      
      const slackCommand = createSlackCommand('schedule on production', 'unauthorized_user');
      
      expect(() => parseSlackCommand(slackCommand)).toThrow('Access denied');
    });
  });

  describe('Error Handling', () => {
    it('should throw error for missing environment', () => {
      const slackCommand = createSlackCommand('schedule on');
      
      expect(() => parseSlackCommand(slackCommand)).toThrow('Environment required');
    });

    it('should throw error for invalid environment', () => {
      const slackCommand = createSlackCommand('schedule on invalid_env');
      
      expect(() => parseSlackCommand(slackCommand)).toThrow('Invalid environment');
    });

    it('should throw error for invalid schedule action', () => {
      const slackCommand = createSlackCommand('schedule invalid staging');
      
      expect(() => parseSlackCommand(slackCommand)).toThrow('Invalid schedule action');
    });

    it('should throw error for invalid granular command', () => {
      const slackCommand = createSlackCommand('schedule open invalid staging');
      
      expect(() => parseSlackCommand(slackCommand)).toThrow('Invalid command');
    });
  });

  describe('Response Formatting', () => {
    it('should format schedule enable response correctly', () => {
      const response: VpnCommandResponse = {
        success: true,
        message: 'Auto-scheduling enabled for staging'
      };
      
      const command: VpnCommandRequest = {
        action: 'schedule-on',
        environment: 'staging',
        user: 'testuser',
        requestId: 'test-123'
      };

      const formatted = formatScheduleResponse(response, command);

      expect(formatted.response_type).toBe('in_channel');
      expect(formatted.text).toContain('Enabled');
      expect(formatted.attachments).toBeDefined();
    });

    it('should format schedule disable response correctly', () => {
      const response: VpnCommandResponse = {
        success: true,
        message: 'Auto-scheduling disabled for staging'
      };
      
      const command: VpnCommandRequest = {
        action: 'schedule-off',
        environment: 'staging',
        user: 'testuser',
        requestId: 'test-123',
        duration: '2h'
      };

      const formatted = formatScheduleResponse(response, command);

      expect(formatted.response_type).toBe('in_channel');
      expect(formatted.text).toContain('Disabled');
      expect(formatted.attachments).toBeDefined();
    });

    it('should format schedule check response with status data', () => {
      const response: VpnCommandResponse = {
        success: true,
        message: 'Schedule status for staging'
      };
      
      const command: VpnCommandRequest = {
        action: 'schedule-check',
        environment: 'staging',
        user: 'testuser',
        requestId: 'test-123'
      };

      const statusData: ScheduleStatusData = {
        autoOpen: {
          enabled: true,
          nextScheduledTime: new Date().toISOString()
        },
        autoClose: {
          enabled: true,
          idleTimeoutMinutes: 100
        },
        businessHoursProtection: {
          enabled: true,
          start: '09:30',
          end: '17:30',
          timezone: 'Asia/Taipei'
        },
        lastModified: new Date().toISOString(),
        modifiedBy: 'system'
      };

      const formatted = formatScheduleResponse(response, command, statusData);

      expect(formatted.response_type).toBe('ephemeral');
      expect(formatted.text).toContain('Status');
      expect(formatted.attachments).toBeDefined();
    });

    it('should format error response correctly', () => {
      const response: VpnCommandResponse = {
        success: false,
        message: 'Schedule command failed',
        error: 'Failed to write schedule state'
      };
      
      const command: VpnCommandRequest = {
        action: 'schedule-on',
        environment: 'staging',
        user: 'testuser',
        requestId: 'test-123'
      };

      const formatted = formatScheduleResponse(response, command);

      expect(formatted.response_type).toBe('ephemeral');
      expect(formatted.text).toContain('failed');
      expect(formatted.attachments[0].color).toBe('danger');
    });

    it('should include bilingual content in responses', () => {
      const response: VpnCommandResponse = {
        success: true,
        message: 'Auto-scheduling enabled for staging'
      };
      
      const command: VpnCommandRequest = {
        action: 'schedule-on',
        environment: 'staging',
        user: 'testuser',
        requestId: 'test-123'
      };

      const formatted = formatScheduleResponse(response, command);
      const formattedStr = JSON.stringify(formatted);

      // Check for Chinese characters (Traditional Chinese)
      expect(formattedStr).toMatch(/[\u4e00-\u9fff]/);
    });
  });
});
