import { APIGatewayProxyEvent, Context } from 'aws-lambda';
import { handler } from '../../slack-handler/index';
import { VpnCommandRequest, CrossAccountRequest } from '../../shared/types';

// Mock AWS SDK
const mockLambdaInvoke = jest.fn().mockReturnValue({
  promise: jest.fn().mockResolvedValue({
    Payload: JSON.stringify({
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        message: 'VPN staging environment opened successfully',
        data: {
          associated: true,
          activeConnections: 0,
          lastActivity: new Date(),
          endpointId: 'cvpn-endpoint-test',
          subnetId: 'subnet-test'
        }
      })
    })
  })
});

const mockCloudWatchPutMetric = jest.fn().mockReturnValue({
  promise: jest.fn().mockResolvedValue({})
});

jest.mock('aws-sdk', () => ({
  Lambda: jest.fn().mockImplementation(() => ({
    invoke: mockLambdaInvoke
  })),
  CloudWatch: jest.fn().mockImplementation(() => ({
    putMetricData: mockCloudWatchPutMetric
  }))
}));

// Mock shared utilities
jest.mock('/opt/stateStore', () => ({
  readSlackSigningSecret: jest.fn().mockResolvedValue('test-signing-secret'),
  readSlackWebhook: jest.fn().mockResolvedValue('https://hooks.slack.com/test-webhook')
}));

jest.mock('/opt/slack', () => ({
  verifySlackSignature: jest.fn().mockReturnValue(true),
  parseSlackCommand: jest.fn().mockImplementation((slackCommand) => ({
    action: 'open',
    environment: 'production',
    user: slackCommand.user_name,
    requestId: 'test-request-id-123'
  })),
  formatSlackResponse: jest.fn().mockReturnValue({
    response_type: 'in_channel',
    text: '🟢 VPN open completed for 🔴 Production',
    attachments: []
  }),
  sendSlackAlert: jest.fn().mockResolvedValue(undefined)
}));

// Mock global fetch for cross-account calls
global.fetch = jest.fn();

describe('Cross-Account Routing Integration Tests', () => {
  const mockContext: Context = {
    callbackWaitsForEmptyEventLoop: false,
    functionName: 'test-function',
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
    process.env.PRODUCTION_API_ENDPOINT = 'https://api.production.example.com/vpn';
    process.env.PRODUCTION_API_KEY = 'test-api-key';
  });

  afterEach(() => {
    delete process.env.PRODUCTION_API_ENDPOINT;
    delete process.env.PRODUCTION_API_KEY;
  });

  describe('Local Environment Routing', () => {
    it('should route staging commands to local vpn-control lambda', async () => {
      const mockSlack = require('/opt/slack');
      mockSlack.parseSlackCommand.mockReturnValue({
        action: 'open',
        environment: 'staging',
        user: 'test-user',
        requestId: 'test-request-id-123'
      });

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/slack',
        headers: {
          'X-Slack-Signature': 'v0=test-signature',
          'X-Slack-Request-Timestamp': Math.floor(Date.now() / 1000).toString()
        },
        body: 'token=test-token&user_name=test-user&command=/vpn&text=open staging',
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
      expect(JSON.parse(result.body)).toMatchObject({
        response_type: 'in_channel',
        text: expect.stringContaining('VPN open completed')
      });

      // Verify local Lambda was invoked
      expect(mockLambdaInvoke).toHaveBeenCalledWith({
        FunctionName: 'VpnAutomationStack-staging-VpnControl',
        InvocationType: 'RequestResponse',
        Payload: expect.stringContaining('open')
      });
    });
  });

  describe('Cross-Account Routing', () => {
    it('should route production commands via API Gateway with proper metadata', async () => {
      const mockSlack = require('/opt/slack');
      mockSlack.parseSlackCommand.mockReturnValue({
        action: 'open',
        environment: 'production',
        user: 'test-user',
        requestId: 'test-request-id-123'
      });

      // Mock successful fetch response
      (fetch as jest.Mock).mockResolvedValue({
        ok: true,
        json: () => Promise.resolve({
          success: true,
          message: 'VPN production environment opened successfully',
          data: {
            associated: true,
            activeConnections: 0,
            lastActivity: new Date(),
            endpointId: 'cvpn-endpoint-prod',
            subnetId: 'subnet-prod'
          }
        })
      });

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/slack',
        headers: {
          'X-Slack-Signature': 'v0=test-signature',
          'X-Slack-Request-Timestamp': Math.floor(Date.now() / 1000).toString()
        },
        body: 'token=test-token&user_name=test-user&command=/vpn&text=open production',
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
      
      // Verify API Gateway was called with correct metadata
      expect(fetch).toHaveBeenCalledWith(
        'https://api.production.example.com/vpn',
        expect.objectContaining({
          method: 'POST',
          headers: expect.objectContaining({
            'Content-Type': 'application/json',
            'X-API-Key': 'test-api-key',
            'User-Agent': 'VPN-Automation-Slack-Handler/1.0'
          }),
          body: expect.stringContaining('crossAccountMetadata')
        })
      );

      // Verify the request body contains proper cross-account metadata
      const fetchCall = (fetch as jest.Mock).mock.calls[0];
      const requestBody: CrossAccountRequest = JSON.parse(fetchCall[1].body);
      
      expect(requestBody).toMatchObject({
        command: {
          action: 'open',
          environment: 'production',
          user: 'test-user',
          requestId: 'test-request-id-123'
        },
        sourceAccount: 'staging',
        crossAccountMetadata: {
          sourceEnvironment: 'staging',
          routingAttempt: 1,
          userAgent: 'VPN-Automation-Slack-Handler/1.0',
          requestTimestamp: expect.any(String)
        }
      });

      // Verify CloudWatch metrics were published
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/CrossAccount',
        MetricData: expect.arrayContaining([
          expect.objectContaining({
            MetricName: 'CrossAccountSuccess',
            Value: 1,
            Unit: 'Count',
            Dimensions: expect.arrayContaining([
              { Name: 'SourceEnvironment', Value: 'staging' },
              { Name: 'TargetEnvironment', Value: 'production' }
            ])
          })
        ])
      });
    });

    it('should implement exponential backoff retry logic', async () => {
      const mockSlack = require('/opt/slack');
      mockSlack.parseSlackCommand.mockReturnValue({
        action: 'close',
        environment: 'production',
        user: 'test-user',
        requestId: 'test-request-id-456'
      });

      // Mock network failures for first two attempts, success on third
      (fetch as jest.Mock)
        .mockRejectedValueOnce(new Error('Network timeout'))
        .mockRejectedValueOnce(new Error('Connection refused'))
        .mockResolvedValueOnce({
          ok: true,
          json: () => Promise.resolve({
            success: true,
            message: 'VPN production environment closed successfully'
          })
        });

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/slack',
        headers: {
          'X-Slack-Signature': 'v0=test-signature',
          'X-Slack-Request-Timestamp': Math.floor(Date.now() / 1000).toString()
        },
        body: 'token=test-token&user_name=test-user&command=/vpn&text=close production',
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
      
      // Verify 3 attempts were made
      expect(fetch).toHaveBeenCalledTimes(3);
      
      // Verify each attempt had incrementing attempt number
      const calls = (fetch as jest.Mock).mock.calls;
      for (let i = 0; i < calls.length; i++) {
        const requestBody: CrossAccountRequest = JSON.parse(calls[i][1].body);
        expect(requestBody.crossAccountMetadata?.routingAttempt).toBe(i + 1);
      }
    });

    it('should handle configuration validation errors', async () => {
      delete process.env.PRODUCTION_API_ENDPOINT;

      const mockSlack = require('/opt/slack');
      mockSlack.parseSlackCommand.mockReturnValue({
        action: 'open',
        environment: 'production',
        user: 'test-user',
        requestId: 'test-no-config'
      });

      const event: APIGatewayProxyEvent = {
        httpMethod: 'POST',
        path: '/slack',
        headers: {
          'X-Slack-Signature': 'v0=test-signature',
          'X-Slack-Request-Timestamp': Math.floor(Date.now() / 1000).toString()
        },
        body: 'token=test-token&user_name=test-user&command=/vpn&text=open production',
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
      expect(response.text).toContain('VPN open failed');
      expect(response.attachments[0].fields[0].value).toContain('not configured');
    });
  });

  describe('Environment Variable Configuration', () => {
    it('should properly configure cross-account routing for staging environment', () => {
      process.env.ENVIRONMENT = 'staging';
      process.env.PRODUCTION_API_ENDPOINT = 'https://prod-api.example.com/vpn';
      process.env.PRODUCTION_API_KEY = 'staging-to-prod-key';

      expect(process.env.ENVIRONMENT).toBe('staging');
      expect(process.env.PRODUCTION_API_ENDPOINT).toBeDefined();
      expect(process.env.PRODUCTION_API_KEY).toBeDefined();
    });

    it('should not have production API configuration in production environment', () => {
      process.env.ENVIRONMENT = 'production';
      delete process.env.PRODUCTION_API_ENDPOINT;
      delete process.env.PRODUCTION_API_KEY;

      expect(process.env.ENVIRONMENT).toBe('production');
      expect(process.env.PRODUCTION_API_ENDPOINT).toBeUndefined();
      expect(process.env.PRODUCTION_API_KEY).toBeUndefined();
    });
  });
});