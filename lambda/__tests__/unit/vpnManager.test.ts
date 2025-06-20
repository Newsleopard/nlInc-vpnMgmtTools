import { mockEC2Methods, mockSSMethods, resetAllMocks, setMockResponse } from '../../__mocks__/aws-sdk';

// Import after mocks are set up
import * as vpnManager from '../../shared/vpnManager';
import { VpnConfig, VpnState } from '../../shared/types';

describe('vpnManager', () => {
  const mockConfig: VpnConfig = {
    ENDPOINT_ID: 'cvpn-endpoint-test123',
    SUBNET_ID: 'subnet-test123'
  };

  const mockState: VpnState = {
    associated: false,
    lastActivity: '2025-06-17T10:00:00.000Z'
  };

  beforeEach(() => {
    resetAllMocks();
    
    // Set up default mocks for config and state
    mockSSMethods.getParameter.mockImplementation((params: any) => {
      const responses: Record<string, any> = {
        '/vpn/endpoint/conf': {
          Parameter: { Value: JSON.stringify(mockConfig) }
        },
        '/vpn/endpoint/state': {
          Parameter: { Value: JSON.stringify(mockState) }
        }
      };
      
      return {
        promise: () => Promise.resolve(responses[params.Name] || { Parameter: { Value: 'mock' } })
      };
    });

    mockSSMethods.putParameter.mockReturnValue({
      promise: () => Promise.resolve({ Version: 1 })
    });
  });

  describe('associateSubnets', () => {
    it('should associate subnets when not already associated', async () => {
      // Mock VPN as currently disassociated
      mockEC2Methods.describeClientVpnTargetNetworks.mockReturnValue({
        promise: () => Promise.resolve({
          ClientVpnTargetNetworks: []
        })
      });

      mockEC2Methods.describeClientVpnConnections.mockReturnValue({
        promise: () => Promise.resolve({
          Connections: []
        })
      });

      mockEC2Methods.associateClientVpnTargetNetwork.mockReturnValue({
        promise: () => Promise.resolve({
          AssociationId: 'cvpn-assoc-test123',
          Status: { Code: 'associating' }
        })
      });

      await vpnManager.associateSubnets();

      expect(mockEC2Methods.associateClientVpnTargetNetwork).toHaveBeenCalledWith({
        ClientVpnEndpointId: mockConfig.ENDPOINT_ID,
        SubnetId: mockConfig.SUBNET_ID
      });

      expect(mockSSMethods.putParameter).toHaveBeenCalledWith(
        expect.objectContaining({
          Name: '/vpn/endpoint/state',
          Value: expect.stringContaining('"associated":true')
        })
      );
    });

    it('should skip association if already associated', async () => {
      // Mock VPN as currently associated
      mockEC2Methods.describeClientVpnTargetNetworks.mockReturnValue({
        promise: () => Promise.resolve({
          ClientVpnTargetNetworks: [{
            TargetNetworkId: mockConfig.SUBNET_ID,
            Status: { Code: 'associated' }
          }]
        })
      });

      mockEC2Methods.describeClientVpnConnections.mockReturnValue({
        promise: () => Promise.resolve({
          Connections: []
        })
      });

      await vpnManager.associateSubnets();

      expect(mockEC2Methods.associateClientVpnTargetNetwork).not.toHaveBeenCalled();
    });

    it('should handle association errors', async () => {
      mockEC2Methods.describeClientVpnTargetNetworks.mockReturnValue({
        promise: () => Promise.resolve({ ClientVpnTargetNetworks: [] })
      });

      mockEC2Methods.describeClientVpnConnections.mockReturnValue({
        promise: () => Promise.resolve({ Connections: [] })
      });

      mockEC2Methods.associateClientVpnTargetNetwork.mockReturnValue({
        promise: () => Promise.reject(new Error('Association failed'))
      });

      await expect(vpnManager.associateSubnets()).rejects.toThrow('Subnet association failed: Association failed');
    });
  });

  describe('disassociateSubnets', () => {
    const mockAssociation = {
      AssociationId: 'cvpn-assoc-test123',
      TargetNetworkId: 'subnet-test123',
      Status: { Code: 'associated' }
    };

    it('should disassociate subnets when associated', async () => {
      // Mock VPN as currently associated
      mockEC2Methods.describeClientVpnTargetNetworks.mockReturnValue({
        promise: () => Promise.resolve({
          ClientVpnTargetNetworks: [mockAssociation]
        })
      });

      mockEC2Methods.describeClientVpnConnections.mockReturnValue({
        promise: () => Promise.resolve({
          Connections: []
        })
      });

      mockEC2Methods.disassociateClientVpnTargetNetwork.mockReturnValue({
        promise: () => Promise.resolve({
          AssociationId: mockAssociation.AssociationId,
          Status: { Code: 'disassociating' }
        })
      });

      await vpnManager.disassociateSubnets();

      expect(mockEC2Methods.disassociateClientVpnTargetNetwork).toHaveBeenCalledWith({
        ClientVpnEndpointId: mockConfig.ENDPOINT_ID,
        AssociationId: mockAssociation.AssociationId
      });

      expect(mockSSMethods.putParameter).toHaveBeenCalledWith(
        expect.objectContaining({
          Name: '/vpn/endpoint/state',
          Value: expect.stringContaining('"associated":false')
        })
      );
    });

    it('should skip disassociation if not associated', async () => {
      // Mock VPN as currently disassociated
      mockEC2Methods.describeClientVpnTargetNetworks.mockReturnValue({
        promise: () => Promise.resolve({
          ClientVpnTargetNetworks: []
        })
      });

      mockEC2Methods.describeClientVpnConnections.mockReturnValue({
        promise: () => Promise.resolve({
          Connections: []
        })
      });

      await vpnManager.disassociateSubnets();

      expect(mockEC2Methods.disassociateClientVpnTargetNetwork).not.toHaveBeenCalled();
    });

    it('should handle disassociation errors', async () => {
      mockEC2Methods.describeClientVpnTargetNetworks.mockReturnValue({
        promise: () => Promise.resolve({
          ClientVpnTargetNetworks: [mockAssociation]
        })
      });

      mockEC2Methods.describeClientVpnConnections.mockReturnValue({
        promise: () => Promise.resolve({ Connections: [] })
      });

      mockEC2Methods.disassociateClientVpnTargetNetwork.mockReturnValue({
        promise: () => Promise.reject(new Error('Disassociation failed'))
      });

      await expect(vpnManager.disassociateSubnets()).rejects.toThrow('Subnet disassociation failed: Disassociation failed');
    });
  });

  describe('fetchStatus', () => {
    it('should return current VPN status', async () => {
      const mockConnections = [
        { ConnectionId: 'conn-1', Status: { Code: 'active' } },
        { ConnectionId: 'conn-2', Status: { Code: 'active' } }
      ];

      const mockAssociations = [{
        TargetNetworkId: mockConfig.SUBNET_ID,
        Status: { Code: 'associated' }
      }];

      mockEC2Methods.describeClientVpnConnections.mockReturnValue({
        promise: () => Promise.resolve({ Connections: mockConnections })
      });

      mockEC2Methods.describeClientVpnTargetNetworks.mockReturnValue({
        promise: () => Promise.resolve({ ClientVpnTargetNetworks: mockAssociations })
      });

      const result = await vpnManager.fetchStatus();

      expect(result).toEqual({
        associated: true,
        activeConnections: 2,
        lastActivity: new Date(mockState.lastActivity),
        endpointId: mockConfig.ENDPOINT_ID,
        subnetId: mockConfig.SUBNET_ID
      });
    });

    it('should correct state mismatch between Parameter Store and AWS', async () => {
      // Mock Parameter Store showing associated=true, but AWS showing disassociated
      const incorrectState = { ...mockState, associated: true };
      mockSSMethods.getParameter.mockImplementation((params) => {
        if (params.Name === '/vpn/endpoint/state') {
          return {
            promise: () => Promise.resolve({
              Parameter: { Value: JSON.stringify(incorrectState) }
            })
          };
        }
        return {
          promise: () => Promise.resolve({
            Parameter: { Value: JSON.stringify(mockConfig) }
          })
        };
      });

      mockEC2Methods.describeClientVpnConnections.mockReturnValue({
        promise: () => Promise.resolve({ Connections: [] })
      });

      // AWS shows no associations (disassociated)
      mockEC2Methods.describeClientVpnTargetNetworks.mockReturnValue({
        promise: () => Promise.resolve({ ClientVpnTargetNetworks: [] })
      });

      const result = await vpnManager.fetchStatus();

      expect(result.associated).toBe(false);
      expect(mockSSMethods.putParameter).toHaveBeenCalledWith(
        expect.objectContaining({
          Name: '/vpn/endpoint/state',
          Value: expect.stringContaining('"associated":false')
        })
      );
    });

    it('should handle API errors gracefully', async () => {
      mockEC2Methods.describeClientVpnConnections.mockReturnValue({
        promise: () => Promise.reject(new Error('API Error'))
      });

      await expect(vpnManager.fetchStatus()).rejects.toThrow('Status fetch failed: API Error');
    });
  });

  describe('updateLastActivity', () => {
    it('should update last activity timestamp', async () => {
      await vpnManager.updateLastActivity();

      expect(mockSSMethods.putParameter).toHaveBeenCalledWith(
        expect.objectContaining({
          Name: '/vpn/endpoint/state',
          Value: expect.stringMatching(/"lastActivity":"[\d-]+T[\d:]+\.[\d]+Z"/)
        })
      );
    });

    it('should handle update errors', async () => {
      mockSSMethods.putParameter.mockReturnValue({
        promise: () => Promise.reject(new Error('Update failed'))
      });

      await expect(vpnManager.updateLastActivity()).rejects.toThrow('Last activity update failed: Unable to update VPN state: Update failed');
    });
  });

  describe('validateEndpoint', () => {
    it('should return true for valid and available endpoint', async () => {
      mockEC2Methods.describeClientVpnEndpoints.mockReturnValue({
        promise: () => Promise.resolve({
          ClientVpnEndpoints: [{
            ClientVpnEndpointId: mockConfig.ENDPOINT_ID,
            Status: { Code: 'available' }
          }]
        })
      });

      const result = await vpnManager.validateEndpoint();

      expect(result).toBe(true);
      expect(mockEC2Methods.describeClientVpnEndpoints).toHaveBeenCalledWith({
        ClientVpnEndpointIds: [mockConfig.ENDPOINT_ID]
      });
    });

    it('should return false for non-existent endpoint', async () => {
      mockEC2Methods.describeClientVpnEndpoints.mockReturnValue({
        promise: () => Promise.resolve({
          ClientVpnEndpoints: []
        })
      });

      const result = await vpnManager.validateEndpoint();

      expect(result).toBe(false);
    });

    it('should return false for endpoint not in available state', async () => {
      mockEC2Methods.describeClientVpnEndpoints.mockReturnValue({
        promise: () => Promise.resolve({
          ClientVpnEndpoints: [{
            ClientVpnEndpointId: mockConfig.ENDPOINT_ID,
            Status: { Code: 'pending-associate' }
          }]
        })
      });

      const result = await vpnManager.validateEndpoint();

      expect(result).toBe(false);
    });

    it('should return false on API errors', async () => {
      mockEC2Methods.describeClientVpnEndpoints.mockReturnValue({
        promise: () => Promise.reject(new Error('API Error'))
      });

      const result = await vpnManager.validateEndpoint();

      expect(result).toBe(false);
    });
  });
});