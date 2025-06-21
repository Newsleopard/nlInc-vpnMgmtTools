// Structured Logging Utility for Epic 4.1: Comprehensive Logging
// Provides centralized, structured logging with correlation IDs, audit trails, and performance metrics

export interface LogContext {
  requestId: string;
  environment: string;
  functionName: string;
  userAgent?: string;
  sourceIP?: string;
  userId?: string;
  correlationId?: string;
  sessionId?: string;
}

export interface AuditEvent {
  operation: string;
  resource: string;
  outcome: 'success' | 'failure' | 'partial';
  details: any;
  performanceMetrics?: PerformanceMetrics;
  securityContext?: SecurityContext;
}

export interface PerformanceMetrics {
  duration: number;
  memoryUsed?: number;
  cpuUsage?: number;
  dbOperations?: number;
  apiCalls?: number;
  networkLatency?: number;
}

export interface SecurityContext {
  authenticationMethod?: string;
  authorization?: string;
  riskScore?: number;
  geolocation?: string;
  deviceFingerprint?: string;
  threatDetection?: string[];
}

export type LogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR' | 'CRITICAL';

export interface StructuredLog {
  timestamp: string;
  level: LogLevel;
  message: string;
  context: LogContext;
  metadata?: any;
  audit?: AuditEvent;
  error?: {
    name: string;
    message: string;
    stack?: string;
    code?: string;
    statusCode?: number;
  };
  performance?: PerformanceMetrics;
  security?: SecurityContext;
  tags?: string[];
}

class VpnLogger {
  private context: LogContext;
  private correlationId: string;
  private performanceStart: [number, number];

  constructor(context: LogContext) {
    this.context = {
      ...context,
      correlationId: context.correlationId || this.generateCorrelationId()
    };
    this.correlationId = this.context.correlationId!;
    this.performanceStart = process.hrtime();
  }

  // Generate unique correlation ID for request tracing
  private generateCorrelationId(): string {
    return `vpn-${Date.now()}-${Math.random().toString(36).substr(2, 12)}`;
  }

  // Calculate performance metrics
  private getPerformanceMetrics(): PerformanceMetrics {
    const [seconds, nanoseconds] = process.hrtime(this.performanceStart);
    const duration = seconds * 1000 + nanoseconds / 1000000; // Convert to milliseconds

    const memoryUsage = process.memoryUsage();
    
    return {
      duration: Math.round(duration * 100) / 100, // Round to 2 decimal places
      memoryUsed: Math.round((memoryUsage.heapUsed / 1024 / 1024) * 100) / 100, // MB
      cpuUsage: process.cpuUsage ? process.cpuUsage().user / 1000 : undefined // Convert microseconds to milliseconds
    };
  }

  // Core logging method with structured output
  private log(level: LogLevel, message: string, metadata?: any, audit?: AuditEvent, error?: any): void {
    const logEntry: StructuredLog = {
      timestamp: new Date().toISOString(),
      level,
      message,
      context: this.context,
      metadata,
      audit,
      performance: this.getPerformanceMetrics(),
      tags: this.generateTags(level, audit)
    };

    if (error) {
      logEntry.error = {
        name: error.name || 'UnknownError',
        message: error.message || String(error),
        stack: error.stack,
        code: error.code,
        statusCode: error.statusCode
      };
    }

    // Output structured JSON for CloudWatch consumption
    console.log(JSON.stringify(logEntry));

    // Additional console output for development/debugging
    if (process.env.NODE_ENV === 'development' || process.env.VERBOSE_LOGGING === 'true') {
      console.log(`[${level}] ${message}`, metadata ? JSON.stringify(metadata, null, 2) : '');
    }

    // Send critical errors to CloudWatch as metrics
    if (level === 'CRITICAL' || level === 'ERROR') {
      this.reportErrorMetric(level, message, error);
    }
  }

  // Generate contextual tags for log filtering and analysis
  private generateTags(level: LogLevel, audit?: AuditEvent): string[] {
    const tags = [
      `env:${this.context.environment}`,
      `function:${this.context.functionName}`,
      `level:${level.toLowerCase()}`,
      `correlation:${this.correlationId}`
    ];

    if (audit) {
      tags.push(`operation:${audit.operation}`);
      tags.push(`outcome:${audit.outcome}`);
      tags.push(`resource:${audit.resource}`);
    }

    if (this.context.userId) {
      tags.push(`user:${this.context.userId}`);
    }

    return tags;
  }

  // Report error metrics to CloudWatch
  private async reportErrorMetric(level: LogLevel, message: string, error?: any): Promise<void> {
    try {
      // Import CloudWatch only when needed to avoid cold start delays
      const { CloudWatch } = await import('aws-sdk');
      const cloudwatch = new CloudWatch();

      await cloudwatch.putMetricData({
        Namespace: 'VPN/Logging',
        MetricData: [{
          MetricName: `${level}Errors`,
          Value: 1,
          Unit: 'Count',
          Dimensions: [
            { Name: 'Environment', Value: this.context.environment },
            { Name: 'Function', Value: this.context.functionName },
            { Name: 'ErrorType', Value: error?.name || 'UnknownError' }
          ],
          Timestamp: new Date()
        }]
      }).promise();
    } catch (metricError) {
      // Fallback: don't fail the original operation due to metric reporting issues
      console.error('Failed to report error metric:', metricError);
    }
  }

  // Public logging methods
  debug(message: string, metadata?: any): void {
    this.log('DEBUG', message, metadata);
  }

  info(message: string, metadata?: any): void {
    this.log('INFO', message, metadata);
  }

  warn(message: string, metadata?: any): void {
    this.log('WARN', message, metadata);
  }

  error(message: string, error?: any, metadata?: any): void {
    this.log('ERROR', message, metadata, undefined, error);
  }

  critical(message: string, error?: any, metadata?: any): void {
    this.log('CRITICAL', message, metadata, undefined, error);
  }

  // Audit logging for compliance and security
  audit(operation: string, resource: string, outcome: 'success' | 'failure' | 'partial', details: any, securityContext?: SecurityContext): void {
    const auditEvent: AuditEvent = {
      operation,
      resource,
      outcome,
      details,
      performanceMetrics: this.getPerformanceMetrics(),
      securityContext
    };

    this.log('INFO', `Audit: ${operation} on ${resource} - ${outcome}`, undefined, auditEvent);
  }

  // Performance tracking for optimization
  performance(operation: string, metrics: Partial<PerformanceMetrics>, metadata?: any): void {
    const fullMetrics: PerformanceMetrics = {
      ...this.getPerformanceMetrics(),
      ...metrics
    };

    this.log('INFO', `Performance: ${operation}`, { 
      ...metadata, 
      performanceMetrics: fullMetrics 
    });
  }

  // Security event logging
  security(event: string, riskLevel: 'low' | 'medium' | 'high' | 'critical', context: SecurityContext, details?: any): void {
    const securityLog = {
      securityEvent: event,
      riskLevel,
      context,
      details
    };

    const level: LogLevel = riskLevel === 'critical' ? 'CRITICAL' : 
                           riskLevel === 'high' ? 'ERROR' : 
                           riskLevel === 'medium' ? 'WARN' : 'INFO';

    this.log(level, `Security Event: ${event} (${riskLevel} risk)`, securityLog);
  }

  // Create child logger with additional context
  child(additionalContext: Partial<LogContext>): VpnLogger {
    return new VpnLogger({
      ...this.context,
      ...additionalContext,
      correlationId: this.correlationId // Preserve correlation ID
    });
  }

  // Get current correlation ID for request tracing
  getCorrelationId(): string {
    return this.correlationId;
  }

  // Update context dynamically
  updateContext(updates: Partial<LogContext>): void {
    this.context = { ...this.context, ...updates };
  }
}

// Factory function for creating loggers
export function createLogger(context: LogContext): VpnLogger {
  return new VpnLogger(context);
}

// Helper for extracting context from Lambda events
export function extractLogContext(event: any, context: any, functionName: string): LogContext {
  const baseContext: LogContext = {
    requestId: context.awsRequestId,
    environment: process.env.ENVIRONMENT || 'unknown',
    functionName,
    correlationId: event.headers?.['x-correlation-id'] || event.requestId
  };

  // Extract additional context from different event types
  if (event.headers) {
    // API Gateway event
    baseContext.userAgent = event.headers['User-Agent'] || event.headers['user-agent'];
    baseContext.sourceIP = event.requestContext?.identity?.sourceIp;
    baseContext.correlationId = event.headers['X-Correlation-ID'] || event.headers['x-correlation-id'];
  }

  if (event.body && typeof event.body === 'string') {
    try {
      const parsed = JSON.parse(event.body);
      baseContext.userId = parsed.user || parsed.user_name;
    } catch (e) {
      // Ignore parsing errors
    }
  }

  if (event.user || event.user_name) {
    baseContext.userId = event.user || event.user_name;
  }

  return baseContext;
}

// Performance monitoring decorator
export function withPerformanceLogging<T extends (...args: any[]) => any>(
  operation: string,
  fn: T,
  logger: VpnLogger
): T {
  return ((...args: any[]) => {
    const start = process.hrtime();
    const startTime = Date.now();

    try {
      const result = fn(...args);

      // Handle both sync and async functions
      if (result && typeof result.then === 'function') {
        return result
          .then((value: any) => {
            const [seconds, nanoseconds] = process.hrtime(start);
            const duration = seconds * 1000 + nanoseconds / 1000000;
            
            logger.performance(operation, { 
              duration: Math.round(duration * 100) / 100,
              apiCalls: 1
            }, { success: true });
            
            return value;
          })
          .catch((error: any) => {
            const [seconds, nanoseconds] = process.hrtime(start);
            const duration = seconds * 1000 + nanoseconds / 1000000;
            
            logger.performance(operation, { 
              duration: Math.round(duration * 100) / 100,
              apiCalls: 1
            }, { success: false, error: error instanceof Error ? error.message : String(error) });
            
            throw error;
          });
      } else {
        const [seconds, nanoseconds] = process.hrtime(start);
        const duration = seconds * 1000 + nanoseconds / 1000000;
        
        logger.performance(operation, { 
          duration: Math.round(duration * 100) / 100
        }, { success: true });
        
        return result;
      }
    } catch (error) {
      const [seconds, nanoseconds] = process.hrtime(start);
      const duration = seconds * 1000 + nanoseconds / 1000000;
      
      logger.performance(operation, { 
        duration: Math.round(duration * 100) / 100
      }, { success: false, error: error instanceof Error ? error.message : String(error) });
      
      throw error;
    }
  }) as T;
}

// Export default logger instance for backward compatibility
export const defaultLogger = createLogger({
  requestId: 'default',
  environment: process.env.ENVIRONMENT || 'unknown',
  functionName: 'shared'
});