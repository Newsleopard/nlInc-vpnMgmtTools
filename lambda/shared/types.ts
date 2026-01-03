// Parameter Store Schema Types

// Matches /vpn/endpoint/state JSON structure
export interface VpnState {
  associated: boolean;
  lastActivity: string;  // ISO 8601 timestamp
}

// Matches /vpn/endpoint/conf JSON structure  
export interface VpnConfig {
  ENDPOINT_ID: string;   // e.g., "cvpn-endpoint-0fee040f83981f12f"
  SUBNET_ID: string;     // e.g., "subnet-02bd062360a525a95"
}

// VPN connection detail for active connections
export interface VpnConnectionDetail {
  connectionId: string;
  username: string;  // From CommonName (certificate-based auth) or Username (AD auth)
  clientIp: string;
  establishedTime: Date;
}

// Runtime status from EC2 API + Parameter Store
export interface VpnStatus {
  associated: boolean;
  associationState?: 'associated' | 'associating' | 'disassociating' | 'disassociated' | 'failed';
  activeConnections: number;
  activeConnectionDetails?: VpnConnectionDetail[];  // Detailed info for each active connection
  lastActivity: Date;
  endpointId: string;
  subnetId: string;
}

// Slack command structure
export interface SlackCommand {
  token: string;
  team_id: string;
  team_domain: string;
  channel_id: string;
  channel_name: string;
  user_id: string;
  user_name: string;
  command: string;
  text: string;
  response_url: string;
  trigger_id: string;
}

// Valid environment types
export type VpnEnvironment = 'staging' | 'production';

// Cost report types (used by cost-analysis command)
export type CostReportType = 'daily' | 'cumulative' | 'summary';

// Combined environment or report type (for commands that use environment field flexibly)
export type VpnEnvironmentOrReportType = VpnEnvironment | CostReportType;

// Valid VPN actions grouped by category
export type VpnCoreAction = 'open' | 'close' | 'check';
export type VpnAdminAction = 'admin-noclose' | 'admin-autoclose' | 'admin-cooldown' | 'admin-force-close';
export type VpnCostAction = 'cost-savings' | 'cost-analysis';
export type VpnScheduleAction =
  | 'schedule-on' | 'schedule-off' | 'schedule-check'
  | 'schedule-open-on' | 'schedule-open-off'
  | 'schedule-close-on' | 'schedule-close-off'
  | 'schedule-help';
export type VpnHelpAction = 'help';

export type VpnAction =
  | VpnCoreAction
  | VpnAdminAction
  | VpnCostAction
  | VpnScheduleAction
  | VpnHelpAction;

// Duration format pattern (Nh, Nd, Nm - e.g., "2h", "24h", "7d", "30m")
export type DurationString = string;

/**
 * Validate duration string format
 * @param s - String to validate
 * @returns true if valid duration format
 */
export function isValidDurationString(s: string): boolean {
  if (!s || typeof s !== 'string') return false;
  return /^(\d+)([hdm])$/.test(s.trim().toLowerCase());
}

/**
 * Check if a value is a valid VPN environment
 */
export function isVpnEnvironment(value: string): value is VpnEnvironment {
  return value === 'staging' || value === 'production';
}

/**
 * Check if a value is a cost report type
 */
export function isCostReportType(value: string): value is CostReportType {
  return value === 'daily' || value === 'cumulative' || value === 'summary';
}

// Parsed VPN command (Enhanced for Epic 3.2 and Schedule Commands)
export interface VpnCommandRequest {
  action: VpnAction;
  environment: VpnEnvironmentOrReportType; // Supports environment or report type for cost commands
  user: string;
  requestId: string;
  helpMessage?: string;      // For help commands
  duration?: DurationString; // For schedule-off with duration (e.g., "2h", "24h", "7d")
}

// Schedule status response data (Requirements: 3.1, 3.2, 3.3, 3.4, 3.5)
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

// API Gateway event for cross-account calls
export interface CrossAccountRequest {
  command: VpnCommandRequest;
  requestId: string;
  sourceAccount: string;
  crossAccountMetadata?: {
    requestTimestamp: string;
    sourceEnvironment: string;
    routingAttempt: number;
    userAgent?: string;
  };
}

// Lambda response format
export interface VpnCommandResponse {
  success: boolean;
  message: string;
  data?: VpnStatus;
  error?: string;
}

// CloudWatch metrics data
export interface MetricData {
  metricName: string;
  value: number;
  unit: string;
  environment: string;
  timestamp?: Date;
}

// Cross-account routing metrics
export interface CrossAccountMetrics {
  totalRequests: number;
  successfulRequests: number;
  failedRequests: number;
  averageResponseTime: number;
  lastRequestTimestamp: string;
  routingErrors: { [errorType: string]: number };
}

// Epic 4.1: Enhanced logging and audit interfaces
export interface LogEntry {
  timestamp: string;
  level: 'DEBUG' | 'INFO' | 'WARN' | 'ERROR' | 'CRITICAL';
  message: string;
  correlationId: string;
  requestId: string;
  environment: string;
  functionName: string;
  metadata?: any;
}

export interface AuditTrail {
  operation: string;
  resource: string;
  outcome: 'success' | 'failure' | 'partial';
  user?: string;
  timestamp: string;
  details: any;
  correlationId: string;
  environment: string;
}