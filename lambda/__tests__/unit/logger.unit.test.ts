// Epic 4.1: Comprehensive Logging Unit Tests
// Simple unit tests to verify the logging functionality

import { createLogger, extractLogContext, withPerformanceLogging } from '../../shared/logger';

// Mock console.log to capture structured logs
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

describe('Epic 4.1: Logger Unit Tests', () => {
  beforeEach(() => {
    logCaptures.length = 0;
  });

  it('should create logger with proper context', () => {
    const logger = createLogger({
      requestId: 'test-123',
      environment: 'staging',
      functionName: 'test-function'
    });

    expect(logger).toBeDefined();
    expect(logger.getCorrelationId()).toBeDefined();
  });

  it('should generate structured log entries', () => {
    const logger = createLogger({
      requestId: 'test-123',
      environment: 'staging',
      functionName: 'test-function'
    });

    logger.info('Test message', { key: 'value' });

    const logEntry = logCaptures.find(log => log.message === 'Test message');
    expect(logEntry).toBeDefined();
    expect(logEntry.level).toBe('INFO');
    expect(logEntry.context.requestId).toBe('test-123');
    expect(logEntry.context.environment).toBe('staging');
    expect(logEntry.metadata.key).toBe('value');
  });

  it('should support audit logging', () => {
    const logger = createLogger({
      requestId: 'test-123',
      environment: 'staging',
      functionName: 'test-function'
    });

    logger.audit('Test operation', 'test_resource', 'success', {
      testData: 'value'
    });

    const auditLog = logCaptures.find(log => log.audit);
    expect(auditLog).toBeDefined();
    expect(auditLog.audit.operation).toBe('Test operation');
    expect(auditLog.audit.resource).toBe('test_resource');
    expect(auditLog.audit.outcome).toBe('success');
  });

  it('should support performance monitoring', async () => {
    const logger = createLogger({
      requestId: 'test-123',
      environment: 'staging',
      functionName: 'test-function'
    });

    const mockOperation = jest.fn().mockResolvedValue('result');
    
    const result = await withPerformanceLogging(
      'test-operation',
      mockOperation,
      logger
    )();

    expect(result).toBe('result');
    expect(mockOperation).toHaveBeenCalled();

    const performanceLog = logCaptures.find(log => 
      log.message === 'Performance: test-operation'
    );
    expect(performanceLog).toBeDefined();
    expect(performanceLog.metadata.success).toBe(true);
  });

  it('should create child loggers with inherited correlation ID', () => {
    const parentLogger = createLogger({
      requestId: 'parent-123',
      environment: 'staging',
      functionName: 'parent-function'
    });

    const childLogger = parentLogger.child({
      functionName: 'child-function'
    });

    parentLogger.info('Parent message');
    childLogger.info('Child message');

    const parentLog = logCaptures.find(log => log.message === 'Parent message');
    const childLog = logCaptures.find(log => log.message === 'Child message');

    expect(parentLog.context.correlationId).toBeDefined();
    expect(childLog.context.correlationId).toBe(parentLog.context.correlationId);
    expect(childLog.context.functionName).toBe('child-function');
  });

  it('should extract log context from API Gateway events', () => {
    const mockEvent = {
      headers: {
        'User-Agent': 'Test-Agent/1.0',
        'X-Correlation-ID': 'test-correlation-123'
      },
      body: JSON.stringify({ user: 'test-user' }),
      requestContext: {
        identity: { sourceIp: '192.168.1.100' }
      }
    };

    const mockContext = {
      awsRequestId: 'aws-request-123'
    };

    const logContext = extractLogContext(mockEvent, mockContext, 'test-function');

    expect(logContext.requestId).toBe('aws-request-123');
    expect(logContext.functionName).toBe('test-function');
    expect(logContext.userAgent).toBe('Test-Agent/1.0');
    expect(logContext.sourceIP).toBe('192.168.1.100');
    expect(logContext.userId).toBe('test-user');
    expect(logContext.correlationId).toBe('test-correlation-123');
  });
});