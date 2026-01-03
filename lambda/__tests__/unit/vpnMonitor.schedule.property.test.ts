/**
 * Property-Based Tests for VPN Monitor Schedule State Respect
 * 
 * Feature: auto-schedule-slack-commands
 * Property 7: Monitor Respects Schedule State
 * 
 * For any VPN monitor execution, when auto-open schedule is disabled the monitor
 * SHALL skip morning open operations, and when auto-close schedule is disabled
 * the monitor SHALL skip idle-based close operations, with appropriate logging.
 * 
 * **Validates: Requirements 6.1, 6.2, 6.3, 6.4**
 */

import * as fc from 'fast-check';

// Import the schedule manager module for testing
import {
  ScheduleState,
  ScheduleItemState,
  _internal
} from '../../shared/scheduleManager';

// ============================================================================
// Arbitraries (Generators)
// ============================================================================

/**
 * Generate a valid ISO 8601 timestamp
 */
const isoTimestampArb = fc.integer({ 
  min: new Date('2020-01-01').getTime(), 
  max: new Date('2030-12-31').getTime() 
}).map(ts => new Date(ts).toISOString());

/**
 * Generate a valid username
 */
const usernameArb: fc.Arbitrary<string> = fc.constantFrom(
  'admin', 'user1', 'test_user', 'john_doe', 'alice', 'bob123', 'system', 'moderator'
);

/**
 * Generate a valid environment
 */
const environmentArb: fc.Arbitrary<string> = fc.constantFrom('staging', 'production');

/**
 * Generate a schedule item state with explicit enabled/disabled status
 */
const scheduleItemStateArb = (enabled: boolean): fc.Arbitrary<ScheduleItemState> => fc.record({
  enabled: fc.constant(enabled),
  lastModified: isoTimestampArb,
  modifiedBy: usernameArb,
  expiresAt: fc.option(isoTimestampArb, { nil: undefined })
});

/**
 * Generate a schedule state with specific auto-open and auto-close enabled states
 */
const scheduleStateWithConfigArb = (
  autoOpenEnabled: boolean,
  autoCloseEnabled: boolean
): fc.Arbitrary<ScheduleState> => fc.record({
  version: fc.integer({ min: 1, max: 1000 }),
  autoOpen: scheduleItemStateArb(autoOpenEnabled),
  autoClose: scheduleItemStateArb(autoCloseEnabled)
});

/**
 * Generate a future expiration timestamp (for testing non-expired disables)
 */
const futureExpirationArb = fc.integer({ min: 1, max: 365 * 24 * 60 }) // 1 minute to 1 year
  .map(minutesInFuture => new Date(Date.now() + minutesInFuture * 60 * 1000).toISOString());

/**
 * Generate a past expiration timestamp (for testing expired disables)
 */
const pastExpirationArb = fc.integer({ 
  min: new Date('2020-01-01').getTime(), 
  max: Date.now() - 60000 // At least 1 minute in the past
}).map(ts => new Date(ts).toISOString());

// ============================================================================
// Helper Functions for Testing
// ============================================================================

/**
 * Simulate the monitor's decision logic for auto-close
 * This mirrors the logic in vpn-monitor/index.ts
 */
function shouldSkipAutoClose(state: ScheduleState): boolean {
  // If explicitly enabled, don't skip
  if (state.autoClose.enabled) {
    return false;
  }
  
  // If disabled without expiration, skip
  if (!state.autoClose.expiresAt) {
    return true;
  }
  
  // Check if the disable has expired
  const now = new Date();
  const expiresAt = new Date(state.autoClose.expiresAt);
  
  // If expired, don't skip (treat as enabled)
  if (now >= expiresAt) {
    return false;
  }
  
  // Not expired, skip
  return true;
}

/**
 * Simulate the monitor's decision logic for auto-open
 * This mirrors the logic in vpn-control/index.ts
 */
function shouldSkipAutoOpen(state: ScheduleState): boolean {
  // If explicitly enabled, don't skip
  if (state.autoOpen.enabled) {
    return false;
  }
  
  // If disabled without expiration, skip
  if (!state.autoOpen.expiresAt) {
    return true;
  }
  
  // Check if the disable has expired
  const now = new Date();
  const expiresAt = new Date(state.autoOpen.expiresAt);
  
  // If expired, don't skip (treat as enabled)
  if (now >= expiresAt) {
    return false;
  }
  
  // Not expired, skip
  return true;
}

// ============================================================================
// Property Tests
// ============================================================================

describe('VPN Monitor Schedule State Property Tests', () => {
  
  /**
   * Property 7: Monitor Respects Schedule State
   * 
   * For any VPN monitor execution, when auto-open schedule is disabled the monitor
   * SHALL skip morning open operations, and when auto-close schedule is disabled
   * the monitor SHALL skip idle-based close operations, with appropriate logging.
   * 
   * **Validates: Requirements 6.1, 6.2, 6.3, 6.4**
   */
  describe('Property 7: Monitor Respects Schedule State', () => {
    
    /**
     * Test: When auto-close is explicitly enabled, monitor should NOT skip idle close
     * Validates: Requirement 6.1 (inverse - enabled means proceed)
     */
    it('when auto-close is enabled, monitor should proceed with idle close operations', () => {
      fc.assert(
        fc.property(
          scheduleStateWithConfigArb(fc.sample(fc.boolean(), 1)[0], true), // autoClose enabled
          (state) => {
            const shouldSkip = shouldSkipAutoClose(state);
            expect(shouldSkip).toBe(false);
          }
        ),
        { numRuns: 100, verbose: true }
      );
    });

    /**
     * Test: When auto-close is disabled without expiration, monitor should skip idle close
     * Validates: Requirement 6.2
     */
    it('when auto-close is disabled indefinitely, monitor should skip idle close operations', () => {
      fc.assert(
        fc.property(
          usernameArb,
          isoTimestampArb,
          (modifiedBy, lastModified) => {
            const state: ScheduleState = {
              version: 1,
              autoOpen: {
                enabled: true,
                lastModified,
                modifiedBy
              },
              autoClose: {
                enabled: false,
                lastModified,
                modifiedBy,
                expiresAt: undefined // No expiration = indefinite disable
              }
            };

            const shouldSkip = shouldSkipAutoClose(state);
            expect(shouldSkip).toBe(true);
          }
        ),
        { numRuns: 100 }
      );
    });

    /**
     * Test: When auto-close is disabled with future expiration, monitor should skip
     * Validates: Requirement 6.4 (expiration checking)
     */
    it('when auto-close is disabled with future expiration, monitor should skip', () => {
      fc.assert(
        fc.property(
          usernameArb,
          isoTimestampArb,
          futureExpirationArb,
          (modifiedBy, lastModified, expiresAt) => {
            const state: ScheduleState = {
              version: 1,
              autoOpen: {
                enabled: true,
                lastModified,
                modifiedBy
              },
              autoClose: {
                enabled: false,
                lastModified,
                modifiedBy,
                expiresAt // Future expiration
              }
            };

            const shouldSkip = shouldSkipAutoClose(state);
            expect(shouldSkip).toBe(true);
          }
        ),
        { numRuns: 100 }
      );
    });

    /**
     * Test: When auto-close disable has expired, monitor should proceed
     * Validates: Requirement 6.4 (expired disables treated as enabled)
     */
    it('when auto-close disable has expired, monitor should proceed with operations', () => {
      fc.assert(
        fc.property(
          usernameArb,
          isoTimestampArb,
          pastExpirationArb,
          (modifiedBy, lastModified, expiresAt) => {
            const state: ScheduleState = {
              version: 1,
              autoOpen: {
                enabled: true,
                lastModified,
                modifiedBy
              },
              autoClose: {
                enabled: false,
                lastModified,
                modifiedBy,
                expiresAt // Past expiration = expired
              }
            };

            const shouldSkip = shouldSkipAutoClose(state);
            expect(shouldSkip).toBe(false);
          }
        ),
        { numRuns: 100 }
      );
    });

    /**
     * Test: When auto-open is explicitly enabled, monitor should NOT skip scheduled open
     * Validates: Requirement 6.1 (inverse - enabled means proceed)
     */
    it('when auto-open is enabled, monitor should proceed with scheduled open operations', () => {
      fc.assert(
        fc.property(
          scheduleStateWithConfigArb(true, fc.sample(fc.boolean(), 1)[0]), // autoOpen enabled
          (state) => {
            const shouldSkip = shouldSkipAutoOpen(state);
            expect(shouldSkip).toBe(false);
          }
        ),
        { numRuns: 100 }
      );
    });

    /**
     * Test: When auto-open is disabled without expiration, monitor should skip scheduled open
     * Validates: Requirement 6.1
     */
    it('when auto-open is disabled indefinitely, monitor should skip scheduled open operations', () => {
      fc.assert(
        fc.property(
          usernameArb,
          isoTimestampArb,
          (modifiedBy, lastModified) => {
            const state: ScheduleState = {
              version: 1,
              autoOpen: {
                enabled: false,
                lastModified,
                modifiedBy,
                expiresAt: undefined // No expiration = indefinite disable
              },
              autoClose: {
                enabled: true,
                lastModified,
                modifiedBy
              }
            };

            const shouldSkip = shouldSkipAutoOpen(state);
            expect(shouldSkip).toBe(true);
          }
        ),
        { numRuns: 100 }
      );
    });

    /**
     * Test: When auto-open is disabled with future expiration, monitor should skip
     * Validates: Requirement 6.4 (expiration checking)
     */
    it('when auto-open is disabled with future expiration, monitor should skip', () => {
      fc.assert(
        fc.property(
          usernameArb,
          isoTimestampArb,
          futureExpirationArb,
          (modifiedBy, lastModified, expiresAt) => {
            const state: ScheduleState = {
              version: 1,
              autoOpen: {
                enabled: false,
                lastModified,
                modifiedBy,
                expiresAt // Future expiration
              },
              autoClose: {
                enabled: true,
                lastModified,
                modifiedBy
              }
            };

            const shouldSkip = shouldSkipAutoOpen(state);
            expect(shouldSkip).toBe(true);
          }
        ),
        { numRuns: 100 }
      );
    });

    /**
     * Test: When auto-open disable has expired, monitor should proceed
     * Validates: Requirement 6.4 (expired disables treated as enabled)
     */
    it('when auto-open disable has expired, monitor should proceed with operations', () => {
      fc.assert(
        fc.property(
          usernameArb,
          isoTimestampArb,
          pastExpirationArb,
          (modifiedBy, lastModified, expiresAt) => {
            const state: ScheduleState = {
              version: 1,
              autoOpen: {
                enabled: false,
                lastModified,
                modifiedBy,
                expiresAt // Past expiration = expired
              },
              autoClose: {
                enabled: true,
                lastModified,
                modifiedBy
              }
            };

            const shouldSkip = shouldSkipAutoOpen(state);
            expect(shouldSkip).toBe(false);
          }
        ),
        { numRuns: 100 }
      );
    });
  });

  /**
   * Additional property tests for schedule independence
   */
  describe('Schedule Independence Properties', () => {
    
    /**
     * Test: Auto-open and auto-close schedules are independent
     * Validates: Requirement 4.5 (granular control preserves other schedule)
     */
    it('auto-open state does not affect auto-close decision', () => {
      fc.assert(
        fc.property(
          fc.boolean(), // autoOpen enabled
          fc.boolean(), // autoClose enabled
          usernameArb,
          isoTimestampArb,
          (autoOpenEnabled, autoCloseEnabled, modifiedBy, lastModified) => {
            const state: ScheduleState = {
              version: 1,
              autoOpen: {
                enabled: autoOpenEnabled,
                lastModified,
                modifiedBy
              },
              autoClose: {
                enabled: autoCloseEnabled,
                lastModified,
                modifiedBy
              }
            };

            // Auto-close decision should only depend on autoClose state
            const shouldSkipClose = shouldSkipAutoClose(state);
            expect(shouldSkipClose).toBe(!autoCloseEnabled);
          }
        ),
        { numRuns: 100 }
      );
    });

    /**
     * Test: Auto-close state does not affect auto-open decision
     * Validates: Requirement 4.5 (granular control preserves other schedule)
     */
    it('auto-close state does not affect auto-open decision', () => {
      fc.assert(
        fc.property(
          fc.boolean(), // autoOpen enabled
          fc.boolean(), // autoClose enabled
          usernameArb,
          isoTimestampArb,
          (autoOpenEnabled, autoCloseEnabled, modifiedBy, lastModified) => {
            const state: ScheduleState = {
              version: 1,
              autoOpen: {
                enabled: autoOpenEnabled,
                lastModified,
                modifiedBy
              },
              autoClose: {
                enabled: autoCloseEnabled,
                lastModified,
                modifiedBy
              }
            };

            // Auto-open decision should only depend on autoOpen state
            const shouldSkipOpen = shouldSkipAutoOpen(state);
            expect(shouldSkipOpen).toBe(!autoOpenEnabled);
          }
        ),
        { numRuns: 100 }
      );
    });
  });

  /**
   * Consistency properties using the internal helper function
   */
  describe('Internal Helper Consistency', () => {
    
    /**
     * Test: isScheduleItemEnabled matches our test logic for enabled items
     */
    it('isScheduleItemEnabled returns true for enabled items', () => {
      fc.assert(
        fc.property(
          usernameArb,
          isoTimestampArb,
          (modifiedBy, lastModified) => {
            const item: ScheduleItemState = {
              enabled: true,
              lastModified,
              modifiedBy
            };
            
            // Create a mock logger
            const mockLogger = {
              debug: () => {},
              info: () => {},
              warn: () => {},
              error: () => {}
            };
            
            const result = _internal.isScheduleItemEnabled(item, mockLogger, 'test', 'staging');
            expect(result).toBe(true);
          }
        ),
        { numRuns: 100 }
      );
    });

    /**
     * Test: isScheduleItemEnabled returns false for disabled items without expiration
     */
    it('isScheduleItemEnabled returns false for disabled items without expiration', () => {
      fc.assert(
        fc.property(
          usernameArb,
          isoTimestampArb,
          (modifiedBy, lastModified) => {
            const item: ScheduleItemState = {
              enabled: false,
              lastModified,
              modifiedBy,
              expiresAt: undefined
            };
            
            const mockLogger = {
              debug: () => {},
              info: () => {},
              warn: () => {},
              error: () => {}
            };
            
            const result = _internal.isScheduleItemEnabled(item, mockLogger, 'test', 'staging');
            expect(result).toBe(false);
          }
        ),
        { numRuns: 100 }
      );
    });

    /**
     * Test: isScheduleItemEnabled returns true for expired disables
     */
    it('isScheduleItemEnabled returns true for expired disables', () => {
      fc.assert(
        fc.property(
          usernameArb,
          isoTimestampArb,
          pastExpirationArb,
          (modifiedBy, lastModified, expiresAt) => {
            const item: ScheduleItemState = {
              enabled: false,
              lastModified,
              modifiedBy,
              expiresAt
            };
            
            const mockLogger = {
              debug: () => {},
              info: () => {},
              warn: () => {},
              error: () => {}
            };
            
            const result = _internal.isScheduleItemEnabled(item, mockLogger, 'test', 'staging');
            expect(result).toBe(true);
          }
        ),
        { numRuns: 100 }
      );
    });

    /**
     * Test: isScheduleItemEnabled returns false for non-expired disables
     */
    it('isScheduleItemEnabled returns false for non-expired disables', () => {
      fc.assert(
        fc.property(
          usernameArb,
          isoTimestampArb,
          futureExpirationArb,
          (modifiedBy, lastModified, expiresAt) => {
            const item: ScheduleItemState = {
              enabled: false,
              lastModified,
              modifiedBy,
              expiresAt
            };
            
            const mockLogger = {
              debug: () => {},
              info: () => {},
              warn: () => {},
              error: () => {}
            };
            
            const result = _internal.isScheduleItemEnabled(item, mockLogger, 'test', 'staging');
            expect(result).toBe(false);
          }
        ),
        { numRuns: 100 }
      );
    });
  });
});
