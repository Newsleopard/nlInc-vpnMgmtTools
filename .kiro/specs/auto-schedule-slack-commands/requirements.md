# Requirements Document

## Introduction

This feature adds Slack commands to manage VPN auto-scheduling functionality, allowing users to enable, disable, and check the status of automatic VPN open/close schedules. The system currently has auto-open (weekday 9:30 AM Taiwan time) and auto-close (after idle timeout) capabilities, but lacks user-facing commands to control these schedules dynamically.

## Glossary

- **Auto_Schedule_System**: The automated scheduling component that controls when VPN endpoints are automatically opened or closed based on time-based rules and idle detection
- **Auto_Open_Schedule**: The scheduled rule that automatically opens VPN at 9:30 AM Taiwan time on weekdays (Monday-Friday)
- **Auto_Close_Schedule**: The idle-based rule that automatically closes VPN after a configurable period of inactivity (default 100 minutes)
- **Schedule_State**: The current enabled/disabled status of auto-open and auto-close schedules stored in Parameter Store
- **Slack_Handler**: The Lambda function that processes incoming Slack slash commands
- **VPN_Monitor**: The Lambda function that executes scheduled monitoring and auto-close logic
- **Business_Hours_Protection**: The safety mechanism that prevents auto-close during business hours (9:30 AM - 5:30 PM)

## Requirements

### Requirement 1: Enable Auto-Schedule

**User Story:** As a VPN administrator, I want to enable auto-scheduling via Slack, so that I can restore automatic VPN management after temporarily disabling it.

#### Acceptance Criteria

1. WHEN a user sends `/vpn schedule on <environment>`, THE Slack_Handler SHALL enable both auto-open and auto-close schedules for the specified environment
2. WHEN auto-schedule is enabled, THE Auto_Schedule_System SHALL store the enabled state in Parameter Store with a timestamp
3. WHEN auto-schedule is successfully enabled, THE Slack_Handler SHALL respond with a confirmation message showing the current schedule configuration
4. IF the user is not authorized for the specified environment, THEN THE Slack_Handler SHALL return an access denied error message

### Requirement 2: Disable Auto-Schedule

**User Story:** As a VPN administrator, I want to disable auto-scheduling via Slack, so that I can prevent automatic VPN state changes during maintenance or special circumstances.

#### Acceptance Criteria

1. WHEN a user sends `/vpn schedule off <environment>`, THE Slack_Handler SHALL disable both auto-open and auto-close schedules for the specified environment
2. WHEN a user sends `/vpn schedule off <environment> <duration>`, THE Slack_Handler SHALL disable schedules for the specified duration (e.g., "2h", "24h", "7d")
3. WHEN auto-schedule is disabled with a duration, THE Auto_Schedule_System SHALL automatically re-enable after the duration expires
4. WHEN auto-schedule is disabled, THE Auto_Schedule_System SHALL store the disabled state with expiration timestamp in Parameter Store
5. WHEN auto-schedule is successfully disabled, THE Slack_Handler SHALL respond with a confirmation message showing when it will be re-enabled (if duration specified)
6. IF the user is not authorized for the specified environment, THEN THE Slack_Handler SHALL return an access denied error message

### Requirement 3: Check Auto-Schedule Status

**User Story:** As a VPN user, I want to check the current auto-schedule status via Slack, so that I can understand when VPN will automatically open or close.

#### Acceptance Criteria

1. WHEN a user sends `/vpn schedule check <environment>`, THE Slack_Handler SHALL return the current auto-schedule status
2. WHEN displaying schedule status, THE Slack_Handler SHALL show auto-open enabled/disabled state with next scheduled open time
3. WHEN displaying schedule status, THE Slack_Handler SHALL show auto-close enabled/disabled state with idle timeout configuration
4. WHEN displaying schedule status, THE Slack_Handler SHALL show business hours protection status
5. WHEN auto-schedule is disabled with expiration, THE Slack_Handler SHALL show the remaining time until re-enabled
6. THE Slack_Handler SHALL format the response with bilingual support (English and Traditional Chinese)

### Requirement 4: Granular Schedule Control

**User Story:** As a VPN administrator, I want to control auto-open and auto-close schedules independently, so that I can fine-tune the automation behavior.

#### Acceptance Criteria

1. WHEN a user sends `/vpn schedule open on <environment>`, THE Slack_Handler SHALL enable only the auto-open schedule
2. WHEN a user sends `/vpn schedule open off <environment>`, THE Slack_Handler SHALL disable only the auto-open schedule
3. WHEN a user sends `/vpn schedule close on <environment>`, THE Slack_Handler SHALL enable only the auto-close schedule
4. WHEN a user sends `/vpn schedule close off <environment>`, THE Slack_Handler SHALL disable only the auto-close schedule
5. WHEN a granular schedule change is made, THE Auto_Schedule_System SHALL preserve the state of the other schedule

### Requirement 5: Schedule State Persistence

**User Story:** As a system operator, I want schedule states to persist across Lambda invocations, so that schedule settings are not lost during system restarts.

#### Acceptance Criteria

1. THE Auto_Schedule_System SHALL store schedule states in AWS Parameter Store under `/vpn/automation/schedule/<environment>/`
2. WHEN the VPN_Monitor Lambda starts, THE Auto_Schedule_System SHALL read the current schedule state from Parameter Store
3. WHEN schedule state changes, THE Auto_Schedule_System SHALL write the new state to Parameter Store immediately
4. THE Auto_Schedule_System SHALL store schedule state as JSON containing enabled status, last modified timestamp, and expiration (if applicable)

### Requirement 6: VPN Monitor Integration

**User Story:** As a system operator, I want the VPN monitor to respect schedule settings, so that auto-open and auto-close only occur when their respective schedules are enabled.

#### Acceptance Criteria

1. WHEN auto-open schedule is disabled, THE VPN_Monitor SHALL skip the scheduled morning VPN open operation
2. WHEN auto-close schedule is disabled, THE VPN_Monitor SHALL skip idle-based VPN close operations
3. WHEN schedule state changes affect pending operations, THE VPN_Monitor SHALL log the skipped operation with reason
4. WHEN a schedule is disabled with expiration, THE VPN_Monitor SHALL check expiration before skipping operations

### Requirement 7: Help Documentation

**User Story:** As a VPN user, I want to see help documentation for schedule commands, so that I can learn how to use the new functionality.

#### Acceptance Criteria

1. WHEN a user sends `/vpn help`, THE Slack_Handler SHALL include schedule command documentation in the help response
2. WHEN a user sends `/vpn schedule help`, THE Slack_Handler SHALL return detailed schedule command usage
3. THE help documentation SHALL include command syntax, examples, and available options
4. THE help documentation SHALL be bilingual (English and Traditional Chinese)

### Requirement 8: Project Documentation Updates

**User Story:** As a project maintainer, I want the project documentation to reflect the new schedule commands, so that users and administrators can reference accurate documentation.

#### Acceptance Criteria

1. THE README.md SHALL be updated to include schedule commands in the Slack integration section
2. THE admin-guide.md SHALL be updated to document schedule management procedures
3. THE user-guide.md SHALL be updated to explain schedule commands for end users
4. THE documentation SHALL include examples of common schedule management scenarios
5. THE documentation SHALL maintain bilingual format (English and Traditional Chinese) where applicable
