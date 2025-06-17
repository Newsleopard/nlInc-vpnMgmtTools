import { mockSSMethods, resetAllMocks } from '../../__mocks__/aws-sdk';

// Import after mocks are set up
import * as stateStore from '../../shared/stateStore';
import { VpnConfig, VpnState } from '../../shared/types';

describe('stateStore', () => {
  beforeEach(() => {
    resetAllMocks();
  });

  describe('readConfig', () => {
    it('should read VPN configuration from Parameter Store', async () => {
      const mockConfig: VpnConfig = {
        ENDPOINT_ID: 'cvpn-endpoint-test123',
        SUBNET_ID: 'subnet-test123'
      };

      mockSSMethods.getParameter.mockReturnValue({
        promise: () => Promise.resolve({
          Parameter: {
            Value: JSON.stringify(mockConfig)
          }
        })
      });

      const result = await stateStore.readConfig();

      expect(result).toEqual(mockConfig);
      expect(mockSSMethods.getParameter).toHaveBeenCalledWith({
        Name: '/vpn/endpoint/conf'
      });
    });

    it('should throw error when parameter has no value', async () => {
      mockSSMethods.getParameter.mockReturnValue({
        promise: () => Promise.resolve({
          Parameter: {}
        })
      });

      await expect(stateStore.readConfig()).rejects.toThrow('Parameter /vpn/endpoint/conf has no value');
    });

    it('should throw error when parameter is not found', async () => {
      mockSSMethods.getParameter.mockReturnValue({
        promise: () => Promise.reject(new Error('ParameterNotFound'))
      });

      await expect(stateStore.readConfig()).rejects.toThrow('Unable to read VPN configuration: ParameterNotFound');
    });

    it('should throw error when parameter value is invalid JSON', async () => {
      mockSSMethods.getParameter.mockReturnValue({
        promise: () => Promise.resolve({
          Parameter: {
            Value: 'invalid-json'
          }
        })
      });

      await expect(stateStore.readConfig()).rejects.toThrow('Unable to read VPN configuration');
    });
  });

  describe('readState', () => {
    it('should read VPN state from Parameter Store', async () => {
      const mockState: VpnState = {
        associated: true,
        lastActivity: '2025-06-17T10:00:00.000Z'
      };

      mockSSMethods.getParameter.mockReturnValue({
        promise: () => Promise.resolve({
          Parameter: {
            Value: JSON.stringify(mockState)
          }
        })
      });

      const result = await stateStore.readState();

      expect(result).toEqual(mockState);
      expect(mockSSMethods.getParameter).toHaveBeenCalledWith({
        Name: '/vpn/endpoint/state'
      });
    });

    it('should handle missing state parameter', async () => {
      mockSSMethods.getParameter.mockReturnValue({
        promise: () => Promise.reject(new Error('ParameterNotFound'))
      });

      await expect(stateStore.readState()).rejects.toThrow('Unable to read VPN state: ParameterNotFound');
    });
  });

  describe('writeState', () => {
    it('should write VPN state to Parameter Store', async () => {
      const testState: VpnState = {
        associated: false,
        lastActivity: '2025-06-17T11:00:00.000Z'
      };

      mockSSMethods.putParameter.mockReturnValue({
        promise: () => Promise.resolve({
          Version: 1,
          Tier: 'Standard'
        })
      });

      await stateStore.writeState(testState);

      expect(mockSSMethods.putParameter).toHaveBeenCalledWith({
        Name: '/vpn/endpoint/state',
        Value: JSON.stringify(testState),
        Type: 'String',
        Overwrite: true,
        Description: 'VPN endpoint state (associated status and last activity)'
      });
    });

    it('should handle write failures', async () => {
      const testState: VpnState = {
        associated: false,
        lastActivity: '2025-06-17T11:00:00.000Z'
      };

      mockSSMethods.putParameter.mockReturnValue({
        promise: () => Promise.reject(new Error('AccessDenied'))
      });

      await expect(stateStore.writeState(testState)).rejects.toThrow('Unable to update VPN state: AccessDenied');
    });
  });

  describe('writeConfig', () => {
    it('should write VPN configuration to Parameter Store', async () => {
      const testConfig: VpnConfig = {
        ENDPOINT_ID: 'cvpn-endpoint-new123',
        SUBNET_ID: 'subnet-new123'
      };

      mockSSMethods.putParameter.mockReturnValue({
        promise: () => Promise.resolve({
          Version: 1,
          Tier: 'Standard'
        })
      });

      await stateStore.writeConfig(testConfig);

      expect(mockSSMethods.putParameter).toHaveBeenCalledWith({
        Name: '/vpn/endpoint/conf',
        Value: JSON.stringify(testConfig),
        Type: 'String',
        Overwrite: true,
        Description: 'VPN endpoint configuration (endpoint ID and subnet ID)'
      });
    });
  });

  describe('readSlackWebhook', () => {
    it('should read encrypted Slack webhook URL', async () => {
      const webhookUrl = 'https://hooks.slack.com/services/test';

      mockSSMethods.getParameter.mockReturnValue({
        promise: () => Promise.resolve({
          Parameter: {
            Value: webhookUrl
          }
        })
      });

      const result = await stateStore.readSlackWebhook();

      expect(result).toBe(webhookUrl);
      expect(mockSSMethods.getParameter).toHaveBeenCalledWith({
        Name: '/vpn/slack/webhook',
        WithDecryption: true
      });
    });
  });

  describe('readSlackSigningSecret', () => {
    it('should read encrypted Slack signing secret', async () => {
      const signingSecret = 'test_signing_secret';

      mockSSMethods.getParameter.mockReturnValue({
        promise: () => Promise.resolve({
          Parameter: {
            Value: signingSecret
          }
        })
      });

      const result = await stateStore.readSlackSigningSecret();

      expect(result).toBe(signingSecret);
      expect(mockSSMethods.getParameter).toHaveBeenCalledWith({
        Name: '/vpn/slack/signing_secret',
        WithDecryption: true
      });
    });
  });

  describe('validateParameterStore', () => {
    it('should return true when all required parameters exist', async () => {
      // Mock successful responses for all parameters
      mockSSMethods.getParameter.mockReturnValue({
        promise: () => Promise.resolve({
          Parameter: { Value: 'mock_value' }
        })
      });

      const result = await stateStore.validateParameterStore();

      expect(result).toBe(true);
      expect(mockSSMethods.getParameter).toHaveBeenCalledTimes(4);
    });

    it('should return false when any parameter is missing', async () => {
      // Mock first call success, second call failure
      mockSSMethods.getParameter
        .mockReturnValueOnce({
          promise: () => Promise.resolve({
            Parameter: { Value: 'mock_value' }
          })
        })
        .mockReturnValueOnce({
          promise: () => Promise.reject(new Error('ParameterNotFound'))
        });

      const result = await stateStore.validateParameterStore();

      expect(result).toBe(false);
    });
  });
});