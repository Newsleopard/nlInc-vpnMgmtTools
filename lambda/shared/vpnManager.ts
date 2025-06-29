import { 
  EC2Client, 
  AssociateClientVpnTargetNetworkCommand,
  DisassociateClientVpnTargetNetworkCommand,
  DescribeClientVpnTargetNetworksCommand,
  DescribeClientVpnConnectionsCommand,
  DescribeClientVpnEndpointsCommand
} from '@aws-sdk/client-ec2';
import { VpnState, VpnStatus } from './types';
import * as stateStore from './stateStore';

const ec2 = new EC2Client({});

// Associate subnets with VPN endpoint
export async function associateSubnets(): Promise<void> {
  console.log('Starting subnet association...');
  
  try {
    // Read configuration from Parameter Store
    const config = await stateStore.readConfig();
    console.log('Retrieved config:', config);
    
    // Check current status including intermediate states
    const currentStatus = await fetchStatus();
    
    // If already associated, no action needed
    if (currentStatus.associated) {
      console.log('Subnets are already associated with VPN endpoint');
      return;
    }
    
    // Check for intermediate states that should block operations
    if (currentStatus.associationState === 'associating') {
      throw new Error('VPN is currently associating subnets. Please wait for the operation to complete before trying again.');
    }
    
    if (currentStatus.associationState === 'disassociating') {
      throw new Error('VPN is currently disassociating subnets. Please wait for the operation to complete before trying to open.');
    }
    
    // Associate subnet with VPN endpoint
    console.log(`Associating subnet ${config.SUBNET_ID} with endpoint ${config.ENDPOINT_ID}`);
    
    await ec2.send(new AssociateClientVpnTargetNetworkCommand({
      ClientVpnEndpointId: config.ENDPOINT_ID,
      SubnetId: config.SUBNET_ID
    }));
    
    console.log('Successfully associated subnet with VPN endpoint');
    
    // Update state in Parameter Store
    const newState: VpnState = {
      associated: true,
      lastActivity: new Date().toISOString()
    };
    
    await stateStore.writeState(newState);
    console.log('Updated state in Parameter Store');
    
  } catch (error) {
    console.error('Failed to associate subnets:', error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(`Subnet association failed: ${errorMessage}`);
  }
}

// Disassociate subnets from VPN endpoint
export async function disassociateSubnets(): Promise<void> {
  console.log('Starting subnet disassociation...');
  
  try {
    // Read configuration from Parameter Store
    const config = await stateStore.readConfig();
    console.log('Retrieved config:', config);
    
    // Check current status including intermediate states
    const currentStatus = await fetchStatus();
    
    // If already disassociated, no action needed
    if (!currentStatus.associated) {
      console.log('Subnets are already disassociated from VPN endpoint');
      return;
    }
    
    // Check for intermediate states that should block operations
    if (currentStatus.associationState === 'disassociating') {
      throw new Error('VPN is currently disassociating subnets. Please wait for the operation to complete before trying again.');
    }
    
    if (currentStatus.associationState === 'associating') {
      throw new Error('VPN is currently associating subnets. Please wait for the operation to complete before trying to close.');
    }
    
    // Get association ID for disassociation
    const associations = await ec2.send(new DescribeClientVpnTargetNetworksCommand({
      ClientVpnEndpointId: config.ENDPOINT_ID
    }));
    
    const targetAssociation = associations.ClientVpnTargetNetworks?.find(
      assoc => assoc.TargetNetworkId === config.SUBNET_ID && assoc.Status?.Code !== 'disassociated'
    );
    
    if (!targetAssociation?.AssociationId) {
      console.log('No active association found for subnet');
      // Update state to reflect reality
      await stateStore.writeState({
        associated: false,
        lastActivity: new Date().toISOString()
      });
      return;
    }
    
    console.log(`Disassociating subnet ${config.SUBNET_ID} from endpoint ${config.ENDPOINT_ID}`);
    
    // Disassociate subnet from VPN endpoint
    await ec2.send(new DisassociateClientVpnTargetNetworkCommand({
      ClientVpnEndpointId: config.ENDPOINT_ID,
      AssociationId: targetAssociation.AssociationId
    }));
    
    console.log('Successfully disassociated subnet from VPN endpoint');
    
    // Update state in Parameter Store
    const newState: VpnState = {
      associated: false,
      lastActivity: new Date().toISOString()
    };
    
    await stateStore.writeState(newState);
    console.log('Updated state in Parameter Store');
    
  } catch (error) {
    console.error('Failed to disassociate subnets:', error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(`Subnet disassociation failed: ${errorMessage}`);
  }
}

// Fetch current VPN status from AWS and Parameter Store
export async function fetchStatus(): Promise<VpnStatus> {
  console.log('Fetching VPN status...');
  
  try {
    // Read current state and configuration
    const [state, config] = await Promise.all([
      stateStore.readState(),
      stateStore.readConfig()
    ]);
    
    console.log('Retrieved state:', state);
    console.log('Retrieved config:', config);
    
    // Query EC2 for current connection status
    const [connections, associations] = await Promise.all([
      ec2.send(new DescribeClientVpnConnectionsCommand({
        ClientVpnEndpointId: config.ENDPOINT_ID
      })),
      ec2.send(new DescribeClientVpnTargetNetworksCommand({
        ClientVpnEndpointId: config.ENDPOINT_ID
      }))
    ]);
    
    // Count active connections
    const activeConnections = connections.Connections?.filter(
      conn => conn.Status?.Code === 'active'
    ).length || 0;
    
    // Check actual association status from AWS
    const targetAssociation = associations.ClientVpnTargetNetworks?.find(
      assoc => assoc.TargetNetworkId === config.SUBNET_ID
    );
    
    const associationState = targetAssociation?.Status?.Code || 'disassociated';
    const actuallyAssociated = associationState === 'associated';
    
    // If state doesn't match reality, update it
    if (state.associated !== actuallyAssociated) {
      console.log(`State mismatch detected. Stored: ${state.associated}, Actual: ${actuallyAssociated}`);
      const correctedState: VpnState = {
        associated: actuallyAssociated,
        lastActivity: state.lastActivity // Keep original lastActivity
      };
      await stateStore.writeState(correctedState);
    }
    
    const status: VpnStatus = {
      associated: actuallyAssociated,
      associationState: associationState as 'associated' | 'associating' | 'disassociating' | 'disassociated' | 'failed',
      activeConnections,
      lastActivity: new Date(state.lastActivity),
      endpointId: config.ENDPOINT_ID,
      subnetId: config.SUBNET_ID
    };
    
    console.log('Current VPN status:', status);
    return status;
    
  } catch (error) {
    console.error('Failed to fetch VPN status:', error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(`Status fetch failed: ${errorMessage}`);
  }
}

// Update last activity timestamp
export async function updateLastActivity(): Promise<void> {
  try {
    const state = await stateStore.readState();
    const updatedState: VpnState = {
      ...state,
      lastActivity: new Date().toISOString()
    };
    await stateStore.writeState(updatedState);
    console.log('Updated last activity timestamp');
  } catch (error) {
    console.error('Failed to update last activity:', error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(`Last activity update failed: ${errorMessage}`);
  }
}

// Validate VPN endpoint exists and is accessible
export async function validateEndpoint(): Promise<boolean> {
  try {
    const config = await stateStore.readConfig();
    
    const endpoints = await ec2.send(new DescribeClientVpnEndpointsCommand({
      ClientVpnEndpointIds: [config.ENDPOINT_ID]
    }));
    
    if (!endpoints.ClientVpnEndpoints || endpoints.ClientVpnEndpoints.length === 0) {
      console.error(`VPN endpoint ${config.ENDPOINT_ID} not found`);
      return false;
    }
    
    const endpoint = endpoints.ClientVpnEndpoints[0];
    const status = endpoint.Status?.Code;
    
    // Valid statuses: 'available' (open) and 'pending-associate' (closed, no subnets)
    // Both are valid operational states and should not trigger alerts
    if (status !== 'available' && status !== 'pending-associate') {
      console.error(`VPN endpoint ${config.ENDPOINT_ID} is in invalid state. Status: ${status}`);
      return false;
    }
    
    console.log(`VPN endpoint ${config.ENDPOINT_ID} is valid. Status: ${status}`);
    return true;
    
  } catch (error) {
    console.error('Failed to validate endpoint:', error);
    return false;
  }
}