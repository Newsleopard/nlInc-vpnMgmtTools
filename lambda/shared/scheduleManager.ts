import { SSMClient, GetParameterCommand, PutParameterCommand } from '@aws-sdk/client-ssm';
import { CloudWatchClient, PutMetricDataCommand, StandardUnit } from '@aws-sdk/client-cloudwatch';
import { createLogger } from './logger';

/**
 * Schedule Manager Module
 * 
 * Manages VPN auto-scheduling state for auto-open and auto-close functionality.
 * State is persisted in AWS Parameter Store under /vpn/automation/schedule/{environment}/
 * 
 * Requirements: 5.1, 5.4
 */

// ============================================================================
// Interfaces and Types
// ============================================================================

/**
 * Individual schedule state for auto-open or auto-close
 */
export interface ScheduleItemState {
  enabled: boolean;
  lastModified: string;      // ISO 8601 timestamp
  modifiedBy: string;        // Slack username
  expiresAt?: string;        // ISO 8601 timestamp (optional, for temporary disables)
}

/**
 * Complete schedule state containing both auto-open and auto-close states
 * Includes version field for optimistic locking to prevent race conditions
 */
export interface ScheduleState {
  version: number;           // Version for optimistic locking
  autoOpen: ScheduleItemState;
  autoClose: ScheduleItemState;
}

/**
 * Schedule configuration (read-only, set during deployment)
 */
export interface ScheduleConfig {
  autoOpenTime: string;        // "09:30" in configured timezone
  autoOpenDays: number[];      // [1,2,3,4,5] for Mon-Fri (1=Monday, 7=Sunday)
  autoCloseIdleMinutes: number;
  businessHoursStart: string;  // "09:30"
  businessHoursEnd: string;    // "17:30"
  timezone: string;            // "Asia/Taipei"
}

/**
 * Schedule status response for status check commands
 */
export interface ScheduleStatusData {
  autoOpen: {
    enabled: boolean;
    nextScheduledTime?: string;
    disabledUntil?: string;
  };
  autoClose: {
    enabled: boolean;
    idleTimeoutMinutes: number;
    disabledUntil?: string;
  };
  businessHoursProtection: {
    enabled: boolean;
    start: string;
    end: string;
    timezone: string;
  };
  lastModified: string;
  modifiedBy: string;
}

/**
 * Schedule type for granular control
 */
export type ScheduleType = 'autoOpen' | 'autoClose' | 'both';

/**
 * Duration parsing result
 */
export interface ParsedDuration {
  valid: boolean;
  milliseconds?: number;
  expiresAt?: string;
}

// ============================================================================
// AWS Client Setup
// ============================================================================

const ssm = new SSMClient({
  region: process.env.AWS_REGION || 'us-east-1',
  maxAttempts: 3
});

const cloudwatch = new CloudWatchClient({
  region: process.env.AWS_REGION || 'us-east-1'
});

// ============================================================================
// Constants
// ============================================================================

// Support environment variable override for Parameter Store paths
const SCHEDULE_STATE_PATH_PREFIX = process.env.SCHEDULE_STATE_PATH || '/vpn/automation/schedule';
const SCHEDULE_CONFIG_PATH_PREFIX = process.env.SCHEDULE_CONFIG_PATH || '/vpn/automation/schedule';

/**
 * Default schedule configuration
 */
const DEFAULT_SCHEDULE_CONFIG: ScheduleConfig = {
  autoOpenTime: '09:30',
  autoOpenDays: [1, 2, 3, 4, 5], // Monday to Friday
  autoCloseIdleMinutes: 100,
  businessHoursStart: '09:30',
  businessHoursEnd: '17:30',
  timezone: 'Asia/Taipei'
};

/**
 * Default schedule state template (for reference/documentation)
 * NOTE: Actual defaults are environment-specific via createDefaultState():
 *   - Production: autoOpen.enabled = true (VPN opens automatically on weekdays)
 *   - Staging: autoOpen.enabled = false (must be explicitly enabled)
 *   - Both environments: autoClose.enabled = false (must be explicitly enabled)
 */
const DEFAULT_SCHEDULE_STATE: ScheduleState = {
  version: 1,
  autoOpen: {
    enabled: false,  // Note: Production defaults to true via createDefaultState()
    lastModified: new Date().toISOString(),
    modifiedBy: 'system'
  },
  autoClose: {
    enabled: false,
    lastModified: new Date().toISOString(),
    modifiedBy: 'system'
  }
};

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Get the Parameter Store path for schedule state
 */
function getScheduleStatePath(environment: string): string {
  return `${SCHEDULE_STATE_PATH_PREFIX}/${environment}/state`;
}

/**
 * Get the Parameter Store path for schedule config
 */
function getScheduleConfigPath(environment: string): string {
  return `${SCHEDULE_CONFIG_PATH_PREFIX}/${environment}/config`;
}

/**
 * Create a logger instance for schedule manager operations
 */
function getLogger(requestId: string = 'schedule-manager') {
  return createLogger({
    requestId,
    environment: process.env.ENVIRONMENT || 'staging',
    functionName: 'ScheduleManager'
  });
}


// ============================================================================
// State Read/Write Functions (Requirements: 5.2, 5.3)
// ============================================================================

/**
 * Read schedule state from Parameter Store
 * Returns default state if parameter doesn't exist
 * Fails fast on infrastructure errors to surface problems
 *
 * @param environment - The environment (staging/production)
 * @returns The current schedule state
 * @throws Error on infrastructure failures (throttling, permission, network errors)
 */
export async function readScheduleState(environment: string): Promise<ScheduleState> {
  const logger = getLogger();
  const parameterPath = getScheduleStatePath(environment);

  try {
    logger.debug('Reading schedule state', { environment, parameterPath });

    const command = new GetParameterCommand({
      Name: parameterPath,
      WithDecryption: false
    });

    const response = await ssm.send(command);

    if (!response.Parameter?.Value) {
      logger.info('Schedule state parameter empty, returning default', { environment });
      return createDefaultState(environment);
    }

    // Parse JSON with explicit error handling
    let state: ScheduleState;
    try {
      state = JSON.parse(response.Parameter.Value) as ScheduleState;
    } catch (parseError: any) {
      logger.error('Failed to parse schedule state JSON - data corruption detected', {
        environment,
        error: parseError.message,
        rawValuePreview: response.Parameter.Value?.substring(0, 100)
      });

      // Publish corruption metric for alerting
      await publishScheduleMetric('StateCorruption', 1, environment);

      // Fail fast on data corruption - don't silently use default
      throw new Error(`Schedule state data corruption in ${environment}: ${parseError.message}`);
    }

    // Validate the state structure
    if (!isValidScheduleState(state)) {
      logger.error('Invalid schedule state schema detected', {
        environment,
        hasVersion: 'version' in state,
        hasAutoOpen: 'autoOpen' in state,
        hasAutoClose: 'autoClose' in state
      });

      await publishScheduleMetric('StateSchemaInvalid', 1, environment);
      throw new Error(`Invalid schedule state schema in ${environment}`);
    }

    // Migrate state if version field is missing (backwards compatibility)
    if (state.version === undefined) {
      state.version = 1;
      logger.info('Migrated schedule state to include version', { environment });
    }

    logger.info('Schedule state read successfully', {
      environment,
      version: state.version,
      autoOpenEnabled: state.autoOpen.enabled,
      autoCloseEnabled: state.autoClose.enabled
    });

    return state;

  } catch (error: any) {
    if (error.name === 'ParameterNotFound') {
      logger.info('Schedule state parameter not found, returning default', { environment });
      return createDefaultState(environment);
    }

    // Fail fast on infrastructure errors - don't hide these problems
    if (error.name === 'ThrottlingException' ||
        error.name === 'ServiceUnavailable' ||
        error.name === 'AccessDeniedException' ||
        error.name === 'InternalServiceError') {
      logger.critical('SSM infrastructure failure', {
        environment,
        errorName: error.name,
        errorMessage: error.message
      });

      await publishScheduleMetric('SSMInfrastructureError', 1, environment);
      throw error; // Re-throw to fail fast
    }

    // Re-throw corruption errors
    if (error.message?.includes('corruption') || error.message?.includes('schema')) {
      throw error;
    }

    logger.error('Failed to read schedule state', {
      environment,
      errorName: error.name,
      error: error.message
    });

    // For unknown errors, fail fast rather than silently using defaults
    throw new Error(`Failed to read schedule state for ${environment}: ${error.message}`);
  }
}

/**
 * Write schedule state to Parameter Store
 * 
 * @param environment - The environment (staging/production)
 * @param state - The schedule state to write
 */
export async function writeScheduleState(environment: string, state: ScheduleState): Promise<void> {
  const logger = getLogger();
  const parameterPath = getScheduleStatePath(environment);

  try {
    logger.debug('Writing schedule state', { environment, parameterPath });

    const command = new PutParameterCommand({
      Name: parameterPath,
      Value: JSON.stringify(state),
      Type: 'String',
      Overwrite: true,
      Description: `VPN auto-schedule state for ${environment} environment`
    });

    await ssm.send(command);

    logger.info('Schedule state written successfully', {
      environment,
      autoOpenEnabled: state.autoOpen.enabled,
      autoCloseEnabled: state.autoClose.enabled
    });

  } catch (error: any) {
    logger.error('Failed to write schedule state', {
      environment,
      error: error.message
    });
    throw new Error(`Failed to write schedule state: ${error.message}`);
  }
}

/**
 * Write schedule state with optimistic locking version check
 * Reads current state and verifies version matches before writing
 *
 * @param environment - The environment (staging/production)
 * @param state - The schedule state to write (with new version)
 * @param expectedVersion - The version we expect to be current
 * @throws Error if version conflict detected
 */
async function writeScheduleStateWithVersionCheck(
  environment: string,
  state: ScheduleState,
  expectedVersion: number
): Promise<void> {
  const logger = getLogger();
  const parameterPath = getScheduleStatePath(environment);

  try {
    // Read current state to check version
    const currentState = await readScheduleStateRaw(environment);

    if (currentState && currentState.version !== expectedVersion) {
      logger.warn('Version conflict detected during write', {
        environment,
        expectedVersion,
        actualVersion: currentState.version
      });
      throw new Error(`Schedule state version conflict: expected ${expectedVersion}, found ${currentState.version}`);
    }

    logger.debug('Writing schedule state with version check', {
      environment,
      parameterPath,
      newVersion: state.version,
      expectedVersion
    });

    const command = new PutParameterCommand({
      Name: parameterPath,
      Value: JSON.stringify(state),
      Type: 'String',
      Overwrite: true,
      Description: `VPN auto-schedule state for ${environment} environment (v${state.version})`
    });

    await ssm.send(command);

    logger.info('Schedule state written successfully with version check', {
      environment,
      version: state.version,
      autoOpenEnabled: state.autoOpen.enabled,
      autoCloseEnabled: state.autoClose.enabled
    });

  } catch (error: any) {
    if (error.message?.includes('version conflict')) {
      throw error; // Re-throw version conflicts for retry handling
    }
    logger.error('Failed to write schedule state', {
      environment,
      error: error.message
    });
    throw new Error(`Failed to write schedule state: ${error.message}`);
  }
}

/**
 * Read raw schedule state without defaults or migration
 * Used internally for version checking
 */
async function readScheduleStateRaw(environment: string): Promise<ScheduleState | null> {
  const parameterPath = getScheduleStatePath(environment);

  try {
    const command = new GetParameterCommand({
      Name: parameterPath,
      WithDecryption: false
    });

    const response = await ssm.send(command);

    if (!response.Parameter?.Value) {
      return null;
    }

    return JSON.parse(response.Parameter.Value) as ScheduleState;
  } catch (error: any) {
    if (error.name === 'ParameterNotFound') {
      return null;
    }
    throw error;
  }
}

/**
 * Create a default schedule state with current timestamp
 * Auto-open defaults: production=enabled, staging=disabled
 * Auto-close defaults: disabled (users must explicitly enable)
 *
 * @param environment - The environment (production/staging)
 * @returns Default schedule state with environment-specific auto-open setting
 */
function createDefaultState(environment: string = 'staging'): ScheduleState {
  const now = new Date().toISOString();
  const isProduction = environment === 'production';

  return {
    version: 1,
    autoOpen: {
      enabled: isProduction,  // Production: enabled by default, Staging: disabled
      lastModified: now,
      modifiedBy: 'system'
    },
    autoClose: {
      enabled: false,
      lastModified: now,
      modifiedBy: 'system'
    }
  };
}

/**
 * Validate that an object is a valid ScheduleState
 */
function isValidScheduleState(obj: any): obj is ScheduleState {
  return (
    obj &&
    typeof obj === 'object' &&
    obj.autoOpen &&
    typeof obj.autoOpen.enabled === 'boolean' &&
    typeof obj.autoOpen.lastModified === 'string' &&
    typeof obj.autoOpen.modifiedBy === 'string' &&
    obj.autoClose &&
    typeof obj.autoClose.enabled === 'boolean' &&
    typeof obj.autoClose.lastModified === 'string' &&
    typeof obj.autoClose.modifiedBy === 'string'
  );
}


// ============================================================================
// CloudWatch Metrics (for monitoring schedule operations)
// ============================================================================

// Metric buffer for retry logic
interface BufferedMetric {
  metricName: string;
  value: number;
  environment: string;
  dimensions?: { [key: string]: string };
  timestamp: Date;
  attempts: number;
}

const metricBuffer: BufferedMetric[] = [];
let consecutiveFailures = 0;
const MAX_BUFFER_SIZE = 100;
const MAX_RETRY_ATTEMPTS = 3;

/**
 * Publish a schedule-related metric to CloudWatch with retry logic
 *
 * Features:
 * - Automatic retry on failure (up to 3 attempts)
 * - Buffering of failed metrics for later retry
 * - Consecutive failure tracking for alerting
 *
 * @param metricName - Name of the metric
 * @param value - Metric value
 * @param environment - Environment (staging/production)
 * @param dimensions - Additional dimensions
 */
async function publishScheduleMetric(
  metricName: string,
  value: number,
  environment: string,
  dimensions?: { [key: string]: string }
): Promise<void> {
  const logger = getLogger();

  try {
    const metricDimensions = [
      { Name: 'Environment', Value: environment },
      ...(dimensions ? Object.entries(dimensions).map(([k, v]) => ({ Name: k, Value: v })) : [])
    ];

    await cloudwatch.send(new PutMetricDataCommand({
      Namespace: 'VPN/Schedule',
      MetricData: [{
        MetricName: metricName,
        Value: value,
        Unit: StandardUnit.Count,
        Dimensions: metricDimensions,
        Timestamp: new Date()
      }]
    }));

    // Reset consecutive failures on success
    consecutiveFailures = 0;

    // Try to flush buffered metrics on successful publish
    if (metricBuffer.length > 0) {
      await flushBufferedMetrics();
    }

  } catch (error) {
    consecutiveFailures++;

    // Buffer the failed metric for retry
    if (metricBuffer.length < MAX_BUFFER_SIZE) {
      metricBuffer.push({
        metricName,
        value,
        environment,
        dimensions,
        timestamp: new Date(),
        attempts: 1
      });
    }

    logger.warn('Failed to publish schedule metric, buffered for retry', {
      metricName,
      environment,
      consecutiveFailures,
      bufferedCount: metricBuffer.length,
      error: error instanceof Error ? error.message : 'Unknown error'
    });

    // Alert if metrics are consistently failing
    if (consecutiveFailures >= 5) {
      logger.error('CloudWatch metrics consistently failing', {
        consecutiveFailures,
        bufferedCount: metricBuffer.length,
        lastError: error instanceof Error ? error.message : 'Unknown'
      });
    }
  }
}

/**
 * Attempt to flush buffered metrics
 * Called after successful metric publish
 */
async function flushBufferedMetrics(): Promise<void> {
  const logger = getLogger();

  if (metricBuffer.length === 0) return;

  const metricsToRetry = [...metricBuffer];
  metricBuffer.length = 0; // Clear buffer

  for (const metric of metricsToRetry) {
    if (metric.attempts >= MAX_RETRY_ATTEMPTS) {
      logger.warn('Dropping metric after max retry attempts', {
        metricName: metric.metricName,
        environment: metric.environment,
        attempts: metric.attempts
      });
      continue;
    }

    try {
      const metricDimensions = [
        { Name: 'Environment', Value: metric.environment },
        ...(metric.dimensions ? Object.entries(metric.dimensions).map(([k, v]) => ({ Name: k, Value: v })) : [])
      ];

      await cloudwatch.send(new PutMetricDataCommand({
        Namespace: 'VPN/Schedule',
        MetricData: [{
          MetricName: metric.metricName,
          Value: metric.value,
          Unit: StandardUnit.Count,
          Dimensions: metricDimensions,
          Timestamp: metric.timestamp
        }]
      }));

      logger.debug('Successfully flushed buffered metric', {
        metricName: metric.metricName,
        environment: metric.environment,
        attempt: metric.attempts + 1
      });

    } catch (retryError) {
      // Re-buffer with incremented attempt count
      if (metric.attempts + 1 < MAX_RETRY_ATTEMPTS && metricBuffer.length < MAX_BUFFER_SIZE) {
        metricBuffer.push({
          ...metric,
          attempts: metric.attempts + 1
        });
      }
    }
  }
}

// ============================================================================
// Schedule Enabled Check Functions (Requirements: 2.3, 6.4)
// ============================================================================

/**
 * Check if auto-open schedule is currently enabled
 * Handles expiration - returns true (enabled) if the disable has expired
 * 
 * @param environment - The environment (staging/production)
 * @returns true if auto-open is enabled or disable has expired
 */
export async function isAutoOpenEnabled(environment: string): Promise<boolean> {
  const logger = getLogger();
  
  try {
    const state = await readScheduleState(environment);
    return isScheduleItemEnabled(state.autoOpen, logger, 'autoOpen', environment);
  } catch (error: any) {
    logger.error('Error checking auto-open enabled status', {
      environment,
      error: error.message
    });
    
    // Publish error metric for monitoring/alerting
    await publishScheduleMetric('ScheduleCheckError', 1, environment, { ScheduleType: 'autoOpen' });
    
    // Default to enabled on error to prevent blocking operations
    return true;
  }
}

/**
 * Check if auto-close schedule is currently enabled
 * Handles expiration - returns true (enabled) if the disable has expired
 * 
 * @param environment - The environment (staging/production)
 * @returns true if auto-close is enabled or disable has expired
 */
export async function isAutoCloseEnabled(environment: string): Promise<boolean> {
  const logger = getLogger();
  
  try {
    const state = await readScheduleState(environment);
    return isScheduleItemEnabled(state.autoClose, logger, 'autoClose', environment);
  } catch (error: any) {
    logger.error('Error checking auto-close enabled status', {
      environment,
      error: error.message
    });
    
    // Publish error metric for monitoring/alerting
    await publishScheduleMetric('ScheduleCheckError', 1, environment, { ScheduleType: 'autoClose' });
    
    // Default to enabled on error to prevent blocking operations
    return true;
  }
}

/**
 * Check if a schedule item is enabled, considering expiration
 */
function isScheduleItemEnabled(
  item: ScheduleItemState, 
  logger: any, 
  scheduleType: string,
  environment: string
): boolean {
  // If explicitly enabled, return true
  if (item.enabled) {
    return true;
  }

  // If disabled without expiration, return false
  if (!item.expiresAt) {
    logger.debug(`${scheduleType} is disabled indefinitely`, { environment });
    return false;
  }

  // Check if the disable has expired
  const now = new Date();
  const expiresAt = new Date(item.expiresAt);

  if (now >= expiresAt) {
    logger.info(`${scheduleType} disable has expired, treating as enabled`, {
      environment,
      expiresAt: item.expiresAt,
      now: now.toISOString()
    });
    return true;
  }

  logger.debug(`${scheduleType} is disabled until ${item.expiresAt}`, { environment });
  return false;
}


// ============================================================================
// Duration Parsing Utility (Requirements: 2.2)
// ============================================================================

/**
 * Parse a duration string and calculate expiration timestamp
 * Supports formats: Nh (hours), Nd (days), Nm (minutes)
 * Examples: "2h", "24h", "7d", "30m"
 * 
 * @param duration - Duration string to parse
 * @returns ParsedDuration with validity and expiration info
 */
export function parseDuration(duration: string): ParsedDuration {
  if (!duration || typeof duration !== 'string') {
    return { valid: false };
  }

  const trimmed = duration.trim().toLowerCase();
  
  // Match pattern: number followed by unit (h, d, m)
  const match = trimmed.match(/^(\d+)([hdm])$/);
  
  if (!match) {
    return { valid: false };
  }

  const value = parseInt(match[1], 10);
  const unit = match[2];

  if (value <= 0 || isNaN(value)) {
    return { valid: false };
  }

  let milliseconds: number;

  switch (unit) {
    case 'm': // minutes
      milliseconds = value * 60 * 1000;
      break;
    case 'h': // hours
      milliseconds = value * 60 * 60 * 1000;
      break;
    case 'd': // days
      milliseconds = value * 24 * 60 * 60 * 1000;
      break;
    default:
      return { valid: false };
  }

  const expiresAt = new Date(Date.now() + milliseconds).toISOString();

  return {
    valid: true,
    milliseconds,
    expiresAt
  };
}

/**
 * Calculate expiration timestamp from duration string
 * Returns null for invalid formats
 * 
 * @param duration - Duration string (e.g., "2h", "24h", "7d")
 * @returns ISO 8601 timestamp or null if invalid
 */
export function calculateExpiration(duration: string): string | null {
  const parsed = parseDuration(duration);
  return parsed.valid ? parsed.expiresAt! : null;
}

/**
 * Calculate remaining time until expiration
 * 
 * @param expiresAt - ISO 8601 expiration timestamp
 * @returns Human-readable remaining time or null if expired
 */
export function getRemainingTime(expiresAt: string): string | null {
  const now = new Date();
  const expiration = new Date(expiresAt);
  
  const remainingMs = expiration.getTime() - now.getTime();
  
  if (remainingMs <= 0) {
    return null;
  }

  const minutes = Math.floor(remainingMs / (60 * 1000));
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (days > 0) {
    const remainingHours = hours % 24;
    return remainingHours > 0 ? `${days}d ${remainingHours}h` : `${days}d`;
  }
  
  if (hours > 0) {
    const remainingMinutes = minutes % 60;
    return remainingMinutes > 0 ? `${hours}h ${remainingMinutes}m` : `${hours}h`;
  }
  
  return `${minutes}m`;
}


// ============================================================================
// Enable/Disable Schedule Functions (Requirements: 1.1, 1.2, 2.1, 2.4, 4.1-4.4)
// ============================================================================

/**
 * Enable schedule(s) for an environment
 * Uses optimistic locking to prevent race conditions
 *
 * @param environment - The environment (staging/production)
 * @param scheduleType - Which schedule to enable: 'autoOpen', 'autoClose', or 'both'
 * @param modifiedBy - Username of the person making the change
 * @param maxRetries - Maximum retry attempts for optimistic locking conflicts (default: 3)
 * @returns Updated schedule state
 * @throws Error if optimistic locking fails after max retries
 */
export async function enableSchedule(
  environment: string,
  scheduleType: ScheduleType,
  modifiedBy: string,
  maxRetries: number = 3
): Promise<ScheduleState> {
  const logger = getLogger();

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    logger.info('Enabling schedule', { environment, scheduleType, modifiedBy, attempt });

    const state = await readScheduleState(environment);
    const originalVersion = state.version;
    const now = new Date().toISOString();

    if (scheduleType === 'autoOpen' || scheduleType === 'both') {
      state.autoOpen = {
        enabled: true,
        lastModified: now,
        modifiedBy,
        expiresAt: undefined
      };
    }

    if (scheduleType === 'autoClose' || scheduleType === 'both') {
      state.autoClose = {
        enabled: true,
        lastModified: now,
        modifiedBy,
        expiresAt: undefined
      };
    }

    // Increment version for optimistic locking
    state.version = originalVersion + 1;

    try {
      await writeScheduleStateWithVersionCheck(environment, state, originalVersion);

      // Publish metrics for schedule enable operation
      await publishScheduleMetric('ScheduleEnabled', 1, environment, {
        ScheduleType: scheduleType,
        ModifiedBy: modifiedBy
      });

      logger.info('Schedule enabled successfully', {
        environment,
        scheduleType,
        modifiedBy,
        version: state.version,
        autoOpenEnabled: state.autoOpen.enabled,
        autoCloseEnabled: state.autoClose.enabled
      });

      return state;
    } catch (error: any) {
      if (error.message?.includes('version conflict') && attempt < maxRetries) {
        logger.warn('Optimistic locking conflict, retrying', {
          environment,
          attempt,
          originalVersion
        });
        await publishScheduleMetric('OptimisticLockRetry', 1, environment);
        // Small delay before retry
        await new Promise(resolve => setTimeout(resolve, 100 * attempt));
        continue;
      }
      throw error;
    }
  }

  await publishScheduleMetric('OptimisticLockFailure', 1, environment);
  throw new Error(`Failed to enable schedule after ${maxRetries} attempts due to concurrent modifications`);
}

/**
 * Disable schedule(s) for an environment
 * Uses optimistic locking to prevent race conditions
 *
 * @param environment - The environment (staging/production)
 * @param scheduleType - Which schedule to disable: 'autoOpen', 'autoClose', or 'both'
 * @param modifiedBy - Username of the person making the change
 * @param duration - Optional duration string (e.g., "2h", "24h", "7d")
 * @param maxRetries - Maximum retry attempts for optimistic locking conflicts (default: 3)
 * @returns Updated schedule state
 * @throws Error if optimistic locking fails after max retries
 */
export async function disableSchedule(
  environment: string,
  scheduleType: ScheduleType,
  modifiedBy: string,
  duration?: string,
  maxRetries: number = 3
): Promise<ScheduleState> {
  const logger = getLogger();

  // Validate duration format upfront (before retry loop)
  let expiresAt: string | undefined;
  if (duration) {
    const parsed = parseDuration(duration);
    if (parsed.valid) {
      expiresAt = parsed.expiresAt;
    } else {
      throw new Error(`Invalid duration format: ${duration}. Use: Nh (hours), Nd (days), Nm (minutes). Examples: 2h, 24h, 7d`);
    }
  }

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    logger.info('Disabling schedule', { environment, scheduleType, modifiedBy, duration, attempt });

    const state = await readScheduleState(environment);
    const originalVersion = state.version;
    const now = new Date().toISOString();

    // Recalculate expiresAt for each attempt to ensure accuracy
    if (duration) {
      const parsed = parseDuration(duration);
      expiresAt = parsed.expiresAt;
    }

    if (scheduleType === 'autoOpen' || scheduleType === 'both') {
      state.autoOpen = {
        enabled: false,
        lastModified: now,
        modifiedBy,
        expiresAt
      };
    }

    if (scheduleType === 'autoClose' || scheduleType === 'both') {
      state.autoClose = {
        enabled: false,
        lastModified: now,
        modifiedBy,
        expiresAt
      };
    }

    // Increment version for optimistic locking
    state.version = originalVersion + 1;

    try {
      await writeScheduleStateWithVersionCheck(environment, state, originalVersion);

      // Publish metrics for schedule disable operation
      await publishScheduleMetric('ScheduleDisabled', 1, environment, {
        ScheduleType: scheduleType,
        ModifiedBy: modifiedBy,
        HasDuration: duration ? 'true' : 'false'
      });

      logger.info('Schedule disabled successfully', {
        environment,
        scheduleType,
        modifiedBy,
        version: state.version,
        expiresAt,
        autoOpenEnabled: state.autoOpen.enabled,
        autoCloseEnabled: state.autoClose.enabled
      });

      return state;
    } catch (error: any) {
      if (error.message?.includes('version conflict') && attempt < maxRetries) {
        logger.warn('Optimistic locking conflict, retrying', {
          environment,
          attempt,
          originalVersion
        });
        await publishScheduleMetric('OptimisticLockRetry', 1, environment);
        // Small delay before retry
        await new Promise(resolve => setTimeout(resolve, 100 * attempt));
        continue;
      }
      throw error;
    }
  }

  await publishScheduleMetric('OptimisticLockFailure', 1, environment);
  throw new Error(`Failed to disable schedule after ${maxRetries} attempts due to concurrent modifications`);
}


// ============================================================================
// Schedule Status Retrieval (Requirements: 3.1-3.5)
// ============================================================================

/**
 * Get schedule configuration for an environment
 * Returns default config if not found in Parameter Store
 * 
 * @param environment - The environment (staging/production)
 * @returns Schedule configuration
 */
export async function getScheduleConfig(environment: string): Promise<ScheduleConfig> {
  const logger = getLogger();
  const parameterPath = getScheduleConfigPath(environment);

  try {
    const command = new GetParameterCommand({
      Name: parameterPath,
      WithDecryption: false
    });

    const response = await ssm.send(command);

    if (!response.Parameter?.Value) {
      logger.info('Schedule config parameter empty, returning default', { environment });
      return { ...DEFAULT_SCHEDULE_CONFIG };
    }

    const config = JSON.parse(response.Parameter.Value) as ScheduleConfig;
    return config;

  } catch (error: any) {
    if (error.name === 'ParameterNotFound') {
      logger.info('Schedule config parameter not found, returning default', { environment });
      return { ...DEFAULT_SCHEDULE_CONFIG };
    }

    logger.error('Failed to read schedule config', {
      environment,
      error: error.message
    });

    return { ...DEFAULT_SCHEDULE_CONFIG };
  }
}

/**
 * Calculate the next scheduled open time based on configuration
 * Uses proper timezone handling via Intl.DateTimeFormat
 * 
 * @param config - Schedule configuration
 * @returns Next scheduled open time as Date (in UTC)
 */
export function getNextScheduledOpenTime(config: ScheduleConfig): Date {
  const now = new Date();
  
  // Parse the auto-open time
  const [hours, minutes] = config.autoOpenTime.split(':').map(Number);
  
  // Create a date for today at the scheduled time in the configured timezone
  const todayScheduled = new Date(now);
  todayScheduled.setHours(hours, minutes, 0, 0);
  
  // Adjust for timezone using the improved getTimezoneOffset function
  const timezoneOffset = getTimezoneOffset(config.timezone, todayScheduled);
  todayScheduled.setTime(todayScheduled.getTime() - timezoneOffset);

  // Find the next valid day
  let nextScheduled = new Date(todayScheduled);
  let daysChecked = 0;
  
  while (daysChecked < 8) {
    const dayOfWeek = nextScheduled.getDay();
    // Convert Sunday=0 to Sunday=7 for comparison with config
    const adjustedDay = dayOfWeek === 0 ? 7 : dayOfWeek;
    
    if (config.autoOpenDays.includes(adjustedDay) && nextScheduled > now) {
      return nextScheduled;
    }
    
    // Move to next day
    nextScheduled.setDate(nextScheduled.getDate() + 1);
    daysChecked++;
  }

  // Fallback: return tomorrow at scheduled time
  const tomorrow = new Date(todayScheduled);
  tomorrow.setDate(tomorrow.getDate() + 1);
  return tomorrow;
}

/**
 * Get timezone offset in milliseconds using Intl.DateTimeFormat
 * This properly handles daylight saving time for all timezones
 *
 * @param timezone - IANA timezone string (e.g., 'Asia/Taipei', 'America/New_York')
 * @param date - Optional date to calculate offset for (defaults to now)
 * @returns Offset in milliseconds from UTC
 */
function getTimezoneOffset(timezone: string, date: Date = new Date()): number {
  const logger = getLogger();

  // Primary method: Use Intl.DateTimeFormat with shortOffset
  try {
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      timeZoneName: 'shortOffset'
    });

    const parts = formatter.formatToParts(date);
    const offsetPart = parts.find(p => p.type === 'timeZoneName');

    if (offsetPart && offsetPart.value) {
      // Parse offset like "GMT+8", "GMT-5", "GMT+5:30", "GMT-4" (DST-aware)
      const match = offsetPart.value.match(/GMT([+-])(\d{1,2})(?::(\d{2}))?/);
      if (match) {
        const sign = match[1] === '+' ? 1 : -1;
        const hours = parseInt(match[2], 10);
        const minutes = match[3] ? parseInt(match[3], 10) : 0;
        return sign * (hours * 60 + minutes) * 60 * 1000;
      }
    }
  } catch (primaryError) {
    logger.debug('Primary timezone offset method failed, trying fallback', {
      timezone,
      error: primaryError instanceof Error ? primaryError.message : 'Unknown'
    });
  }

  // Fallback method: Compare UTC and local time strings (DST-aware)
  try {
    const utcDate = new Date(date.toLocaleString('en-US', { timeZone: 'UTC' }));
    const tzDate = new Date(date.toLocaleString('en-US', { timeZone: timezone }));
    const offset = tzDate.getTime() - utcDate.getTime();

    logger.debug('Using fallback timezone calculation', {
      timezone,
      offsetHours: offset / (60 * 60 * 1000)
    });

    return offset;
  } catch (fallbackError) {
    logger.debug('Fallback timezone method failed, trying hardcoded', {
      timezone,
      error: fallbackError instanceof Error ? fallbackError.message : 'Unknown'
    });
  }

  // Last resort: Hardcoded offsets for timezones without DST only
  // For DST timezones, we fail rather than return incorrect values
  const noDstTimezones: { [key: string]: number } = {
    'Asia/Taipei': 8 * 60 * 60 * 1000,     // No DST in Taiwan
    'Asia/Tokyo': 9 * 60 * 60 * 1000,      // No DST in Japan
    'Asia/Singapore': 8 * 60 * 60 * 1000,  // No DST in Singapore
    'Asia/Shanghai': 8 * 60 * 60 * 1000,   // No DST in China
    'Asia/Hong_Kong': 8 * 60 * 60 * 1000,  // No DST in Hong Kong
    'UTC': 0,
    'GMT': 0
  };

  if (timezone in noDstTimezones) {
    logger.warn('Using hardcoded timezone offset (timezone has no DST)', {
      timezone,
      offsetHours: noDstTimezones[timezone] / (60 * 60 * 1000)
    });
    return noDstTimezones[timezone];
  }

  // For DST-affected timezones without working Intl, throw error
  // This prevents silent incorrect scheduling
  const dstAffectedTimezones = [
    'America/New_York', 'America/Los_Angeles', 'America/Chicago',
    'Europe/London', 'Europe/Paris', 'Europe/Berlin',
    'Australia/Sydney', 'Australia/Melbourne'
  ];

  if (dstAffectedTimezones.includes(timezone)) {
    logger.error('Cannot determine timezone offset for DST-affected timezone', {
      timezone,
      message: 'Intl.DateTimeFormat failed and hardcoded fallback not safe for DST timezones'
    });
    throw new Error(`Cannot calculate timezone offset for ${timezone} - DST handling unavailable`);
  }

  // Unknown timezone - default to UTC with warning
  logger.warn('Unknown timezone, defaulting to UTC offset', { timezone });
  return 0;
}

/**
 * Get comprehensive schedule status for an environment
 * 
 * @param environment - The environment (staging/production)
 * @returns Complete schedule status data
 */
export async function getScheduleStatus(environment: string): Promise<ScheduleStatusData> {
  const logger = getLogger();
  
  logger.info('Getting schedule status', { environment });

  const [state, config] = await Promise.all([
    readScheduleState(environment),
    getScheduleConfig(environment)
  ]);

  const nextOpenTime = getNextScheduledOpenTime(config);

  // Determine effective enabled status (considering expiration)
  const autoOpenEffectivelyEnabled = isScheduleItemEnabled(
    state.autoOpen, 
    logger, 
    'autoOpen', 
    environment
  );
  const autoCloseEffectivelyEnabled = isScheduleItemEnabled(
    state.autoClose, 
    logger, 
    'autoClose', 
    environment
  );

  // Calculate remaining disable time if applicable
  const autoOpenDisabledUntil = !state.autoOpen.enabled && state.autoOpen.expiresAt
    ? getRemainingTime(state.autoOpen.expiresAt) || undefined
    : undefined;
  
  const autoCloseDisabledUntil = !state.autoClose.enabled && state.autoClose.expiresAt
    ? getRemainingTime(state.autoClose.expiresAt) || undefined
    : undefined;

  // Determine the most recent modification
  const autoOpenModified = new Date(state.autoOpen.lastModified);
  const autoCloseModified = new Date(state.autoClose.lastModified);
  const lastModified = autoOpenModified > autoCloseModified 
    ? state.autoOpen.lastModified 
    : state.autoClose.lastModified;
  const modifiedBy = autoOpenModified > autoCloseModified 
    ? state.autoOpen.modifiedBy 
    : state.autoClose.modifiedBy;

  const status: ScheduleStatusData = {
    autoOpen: {
      enabled: autoOpenEffectivelyEnabled,
      nextScheduledTime: autoOpenEffectivelyEnabled ? nextOpenTime.toISOString() : undefined,
      disabledUntil: autoOpenDisabledUntil
    },
    autoClose: {
      enabled: autoCloseEffectivelyEnabled,
      idleTimeoutMinutes: config.autoCloseIdleMinutes,
      disabledUntil: autoCloseDisabledUntil
    },
    businessHoursProtection: {
      enabled: true,
      start: config.businessHoursStart,
      end: config.businessHoursEnd,
      timezone: config.timezone
    },
    lastModified,
    modifiedBy
  };

  logger.info('Schedule status retrieved', {
    environment,
    autoOpenEnabled: status.autoOpen.enabled,
    autoCloseEnabled: status.autoClose.enabled
  });

  return status;
}

// ============================================================================
// Exports for Testing
// ============================================================================

// Export internal functions for testing purposes
export const _internal = {
  createDefaultState,
  isValidScheduleState,
  isScheduleItemEnabled,
  getTimezoneOffset,
  getScheduleStatePath,
  getScheduleConfigPath,
  publishScheduleMetric,
  DEFAULT_SCHEDULE_CONFIG,
  DEFAULT_SCHEDULE_STATE
};
