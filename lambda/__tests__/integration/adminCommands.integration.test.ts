import { APIGatewayProxyEvent, Context } from 'aws-lambda';
import { handler } from '../../vpn-control/index';
import { VpnCommandRequest } from '../../shared/types';

// Mock AWS SDK
const mockCloudWatchPutMetric = jest.fn().mockReturnValue({
  promise: jest.fn().mockResolvedValue({})
});

jest.mock('aws-sdk', () => ({
  CloudWatch: jest.fn().mockImplementation(() => ({
    putMetricData: mockCloudWatchPutMetric
  }))
}));

// Mock shared utilities
jest.mock('/opt/nodejs/stateStore', () => ({
  readParameter: jest.fn().mockImplementation((key: string) => {
    if (key.includes('cumulative_savings/staging')) {
      return Promise.resolve('150.75');
    }
    if (key.includes('cumulative_savings/production')) {
      return Promise.resolve('425.25');
    }
    if (key.includes('daily_savings')) {
      const today = new Date().toISOString().split('T')[0];
      if (key.includes(today)) {
        return Promise.resolve('12.50');
      }
    }
    return Promise.reject(new Error('Parameter not found'));
  }),
  writeParameter: jest.fn().mockResolvedValue(undefined)
}));

jest.mock('/opt/nodejs/vpnManager', () => ({
  validateEndpoint: jest.fn().mockResolvedValue(true),
  fetchStatus: jest.fn().mockResolvedValue({
    associated: true,
    activeConnections: 2,
    lastActivity: new Date(),
    endpointId: 'cvpn-endpoint-test',
    subnetId: 'subnet-test'
  }),
  disassociateSubnets: jest.fn().mockResolvedValue(undefined)
}));

jest.mock('/opt/nodejs/slack', () => ({
  sendSlackNotification: jest.fn().mockResolvedValue(undefined)
}));

describe('Epic 3.2: Administrative Commands Integration Tests', () => {
  const mockContext: Context = {
    callbackWaitsForEmptyEventLoop: false,
    functionName: 'vpn-control',
    functionVersion: '1',
    invokedFunctionArn: 'arn:aws:lambda:test',
    memoryLimitInMB: '128',
    awsRequestId: 'test-request-id',
    logGroupName: 'test-log-group',
    logStreamName: 'test-log-stream',
    getRemainingTimeInMillis: () => 30000,
    done: jest.fn(),
    fail: jest.fn(),
    succeed: jest.fn()
  };

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.ENVIRONMENT = 'staging';
    process.env.COOLDOWN_MINUTES = '30';
  });

  describe('Administrative Override Commands', () => {
    it('should enable administrative override', async () => {
      const command: VpnCommandRequest = {
        action: 'admin-override' as any,
        environment: 'staging',
        user: 'admin-user',
        requestId: 'test-override'
      };

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/vpn',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(command),
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        requestContext: {} as any,
        resource: '',
        multiValueQueryStringParameters: null
      };

      const result = await handler(event, mockContext);
      expect(result.statusCode).toBe(200);

      const response = JSON.parse(result.body);
      expect(response.success).toBe(true);
      expect(response.message).toContain('Administrative override enabled');

      // Verify parameter was set with expiry
      const mockStateStore = require('/opt/nodejs/stateStore');
      expect(mockStateStore.writeParameter).toHaveBeenCalledWith(
        '/vpn/automation/admin_override/staging',
        expect.stringContaining('enabled:expires:')
      );

      // Verify metric was published
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/Automation',
        MetricData: expect.arrayContaining([
          expect.objectContaining({
            MetricName: 'AdminOverrideEnabled',
            Value: 1
          })
        ])
      });

      // Verify Slack notification
      const mockSlack = require('/opt/nodejs/slack');
      expect(mockSlack.sendSlackNotification).toHaveBeenCalledWith(
        expect.stringContaining('Administrative Override Enabled'),
        '#vpn-alerts'
      );
    });

    it('should clear administrative override', async () => {
      const command: VpnCommandRequest = {
        action: 'admin-clear-override' as any,
        environment: 'staging',
        user: 'admin-user',
        requestId: 'test-clear'
      };

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/vpn',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(command),
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        requestContext: {} as any,
        resource: '',
        multiValueQueryStringParameters: null
      };

      const result = await handler(event, mockContext);
      expect(result.statusCode).toBe(200);

      const response = JSON.parse(result.body);
      expect(response.success).toBe(true);
      expect(response.message).toContain('override cleared');

      // Verify parameter was cleared
      const mockStateStore = require('/opt/nodejs/stateStore');
      expect(mockStateStore.writeParameter).toHaveBeenCalledWith(
        '/vpn/automation/admin_override/staging',
        ''
      );

      // Verify metric was published
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/Automation',
        MetricData: expect.arrayContaining([
          expect.objectContaining({
            MetricName: 'AdminOverrideCleared',
            Value: 1
          })
        ])
      });
    });

    it('should check cooldown status', async () => {
      const mockStateStore = require('/opt/nodejs/stateStore');
      
      // Mock cooldown active (15 minutes ago)
      const cooldownStart = new Date(Date.now() - 15 * 60 * 1000);
      mockStateStore.readParameter.mockImplementation((key: string) => {
        if (key.includes('cooldown')) {
          return Promise.resolve(cooldownStart.toISOString());
        }
        return Promise.reject(new Error('Not found'));
      });

      const command: VpnCommandRequest = {
        action: 'admin-cooldown' as any,
        environment: 'staging',
        user: 'admin-user',
        requestId: 'test-cooldown'
      };

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/vpn',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(command),
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        requestContext: {} as any,
        resource: '',
        multiValueQueryStringParameters: null
      };

      const result = await handler(event, mockContext);
      expect(result.statusCode).toBe(200);

      const response = JSON.parse(result.body);
      expect(response.success).toBe(true);
      expect(response.data.cooldownActive).toBe(true);
      expect(response.data.remainingMinutes).toBe(15); // 30 - 15
    });

    it('should execute force close with cooldown bypass', async () => {
      const command: VpnCommandRequest = {
        action: 'admin-force-close' as any,
        environment: 'staging',
        user: 'admin-user',
        requestId: 'test-force-close'
      };

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/vpn',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(command),
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        requestContext: {} as any,
        resource: '',
        multiValueQueryStringParameters: null
      };

      const result = await handler(event, mockContext);
      expect(result.statusCode).toBe(200);

      const response = JSON.parse(result.body);
      expect(response.success).toBe(true);
      expect(response.message).toContain('force closed successfully');

      // Verify VPN was disassociated
      const mockVpnManager = require('/opt/nodejs/vpnManager');
      expect(mockVpnManager.disassociateSubnets).toHaveBeenCalled();

      // Verify cooldown was cleared
      const mockStateStore = require('/opt/nodejs/stateStore');
      expect(mockStateStore.writeParameter).toHaveBeenCalledWith(
        '/vpn/automation/cooldown/staging',
        ''
      );

      // Verify force close metric
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/Automation',
        MetricData: expect.arrayContaining([
          expect.objectContaining({
            MetricName: 'AdminForceCloseOperations',
            Value: 1
          })
        ])
      });
    });
  });

  describe('Cost Analysis Commands', () => {
    it('should generate cost savings report', async () => {
      const command: VpnCommandRequest = {
        action: 'cost-savings' as any,
        environment: 'staging',
        user: 'user',
        requestId: 'test-savings'
      };

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/vpn',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(command),
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        requestContext: {} as any,
        resource: '',
        multiValueQueryStringParameters: null
      };

      const result = await handler(event, mockContext);
      expect(result.statusCode).toBe(200);

      const response = JSON.parse(result.body);
      expect(response.success).toBe(true);
      expect(response.data.environment).toBe('staging');
      expect(response.data.cumulativeSavings).toBe('150.75');
      expect(response.data.todaySavings).toBe('12.50');
      expect(response.data.currentStatus).toBe('Running');
      expect(response.data.potentialHourlySavings).toBe('0.10');
    });

    it('should generate daily cost analysis', async () => {
      const command: VpnCommandRequest = {
        action: 'cost-analysis' as any,
        environment: 'daily' as any, // Using environment field for report type
        user: 'user',
        requestId: 'test-daily'
      };

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/vpn',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(command),
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        requestContext: {} as any,
        resource: '',
        multiValueQueryStringParameters: null
      };

      const result = await handler(event, mockContext);
      expect(result.statusCode).toBe(200);

      const response = JSON.parse(result.body);
      expect(response.success).toBe(true);
      expect(response.data.reportType).toBe('daily');
      expect(response.data.data).toHaveLength(7); // Last 7 days
      expect(response.data.data[0].date).toMatch(/\d{4}-\d{2}-\d{2}/);
    });

    it('should generate cumulative cost analysis', async () => {
      const command: VpnCommandRequest = {
        action: 'cost-analysis' as any,
        environment: 'cumulative' as any,
        user: 'user',
        requestId: 'test-cumulative'
      };

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/vpn',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(command),
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        requestContext: {} as any,
        resource: '',
        multiValueQueryStringParameters: null
      };

      const result = await handler(event, mockContext);
      expect(result.statusCode).toBe(200);

      const response = JSON.parse(result.body);
      expect(response.success).toBe(true);
      expect(response.data.reportType).toBe('cumulative');
      expect(response.data.data.stagingTotal).toBe(150.75);
      expect(response.data.data.productionTotal).toBe(425.25);
      expect(response.data.data.grandTotal).toBe(576); // 150.75 + 425.25
      expect(response.data.data.estimatedMonthlySavings).toBe(17280); // 576 * 30
    });
  });

  describe('Command Validation', () => {
    it('should reject invalid administrative actions', async () => {
      const command: VpnCommandRequest = {
        action: 'admin-invalid' as any,
        environment: 'staging',
        user: 'admin-user',
        requestId: 'test-invalid'
      };

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/vpn',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(command),
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        requestContext: {} as any,
        resource: '',
        multiValueQueryStringParameters: null
      };

      const result = await handler(event, mockContext);
      expect(result.statusCode).toBe(400);

      const response = JSON.parse(result.body);
      expect(response.success).toBe(false);
      expect(response.error).toContain('Invalid action');
    });

    it('should validate environment mismatch', async () => {
      process.env.ENVIRONMENT = 'production';
      
      const command: VpnCommandRequest = {
        action: 'admin-override' as any,
        environment: 'staging',
        user: 'admin-user',
        requestId: 'test-mismatch'
      };

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/vpn',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(command),
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        requestContext: {} as any,
        resource: '',
        multiValueQueryStringParameters: null
      };

      const result = await handler(event, mockContext);
      expect(result.statusCode).toBe(400);

      const response = JSON.parse(result.body);
      expect(response.success).toBe(false);
      expect(response.error).toContain('Environment mismatch');
    });
  });

  describe('Error Handling', () => {
    it('should handle parameter store errors gracefully', async () => {
      const mockStateStore = require('/opt/nodejs/stateStore');
      mockStateStore.writeParameter.mockRejectedValue(new Error('Parameter store error'));

      const command: VpnCommandRequest = {
        action: 'admin-override' as any,
        environment: 'staging',
        user: 'admin-user',
        requestId: 'test-error'
      };

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/vpn',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(command),
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        requestContext: {} as any,
        resource: '',
        multiValueQueryStringParameters: null
      };

      const result = await handler(event, mockContext);
      expect(result.statusCode).toBe(500);

      const response = JSON.parse(result.body);
      expect(response.success).toBe(false);
      expect(response.error).toContain('Failed to enable admin override');
    });

    it('should handle VPN manager errors in force close', async () => {
      const mockVpnManager = require('/opt/nodejs/vpnManager');
      mockVpnManager.disassociateSubnets.mockRejectedValue(new Error('VPN operation failed'));

      const command: VpnCommandRequest = {
        action: 'admin-force-close' as any,
        environment: 'staging',
        user: 'admin-user',
        requestId: 'test-vpn-error'
      };

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/vpn',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(command),
        isBase64Encoded: false,
        multiValueHeaders: {},
        pathParameters: null,
        queryStringParameters: null,
        stageVariables: null,
        requestContext: {} as any,
        resource: '',
        multiValueQueryStringParameters: null
      };

      const result = await handler(event, mockContext);
      expect(result.statusCode).toBe(500);

      const response = JSON.parse(result.body);
      expect(response.success).toBe(false);
      expect(response.error).toContain('Failed to force close');
    });
  });
});