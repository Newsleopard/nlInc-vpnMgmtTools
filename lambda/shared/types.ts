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

// Runtime status from EC2 API + Parameter Store
export interface VpnStatus {
  associated: boolean;
  activeConnections: number;
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

// Parsed VPN command (Enhanced for Epic 3.2)
export interface VpnCommandRequest {
  action: 'open' | 'close' | 'check' | 'admin-override' | 'admin-clear-override' | 'admin-cooldown' | 'admin-force-close' | 'cost-savings' | 'cost-analysis';
  environment: 'staging' | 'production' | string; // Allow string for report types
  user: string;
  requestId: string;
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