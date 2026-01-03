import { APIGatewayProxyEvent, Context } from 'aws-lambda';
import { resetAllMocks, setMockResponse } from '../../__mocks__/aws-sdk';

// Import test fixtures
import vpnControlEvents from '../fixtures/vpnControlEvents.json';

// Import test handler with relative imports
import { handler } from '../helpers/vpn-control.test-handler';

describe('VPN Control Integration Tests', () => {
  const mockContext: Context = {
    callbackWaitsForEmptyEventLoop: false,
    functionName: 'vpn-control-test',
    functionVersion: '$LATEST',
    invokedFunctionArn: 'arn:aws:lambda:us-east-1:TEST_ACCOUNT_ID:function:vpn-control-test',
    memoryLimitInMB: '256',
    awsRequestId: 'test-request-id',
    logGroupName: '/aws/lambda/vpn-control-test',
    logStreamName: '2025/06/17/[$LATEST]abcdef123456',
    getRemainingTimeInMillis: () => 5000,
    done: jest.fn(),
    fail: jest.fn(),
    succeed: jest.fn()
  };

  beforeEach(() => {
    resetAllMocks();
    
    // Set environment to staging for most tests
    process.env.ENVIRONMENT = 'staging';
    
    // Mock successful endpoint validation
    setMockResponse('EC2', 'describeClientVpnEndpoints', {
      ClientVpnEndpoints: [{
        ClientVpnEndpointId: 'cvpn-endpoint-test123',
        Status: { Code: 'available' }
      }]
    });
  });

  describe('VPN Open Operation', () => {
    it('should successfully open VPN (associate subnets)', async () => {
      // Ensure environment matches the test request
      process.env.ENVIRONMENT = 'staging';
      
      const event = vpnControlEvents.vpnOpenStaging as unknown as APIGatewayProxyEvent;

      // Mock VPN as currently disassociated
      setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
        ClientVpnTargetNetworks: []
      });
      
      setMockResponse('EC2', 'describeClientVpnConnections', {
        Connections: []
      });

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(200);
      
      const body = JSON.parse(result.body);
      expect(body.success).toBe(true);
      expect(body.message).toContain('opened successfully');
      expect(body.data).toBeDefined();
      expect(body.data.associated).toBe(true);
    });

    it('should handle already associated VPN gracefully', async () => {
      const event = vpnControlEvents.vpnOpenStaging as unknown as unknown as APIGatewayProxyEvent;

      // Mock VPN as already associated
      setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
        ClientVpnTargetNetworks: [{
          TargetNetworkId: 'subnet-test123',
          Status: { Code: 'associated' }
        }]
      });
      
      setMockResponse('EC2', 'describeClientVpnConnections', {
        Connections: []
      });

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(200);
      
      const body = JSON.parse(result.body);
      expect(body.success).toBe(true);
    });
  });

  describe('VPN Close Operation', () => {
    it('should successfully close VPN (disassociate subnets)', async () => {
      const event = vpnControlEvents.vpnCloseStaging as unknown as APIGatewayProxyEvent;

      // Mock VPN as currently associated
      setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
        ClientVpnTargetNetworks: [{
          AssociationId: 'cvpn-assoc-test123',
          TargetNetworkId: 'subnet-test123',
          Status: { Code: 'associated' }
        }]
      });
      
      setMockResponse('EC2', 'describeClientVpnConnections', {
        Connections: []
      });

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(200);
      
      const body = JSON.parse(result.body);
      expect(body.success).toBe(true);
      expect(body.message).toContain('closed successfully');
      expect(body.data.associated).toBe(false);
    });

    it('should handle already disassociated VPN gracefully', async () => {
      const event = vpnControlEvents.vpnCloseStaging as unknown as APIGatewayProxyEvent;

      // Mock VPN as already disassociated
      setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
        ClientVpnTargetNetworks: []
      });
      
      setMockResponse('EC2', 'describeClientVpnConnections', {
        Connections: []
      });

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(200);
      
      const body = JSON.parse(result.body);
      expect(body.success).toBe(true);
    });
  });

  describe('VPN Check Operation', () => {
    it('should return current VPN status', async () => {
      const event = vpnControlEvents.vpnCheckStaging as unknown as APIGatewayProxyEvent;

      // Mock VPN status with active connections
      setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
        ClientVpnTargetNetworks: [{
          TargetNetworkId: 'subnet-test123',
          Status: { Code: 'associated' }
        }]
      });
      
      setMockResponse('EC2', 'describeClientVpnConnections', {
        Connections: [
          { ConnectionId: 'conn-1', Status: { Code: 'active' } },
          { ConnectionId: 'conn-2', Status: { Code: 'active' } }
        ]
      });

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(200);
      
      const body = JSON.parse(result.body);
      expect(body.success).toBe(true);
      expect(body.data).toBeDefined();
      expect(body.data.associated).toBe(true);
      expect(body.data.activeConnections).toBe(2);
      expect(body.data.endpointId).toBe('cvpn-endpoint-test123');
    });
  });

  describe('Cross-Account Requests', () => {
    it('should handle cross-account request format', async () => {
      const event = vpnControlEvents.vpnCrossAccountRequest as unknown as APIGatewayProxyEvent;
      
      // Set environment to production to match request
      process.env.ENVIRONMENT = 'production';

      // Mock VPN as disassociated
      setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
        ClientVpnTargetNetworks: []
      });
      
      setMockResponse('EC2', 'describeClientVpnConnections', {
        Connections: []
      });

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(200);
      
      const body = JSON.parse(result.body);
      expect(body.success).toBe(true);
    });
  });

  describe('Error Handling', () => {
    it('should handle invalid JSON request body', async () => {
      const event = vpnControlEvents.vpnMalformedJson as unknown as APIGatewayProxyEvent;

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(400);
      
      const body = JSON.parse(result.body);
      expect(body.success).toBe(false);
      expect(body.error).toContain('Invalid JSON');
    });

    it('should handle invalid action', async () => {
      const event = vpnControlEvents.vpnInvalidAction as unknown as APIGatewayProxyEvent;

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(400);
      
      const body = JSON.parse(result.body);
      expect(body.success).toBe(false);
      expect(body.error).toContain('Invalid action');
    });

    it('should handle environment mismatch', async () => {
      const event = vpnControlEvents.vpnInvalidEnvironment as unknown as APIGatewayProxyEvent;
      
      // Keep environment as staging, but request is for production

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(400);
      
      const body = JSON.parse(result.body);
      expect(body.success).toBe(false);
      expect(body.error).toContain('Environment mismatch');
    });

    it('should handle endpoint validation failure', async () => {
      const event = vpnControlEvents.vpnOpenStaging as unknown as unknown as APIGatewayProxyEvent;

      // Mock endpoint validation failure
      setMockResponse('EC2', 'describeClientVpnEndpoints', {
        ClientVpnEndpoints: []
      });

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(500);
      
      const body = JSON.parse(result.body);
      expect(body.success).toBe(false);
      expect(body.error).toContain('endpoint validation failed');
    });

    it('should handle AWS API errors', async () => {
      const event = vpnControlEvents.vpnOpenStaging as unknown as unknown as APIGatewayProxyEvent;

      // Mock AWS API failure
      const mockEC2Methods = require('../../__mocks__/aws-sdk').mockEC2Methods;
      mockEC2Methods.describeClientVpnTargetNetworks.mockReturnValue({
        promise: () => Promise.reject(new Error('AWS API Error'))
      });

      const result = await handler(event, mockContext);

      expect(result.statusCode).toBe(500);
      
      const body = JSON.parse(result.body);
      expect(body.success).toBe(false);
    });
  });

  describe('CloudWatch Metrics', () => {
    it('should publish metrics for successful operations', async () => {
      const event = vpnControlEvents.vpnOpenStaging as unknown as unknown as APIGatewayProxyEvent;

      setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
        ClientVpnTargetNetworks: []
      });

      setMockResponse('EC2', 'describeClientVpnConnections', {
        Connections: []
      });

      await handler(event, mockContext);

      const mockCloudWatchMethods = require('../../__mocks__/aws-sdk').mockCloudWatchMethods;
      expect(mockCloudWatchMethods.putMetricData).toHaveBeenCalledWith(
        expect.objectContaining({
          Namespace: 'VPN/Automation',
          MetricData: expect.arrayContaining([
            expect.objectContaining({
              MetricName: 'VpnOpenOperations',
              Value: 1,
              Unit: 'Count'
            })
          ])
        })
      );
    });
  });

  describe('Scheduled Events', () => {
    describe('Warming Request', () => {
      it('should handle warming request successfully', async () => {
        const event = vpnControlEvents.vpnWarmingEvent as unknown as APIGatewayProxyEvent;

        const result = await handler(event, mockContext);

        expect(result.statusCode).toBe(200);

        const body = JSON.parse(result.body);
        expect(body.message).toContain('warmed successfully');
        expect(body.functionName).toBe('vpn-control-test');
        expect(body.environment).toBe('staging');
        expect(body.timestamp).toBeDefined();
      });
    });

    describe('Auto-Open Request', () => {
      it('should auto-open VPN when currently closed', async () => {
        const event = vpnControlEvents.vpnAutoOpenEvent as unknown as APIGatewayProxyEvent;

        // Mock VPN as currently disassociated (closed)
        setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
          ClientVpnTargetNetworks: []
        });

        setMockResponse('EC2', 'describeClientVpnConnections', {
          Connections: []
        });

        const result = await handler(event, mockContext);

        expect(result.statusCode).toBe(200);

        const body = JSON.parse(result.body);
        expect(body.message).toContain('auto-opened successfully');
        expect(body.status).toBe('opened');
        expect(body.data).toBeDefined();
        expect(body.timestamp).toBeDefined();
      });

      it('should skip auto-open when VPN is already open', async () => {
        const event = vpnControlEvents.vpnAutoOpenEvent as unknown as APIGatewayProxyEvent;

        // Mock VPN as already associated (open)
        setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
          ClientVpnTargetNetworks: [{
            TargetNetworkId: 'subnet-test123',
            Status: { Code: 'associated' }
          }]
        });

        setMockResponse('EC2', 'describeClientVpnConnections', {
          Connections: []
        });

        const result = await handler(event, mockContext);

        expect(result.statusCode).toBe(200);

        const body = JSON.parse(result.body);
        expect(body.message).toContain('already open');
        expect(body.status).toBe('already_open');
        expect(body.timestamp).toBeDefined();
      });

      it('should handle auto-open failure with error response', async () => {
        const event = vpnControlEvents.vpnAutoOpenEvent as unknown as APIGatewayProxyEvent;

        // Mock VPN as disassociated initially
        setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
          ClientVpnTargetNetworks: []
        });

        setMockResponse('EC2', 'describeClientVpnConnections', {
          Connections: []
        });

        // Mock association failure
        const mockEC2Methods = require('../../__mocks__/aws-sdk').mockEC2Methods;
        mockEC2Methods.associateClientVpnTargetNetwork.mockReturnValue({
          promise: () => Promise.reject(new Error('Failed to associate subnet'))
        });

        const result = await handler(event, mockContext);

        expect(result.statusCode).toBe(500);

        const body = JSON.parse(result.body);
        expect(body.message).toContain('Failed to auto-open');
        expect(body.error).toBeDefined();
        expect(body.timestamp).toBeDefined();
      });
    });
  });
});