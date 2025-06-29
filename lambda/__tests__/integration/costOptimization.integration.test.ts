import { ScheduledEvent, Context } from 'aws-lambda';
import { handler } from '../../vpn-monitor/index';

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
jest.mock('/opt/stateStore', () => ({
  validateParameterStore: jest.fn().mockResolvedValue(true),
  readState: jest.fn().mockResolvedValue({
    associated: true,
    lastActivity: new Date(Date.now() - 70 * 60 * 1000).toISOString() // 70 minutes ago
  }),
  readConfig: jest.fn().mockResolvedValue({
    ENDPOINT_ID: 'cvpn-endpoint-test',
    SUBNET_ID: 'subnet-test'
  }),
  readParameter: jest.fn().mockImplementation((key: string) => {
    if (key.includes('cumulative_savings')) {
      return Promise.resolve('25.75');
    }
    if (key.includes('daily_savings')) {
      return Promise.resolve('5.20');
    }
    if (key.includes('admin_override')) {
      return Promise.reject(new Error('Not found'));
    }
    if (key.includes('manual_activity')) {
      return Promise.reject(new Error('Not found'));
    }
    if (key.includes('cooldown')) {
      return Promise.reject(new Error('Not found'));
    }
    return Promise.reject(new Error('Parameter not found'));
  }),
  writeParameter: jest.fn().mockResolvedValue(undefined)
}));

jest.mock('/opt/vpnManager', () => ({
  validateEndpoint: jest.fn().mockResolvedValue(true),
  fetchStatus: jest.fn().mockResolvedValue({
    associated: true,
    activeConnections: 0,
    lastActivity: new Date(Date.now() - 70 * 60 * 1000), // 70 minutes ago
    endpointId: 'cvpn-endpoint-test',
    subnetId: 'subnet-test'
  }),
  disassociateSubnets: jest.fn().mockResolvedValue(undefined),
  updateLastActivity: jest.fn().mockResolvedValue(undefined)
}));

jest.mock('/opt/slack', () => ({
  sendSlackAlert: jest.fn().mockResolvedValue(undefined),
  sendSlackNotification: jest.fn().mockResolvedValue(undefined)
}));

describe('Epic 3.2: Automatic Cost-Saving Actions Integration Tests', () => {
  const mockContext: Context = {
    callbackWaitsForEmptyEventLoop: false,
    functionName: 'vpn-monitor',
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

  const mockScheduledEvent: ScheduledEvent = {
    version: '0',
    id: 'test-event-id',
    'detail-type': 'Scheduled Event',
    source: 'aws.events',
    account: 'TEST_ACCOUNT_ID',
    time: new Date().toISOString(),
    region: 'us-east-1',
    resources: ['arn:aws:events:us-east-1:TEST_ACCOUNT_ID:rule/test-rule'],
    detail: {}
  };

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.ENVIRONMENT = 'staging';
    process.env.IDLE_MINUTES = '54';
    process.env.COOLDOWN_MINUTES = '30';
    process.env.BUSINESS_HOURS_PROTECTION = 'false'; // Disable for testing
    process.env.COST_TRACKING_ENABLED = 'true';
    process.env.AWS_REGION = 'us-east-1';
  });

  describe('Enhanced Cost Savings Calculation', () => {
    it('should calculate regional cost savings with multiple subnets', async () => {
      const mockStateStore = require('/opt/stateStore');
      mockStateStore.readConfig.mockResolvedValue({
        ENDPOINT_ID: 'cvpn-endpoint-test',
        SUBNET_ID: 'subnet-1,subnet-2,subnet-3' // 3 subnets
      });

      await handler(mockScheduledEvent, mockContext);

      // Verify cost optimization metrics were published
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/CostOptimization',
        MetricData: expect.arrayContaining([
          expect.objectContaining({
            MetricName: 'CostSavingsPerHour',
            Value: 0.30, // 3 subnets * $0.10
            Unit: 'Count',
            Dimensions: expect.arrayContaining([
              { Name: 'Environment', Value: 'staging' },
              { Name: 'Region', Value: 'us-east-1' }
            ])
          }),
          expect.objectContaining({
            MetricName: 'SubnetCount',
            Value: 3,
            Unit: 'Count'
          })
        ])
      });
    });

    it('should track cumulative savings over time', async () => {
      const mockStateStore = require('/opt/stateStore');
      
      await handler(mockScheduledEvent, mockContext);

      // Verify cumulative savings were updated
      expect(mockStateStore.writeParameter).toHaveBeenCalledWith(
        '/vpn/cost_optimization/cumulative_savings/staging',
        expect.any(String)
      );

      // Verify cumulative savings metric was published
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/CostOptimization',
        MetricData: expect.arrayContaining([
          expect.objectContaining({
            MetricName: 'CumulativeSavings',
            Dimensions: [{ Name: 'Environment', Value: 'staging' }]
          })
        ])
      });
    });

    it('should track daily savings separately', async () => {
      const mockStateStore = require('/opt/stateStore');
      const today = new Date().toISOString().split('T')[0];
      
      await handler(mockScheduledEvent, mockContext);

      // Verify daily savings were updated
      expect(mockStateStore.writeParameter).toHaveBeenCalledWith(
        `/vpn/cost_optimization/daily_savings/staging/${today}`,
        expect.any(String)
      );

      // Verify daily savings metric was published
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/CostOptimization',
        MetricData: expect.arrayContaining([
          expect.objectContaining({
            MetricName: 'DailySavings',
            Dimensions: expect.arrayContaining([
              { Name: 'Environment', Value: 'staging' },
              { Name: 'Date', Value: today }
            ])
          })
        ])
      });
    });
  });

  describe('Enhanced Safety Mechanisms', () => {
    it('should respect administrative override', async () => {
      const mockStateStore = require('/opt/stateStore');
      const mockSlack = require('/opt/slack');
      
      // Mock admin override exists
      mockStateStore.readParameter.mockImplementation((key: string) => {
        if (key.includes('admin_override')) {
          return Promise.resolve('enabled');
        }
        return Promise.reject(new Error('Not found'));
      });

      await handler(mockScheduledEvent, mockContext);

      // Verify no disassociation occurred
      const mockVpnManager = require('/opt/vpnManager');
      expect(mockVpnManager.disassociateSubnets).not.toHaveBeenCalled();

      // Verify administrative override notification
      expect(mockSlack.sendSlackNotification).toHaveBeenCalledWith(
        expect.stringContaining('administrative override'),
        '#vpn-alerts'
      );

      // Verify administrative override metric
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/Automation',
        MetricData: expect.arrayContaining([
          expect.objectContaining({
            MetricName: 'AdministrativeOverrideSkips',
            Value: 1
          })
        ])
      });
    });

    it('should provide enhanced business hours protection with cost impact', async () => {
      process.env.BUSINESS_HOURS_PROTECTION = 'true';
      
      // Mock current time to be during business hours (2 PM UTC)
      const mockDate = new Date('2024-06-20T14:00:00Z'); // Thursday 2 PM UTC
      jest.spyOn(global, 'Date').mockImplementation(() => mockDate as any);

      const mockSlack = require('/opt/slack');
      
      await handler(mockScheduledEvent, mockContext);

      // Verify enhanced business hours notification with cost impact
      expect(mockSlack.sendSlackNotification).toHaveBeenCalledWith(
        expect.stringContaining('Business Hours Protection'),
        `#vpn-staging`
      );

      expect(mockSlack.sendSlackNotification).toHaveBeenCalledWith(
        expect.stringContaining('Potential Savings'),
        `#vpn-staging`
      );

      // Verify business hours cost impact metric
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/Automation',
        MetricData: expect.arrayContaining([
          expect.objectContaining({
            MetricName: 'BusinessHoursSkipCostImpact'
          })
        ])
      });

      jest.restoreAllMocks();
    });

    it('should provide enhanced cooldown protection with context', async () => {
      const mockStateStore = require('/opt/stateStore');
      const mockSlack = require('/opt/slack');
      
      // Mock cooldown is active (started 10 minutes ago)
      const cooldownStart = new Date(Date.now() - 10 * 60 * 1000);
      mockStateStore.readParameter.mockImplementation((key: string) => {
        if (key.includes('cooldown')) {
          return Promise.resolve(cooldownStart.toISOString());
        }
        return Promise.reject(new Error('Not found'));
      });

      await handler(mockScheduledEvent, mockContext);

      // Verify enhanced cooldown notification
      expect(mockSlack.sendSlackNotification).toHaveBeenCalledWith(
        expect.stringContaining('Cooldown Protection Active'),
        `#vpn-staging`
      );

      // Verify cooldown remaining minutes metric
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/Automation',
        MetricData: expect.arrayContaining([
          expect.objectContaining({
            MetricName: 'CooldownRemainingMinutes',
            Value: 20 // 30 - 10 minutes
          })
        ])
      });
    });

    it('should provide enhanced manual activity detection with notification', async () => {
      const mockStateStore = require('/opt/stateStore');
      const mockSlack = require('/opt/slack');
      
      // Mock recent manual activity (5 minutes ago)
      const recentActivity = new Date(Date.now() - 5 * 60 * 1000);
      mockStateStore.readParameter.mockImplementation((key: string) => {
        if (key.includes('manual_activity')) {
          return Promise.resolve(recentActivity.toISOString());
        }
        return Promise.reject(new Error('Not found'));
      });

      await handler(mockScheduledEvent, mockContext);

      // Verify enhanced manual activity notification
      expect(mockSlack.sendSlackNotification).toHaveBeenCalledWith(
        expect.stringContaining('Manual Activity Detected'),
        `#vpn-staging`
      );

      // Verify manual activity skip metric
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/Automation',
        MetricData: expect.arrayContaining([
          expect.objectContaining({
            MetricName: 'ManualActivitySkips',
            Value: 1
          })
        ])
      });
    });
  });

  describe('Enhanced Slack Notifications', () => {
    it('should send comprehensive auto-disassociation notification', async () => {
      const mockSlack = require('/opt/slack');
      
      await handler(mockScheduledEvent, mockContext);

      // Verify enhanced Slack notification with all details
      expect(mockSlack.sendSlackNotification).toHaveBeenCalledWith(
        expect.stringMatching(/Auto-Cost Optimization.*staging.*Idle Time.*70 minutes.*Cost Savings.*Re-enable.*Cooldown/s),
        `#vpn-staging`
      );
    });

    it('should send different notifications for production vs staging', async () => {
      process.env.ENVIRONMENT = 'production';
      const mockSlack = require('/opt/slack');
      
      await handler(mockScheduledEvent, mockContext);

      // Verify production emoji in notification
      expect(mockSlack.sendSlackNotification).toHaveBeenCalledWith(
        expect.stringContaining('🔴'),
        `#vpn-production`
      );
    });
  });

  describe('Comprehensive Metrics', () => {
    it('should publish all required Epic 3.2 metrics', async () => {
      await handler(mockScheduledEvent, mockContext);

      // Verify all new metrics are published
      const expectedMetrics = [
        'VpnUptimeMinutes',
        'VpnDowntimeMinutes',
        'CostSavingsPerHour',
        'CostSavingsTotal',
        'IdleTimeBeforeDisassociation',
        'SubnetCount',
        'CumulativeSavings',
        'DailySavings',
        'AutoDisassociationTriggerCount'
      ];

      expectedMetrics.forEach(metricName => {
        expect(mockCloudWatchPutMetric).toHaveBeenCalledWith(
          expect.objectContaining({
            MetricData: expect.arrayContaining([
              expect.objectContaining({
                MetricName: metricName
              })
            ])
          })
        );
      });
    });

    it('should use correct namespaces for different metric types', async () => {
      await handler(mockScheduledEvent, mockContext);

      // Verify VPN/Automation namespace for operational metrics
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/Automation',
        MetricData: expect.any(Array)
      });

      // Verify VPN/CostOptimization namespace for cost metrics
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/CostOptimization',
        MetricData: expect.any(Array)
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle cost calculation errors gracefully', async () => {
      const mockStateStore = require('/opt/stateStore');
      mockStateStore.readConfig.mockRejectedValue(new Error('Config read failed'));
      
      // Should not throw error
      await expect(handler(mockScheduledEvent, mockContext)).resolves.not.toThrow();
      
      // Verify fallback cost calculation is used
      expect(mockCloudWatchPutMetric).toHaveBeenCalled();
    });

    it('should handle parameter store failures for cost tracking', async () => {
      const mockStateStore = require('/opt/stateStore');
      mockStateStore.writeParameter.mockRejectedValue(new Error('Write failed'));
      
      // Should not throw error
      await expect(handler(mockScheduledEvent, mockContext)).resolves.not.toThrow();
      
      // Verify operation continues despite storage failure
      const mockVpnManager = require('/opt/vpnManager');
      expect(mockVpnManager.disassociateSubnets).toHaveBeenCalled();
    });
  });

  describe('Regional Pricing Support', () => {
    it('should use correct pricing for different regions', async () => {
      process.env.AWS_REGION = 'eu-west-1';
      
      await handler(mockScheduledEvent, mockContext);

      // Verify EU pricing is used (higher than US)
      expect(mockCloudWatchPutMetric).toHaveBeenCalledWith({
        Namespace: 'VPN/CostOptimization',
        MetricData: expect.arrayContaining([
          expect.objectContaining({
            MetricName: 'CostSavingsPerHour',
            Value: 0.12, // EU pricing
            Dimensions: expect.arrayContaining([
              { Name: 'Region', Value: 'eu-west-1' }
            ])
          })
        ])
      });
    });
  });
});