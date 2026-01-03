# Implementation Plan: Auto-Schedule Slack Commands

## Overview

This implementation plan breaks down the auto-schedule Slack commands feature into discrete coding tasks. The implementation follows the existing codebase patterns, extending the Lambda-based architecture with new schedule management capabilities.

## Tasks

- [x] 1. Create Schedule Manager Module
  - [x] 1.1 Create scheduleManager.ts with core interfaces and types
    - Create `lambda/shared/scheduleManager.ts`
    - Define ScheduleState and ScheduleConfig interfaces
    - Export type definitions
    - _Requirements: 5.1, 5.4_

  - [x] 1.2 Implement schedule state read/write functions
    - Implement `readScheduleState(environment)` function
    - Implement `writeScheduleState(environment, state)` function
    - Handle Parameter Store path `/vpn/automation/schedule/{environment}/state`
    - Include error handling for missing/invalid state
    - _Requirements: 5.2, 5.3_

  - [x] 1.3 Write property test for state persistence round-trip
    - **Property 2: State Persistence Round-Trip**
    - **Validates: Requirements 1.2, 2.4, 5.3, 5.4**

  - [x] 1.4 Implement schedule enabled check functions
    - Implement `isAutoOpenEnabled(environment)` with expiration check
    - Implement `isAutoCloseEnabled(environment)` with expiration check
    - Handle expired states by returning enabled=true
    - _Requirements: 2.3, 6.4_

  - [x] 1.5 Implement enable/disable schedule functions
    - Implement `enableSchedule(environment, scheduleType, modifiedBy)`
    - Implement `disableSchedule(environment, scheduleType, modifiedBy, duration?)`
    - Support 'autoOpen', 'autoClose', and 'both' schedule types
    - _Requirements: 1.1, 1.2, 2.1, 2.4, 4.1, 4.2, 4.3, 4.4_

  - [x] 1.6 Write property test for schedule state mutation
    - **Property 1: Schedule State Mutation Correctness**
    - **Validates: Requirements 1.1, 2.1, 4.1, 4.2, 4.3, 4.4, 4.5**

  - [x] 1.7 Implement duration parsing utility
    - Parse duration strings like "2h", "24h", "7d"
    - Calculate expiration timestamp from duration
    - Return null for invalid formats
    - _Requirements: 2.2_

  - [x] 1.8 Write property test for duration parsing and expiration
    - **Property 3: Duration Parsing and Expiration**
    - **Validates: Requirements 2.2, 2.3**

  - [x] 1.9 Implement schedule status retrieval
    - Implement `getScheduleStatus(environment)` function
    - Calculate next scheduled open time
    - Include business hours protection status
    - Calculate remaining disable time if applicable
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 2. Checkpoint - Schedule Manager Module Complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 3. Extend Types and Slack Command Parser
  - [x] 3.1 Update types.ts with schedule command types
    - Add schedule action types to VpnCommandRequest
    - Add ScheduleStatusData interface
    - Add duration field to VpnCommandRequest
    - _Requirements: 1.1, 2.1, 3.1_

  - [x] 3.2 Implement schedule command parsing in slack.ts
    - Add `parseScheduleCommand` function
    - Handle `/vpn schedule on|off|check <environment>`
    - Handle `/vpn schedule open|close on|off <environment>`
    - Handle `/vpn schedule off <environment> <duration>`
    - Handle `/vpn schedule help`
    - _Requirements: 1.1, 2.1, 2.2, 3.1, 4.1, 4.2, 4.3, 4.4_

  - [x] 3.3 Add authorization check for schedule commands
    - Reuse existing `isAuthorizedForProduction` function
    - Add `isAuthorizedForSchedule` function if needed
    - _Requirements: 1.4, 2.6_

  - [x] 3.4 Write property test for authorization enforcement
    - **Property 4: Authorization Enforcement**
    - **Validates: Requirements 1.4, 2.6**

  - [x] 3.5 Implement schedule response formatting
    - Add `formatScheduleResponse` function in slack.ts
    - Format enable/disable confirmation messages
    - Format status check response with all fields
    - Include bilingual support (English and Traditional Chinese)
    - _Requirements: 1.3, 2.5, 3.2, 3.3, 3.4, 3.5, 3.6_

  - [x] 3.6 Write property test for status response completeness
    - **Property 5: Status Response Completeness**
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**

  - [x] 3.7 Write property test for bilingual response format
    - **Property 6: Bilingual Response Format**
    - **Validates: Requirements 3.6, 7.4**

- [x] 4. Checkpoint - Types and Parser Complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Integrate with Slack Handler
  - [x] 5.1 Add schedule command routing in slack-handler/index.ts
    - Import scheduleManager from Lambda layer
    - Add routing for schedule-* actions
    - Handle schedule commands synchronously (quick operations)
    - _Requirements: 1.1, 2.1, 3.1_

  - [x] 5.2 Implement schedule command handlers
    - Implement handler for schedule-on
    - Implement handler for schedule-off (with optional duration)
    - Implement handler for schedule-check
    - Implement handlers for granular schedule commands
    - _Requirements: 1.1, 2.1, 3.1, 4.1, 4.2, 4.3, 4.4_

  - [x] 5.3 Write integration test for schedule commands
    - Test end-to-end flow for enable/disable/check
    - Test authorization enforcement
    - Test error handling
    - _Requirements: 1.1, 1.4, 2.1, 3.1_

- [x] 6. Integrate with VPN Monitor
  - [x] 6.1 Add schedule state check to vpn-monitor/index.ts
    - Import scheduleManager from Lambda layer
    - Check auto-close enabled before idle disassociation
    - Log skipped operations with reason
    - _Requirements: 6.1, 6.2, 6.3_

  - [x] 6.2 Add schedule state check to auto-open logic
    - Check auto-open enabled before scheduled open
    - Handle expiration checking
    - _Requirements: 6.1, 6.4_

  - [x] 6.3 Write property test for monitor respects schedule state
    - **Property 7: Monitor Respects Schedule State**
    - **Validates: Requirements 6.1, 6.2, 6.3, 6.4**

- [x] 7. Checkpoint - Lambda Integration Complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Update Help Documentation
  - [x] 8.1 Update getHelpMessage in slack.ts
    - Add schedule commands section to help
    - Include command syntax and examples
    - Maintain bilingual format
    - _Requirements: 7.1, 7.3, 7.4_

  - [x] 8.2 Implement getScheduleHelpMessage function
    - Create detailed schedule-specific help
    - Include all schedule command variants
    - Include duration format examples
    - _Requirements: 7.2, 7.3_

  - [x] 8.3 Write property test for help documentation completeness
    - **Property 8: Help Documentation Completeness**
    - **Validates: Requirements 7.1, 7.2, 7.3**

- [x] 9. Build Lambda Layer
  - [x] 9.1 Update shared module build configuration
    - Add scheduleManager.ts to build
    - Update tsconfig.json if needed
    - Run build-layer.sh to create updated layer
    - _Requirements: 5.1_

  - [x] 9.2 Update layer-package exports
    - Add scheduleManager exports to layer-package/nodejs
    - Verify all exports are accessible
    - _Requirements: 5.1_

- [x] 10. Update Project Documentation
  - [x] 10.1 Update README.md
    - Add schedule commands to Slack integration section
    - Include command examples
    - _Requirements: 8.1_

  - [x] 10.2 Update docs/admin-guide.md
    - Add schedule management section
    - Document administrative procedures
    - Include troubleshooting guidance
    - _Requirements: 8.2, 8.4_

  - [x] 10.3 Update docs/user-guide.md
    - Add schedule commands for end users
    - Include common usage scenarios
    - Maintain bilingual format
    - _Requirements: 8.3, 8.4, 8.5_

- [x] 11. Final Checkpoint - All Tests Pass
  - Ensure all tests pass, ask the user if questions arise.
  - Verify all documentation is updated
  - Verify Lambda layer builds successfully

## Notes

- All tasks including property-based tests are required for comprehensive coverage
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties
- Unit tests validate specific examples and edge cases
- The implementation follows existing codebase patterns for consistency
