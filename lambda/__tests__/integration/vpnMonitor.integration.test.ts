import { ScheduledEvent, Context } from 'aws-lambda';
import { resetAllMocks, setMockResponse } from '../../__mocks__/aws-sdk';

// Import test fixtures
import scheduleEvent from '../fixtures/scheduleEvent.json';

// Import test handler with relative imports
import { handler } from '../helpers/vpn-monitor.test-handler';

describe('VPN Monitor Integration Tests', () => {
  const mockContext: Context = {
    callbackWaitsForEmptyEventLoop: false,
    functionName: 'vpn-monitor-test',
    functionVersion: '$LATEST',
    invokedFunctionArn: 'arn:aws:lambda:us-east-1:TEST_ACCOUNT_ID:function:vpn-monitor-test',
    memoryLimitInMB: '256',
    awsRequestId: 'test-request-id',
    logGroupName: '/aws/lambda/vpn-monitor-test',
    logStreamName: '2025/06/17/[$LATEST]abcdef123456',
    getRemainingTimeInMillis: () => 30000,
    done: jest.fn(),
    fail: jest.fn(),
    succeed: jest.fn()
  };

  beforeEach(() => {
    resetAllMocks();
    
    process.env.ENVIRONMENT = 'staging';
    process.env.IDLE_MINUTES = '54';
    
    // Mock successful Parameter Store validation
    setMockResponse('SSM', 'getParameter', {
      Parameter: { Value: 'mock_value' }
    });
    
    // Mock successful endpoint validation
    setMockResponse('EC2', 'describeClientVpnEndpoints', {
      ClientVpnEndpoints: [{
        ClientVpnEndpointId: 'cvpn-endpoint-test123',
        Status: { Code: 'available' }
      }]
    });
  });

  describe('Normal Operation Scenarios', () => {
    it('should skip action when VPN has active connections', async () => {
      const event = scheduleEvent as ScheduledEvent;

      // Mock VPN as associated with active connections
      setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
        ClientVpnTargetNetworks: [{
          TargetNetworkId: 'subnet-test123',
          Status: { Code: 'associated' }
        }]
      });
      
      setMockResponse('EC2', 'describeClientVpnConnections', {
        Connections: [
          { ConnectionId: 'conn-1', Status: { Code: 'active' } }
        ]
      });

      await handler(event, mockContext);

      const mockEC2Methods = require('../../__mocks__/aws-sdk').mockEC2Methods;
      expect(mockEC2Methods.disassociateClientVpnTargetNetwork).not.toHaveBeenCalled();
    });

    it('should skip action when VPN is already disassociated', async () => {
      const event = scheduleEvent as ScheduledEvent;

      // Mock VPN as disassociated
      setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
        ClientVpnTargetNetworks: []
      });
      
      setMockResponse('EC2', 'describeClientVpnConnections', {
        Connections: []
      });

      await handler(event, mockContext);

      const mockEC2Methods = require('../../__mocks__/aws-sdk').mockEC2Methods;
      expect(mockEC2Methods.disassociateClientVpnTargetNetwork).not.toHaveBeenCalled();
    });

    it('should skip action when idle time is below threshold', async () => {
      const event = scheduleEvent as ScheduledEvent;

      // Mock recent activity (30 minutes ago)
      const recentActivity = new Date(Date.now() - 30 * 60 * 1000).toISOString();
      const mockSSMethods = require('../../__mocks__/aws-sdk').mockSSMethods;
      mockSSMethods.getParameter.mockImplementation((params: any) => {
        if (params.Name === '/vpn/endpoint/state') {
          return {
            promise: () => Promise.resolve({
              Parameter: {
                Value: JSON.stringify({
                  associated: true,
                  lastActivity: recentActivity
                })
              }
            })
          };
        }
        return {
          promise: () => Promise.resolve({
            Parameter: { Value: JSON.stringify({ ENDPOINT_ID: 'test', SUBNET_ID: 'test' }) }
          })
        };
      });

      // Mock VPN as associated with no connections
      setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
        ClientVpnTargetNetworks: [{
          TargetNetworkId: 'subnet-test123',
          Status: { Code: 'associated' }
        }]
      });
      
      setMockResponse('EC2', 'describeClientVpnConnections', {
        Connections: []
      });

      await handler(event, mockContext);

      const mockEC2Methods = require('../../__mocks__/aws-sdk').mockEC2Methods;
      expect(mockEC2Methods.disassociateClientVpnTargetNetwork).not.toHaveBeenCalled();
    });
  });

  describe('Auto-Disassociation Scenarios', () => {
    beforeEach(() => {
      // Mock old activity (2 hours ago)
      const oldActivity = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
      const mockSSMethods = require('../../__mocks__/aws-sdk').mockSSMethods;
      mockSSMethods.getParameter.mockImplementation((params: any) => {
        if (params.Name === '/vpn/endpoint/state') {
          return {
            promise: () => Promise.resolve({
              Parameter: {
                Value: JSON.stringify({
                  associated: true,
                  lastActivity: oldActivity
                })
              }
            })
          };
        }
        if (params.Name === '/vpn/endpoint/conf') {
          return {
            promise: () => Promise.resolve({
              Parameter: {
                Value: JSON.stringify({
                  ENDPOINT_ID: 'cvpn-endpoint-test123',
                  SUBNET_ID: 'subnet-test123'
                })
              }
            })
          };
        }
        return {
          promise: () => Promise.resolve({
            Parameter: { Value: 'mock_value' }
          })
        };
      });

      // Mock fetch for Slack notifications
      global.fetch = jest.fn().mockResolvedValue({
        ok: true,
        status: 200
      });
    });

    afterEach(() => {
      jest.restoreAllMocks();
    });

    it('should auto-disassociate when VPN is idle beyond threshold', async () => {
      const event = scheduleEvent as ScheduledEvent;

      // Mock VPN as associated with no connections (idle)
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

      await handler(event, mockContext);

      const mockEC2Methods = require('../../__mocks__/aws-sdk').mockEC2Methods;
      expect(mockEC2Methods.disassociateClientVpnTargetNetwork).toHaveBeenCalledWith({
        ClientVpnEndpointId: 'cvpn-endpoint-test123',
        AssociationId: 'cvpn-assoc-test123'
      });
    });

    it('should publish CloudWatch metric for auto-disassociation', async () => {
      const event = scheduleEvent as ScheduledEvent;

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

      await handler(event, mockContext);

      const mockCloudWatchMethods = require('../../__mocks__/aws-sdk').mockCloudWatchMethods;
      expect(mockCloudWatchMethods.putMetricData).toHaveBeenCalledWith(
        expect.objectContaining({
          Namespace: 'VPN/Automation',
          MetricData: expect.arrayContaining([
            expect.objectContaining({
              MetricName: 'IdleSubnetDisassociations',
              Value: 1,
              Unit: 'Count'
            })
          ])
        })
      );
    });

    it('should send Slack notification for auto-disassociation', async () => {
      const event = scheduleEvent as ScheduledEvent;

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

      await handler(event, mockContext);

      expect(global.fetch).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          method: 'POST',
          body: expect.stringContaining('idle for')
        })
      );
    });
  });

  describe('Business Hours Protection', () => {
    it('should skip auto-disassociation during business hours', async () => {
      const event = scheduleEvent as ScheduledEvent;

      // Mock current time as business hours (Monday 10 AM UTC)
      const businessHourTime = new Date('2025-06-23T10:00:00.000Z'); // Monday
      jest.spyOn(Date, 'now').mockReturnValue(businessHourTime.getTime());

      // Mock old activity (2 hours ago)
      const oldActivity = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
      const mockSSMethods = require('../../__mocks__/aws-sdk').mockSSMethods;
      mockSSMethods.getParameter.mockImplementation((params: any) => {
        if (params.Name === '/vpn/endpoint/state') {
          return {
            promise: () => Promise.resolve({
              Parameter: {
                Value: JSON.stringify({
                  associated: true,
                  lastActivity: oldActivity
                })
              }
            })
          };
        }
        return {
          promise: () => Promise.resolve({
            Parameter: { Value: JSON.stringify({ ENDPOINT_ID: 'test', SUBNET_ID: 'test' }) }
          })
        };
      });

      setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
        ClientVpnTargetNetworks: [{
          TargetNetworkId: 'subnet-test123',
          Status: { Code: 'associated' }
        }]
      });
      
      setMockResponse('EC2', 'describeClientVpnConnections', {
        Connections: []
      });

      global.fetch = jest.fn().mockResolvedValue({ ok: true, status: 200 });

      await handler(event, mockContext);

      const mockEC2Methods = require('../../__mocks__/aws-sdk').mockEC2Methods;
      expect(mockEC2Methods.disassociateClientVpnTargetNetwork).not.toHaveBeenCalled();

      // Should still send warning notification
      expect(global.fetch).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          body: expect.stringContaining('business hours')
        })
      );

      jest.restoreAllMocks();
    });
  });

  describe('Error Handling', () => {
    it('should handle Parameter Store validation failure', async () => {
      const event = scheduleEvent as ScheduledEvent;

      // Mock Parameter Store failure
      const mockSSMethods = require('../../__mocks__/aws-sdk').mockSSMethods;
      mockSSMethods.getParameter.mockReturnValue({
        promise: () => Promise.reject(new Error('ParameterNotFound'))
      });

      global.fetch = jest.fn().mockResolvedValue({ ok: true, status: 200 });

      await handler(event, mockContext);

      // Should send alert
      expect(global.fetch).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          body: expect.stringContaining('Parameter Store validation failed')
        })
      );

      jest.restoreAllMocks();
    });

    it('should handle endpoint validation failure', async () => {
      const event = scheduleEvent as ScheduledEvent;

      // Mock endpoint validation failure
      setMockResponse('EC2', 'describeClientVpnEndpoints', {
        ClientVpnEndpoints: []
      });

      global.fetch = jest.fn().mockResolvedValue({ ok: true, status: 200 });

      await handler(event, mockContext);

      // Should send alert
      expect(global.fetch).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          body: expect.stringContaining('endpoint validation failed')
        })
      );

      jest.restoreAllMocks();
    });

    it('should handle disassociation failure', async () => {
      const event = scheduleEvent as ScheduledEvent;

      // Mock old activity
      const oldActivity = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
      const mockSSMethods = require('../../__mocks__/aws-sdk').mockSSMethods;
      mockSSMethods.getParameter.mockImplementation((params: any) => {
        if (params.Name === '/vpn/endpoint/state') {
          return {
            promise: () => Promise.resolve({
              Parameter: {
                Value: JSON.stringify({
                  associated: true,
                  lastActivity: oldActivity
                })
              }
            })
          };
        }
        return {
          promise: () => Promise.resolve({
            Parameter: { Value: JSON.stringify({ ENDPOINT_ID: 'test', SUBNET_ID: 'test' }) }
          })
        };
      });

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

      // Mock disassociation failure
      const mockEC2Methods = require('../../__mocks__/aws-sdk').mockEC2Methods;
      mockEC2Methods.disassociateClientVpnTargetNetwork.mockReturnValue({
        promise: () => Promise.reject(new Error('Disassociation failed'))
      });

      global.fetch = jest.fn().mockResolvedValue({ ok: true, status: 200 });

      await handler(event, mockContext);

      // Should send critical alert
      expect(global.fetch).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          body: expect.stringContaining('Failed to auto-disassociate')
        })
      );

      // Should publish error metric
      const mockCloudWatchMethods = require('../../__mocks__/aws-sdk').mockCloudWatchMethods;
      expect(mockCloudWatchMethods.putMetricData).toHaveBeenCalledWith(
        expect.objectContaining({
          MetricData: expect.arrayContaining([
            expect.objectContaining({
              MetricName: 'AutoDisassociationErrors'
            })
          ])
        })
      );

      jest.restoreAllMocks();
    });
  });

  describe('Metrics Publishing', () => {
    it('should publish status metrics for all monitoring runs', async () => {
      const event = scheduleEvent as ScheduledEvent;

      setMockResponse('EC2', 'describeClientVpnTargetNetworks', {
        ClientVpnTargetNetworks: [{
          TargetNetworkId: 'subnet-test123',
          Status: { Code: 'associated' }
        }]
      });
      
      setMockResponse('EC2', 'describeClientVpnConnections', {
        Connections: [
          { ConnectionId: 'conn-1', Status: { Code: 'active' } }
        ]
      });

      await handler(event, mockContext);

      const mockCloudWatchMethods = require('../../__mocks__/aws-sdk').mockCloudWatchMethods;
      expect(mockCloudWatchMethods.putMetricData).toHaveBeenCalledWith(
        expect.objectContaining({
          Namespace: 'VPN/Automation',
          MetricData: expect.arrayContaining([
            expect.objectContaining({
              MetricName: 'VpnAssociationStatus',
              Value: 1
            }),
            expect.objectContaining({
              MetricName: 'VpnActiveConnections',
              Value: 1
            })
          ])
        })
      );
    });
  });

  describe('Enhanced Idle Detection Features', () => {
    beforeEach(() => {
      // Set up environment for enhanced features
      process.env.COOLDOWN_MINUTES = '30';
      process.env.BUSINESS_HOURS_PROTECTION = 'true';
      process.env.BUSINESS_HOURS_TIMEZONE = 'UTC';
    });

    it('should skip auto-disassociation during cooldown period', async () => {
      const event = scheduleEvent as ScheduledEvent;
      const recentCooldown = new Date(Date.now() - 15 * 60 * 1000).toISOString(); // 15 minutes ago
      const oldActivity = new Date(Date.now() - 90 * 60 * 1000).toISOString(); // 90 minutes ago

      const mockSSMethods = require('../../__mocks__/aws-sdk').mockSSMethods;
      
      mockSSMethods.getParameter.mockImplementation((params: any) => {
        if (params.Name === '/vpn/endpoint/state') {
          return {
            promise: () => Promise.resolve({
              Parameter: {
                Value: JSON.stringify({
                  associated: true,
                  lastActivity: oldActivity
                })
              }
            })
          };
        } else if (params.Name === '/vpn/automation/cooldown/staging') {
          return {
            promise: () => Promise.resolve({
              Parameter: { Value: recentCooldown }
            })
          };
        }
        return {
          promise: () => Promise.resolve({
            Parameter: { Value: JSON.stringify({ ENDPOINT_ID: 'test', SUBNET_ID: 'test' }) }
          })
        };
      });

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

      await handler(event, mockContext);

      // Should publish cooldown skip metric
      const mockCloudWatchMethods = require('../../__mocks__/aws-sdk').mockCloudWatchMethods;
      expect(mockCloudWatchMethods.putMetricData).toHaveBeenCalledWith(
        expect.objectContaining({
          MetricData: expect.arrayContaining([
            expect.objectContaining({
              MetricName: 'CooldownSkips',
              Value: 1
            })
          ])
        })
      );
    });

    it('should skip auto-disassociation when recent manual activity detected', async () => {
      const event = scheduleEvent as ScheduledEvent;
      const recentManualActivity = new Date(Date.now() - 10 * 60 * 1000).toISOString(); // 10 minutes ago
      const oldActivity = new Date(Date.now() - 90 * 60 * 1000).toISOString(); // 90 minutes ago

      const mockSSMethods = require('../../__mocks__/aws-sdk').mockSSMethods;
      
      mockSSMethods.getParameter.mockImplementation((params: any) => {
        if (params.Name === '/vpn/endpoint/state') {
          return {
            promise: () => Promise.resolve({
              Parameter: {
                Value: JSON.stringify({
                  associated: true,
                  lastActivity: oldActivity
                })
              }
            })
          };
        } else if (params.Name === '/vpn/automation/manual_activity/staging') {
          return {
            promise: () => Promise.resolve({
              Parameter: { Value: recentManualActivity }
            })
          };
        } else if (params.Name === '/vpn/automation/cooldown/staging') {
          return {
            promise: () => Promise.reject({ code: 'ParameterNotFound' })
          };
        }
        return {
          promise: () => Promise.resolve({
            Parameter: { Value: JSON.stringify({ ENDPOINT_ID: 'test', SUBNET_ID: 'test' }) }
          })
        };
      });

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

      await handler(event, mockContext);

      // Should publish manual activity skip metric
      const mockCloudWatchMethods = require('../../__mocks__/aws-sdk').mockCloudWatchMethods;
      expect(mockCloudWatchMethods.putMetricData).toHaveBeenCalledWith(
        expect.objectContaining({
          MetricData: expect.arrayContaining([
            expect.objectContaining({
              MetricName: 'ManualActivitySkips',
              Value: 1
            })
          ])
        })
      );
    });

    it('should record cooldown timestamp after successful auto-disassociation', async () => {
      const event = scheduleEvent as ScheduledEvent;
      const oldActivity = new Date(Date.now() - 90 * 60 * 1000).toISOString(); // 90 minutes ago

      const mockSSMethods = require('../../__mocks__/aws-sdk').mockSSMethods;
      
      mockSSMethods.getParameter.mockImplementation((params: any) => {
        if (params.Name === '/vpn/endpoint/state') {
          return {
            promise: () => Promise.resolve({
              Parameter: {
                Value: JSON.stringify({
                  associated: true,
                  lastActivity: oldActivity
                })
              }
            })
          };
        } else if (params.Name.includes('/vpn/automation/')) {
          return {
            promise: () => Promise.reject({ code: 'ParameterNotFound' })
          };
        }
        return {
          promise: () => Promise.resolve({
            Parameter: { Value: JSON.stringify({ ENDPOINT_ID: 'test', SUBNET_ID: 'test' }) }
          })
        };
      });

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

      // Mock current time outside business hours (e.g., 22:00 UTC = 10 PM)
      const originalDate = Date;
      const mockDate = new Date('2025-06-20T22:00:00.000Z');
      global.Date = jest.fn(() => mockDate) as any;
      global.Date.now = jest.fn(() => mockDate.getTime());

      global.fetch = jest.fn().mockResolvedValue({ ok: true, status: 200 });

      await handler(event, mockContext);

      // Should record cooldown timestamp
      expect(mockSSMethods.putParameter).toHaveBeenCalledWith(
        expect.objectContaining({
          Name: '/vpn/automation/cooldown/staging',
          Value: expect.stringMatching(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d{3}Z$/)
        })
      );

      // Restore original Date
      global.Date = originalDate;
    });

    it('should include cost savings in Slack notification', async () => {
      const event = scheduleEvent as ScheduledEvent;
      const oldActivity = new Date(Date.now() - 90 * 60 * 1000).toISOString(); // 90 minutes ago

      const mockSSMethods = require('../../__mocks__/aws-sdk').mockSSMethods;
      
      mockSSMethods.getParameter.mockImplementation((params: any) => {
        if (params.Name === '/vpn/endpoint/state') {
          return {
            promise: () => Promise.resolve({
              Parameter: {
                Value: JSON.stringify({
                  associated: true,
                  lastActivity: oldActivity
                })
              }
            })
          };
        } else if (params.Name.includes('/vpn/automation/')) {
          return {
            promise: () => Promise.reject({ code: 'ParameterNotFound' })
          };
        } else if (params.Name === '/vpn/slack/webhook') {
          return {
            promise: () => Promise.resolve({
              Parameter: { Value: 'https://hooks.slack.com/test' }
            })
          };
        }
        return {
          promise: () => Promise.resolve({
            Parameter: { Value: JSON.stringify({ ENDPOINT_ID: 'test', SUBNET_ID: 'test' }) }
          })
        };
      });

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

      // Mock current time outside business hours
      const originalDate = Date;
      const mockDate = new Date('2025-06-20T22:00:00.000Z');
      global.Date = jest.fn(() => mockDate) as any;
      global.Date.now = jest.fn(() => mockDate.getTime());

      global.fetch = jest.fn().mockResolvedValue({ ok: true, status: 200 });

      await handler(event, mockContext);

      // Should include cost savings in notification
      expect(global.fetch).toHaveBeenCalledWith(
        'https://hooks.slack.com/test',
        expect.objectContaining({
          body: expect.stringContaining('~$0.10/hour saved')
        })
      );

      // Restore original Date
      global.Date = originalDate;
    });
  });
});