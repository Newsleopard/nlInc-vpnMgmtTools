/**
 * Property-Based Tests for Slack Schedule Commands
 * 
 * Feature: auto-schedule-slack-commands
 * 
 * These tests use fast-check to verify universal properties
 * that should hold for all valid inputs.
 */

import * as fc from 'fast-check';
import { SlackCommand } from '../../shared/types';
import {
  parseScheduleCommand,
  isAuthorizedForSchedule,
  isAuthorizedForProduction,
  formatScheduleResponse,
  getScheduleHelpMessage
} from '../../shared/slack';

// ============================================================================
// Arbitraries (Generators)
// ============================================================================

/**
 * Generate a valid username
 */
const usernameArb: fc.Arbitrary<string> = fc.constantFrom(
  'admin', 'user1', 'test_user', 'john_doe', 'alice', 'bob123', 'moderator', 'developer'
);

/**
 * Generate a valid environment
 */
const environmentArb: fc.Arbitrary<string> = fc.constantFrom('staging', 'production');

/**
 * Generate environment aliases
 */
const environmentAliasArb: fc.Arbitrary<string> = fc.constantFrom(
  'staging', 'production', 'stage', 'prod', 'dev', 'staging-env', 'production-env'
);

/**
 * Generate a valid duration string
 */
const validDurationArb: fc.Arbitrary<string> = fc.tuple(
  fc.integer({ min: 1, max: 999 }),
  fc.constantFrom('h', 'd', 'm')
).map(([value, unit]) => `${value}${unit}`);

/**
 * Generate an invalid duration string
 */
const invalidDurationArb: fc.Arbitrary<string> = fc.constantFrom(
  '', 'abc', '0h', '-1h', '1x', 'h1', '1.5h', 'hello', '10', 'hh', 'dd'
);

/**
 * Generate a basic SlackCommand object
 */
const slackCommandArb = (text: string, username: string = 'testuser'): SlackCommand => ({
  token: 'test_token',
  team_id: 'T123456',
  team_domain: 'test-team',
  channel_id: 'C123456',
  channel_name: 'general',
  user_id: 'U123456',
  user_name: username,
  command: '/vpn',
  text,
  response_url: 'https://hooks.slack.com/commands/123',
  trigger_id: 'trigger123'
});

/**
 * Generate schedule status data for testing
 */
const scheduleStatusDataArb = fc.record({
  autoOpen: fc.record({
    enabled: fc.boolean(),
    nextScheduledTime: fc.option(
      fc.integer({ min: Date.now(), max: Date.now() + 7 * 24 * 60 * 60 * 1000 })
        .map(ts => new Date(ts).toISOString()), 
      { nil: undefined }
    ),
    disabledUntil: fc.option(fc.constantFrom('2h', '24h', '7d'), { nil: undefined })
  }),
  autoClose: fc.record({
    enabled: fc.boolean(),
    idleTimeoutMinutes: fc.integer({ min: 30, max: 300 }),
    disabledUntil: fc.option(fc.constantFrom('2h', '24h', '7d'), { nil: undefined })
  }),
  businessHoursProtection: fc.record({
    enabled: fc.boolean(),
    start: fc.constant('09:30'),
    end: fc.constant('17:30'),
    timezone: fc.constant('Asia/Taipei')
  }),
  lastModified: fc.integer({ min: Date.now() - 30 * 24 * 60 * 60 * 1000, max: Date.now() })
    .map(ts => new Date(ts).toISOString()),
  modifiedBy: usernameArb
});

// ============================================================================
// Property Tests
// ============================================================================

describe('Slack Schedule Command Property Tests', () => {
  
  // Store original environment variables
  let originalProdUsers: string | undefined;
  let originalAdminUsers: string | undefined;
  let originalScheduleUsers: string | undefined;

  beforeEach(() => {
    originalProdUsers = process.env.PRODUCTION_AUTHORIZED_USERS;
    originalAdminUsers = process.env.ADMIN_AUTHORIZED_USERS;
    originalScheduleUsers = process.env.SCHEDULE_AUTHORIZED_USERS;
  });

  afterEach(() => {
    // Restore environment variables
    if (originalProdUsers !== undefined) {
      process.env.PRODUCTION_AUTHORIZED_USERS = originalProdUsers;
    } else {
      delete process.env.PRODUCTION_AUTHORIZED_USERS;
    }
    if (originalAdminUsers !== undefined) {
      process.env.ADMIN_AUTHORIZED_USERS = originalAdminUsers;
    } else {
      delete process.env.ADMIN_AUTHORIZED_USERS;
    }
    if (originalScheduleUsers !== undefined) {
      process.env.SCHEDULE_AUTHORIZED_USERS = originalScheduleUsers;
    } else {
      delete process.env.SCHEDULE_AUTHORIZED_USERS;
    }
  });

  /**
   * Property 4: Authorization Enforcement
   * 
   * For any user not in the authorized list for a given environment,
   * attempting any schedule command SHALL return an access denied error
   * without modifying schedule state.
   * 
   * **Validates: Requirements 1.4, 2.6**
   */
  describe('Property 4: Authorization Enforcement', () => {
    it('unauthorized users cannot access production schedule commands', () => {
      fc.assert(
        fc.property(
          usernameArb,
          fc.constantFrom('on', 'off', 'check'),
          (username, action) => {
            // Set up environment with specific authorized users (not including test user)
            process.env.PRODUCTION_AUTHORIZED_USERS = 'admin_only,special_user';
            process.env.ADMIN_AUTHORIZED_USERS = 'admin_only';
            process.env.SCHEDULE_AUTHORIZED_USERS = '';

            // Skip if user happens to be in authorized list
            if (username === 'admin_only' || username === 'special_user') {
              return true;
            }

            const slackCommand = slackCommandArb(`schedule ${action} production`, username);
            const parts = slackCommand.text.split(/\s+/);

            expect(() => parseScheduleCommand(slackCommand, parts)).toThrow('Access denied');
          }
        ),
        { numRuns: 100 }
      );
    });

    it('authorized users can access schedule commands', () => {
      fc.assert(
        fc.property(
          environmentArb,
          fc.constantFrom('on', 'off', 'check'),
          (environment, action) => {
            // Set up environment with wildcard authorization
            process.env.PRODUCTION_AUTHORIZED_USERS = '*';
            process.env.ADMIN_AUTHORIZED_USERS = '*';

            const slackCommand = slackCommandArb(`schedule ${action} ${environment}`, 'any_user');
            const parts = slackCommand.text.split(/\s+/);

            // Should not throw for authorized users
            const result = parseScheduleCommand(slackCommand, parts);
            expect(result.action).toMatch(/^schedule-/);
            expect(result.user).toBe('any_user');
          }
        ),
        { numRuns: 100 }
      );
    });

    it('isAuthorizedForSchedule returns false for unauthorized production users', () => {
      fc.assert(
        fc.property(usernameArb, (username) => {
          // Set up environment with no authorized users
          process.env.PRODUCTION_AUTHORIZED_USERS = '';
          process.env.ADMIN_AUTHORIZED_USERS = '';
          process.env.SCHEDULE_AUTHORIZED_USERS = '';

          const result = isAuthorizedForSchedule(username, 'production');
          expect(result).toBe(false);
        }),
        { numRuns: 100 }
      );
    });

    it('isAuthorizedForSchedule returns true for admin users', () => {
      fc.assert(
        fc.property(usernameArb, environmentArb, (username, environment) => {
          // Set up environment with the test user as admin
          process.env.ADMIN_AUTHORIZED_USERS = username;
          process.env.PRODUCTION_AUTHORIZED_USERS = username;

          const result = isAuthorizedForSchedule(username, environment);
          expect(result).toBe(true);
        }),
        { numRuns: 100 }
      );
    });

    it('wildcard authorization grants access to all users', () => {
      fc.assert(
        fc.property(usernameArb, environmentArb, (username, environment) => {
          process.env.PRODUCTION_AUTHORIZED_USERS = '*';
          process.env.ADMIN_AUTHORIZED_USERS = '*';

          const result = isAuthorizedForSchedule(username, environment);
          expect(result).toBe(true);
        }),
        { numRuns: 100 }
      );
    });
  });

  /**
   * Property 5: Status Response Completeness
   * 
   * For any schedule check command, the response SHALL contain all required fields:
   * autoOpen enabled state with next scheduled time, autoClose enabled state with
   * idle timeout, business hours protection status, and remaining disable time if applicable.
   * 
   * **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**
   */
  describe('Property 5: Status Response Completeness', () => {
    it('status response contains all required fields', () => {
      fc.assert(
        fc.property(
          scheduleStatusDataArb,
          environmentArb,
          (statusData, environment) => {
            const command = {
              action: 'schedule-check' as const,
              environment: environment as 'staging' | 'production',
              user: 'testuser',
              requestId: 'test-123'
            };

            const response = {
              success: true,
              message: 'Schedule status retrieved'
            };

            const result = formatScheduleResponse(response, command, statusData);

            // Verify response structure
            expect(result).toHaveProperty('response_type');
            expect(result).toHaveProperty('text');
            expect(result).toHaveProperty('attachments');
            expect(result.attachments).toHaveLength(1);
            expect(result.attachments[0]).toHaveProperty('fields');

            // Extract field titles
            const fieldTitles = result.attachments[0].fields.map((f: any) => f.title);

            // Verify required fields are present (Requirements 3.2, 3.3, 3.4, 3.5)
            expect(fieldTitles.some((t: string) => t.includes('Environment'))).toBe(true);
            expect(fieldTitles.some((t: string) => t.includes('Auto-Open'))).toBe(true);
            expect(fieldTitles.some((t: string) => t.includes('Auto-Close'))).toBe(true);
            expect(fieldTitles.some((t: string) => t.includes('Idle Timeout'))).toBe(true);
            expect(fieldTitles.some((t: string) => t.includes('Business Hours Protection'))).toBe(true);
            expect(fieldTitles.some((t: string) => t.includes('Last Modified'))).toBe(true);
          }
        ),
        { numRuns: 100 }
      );
    });

    it('status response shows disabled until time when schedule is disabled with expiration', () => {
      fc.assert(
        fc.property(
          environmentArb,
          validDurationArb,
          (environment, duration) => {
            const statusData = {
              autoOpen: {
                enabled: false,
                disabledUntil: duration
              },
              autoClose: {
                enabled: false,
                idleTimeoutMinutes: 100,
                disabledUntil: duration
              },
              businessHoursProtection: {
                enabled: true,
                start: '09:30',
                end: '17:30',
                timezone: 'Asia/Taipei'
              },
              lastModified: new Date().toISOString(),
              modifiedBy: 'testuser'
            };

            const command = {
              action: 'schedule-check' as const,
              environment: environment as 'staging' | 'production',
              user: 'testuser',
              requestId: 'test-123'
            };

            const response = {
              success: true,
              message: 'Schedule status retrieved'
            };

            const result = formatScheduleResponse(response, command, statusData);
            const fieldTitles = result.attachments[0].fields.map((f: any) => f.title);

            // When disabled with expiration, should show re-enable time
            expect(fieldTitles.some((t: string) => t.includes('Re-enables'))).toBe(true);
          }
        ),
        { numRuns: 100 }
      );
    });
  });

  /**
   * Property 6: Bilingual Response Format
   * 
   * For any schedule command response (enable, disable, check, help),
   * the formatted Slack message SHALL contain both English and Traditional Chinese
   * text for all user-facing content.
   * 
   * **Validates: Requirements 3.6, 7.4**
   */
  describe('Property 6: Bilingual Response Format', () => {
    it('schedule help message contains both English and Chinese', () => {
      const helpMessage = getScheduleHelpMessage();
      const parsed = JSON.parse(helpMessage);

      // Check main text is bilingual
      expect(parsed.text).toContain('|');
      expect(parsed.text).toMatch(/[\u4e00-\u9fff]/); // Contains Chinese characters

      // Check attachments contain bilingual content
      parsed.attachments.forEach((attachment: any) => {
        if (attachment.fields) {
          attachment.fields.forEach((field: any) => {
            // Field titles should be bilingual
            expect(field.title).toContain('|');
          });
        }
      });
    });

    it('enable response contains bilingual content', () => {
      fc.assert(
        fc.property(environmentArb, (environment) => {
          const command = {
            action: 'schedule-on' as const,
            environment: environment as 'staging' | 'production',
            user: 'testuser',
            requestId: 'test-123'
          };

          const response = {
            success: true,
            message: 'Schedule enabled'
          };

          const result = formatScheduleResponse(response, command);

          // Check main text is bilingual
          expect(result.text).toContain('|');

          // Check fields contain bilingual content
          result.attachments[0].fields.forEach((field: any) => {
            expect(field.title).toContain('|');
          });
        }),
        { numRuns: 100 }
      );
    });

    it('disable response contains bilingual content', () => {
      fc.assert(
        fc.property(
          environmentArb,
          fc.option(validDurationArb, { nil: undefined }),
          (environment, duration) => {
            const command = {
              action: 'schedule-off' as const,
              environment: environment as 'staging' | 'production',
              user: 'testuser',
              requestId: 'test-123',
              duration
            };

            const response = {
              success: true,
              message: 'Schedule disabled'
            };

            const result = formatScheduleResponse(response, command);

            // Check main text is bilingual
            expect(result.text).toContain('|');

            // Check fields contain bilingual content
            result.attachments[0].fields.forEach((field: any) => {
              expect(field.title).toContain('|');
            });
          }
        ),
        { numRuns: 100 }
      );
    });

    it('status check response contains bilingual content', () => {
      fc.assert(
        fc.property(
          scheduleStatusDataArb,
          environmentArb,
          (statusData, environment) => {
            const command = {
              action: 'schedule-check' as const,
              environment: environment as 'staging' | 'production',
              user: 'testuser',
              requestId: 'test-123'
            };

            const response = {
              success: true,
              message: 'Schedule status retrieved'
            };

            const result = formatScheduleResponse(response, command, statusData);

            // Check main text is bilingual
            expect(result.text).toContain('|');

            // Check fields contain bilingual content
            result.attachments[0].fields.forEach((field: any) => {
              expect(field.title).toContain('|');
            });
          }
        ),
        { numRuns: 100 }
      );
    });

    it('error response contains bilingual content', () => {
      fc.assert(
        fc.property(environmentArb, (environment) => {
          const command = {
            action: 'schedule-on' as const,
            environment: environment as 'staging' | 'production',
            user: 'testuser',
            requestId: 'test-123'
          };

          const response = {
            success: false,
            message: '',
            error: 'Test error'
          };

          const result = formatScheduleResponse(response, command);

          // Check main text is bilingual
          expect(result.text).toContain('|');

          // Check error field title is bilingual
          expect(result.attachments[0].fields[0].title).toContain('|');
        }),
        { numRuns: 100 }
      );
    });
  });

  /**
   * Additional parsing properties
   */
  describe('Schedule Command Parsing Properties', () => {
    beforeEach(() => {
      // Allow all users for parsing tests
      process.env.PRODUCTION_AUTHORIZED_USERS = '*';
      process.env.ADMIN_AUTHORIZED_USERS = '*';
    });

    it('valid basic schedule commands parse correctly', () => {
      fc.assert(
        fc.property(
          fc.constantFrom('on', 'off', 'check'),
          environmentAliasArb,
          (action, environment) => {
            const slackCommand = slackCommandArb(`schedule ${action} ${environment}`);
            const parts = slackCommand.text.split(/\s+/);

            const result = parseScheduleCommand(slackCommand, parts);

            expect(result.action).toBe(`schedule-${action}`);
            // Environment should be normalized
            expect(['staging', 'production']).toContain(result.environment);
            expect(result.user).toBe('testuser');
            expect(result.requestId).toMatch(/^vpn-/);
          }
        ),
        { numRuns: 100 }
      );
    });

    it('schedule off with valid duration parses correctly', () => {
      fc.assert(
        fc.property(
          environmentArb,
          validDurationArb,
          (environment, duration) => {
            const slackCommand = slackCommandArb(`schedule off ${environment} ${duration}`);
            const parts = slackCommand.text.split(/\s+/);

            const result = parseScheduleCommand(slackCommand, parts);

            expect(result.action).toBe('schedule-off');
            expect(result.environment).toBe(environment);
            expect(result.duration).toBe(duration);
          }
        ),
        { numRuns: 100 }
      );
    });

    it('schedule off with invalid duration throws error', () => {
      fc.assert(
        fc.property(
          environmentArb,
          invalidDurationArb,
          (environment, duration) => {
            // Skip empty string as it's treated as no duration
            if (duration === '') return true;

            const slackCommand = slackCommandArb(`schedule off ${environment} ${duration}`);
            const parts = slackCommand.text.split(/\s+/);

            expect(() => parseScheduleCommand(slackCommand, parts)).toThrow('Invalid duration format');
          }
        ),
        { numRuns: 100 }
      );
    });

    it('granular schedule commands parse correctly', () => {
      fc.assert(
        fc.property(
          fc.constantFrom('open', 'close'),
          fc.constantFrom('on', 'off'),
          environmentArb,
          (scheduleType, onOff, environment) => {
            const slackCommand = slackCommandArb(`schedule ${scheduleType} ${onOff} ${environment}`);
            const parts = slackCommand.text.split(/\s+/);

            const result = parseScheduleCommand(slackCommand, parts);

            expect(result.action).toBe(`schedule-${scheduleType}-${onOff}`);
            expect(result.environment).toBe(environment);
          }
        ),
        { numRuns: 100 }
      );
    });

    it('schedule help returns help action', () => {
      fc.assert(
        fc.property(
          fc.constantFrom('help', '--help', '-h', ''),
          (helpVariant) => {
            const text = helpVariant ? `schedule ${helpVariant}` : 'schedule';
            const slackCommand = slackCommandArb(text);
            const parts = slackCommand.text.split(/\s+/);

            const result = parseScheduleCommand(slackCommand, parts);

            expect(result.action).toBe('schedule-help');
            expect(result.helpMessage).toBeDefined();
          }
        ),
        { numRuns: 100 }
      );
    });

    it('invalid schedule action throws error', () => {
      fc.assert(
        fc.property(
          fc.constantFrom('invalid', 'start', 'stop', 'enable', 'disable', 'status'),
          environmentArb,
          (invalidAction, environment) => {
            const slackCommand = slackCommandArb(`schedule ${invalidAction} ${environment}`);
            const parts = slackCommand.text.split(/\s+/);

            expect(() => parseScheduleCommand(slackCommand, parts)).toThrow('Invalid schedule action');
          }
        ),
        { numRuns: 100 }
      );
    });

    it('missing environment throws error', () => {
      fc.assert(
        fc.property(
          fc.constantFrom('on', 'off', 'check'),
          (action) => {
            const slackCommand = slackCommandArb(`schedule ${action}`);
            const parts = slackCommand.text.split(/\s+/);

            expect(() => parseScheduleCommand(slackCommand, parts)).toThrow('Environment required');
          }
        ),
        { numRuns: 100 }
      );
    });
  });

  /**
   * Property 8: Help Documentation Completeness
   * 
   * For any help command (general or schedule-specific), the response SHALL include
   * command syntax, usage examples, and available options for all schedule commands.
   * 
   * **Validates: Requirements 7.1, 7.2, 7.3**
   */
  describe('Property 8: Help Documentation Completeness', () => {
    
    /**
     * Required schedule command patterns that must be documented
     */
    const requiredScheduleCommandPatterns = [
      'schedule on',
      'schedule off',
      'schedule check',
      'schedule open',
      'schedule close'
    ];

    /**
     * Required duration format examples
     */
    const requiredDurationFormats = ['h', 'd', 'm'];

    it('schedule help message includes all required command syntax', () => {
      const helpMessage = getScheduleHelpMessage();
      const parsed = JSON.parse(helpMessage);
      const helpText = JSON.stringify(parsed).toLowerCase();

      // Verify all required schedule command patterns are documented
      requiredScheduleCommandPatterns.forEach(pattern => {
        expect(helpText).toContain(pattern);
      });
    });

    it('schedule help message includes duration format examples', () => {
      const helpMessage = getScheduleHelpMessage();
      const parsed = JSON.parse(helpMessage);
      const helpText = JSON.stringify(parsed);

      // Verify duration format documentation
      requiredDurationFormats.forEach(format => {
        expect(helpText).toContain(format);
      });

      // Verify specific duration examples are present
      expect(helpText).toMatch(/\d+h/); // Hours example like "2h" or "24h"
      expect(helpText).toMatch(/\d+d/); // Days example like "7d"
      expect(helpText).toMatch(/\d+m/); // Minutes example like "30m"
    });

    it('schedule help message includes granular control commands', () => {
      const helpMessage = getScheduleHelpMessage();
      const parsed = JSON.parse(helpMessage);
      const helpText = JSON.stringify(parsed).toLowerCase();

      // Verify granular schedule control commands are documented
      expect(helpText).toContain('schedule open on');
      expect(helpText).toContain('schedule open off');
      expect(helpText).toContain('schedule close on');
      expect(helpText).toContain('schedule close off');
    });

    it('schedule help message includes environment parameter documentation', () => {
      const helpMessage = getScheduleHelpMessage();
      const parsed = JSON.parse(helpMessage);
      const helpText = JSON.stringify(parsed).toLowerCase();

      // Verify environment parameter is documented
      expect(helpText).toContain('environment');
      expect(helpText).toContain('<env>');
    });

    it('schedule help message has proper Slack response structure', () => {
      const helpMessage = getScheduleHelpMessage();
      const parsed = JSON.parse(helpMessage);

      // Verify Slack response structure
      expect(parsed).toHaveProperty('response_type', 'ephemeral');
      expect(parsed).toHaveProperty('text');
      expect(parsed).toHaveProperty('attachments');
      expect(Array.isArray(parsed.attachments)).toBe(true);
      expect(parsed.attachments.length).toBeGreaterThan(0);

      // Verify attachments have required fields
      parsed.attachments.forEach((attachment: any) => {
        expect(attachment).toHaveProperty('color');
        expect(attachment).toHaveProperty('title');
      });
    });

    it('schedule help message includes usage examples', () => {
      const helpMessage = getScheduleHelpMessage();
      const parsed = JSON.parse(helpMessage);
      const helpText = JSON.stringify(parsed);

      // Verify usage examples are present
      expect(helpText).toContain('/vpn schedule off staging 2h');
      expect(helpText).toContain('/vpn schedule');
    });

    it('for any schedule help variant, help message is returned', () => {
      fc.assert(
        fc.property(
          fc.constantFrom('help', '--help', '-h', ''),
          (helpVariant) => {
            const text = helpVariant ? `schedule ${helpVariant}` : 'schedule';
            const slackCommand = slackCommandArb(text);
            const parts = slackCommand.text.split(/\s+/);

            // Allow all users for this test
            process.env.PRODUCTION_AUTHORIZED_USERS = '*';
            process.env.ADMIN_AUTHORIZED_USERS = '*';

            const result = parseScheduleCommand(slackCommand, parts);

            // Verify help action is returned
            expect(result.action).toBe('schedule-help');
            expect(result.helpMessage).toBeDefined();

            // Verify help message contains required content
            const parsed = JSON.parse(result.helpMessage!);
            expect(parsed.text).toContain('Schedule');
            expect(parsed.attachments.length).toBeGreaterThan(0);

            // Verify help message includes command syntax
            const helpText = JSON.stringify(parsed).toLowerCase();
            expect(helpText).toContain('schedule on');
            expect(helpText).toContain('schedule off');
            expect(helpText).toContain('schedule check');
          }
        ),
        { numRuns: 100 }
      );
    });

    it('help message includes all schedule configuration information', () => {
      const helpMessage = getScheduleHelpMessage();
      const parsed = JSON.parse(helpMessage);
      const helpText = JSON.stringify(parsed);

      // Verify schedule configuration info is documented
      expect(helpText).toContain('9:30'); // Auto-open time
      expect(helpText).toContain('100'); // Idle timeout minutes
      expect(helpText).toContain('17:30'); // Business hours end
      expect(helpText).toContain('Taiwan'); // Timezone reference
    });
  });
});
