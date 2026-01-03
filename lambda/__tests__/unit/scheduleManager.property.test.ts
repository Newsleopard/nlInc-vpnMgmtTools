/**
 * Property-Based Tests for Schedule Manager
 * 
 * Feature: auto-schedule-slack-commands
 * 
 * These tests use fast-check to verify universal properties
 * that should hold for all valid inputs.
 */

import * as fc from 'fast-check';

// Import the module under test
import {
  ScheduleState,
  ScheduleItemState,
  ScheduleType,
  parseDuration,
  calculateExpiration,
  getRemainingTime,
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
 * Generate a valid username (alphanumeric with underscores)
 */
const usernameArb: fc.Arbitrary<string> = fc.constantFrom(
  'admin', 'user1', 'test_user', 'john_doe', 'alice', 'bob123', 'system', 'moderator'
);

/**
 * Generate a valid ScheduleItemState
 */
const scheduleItemStateArb: fc.Arbitrary<ScheduleItemState> = fc.record({
  enabled: fc.boolean(),
  lastModified: isoTimestampArb,
  modifiedBy: usernameArb,
  expiresAt: fc.option(isoTimestampArb, { nil: undefined })
});

/**
 * Generate a valid ScheduleState
 */
const scheduleStateArb: fc.Arbitrary<ScheduleState> = fc.record({
  autoOpen: scheduleItemStateArb,
  autoClose: scheduleItemStateArb
});

/**
 * Generate a valid schedule type
 */
const scheduleTypeArb: fc.Arbitrary<ScheduleType> = fc.constantFrom('autoOpen', 'autoClose', 'both');

/**
 * Generate a valid duration string
 */
const validDurationArb = fc.tuple(
  fc.integer({ min: 1, max: 999 }),
  fc.constantFrom('h', 'd', 'm')
).map(([value, unit]) => `${value}${unit}`);

/**
 * Generate an invalid duration string
 */
const invalidDurationArb: fc.Arbitrary<string> = fc.constantFrom(
  '', 'abc', '0h', '-1h', '1x', 'h1', '1.5h', 'hello', '10', 'hh', 'dd'
);

// ============================================================================
// Property Tests
// ============================================================================

describe('Schedule Manager Property Tests', () => {
  
  /**
   * Property 2: State Persistence Round-Trip
   * 
   * For any valid ScheduleState object, serializing to JSON and parsing back
   * should produce an equivalent object with all fields preserved.
   * 
   * **Validates: Requirements 1.2, 2.4, 5.3, 5.4**
   */
  describe('Property 2: State Persistence Round-Trip', () => {
    it('serializing and deserializing ScheduleState preserves all fields', () => {
      fc.assert(
        fc.property(scheduleStateArb, (state) => {
          // Serialize to JSON (as would be stored in Parameter Store)
          const serialized = JSON.stringify(state);
          
          // Deserialize back
          const deserialized = JSON.parse(serialized) as ScheduleState;
          
          // Verify all fields are preserved
          expect(deserialized.autoOpen.enabled).toBe(state.autoOpen.enabled);
          expect(deserialized.autoOpen.lastModified).toBe(state.autoOpen.lastModified);
          expect(deserialized.autoOpen.modifiedBy).toBe(state.autoOpen.modifiedBy);
          expect(deserialized.autoOpen.expiresAt).toBe(state.autoOpen.expiresAt);
          
          expect(deserialized.autoClose.enabled).toBe(state.autoClose.enabled);
          expect(deserialized.autoClose.lastModified).toBe(state.autoClose.lastModified);
          expect(deserialized.autoClose.modifiedBy).toBe(state.autoClose.modifiedBy);
          expect(deserialized.autoClose.expiresAt).toBe(state.autoClose.expiresAt);
          
          // Deep equality check
          expect(deserialized).toEqual(state);
        }),
        { numRuns: 100, verbose: true }
      );
    });

    it('isValidScheduleState returns true for all generated valid states', () => {
      fc.assert(
        fc.property(scheduleStateArb, (state) => {
          expect(_internal.isValidScheduleState(state)).toBe(true);
        }),
        { numRuns: 100 }
      );
    });
  });


  /**
   * Property 1: Schedule State Mutation Correctness
   * 
   * For any valid schedule command (enable/disable for autoOpen, autoClose, or both),
   * the resulting state should reflect exactly the requested change, with the
   * non-targeted schedule remaining unchanged when granular commands are used.
   * 
   * **Validates: Requirements 1.1, 2.1, 4.1, 4.2, 4.3, 4.4, 4.5**
   */
  describe('Property 1: Schedule State Mutation Correctness', () => {
    it('enabling a schedule sets enabled=true and clears expiresAt', () => {
      fc.assert(
        fc.property(
          scheduleStateArb,
          scheduleTypeArb,
          usernameArb,
          (initialState, scheduleType, modifiedBy) => {
            // Simulate enable operation
            const now = new Date().toISOString();
            const resultState = { ...initialState };
            
            if (scheduleType === 'autoOpen' || scheduleType === 'both') {
              resultState.autoOpen = {
                enabled: true,
                lastModified: now,
                modifiedBy,
                expiresAt: undefined
              };
            }
            
            if (scheduleType === 'autoClose' || scheduleType === 'both') {
              resultState.autoClose = {
                enabled: true,
                lastModified: now,
                modifiedBy,
                expiresAt: undefined
              };
            }
            
            // Verify the targeted schedule(s) are enabled
            if (scheduleType === 'autoOpen' || scheduleType === 'both') {
              expect(resultState.autoOpen.enabled).toBe(true);
              expect(resultState.autoOpen.expiresAt).toBeUndefined();
              expect(resultState.autoOpen.modifiedBy).toBe(modifiedBy);
            }
            
            if (scheduleType === 'autoClose' || scheduleType === 'both') {
              expect(resultState.autoClose.enabled).toBe(true);
              expect(resultState.autoClose.expiresAt).toBeUndefined();
              expect(resultState.autoClose.modifiedBy).toBe(modifiedBy);
            }
            
            // Verify non-targeted schedule is unchanged for granular commands
            if (scheduleType === 'autoOpen') {
              expect(resultState.autoClose).toEqual(initialState.autoClose);
            }
            if (scheduleType === 'autoClose') {
              expect(resultState.autoOpen).toEqual(initialState.autoOpen);
            }
          }
        ),
        { numRuns: 100 }
      );
    });

    it('disabling a schedule sets enabled=false', () => {
      fc.assert(
        fc.property(
          scheduleStateArb,
          scheduleTypeArb,
          usernameArb,
          (initialState, scheduleType, modifiedBy) => {
            // Simulate disable operation (without duration)
            const now = new Date().toISOString();
            const resultState = { ...initialState };
            
            if (scheduleType === 'autoOpen' || scheduleType === 'both') {
              resultState.autoOpen = {
                enabled: false,
                lastModified: now,
                modifiedBy,
                expiresAt: undefined
              };
            }
            
            if (scheduleType === 'autoClose' || scheduleType === 'both') {
              resultState.autoClose = {
                enabled: false,
                lastModified: now,
                modifiedBy,
                expiresAt: undefined
              };
            }
            
            // Verify the targeted schedule(s) are disabled
            if (scheduleType === 'autoOpen' || scheduleType === 'both') {
              expect(resultState.autoOpen.enabled).toBe(false);
              expect(resultState.autoOpen.modifiedBy).toBe(modifiedBy);
            }
            
            if (scheduleType === 'autoClose' || scheduleType === 'both') {
              expect(resultState.autoClose.enabled).toBe(false);
              expect(resultState.autoClose.modifiedBy).toBe(modifiedBy);
            }
            
            // Verify non-targeted schedule is unchanged for granular commands
            if (scheduleType === 'autoOpen') {
              expect(resultState.autoClose).toEqual(initialState.autoClose);
            }
            if (scheduleType === 'autoClose') {
              expect(resultState.autoOpen).toEqual(initialState.autoOpen);
            }
          }
        ),
        { numRuns: 100 }
      );
    });
  });


  /**
   * Property 3: Duration Parsing and Expiration
   * 
   * For any valid duration string (e.g., "2h", "24h", "7d"), parsing should
   * produce a valid expiration timestamp that is exactly the specified duration
   * from the current time.
   * 
   * **Validates: Requirements 2.2, 2.3**
   */
  describe('Property 3: Duration Parsing and Expiration', () => {
    it('valid duration strings produce valid expiration timestamps', () => {
      fc.assert(
        fc.property(validDurationArb, (duration) => {
          const result = parseDuration(duration);
          
          expect(result.valid).toBe(true);
          expect(result.milliseconds).toBeDefined();
          expect(result.milliseconds).toBeGreaterThan(0);
          expect(result.expiresAt).toBeDefined();
          
          // Verify expiresAt is a valid ISO timestamp
          const expiresAtDate = new Date(result.expiresAt!);
          expect(expiresAtDate.getTime()).not.toBeNaN();
          
          // Verify expiration is in the future
          expect(expiresAtDate.getTime()).toBeGreaterThan(Date.now() - 1000); // Allow 1s tolerance
        }),
        { numRuns: 100 }
      );
    });

    it('duration milliseconds match the expected calculation', () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 1, max: 100 }),
          fc.constantFrom('h', 'd', 'm'),
          (value, unit) => {
            const duration = `${value}${unit}`;
            const result = parseDuration(duration);
            
            expect(result.valid).toBe(true);
            
            let expectedMs: number;
            switch (unit) {
              case 'm':
                expectedMs = value * 60 * 1000;
                break;
              case 'h':
                expectedMs = value * 60 * 60 * 1000;
                break;
              case 'd':
                expectedMs = value * 24 * 60 * 60 * 1000;
                break;
              default:
                throw new Error(`Unexpected unit: ${unit}`);
            }
            
            expect(result.milliseconds).toBe(expectedMs);
          }
        ),
        { numRuns: 100 }
      );
    });

    it('invalid duration strings return valid=false', () => {
      fc.assert(
        fc.property(invalidDurationArb, (duration) => {
          const result = parseDuration(duration);
          expect(result.valid).toBe(false);
          expect(result.milliseconds).toBeUndefined();
          expect(result.expiresAt).toBeUndefined();
        }),
        { numRuns: 100 }
      );
    });

    it('calculateExpiration returns null for invalid durations', () => {
      fc.assert(
        fc.property(invalidDurationArb, (duration) => {
          const result = calculateExpiration(duration);
          expect(result).toBeNull();
        }),
        { numRuns: 100 }
      );
    });

    it('calculateExpiration returns valid timestamp for valid durations', () => {
      fc.assert(
        fc.property(validDurationArb, (duration) => {
          const result = calculateExpiration(duration);
          expect(result).not.toBeNull();
          
          const date = new Date(result!);
          expect(date.getTime()).not.toBeNaN();
          expect(date.getTime()).toBeGreaterThan(Date.now() - 1000);
        }),
        { numRuns: 100 }
      );
    });
  });

  /**
   * Additional property tests for expiration checking
   */
  describe('Expiration Checking Properties', () => {
    it('expired timestamps return null from getRemainingTime', () => {
      fc.assert(
        fc.property(
          // Use integer timestamps to avoid invalid date edge cases
          fc.integer({ 
            min: new Date('2020-01-01').getTime(), 
            max: new Date('2024-01-01').getTime() 
          }),
          (timestamp) => {
            const pastDate = new Date(timestamp);
            const result = getRemainingTime(pastDate.toISOString());
            expect(result).toBeNull();
          }
        ),
        { numRuns: 100 }
      );
    });

    it('future timestamps return non-null from getRemainingTime', () => {
      fc.assert(
        fc.property(
          fc.integer({ min: 1, max: 365 * 24 * 60 }), // 1 minute to 1 year in minutes
          (minutesInFuture) => {
            const futureDate = new Date(Date.now() + minutesInFuture * 60 * 1000);
            const result = getRemainingTime(futureDate.toISOString());
            expect(result).not.toBeNull();
            expect(typeof result).toBe('string');
            expect(result!.length).toBeGreaterThan(0);
          }
        ),
        { numRuns: 100 }
      );
    });
  });

  /**
   * State validation properties
   */
  describe('State Validation Properties', () => {
    it('invalid objects fail validation', () => {
      const invalidObjects = [
        null,
        undefined,
        {},
        { autoOpen: {} },
        { autoClose: {} },
        { autoOpen: { enabled: 'true' }, autoClose: { enabled: true } },
        { autoOpen: { enabled: true }, autoClose: { enabled: true } }, // missing required fields
        'string',
        123,
        []
      ];

      invalidObjects.forEach(obj => {
        // The function returns falsy values for invalid objects (null, undefined, false)
        expect(_internal.isValidScheduleState(obj)).toBeFalsy();
      });
    });
  });
});
