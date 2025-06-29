// Epic 4.1: Comprehensive Logging Integration Tests
// Tests structured logging, audit trails, performance monitoring, and security logging

import { APIGatewayProxyEvent, Context, ScheduledEvent } from 'aws-lambda';
import { handler as slackHandler } from '../../slack-handler/index';
import { handler as vpnControlHandler } from '../../vpn-control/index';
import { handler as vpnMonitorHandler } from '../../vpn-monitor/index';
import { createLogger, extractLogContext, withPerformanceLogging } from '../../shared/logger';

// Mock AWS SDK and console methods to capture logs
const mockCloudWatchPutMetric = jest.fn().mockReturnValue({
  promise: jest.fn().mockResolvedValue({})
});

jest.mock('aws-sdk', () => ({
  CloudWatch: jest.fn().mockImplementation(() => ({
    putMetricData: mockCloudWatchPutMetric
  })),
  Lambda: jest.fn().mockImplementation(() => ({
    invoke: jest.fn().mockReturnValue({
      promise: jest.fn().mockResolvedValue({
        Payload: JSON.stringify({
          statusCode: 200,
          body: JSON.stringify({ success: true, message: 'Test response' })
        })
      })
    })
  }))
}));

// Mock shared utilities
jest.mock('/opt/stateStore', () => ({
  validateParameterStore: jest.fn().mockResolvedValue(true),
  readSlackSigningSecret: jest.fn().mockResolvedValue('test-secret'),
  readState: jest.fn().mockResolvedValue({
    associated: true,
    lastActivity: new Date(Date.now() - 70 * 60 * 1000).toISOString()
  }),
  readConfig: jest.fn().mockResolvedValue({
    ENDPOINT_ID: 'cvpn-endpoint-test',
    SUBNET_ID: 'subnet-test'
  }),
  readParameter: jest.fn().mockRejectedValue(new Error('Parameter not found')),
  writeParameter: jest.fn().mockResolvedValue(undefined)
}));

jest.mock('/opt/vpnManager', () => ({
  validateEndpoint: jest.fn().mockResolvedValue(true),
  fetchStatus: jest.fn().mockResolvedValue({
    associated: true,
    activeConnections: 0,
    lastActivity: new Date(Date.now() - 70 * 60 * 1000),
    endpointId: 'cvpn-endpoint-test',
    subnetId: 'subnet-test'
  }),
  disassociateSubnets: jest.fn().mockResolvedValue(undefined),
  associateSubnets: jest.fn().mockResolvedValue(undefined),
  updateLastActivity: jest.fn().mockResolvedValue(undefined)
}));

jest.mock('/opt/slack', () => ({
  verifySlackSignature: jest.fn().mockReturnValue(true),
  parseSlackCommand: jest.fn().mockReturnValue({
    action: 'open',
    environment: 'staging',
    user: 'test-user',
    requestId: 'test-request-123'
  }),
  formatSlackResponse: jest.fn().mockReturnValue({
    response_type: 'in_channel',
    text: 'Test response'
  }),
  sendSlackAlert: jest.fn().mockResolvedValue(undefined),
  sendSlackNotification: jest.fn().mockResolvedValue(undefined)
}));

// Capture console output for log analysis
const originalConsoleLog = console.log;
const logCaptures: any[] = [];

beforeAll(() => {
  console.log = jest.fn().mockImplementation((message) => {
    if (typeof message === 'string' && message.startsWith('{')) {
      try {
        const logEntry = JSON.parse(message);
        logCaptures.push(logEntry);
      } catch (e) {
        // Not a JSON log entry
      }
    }
    originalConsoleLog(message);
  });
});

afterAll(() => {
  console.log = originalConsoleLog;
});

describe('Epic 4.1: Comprehensive Logging Integration Tests', () => {
  const mockContext: Context = {
    callbackWaitsForEmptyEventLoop: false,
    functionName: 'test-function',
    functionVersion: '1',
    invokedFunctionArn: 'arn:aws:lambda:test',
    memoryLimitInMB: '128',
    awsRequestId: 'test-request-id-123',
    logGroupName: 'test-log-group',
    logStreamName: 'test-log-stream',
    getRemainingTimeInMillis: () => 30000,
    done: jest.fn(),
    fail: jest.fn(),
    succeed: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
    logCaptures.length = 0;
    process.env.ENVIRONMENT = 'staging';
    process.env.IDLE_MINUTES = '54';
    process.env.BUSINESS_HOURS_PROTECTION = 'false';
  });

  describe('Structured Logging Core Functionality', () => {
    it('should create logger with proper context extraction', () => {
      const mockEvent: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/vpn',
        headers: {
          'User-Agent': 'Test-Agent/1.0',
          'X-Correlation-ID': 'test-correlation-123'
        },
        body: JSON.stringify({ user: 'test-user' }),
        requestContext: {
          identity: { sourceIp: '192.168.1.100' }
        } as any,
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        resource: '',
        multiValueQueryStringParameters: null
      };

      const logContext = extractLogContext(mockEvent, mockContext, 'test-function');
      
      expect(logContext.requestId).toBe('test-request-id-123');
      expect(logContext.environment).toBe('staging');
      expect(logContext.functionName).toBe('test-function');
      expect(logContext.userAgent).toBe('Test-Agent/1.0');
      expect(logContext.sourceIP).toBe('192.168.1.100');
      expect(logContext.userId).toBe('test-user');
      expect(logContext.correlationId).toBe('test-correlation-123');
    });

    it('should generate structured log entries with all required fields', () => {
      const logger = createLogger({
        requestId: 'test-request-123',
        environment: 'staging',
        functionName: 'test-function'
      });

      logger.info('Test log message', { key: 'value' });

      const logEntry = logCaptures.find(log => log.message === 'Test log message');
      expect(logEntry).toBeDefined();
      expect(logEntry.level).toBe('INFO');
      expect(logEntry.timestamp).toBeDefined();
      expect(logEntry.context.requestId).toBe('test-request-123');
      expect(logEntry.context.environment).toBe('staging');
      expect(logEntry.context.functionName).toBe('test-function');
      expect(logEntry.context.correlationId).toBeDefined();
      expect(logEntry.metadata.key).toBe('value');
      expect(logEntry.performance).toBeDefined();
      expect(logEntry.performance.duration).toBeGreaterThan(0);
      expect(logEntry.tags).toContain('env:staging');
      expect(logEntry.tags).toContain('function:test-function');
      expect(logEntry.tags).toContain('level:info');
    });

    it('should support all log levels with proper escalation', () => {
      const logger = createLogger({
        requestId: 'test-request-123',
        environment: 'staging',
        functionName: 'test-function'
      });

      logger.debug('Debug message');
      logger.info('Info message');
      logger.warn('Warning message');
      logger.error('Error message', new Error('Test error'));
      logger.critical('Critical message', new Error('Critical error'));

      const debugLog = logCaptures.find(log => log.message === 'Debug message');
      const infoLog = logCaptures.find(log => log.message === 'Info message');
      const warnLog = logCaptures.find(log => log.message === 'Warning message');
      const errorLog = logCaptures.find(log => log.message === 'Error message');
      const criticalLog = logCaptures.find(log => log.message === 'Critical message');

      expect(debugLog.level).toBe('DEBUG');
      expect(infoLog.level).toBe('INFO');
      expect(warnLog.level).toBe('WARN');
      expect(errorLog.level).toBe('ERROR');
      expect(criticalLog.level).toBe('CRITICAL');

      // Error logs should include error details
      expect(errorLog.error.name).toBe('Error');
      expect(errorLog.error.message).toBe('Test error');
      expect(criticalLog.error.stack).toBeDefined();

      // Critical and error logs should trigger CloudWatch metrics
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith(
        expect.objectContaining({
          Namespace: 'VPN/Logging',
          MetricData: expect.arrayContaining([
            expect.objectContaining({
              MetricName: 'ERRORErrors'
            })
          ])
        })
      );
    });
  });

  describe('Audit Trail Implementation', () => {
    it('should capture audit events for VPN operations', () => {
      const logger = createLogger({
        requestId: 'test-request-123',
        environment: 'staging',
        functionName: 'vpn-control'
      });

      logger.audit('VPN open operation', 'vpn_endpoint', 'success', {
        endpointId: 'cvpn-endpoint-123',
        subnetId: 'subnet-123',
        user: 'test-user',
        duration: 1500
      });

      const auditLog = logCaptures.find(log => log.audit);
      expect(auditLog).toBeDefined();
      expect(auditLog.audit.operation).toBe('VPN open operation');
      expect(auditLog.audit.resource).toBe('vpn_endpoint');
      expect(auditLog.audit.outcome).toBe('success');
      expect(auditLog.audit.details.endpointId).toBe('cvpn-endpoint-123');
      expect(auditLog.audit.details.user).toBe('test-user');
      expect(auditLog.audit.performanceMetrics).toBeDefined();
      expect(auditLog.tags).toContain('operation:VPN open operation');
      expect(auditLog.tags).toContain('outcome:success');
      expect(auditLog.tags).toContain('resource:vpn_endpoint');
    });

    it('should create audit trail for failed operations', () => {
      const logger = createLogger({
        requestId: 'test-request-123',
        environment: 'production',
        functionName: 'vpn-control'
      });

      logger.audit('VPN close operation', 'vpn_endpoint', 'failure', {
        endpointId: 'cvpn-endpoint-123',
        error: 'Subnet disassociation failed',
        user: 'admin-user'
      });

      const auditLog = logCaptures.find(log => log.audit && log.audit.outcome === 'failure');
      expect(auditLog).toBeDefined();
      expect(auditLog.audit.outcome).toBe('failure');
      expect(auditLog.audit.details.error).toBe('Subnet disassociation failed');
      expect(auditLog.context.environment).toBe('production');
      expect(auditLog.tags).toContain('outcome:failure');
    });
  });

  describe('Performance Monitoring', () => {
    it('should track performance metrics for operations', async () => {
      const logger = createLogger({
        requestId: 'test-request-123',
        environment: 'staging',
        functionName: 'test-function'
      });

      const mockOperation = jest.fn().mockResolvedValue('operation result');
      
      const result = await withPerformanceLogging(
        'test-operation',
        mockOperation,
        logger
      )();

      expect(result).toBe('operation result');
      expect(mockOperation).toHaveBeenCalled();

      const performanceLog = logCaptures.find(log => 
        log.message === 'Performance: test-operation'
      );
      
      expect(performanceLog).toBeDefined();
      expect(performanceLog.metadata.performanceMetrics.duration).toBeGreaterThan(0);
      expect(performanceLog.metadata.performanceMetrics.apiCalls).toBe(1);
      expect(performanceLog.metadata.success).toBe(true);
    });

    it('should handle performance monitoring for failed operations', async () => {
      const logger = createLogger({
        requestId: 'test-request-123',
        environment: 'staging',
        functionName: 'test-function'
      });

      const mockOperation = jest.fn().mockRejectedValue(new Error('Operation failed'));
      
      await expect(
        withPerformanceLogging('failing-operation', mockOperation, logger)()
      ).rejects.toThrow('Operation failed');

      const performanceLog = logCaptures.find(log => 
        log.message === 'Performance: failing-operation'
      );
      
      expect(performanceLog).toBeDefined();
      expect(performanceLog.metadata.success).toBe(false);
      expect(performanceLog.metadata.error).toBe('Operation failed');
    });

    it('should include memory and performance metrics in logs', () => {
      const logger = createLogger({
        requestId: 'test-request-123',
        environment: 'staging',
        functionName: 'test-function'
      });

      logger.performance('memory-intensive-operation', {
        duration: 2500,
        memoryUsed: 128.5,
        dbOperations: 5,
        networkLatency: 150
      }, { operationType: 'database_query' });

      const performanceLog = logCaptures.find(log => 
        log.message === 'Performance: memory-intensive-operation'
      );
      
      expect(performanceLog).toBeDefined();
      expect(performanceLog.metadata.performanceMetrics.duration).toBe(2500);
      expect(performanceLog.metadata.performanceMetrics.memoryUsed).toBe(128.5);
      expect(performanceLog.metadata.performanceMetrics.dbOperations).toBe(5);
      expect(performanceLog.metadata.performanceMetrics.networkLatency).toBe(150);
      expect(performanceLog.metadata.operationType).toBe('database_query');
    });
  });

  describe('Security Event Logging', () => {
    it('should log security events with risk levels', () => {
      const logger = createLogger({
        requestId: 'test-request-123',
        environment: 'production',
        functionName: 'slack-handler'
      });

      logger.security('Suspicious authentication attempt', 'high', {
        authenticationMethod: 'slack_signature',
        riskScore: 9,
        geolocation: 'Unknown',
        threatDetection: ['signature_mismatch', 'unusual_timing']
      }, {
        sourceIP: '192.168.1.100',
        userAgent: 'Suspicious-Agent/1.0',
        attemptCount: 5
      });

      const securityLog = logCaptures.find(log => 
        log.message.includes('Suspicious authentication attempt')
      );
      
      expect(securityLog).toBeDefined();
      expect(securityLog.level).toBe('ERROR'); // High risk maps to ERROR
      expect(securityLog.metadata.securityEvent).toBe('Suspicious authentication attempt');
      expect(securityLog.metadata.riskLevel).toBe('high');
      expect(securityLog.metadata.context.riskScore).toBe(9);
      expect(securityLog.metadata.context.threatDetection).toContain('signature_mismatch');
      expect(securityLog.metadata.details.sourceIP).toBe('192.168.1.100');
    });

    it('should escalate critical security events appropriately', () => {
      const logger = createLogger({
        requestId: 'test-request-123',
        environment: 'production',
        functionName: 'vpn-control'
      });

      logger.security('Unauthorized VPN access attempt', 'critical', {
        authenticationMethod: 'api_key',
        riskScore: 10,
        geolocation: 'Blacklisted Country'
      });

      const securityLog = logCaptures.find(log => 
        log.message.includes('Unauthorized VPN access attempt')
      );
      
      expect(securityLog).toBeDefined();
      expect(securityLog.level).toBe('CRITICAL');
      expect(securityLog.metadata.riskLevel).toBe('critical');
      
      // Critical security events should trigger CloudWatch metrics
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith(
        expect.objectContaining({
          Namespace: 'VPN/Logging',
          MetricData: expect.arrayContaining([
            expect.objectContaining({
              MetricName: 'CRITICALErrors'
            })
          ])
        })
      );
    });
  });

  describe('Request Correlation and Tracing', () => {
    it('should maintain correlation IDs across function calls', () => {
      const parentLogger = createLogger({
        requestId: 'parent-request-123',
        environment: 'staging',
        functionName: 'parent-function'
      });

      const childLogger = parentLogger.child({ 
        functionName: 'child-function' 
      });

      parentLogger.info('Parent operation started');
      childLogger.info('Child operation started');

      const parentLog = logCaptures.find(log => log.message === 'Parent operation started');
      const childLog = logCaptures.find(log => log.message === 'Child operation started');

      expect(parentLog.context.correlationId).toBeDefined();
      expect(childLog.context.correlationId).toBe(parentLog.context.correlationId);
      expect(childLog.context.functionName).toBe('child-function');
      expect(childLog.tags).toContain('correlation:' + parentLog.context.correlationId);
    });

    it('should include correlation IDs in HTTP headers', async () => {
      const mockEvent: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/vpn',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          token: 'test-token',
          user_name: 'test-user',
          text: 'open staging',
          response_url: 'https://hooks.slack.com/test'
        }),
        requestContext: {} as any,
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        resource: '',
        multiValueQueryStringParameters: null
      };

      const result = await slackHandler(mockEvent, mockContext);
      
      expect(result.statusCode).toBe(200);
      expect(result.headers && result.headers['X-Correlation-ID']).toBeDefined();
      
      // Find log entries with correlation ID
      const correlationId = result.headers ? result.headers['X-Correlation-ID'] : '';
      const logsWithCorrelation = logCaptures.filter(log => 
        log.context && log.context.correlationId === correlationId
      );
      
      expect(logsWithCorrelation.length).toBeGreaterThan(0);
    });
  });

  describe('Lambda Function Integration', () => {
    it('should integrate comprehensive logging in slack-handler', async () => {
      const mockEvent: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/slack',
        headers: { 
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-Slack-Signature': 'v0=test-signature',
          'X-Slack-Request-Timestamp': Math.floor(Date.now() / 1000).toString()
        },
        body: 'token=test-token&user_name=test-user&text=check staging',
        requestContext: {
          identity: { sourceIp: '192.168.1.100' }
        } as any,
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        resource: '',
        multiValueQueryStringParameters: null
      };

      await slackHandler(mockEvent, mockContext);

      // Verify structured logging is present
      const invocationLog = logCaptures.find(log => 
        log.message === 'Slack Handler Lambda invoked'
      );
      expect(invocationLog).toBeDefined();
      expect(invocationLog.context.functionName).toBe('slack-handler');
      expect(invocationLog.metadata.httpMethod).toBe('POST');
      expect(invocationLog.metadata.sourceIP).toBe('192.168.1.100');

      // Verify audit logging
      const auditLogs = logCaptures.filter(log => log.audit);
      expect(auditLogs.length).toBeGreaterThan(0);
    });

    it('should integrate comprehensive logging in vpn-monitor', async () => {
      const mockScheduledEvent: ScheduledEvent = {
        version: '0',
        id: 'scheduled-event-123',
        'detail-type': 'Scheduled Event',
        source: 'aws.events',
        account: '123456789012',
        time: new Date().toISOString(),
        region: 'us-east-1',
        resources: ['arn:aws:events:us-east-1:123456789012:rule/vpn-monitor'],
        detail: {}
      };

      await vpnMonitorHandler(mockScheduledEvent, mockContext);

      // Verify structured logging
      const invocationLog = logCaptures.find(log => 
        log.message === 'VPN Monitor Lambda triggered'
      );
      expect(invocationLog).toBeDefined();
      expect(invocationLog.context.functionName).toBe('vpn-monitor');
      expect(invocationLog.metadata.eventSource).toBe('aws.events');

      // Verify performance monitoring
      const performanceLogs = logCaptures.filter(log => 
        log.message && log.message.startsWith('Performance:')
      );
      expect(performanceLogs.length).toBeGreaterThan(0);

      // Verify audit trail for VPN operations
      const auditLogs = logCaptures.filter(log => log.audit);
      expect(auditLogs.length).toBeGreaterThan(0);
    });
  });

  describe('Error Handling and Recovery', () => {
    it('should handle logging failures gracefully', () => {
      // Mock CloudWatch failure
      mockCloudWatchPutMetric.mockRejectedValueOnce(new Error('CloudWatch unavailable'));

      const logger = createLogger({
        requestId: 'test-request-123',
        environment: 'staging',
        functionName: 'test-function'
      });

      // Should not throw even if CloudWatch metrics fail
      expect(() => {
        logger.critical('Test critical message', new Error('Test error'));
      }).not.toThrow();

      const criticalLog = logCaptures.find(log => 
        log.message === 'Test critical message'
      );
      expect(criticalLog).toBeDefined();
      expect(criticalLog.level).toBe('CRITICAL');
    });

    it('should continue operation when individual log operations fail', () => {
      const logger = createLogger({
        requestId: 'test-request-123',
        environment: 'staging',
        functionName: 'test-function'
      });

      // Should continue logging even with malformed metadata
      logger.info('Test with circular reference', {
        circular: {}
      });

      // Add circular reference
      const metadata = { circular: {} };
      metadata.circular = metadata;

      logger.info('Test with problematic metadata', metadata);

      const infoLogs = logCaptures.filter(log => 
        log.message.startsWith('Test with')
      );
      expect(infoLogs.length).toBe(2);
    });
  });

  describe('Compliance and Retention', () => {
    it('should include all required fields for compliance audit', () => {
      const logger = createLogger({
        requestId: 'compliance-request-123',
        environment: 'production',
        functionName: 'vpn-control',
        userId: 'compliance-user'
      });

      logger.audit('Production VPN modification', 'vpn_endpoint', 'success', {
        endpointId: 'cvpn-endpoint-prod-123',
        modification: 'subnet_association',
        authorizedBy: 'admin@company.com',
        businessJustification: 'Emergency maintenance access',
        approvalTicket: 'TICKET-12345'
      }, {
        authenticationMethod: 'multi_factor',
        authorization: 'admin_role',
        riskScore: 3
      });

      const complianceAudit = logCaptures.find(log => 
        log.audit && log.audit.operation === 'Production VPN modification'
      );

      expect(complianceAudit).toBeDefined();
      expect(complianceAudit.timestamp).toBeDefined();
      expect(complianceAudit.context.environment).toBe('production');
      expect(complianceAudit.context.userId).toBe('compliance-user');
      expect(complianceAudit.audit.details.authorizedBy).toBe('admin@company.com');
      expect(complianceAudit.audit.details.businessJustification).toBeDefined();
      expect(complianceAudit.audit.details.approvalTicket).toBe('TICKET-12345');
      expect(complianceAudit.audit.securityContext.authenticationMethod).toBe('multi_factor');
    });
  });
});