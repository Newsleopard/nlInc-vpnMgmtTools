// Mock AWS SDK for testing

export const mockEC2Methods = {
  associateClientVpnTargetNetwork: jest.fn(),
  disassociateClientVpnTargetNetwork: jest.fn(),
  describeClientVpnEndpoints: jest.fn(),
  describeClientVpnTargetNetworks: jest.fn(),
  describeClientVpnConnections: jest.fn(),
  describeSubnets: jest.fn()
};

export const mockSSMethods = {
  getParameter: jest.fn(),
  putParameter: jest.fn()
};

export const mockCloudWatchMethods = {
  putMetricData: jest.fn()
};

export const mockLambdaMethods = {
  invoke: jest.fn()
};

// Mock EC2 class
export class EC2 {
  associateClientVpnTargetNetwork = mockEC2Methods.associateClientVpnTargetNetwork.mockReturnValue({
    promise: () => Promise.resolve({
      AssociationId: 'cvpn-assoc-mock123',
      Status: { Code: 'associating' }
    })
  });

  disassociateClientVpnTargetNetwork = mockEC2Methods.disassociateClientVpnTargetNetwork.mockReturnValue({
    promise: () => Promise.resolve({
      AssociationId: 'cvpn-assoc-mock123',
      Status: { Code: 'disassociating' }
    })
  });

  describeClientVpnEndpoints = mockEC2Methods.describeClientVpnEndpoints.mockReturnValue({
    promise: () => Promise.resolve({
      ClientVpnEndpoints: [{
        ClientVpnEndpointId: 'cvpn-endpoint-mock123',
        Status: { Code: 'available' },
        State: 'available'
      }]
    })
  });

  describeClientVpnTargetNetworks = mockEC2Methods.describeClientVpnTargetNetworks.mockReturnValue({
    promise: () => Promise.resolve({
      ClientVpnTargetNetworks: [{
        AssociationId: 'cvpn-assoc-mock123',
        TargetNetworkId: 'subnet-mock123',
        Status: { Code: 'associated' }
      }]
    })
  });

  describeClientVpnConnections = mockEC2Methods.describeClientVpnConnections.mockReturnValue({
    promise: () => Promise.resolve({
      Connections: [
        { ConnectionId: 'cvpn-connection-1', Status: { Code: 'active' } },
        { ConnectionId: 'cvpn-connection-2', Status: { Code: 'active' } }
      ]
    })
  });

  describeSubnets = mockEC2Methods.describeSubnets.mockReturnValue({
    promise: () => Promise.resolve({
      Subnets: [{
        SubnetId: 'subnet-mock123',
        State: 'available'
      }]
    })
  });
}

// Mock SSM class
export class SSM {
  getParameter = mockSSMethods.getParameter.mockImplementation((params: any) => {
    const mockResponses: Record<string, any> = {
      '/vpn/endpoint/conf': {
        Parameter: {
          Value: JSON.stringify({
            ENDPOINT_ID: 'cvpn-endpoint-mock123',
            SUBNET_ID: 'subnet-mock123'
          })
        }
      },
      '/vpn/endpoint/state': {
        Parameter: {
          Value: JSON.stringify({
            associated: false,
            lastActivity: '2025-06-17T10:00:00.000Z'
          })
        }
      },
      '/vpn/slack/webhook': {
        Parameter: {
          Value: 'https://hooks.slack.com/services/mock'
        }
      },
      '/vpn/slack/signing_secret': {
        Parameter: {
          Value: 'mock_signing_secret'
        }
      }
    };

    return {
      promise: () => Promise.resolve(mockResponses[params.Name] || {
        Parameter: { Value: 'mock_value' }
      })
    };
  });

  putParameter = mockSSMethods.putParameter.mockReturnValue({
    promise: () => Promise.resolve({
      Version: 1,
      Tier: 'Standard'
    })
  });
}

// Mock CloudWatch class
export class CloudWatch {
  putMetricData = mockCloudWatchMethods.putMetricData.mockReturnValue({
    promise: () => Promise.resolve({})
  });
}

// Mock Lambda class
export class Lambda {
  invoke = mockLambdaMethods.invoke.mockReturnValue({
    promise: () => Promise.resolve({
      StatusCode: 200,
      Payload: JSON.stringify({
        statusCode: 200,
        body: JSON.stringify({
          success: true,
          message: 'Mock response',
          data: { associated: true, activeConnections: 2 }
        })
      })
    })
  });
}

// Helper function to reset all mocks
export const resetAllMocks = () => {
  Object.values(mockEC2Methods).forEach(mock => mock.mockClear());
  Object.values(mockSSMethods).forEach(mock => mock.mockClear());
  Object.values(mockCloudWatchMethods).forEach(mock => mock.mockClear());
  Object.values(mockLambdaMethods).forEach(mock => mock.mockClear());
};

// Helper function to set mock responses
export const setMockResponse = (service: string, method: string, response: any) => {
  const mockMethods: Record<string, Record<string, any>> = {
    EC2: mockEC2Methods,
    SSM: mockSSMethods,
    CloudWatch: mockCloudWatchMethods,
    Lambda: mockLambdaMethods
  };

  if (mockMethods[service] && mockMethods[service][method]) {
    mockMethods[service][method].mockReturnValue({
      promise: () => Promise.resolve(response)
    });
  }
};