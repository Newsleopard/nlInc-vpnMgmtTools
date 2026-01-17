import { 
  EC2Client, 
  AssociateClientVpnTargetNetworkCommand,
  DisassociateClientVpnTargetNetworkCommand,
  DescribeClientVpnTargetNetworksCommand,
  DescribeClientVpnConnectionsCommand,
  DescribeClientVpnEndpointsCommand
} from '@aws-sdk/client-ec2';
import { VpnState, VpnStatus, VpnConnectionDetail, TrafficSnapshot, TrafficSummary } from './types';
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

    // Update state in Parameter Store (preserve existing traffic snapshot)
    const existingState = await stateStore.readState();
    const newState: VpnState = {
      associated: true,
      lastActivity: new Date().toISOString(),
      lastTrafficSnapshot: existingState.lastTrafficSnapshot
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
      // Update state to reflect reality (preserve traffic snapshot)
      const existingState = await stateStore.readState();
      await stateStore.writeState({
        associated: false,
        lastActivity: new Date().toISOString(),
        lastTrafficSnapshot: existingState.lastTrafficSnapshot
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

    // Update state in Parameter Store (clear traffic snapshot on close)
    const newState: VpnState = {
      associated: false,
      lastActivity: new Date().toISOString()
      // Intentionally not preserving lastTrafficSnapshot - start fresh on next open
    };

    await stateStore.writeState(newState);
    console.log('Updated state in Parameter Store');
    
  } catch (error) {
    console.error('Failed to disassociate subnets:', error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(`Subnet disassociation failed: ${errorMessage}`);
  }
}

// Calculate traffic summary with delta from previous snapshot
function calculateTrafficSummary(
  connections: VpnConnectionDetail[],
  previousSnapshot?: TrafficSnapshot
): TrafficSummary {
  // Calculate totals
  const totalIngressBytes = connections.reduce((sum, conn) => sum + conn.ingressBytes, 0);
  const totalEgressBytes = connections.reduce((sum, conn) => sum + conn.egressBytes, 0);

  // No connections - no traffic
  if (connections.length === 0) {
    return {
      status: 'no_connections',
      totalIngressBytes: 0,
      totalEgressBytes: 0,
      ingressDelta: 0,
      egressDelta: 0
    };
  }

  // No previous snapshot - assume active (first run)
  if (!previousSnapshot) {
    return {
      status: 'active',
      totalIngressBytes,
      totalEgressBytes,
      ingressDelta: 0,
      egressDelta: 0
    };
  }

  // Calculate delta from previous snapshot
  let ingressDelta = 0;
  let egressDelta = 0;

  for (const conn of connections) {
    const prev = previousSnapshot.connections[conn.connectionId];
    if (prev) {
      // Detect counter reset (negative diff or huge jump > 2x previous)
      // If counter appears to have reset, treat all current traffic as delta
      const ingressDiff = conn.ingressBytes - prev.ingress;
      const egressDiff = conn.egressBytes - prev.egress;

      if (ingressDiff < 0 || (prev.ingress > 0 && ingressDiff > prev.ingress * 2)) {
        // Counter reset detected - count all current traffic
        ingressDelta += conn.ingressBytes;
      } else {
        ingressDelta += ingressDiff;
      }

      if (egressDiff < 0 || (prev.egress > 0 && egressDiff > prev.egress * 2)) {
        // Counter reset detected - count all current traffic
        egressDelta += conn.egressBytes;
      } else {
        egressDelta += egressDiff;
      }
    } else {
      // New connection - count all its traffic as delta
      ingressDelta += conn.ingressBytes;
      egressDelta += conn.egressBytes;
    }
  }

  const hasTraffic = ingressDelta > 0 || egressDelta > 0;
  const snapshotTime = new Date(previousSnapshot.timestamp);
  const idleMinutes = hasTraffic ? undefined : Math.floor((Date.now() - snapshotTime.getTime()) / (1000 * 60));

  return {
    status: hasTraffic ? 'active' : 'idle',
    totalIngressBytes,
    totalEgressBytes,
    ingressDelta,
    egressDelta,
    idleMinutes
  };
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
    
    // Helper to safely parse traffic bytes with NaN validation
    const parseTrafficBytes = (value: string | undefined): number => {
      const parsed = parseInt(value || '0', 10);
      return isNaN(parsed) ? 0 : Math.max(0, parsed);
    };

    // Get active connection details including usernames and traffic metrics
    const activeConnectionDetails: VpnConnectionDetail[] = connections.Connections?.filter(
      conn => conn.Status?.Code === 'active'
    ).map(conn => ({
      connectionId: conn.ConnectionId || '',
      username: conn.CommonName || conn.Username || 'unknown',
      clientIp: conn.ClientIp || '',
      establishedTime: new Date(conn.ConnectionEstablishedTime || Date.now()),
      // Extract traffic metrics from AWS API with NaN validation
      ingressBytes: parseTrafficBytes(conn.IngressBytes),
      egressBytes: parseTrafficBytes(conn.EgressBytes)
    })) || [];

    const activeConnections = activeConnectionDetails.length;

    // Calculate traffic delta and update snapshot
    const trafficSummary = calculateTrafficSummary(activeConnectionDetails, state.lastTrafficSnapshot);

    // Build current traffic snapshot for next check
    const currentSnapshot: TrafficSnapshot = {
      timestamp: new Date().toISOString(),
      connections: activeConnectionDetails.reduce((acc, conn) => {
        acc[conn.connectionId] = { ingress: conn.ingressBytes, egress: conn.egressBytes };
        return acc;
      }, {} as { [connectionId: string]: { ingress: number; egress: number } })
    };

    // Update connection details with traffic status
    if (state.lastTrafficSnapshot) {
      for (const conn of activeConnectionDetails) {
        const prev = state.lastTrafficSnapshot.connections[conn.connectionId];
        if (prev) {
          const hasTraffic = conn.ingressBytes > prev.ingress || conn.egressBytes > prev.egress;
          conn.trafficStatus = hasTraffic ? 'active' : 'idle';
          if (!hasTraffic) {
            // Calculate idle time from last traffic snapshot
            const snapshotTime = new Date(state.lastTrafficSnapshot.timestamp);
            conn.idleMinutes = Math.floor((Date.now() - snapshotTime.getTime()) / (1000 * 60));
          }
        } else {
          // New connection - consider active
          conn.trafficStatus = 'active';
        }
      }
    }
    
    // Check actual association status from AWS
    const targetAssociation = associations.ClientVpnTargetNetworks?.find(
      assoc => assoc.TargetNetworkId === config.SUBNET_ID
    );
    
    const associationState = targetAssociation?.Status?.Code || 'disassociated';
    const actuallyAssociated = associationState === 'associated';
    
    // Update state with traffic snapshot and correct association if needed
    // Fix: Only update if association state changed OR traffic snapshot actually changed
    // This prevents excessive SSM writes and potential race conditions
    const snapshotChanged = !state.lastTrafficSnapshot ||
      JSON.stringify(Object.keys(currentSnapshot.connections).sort()) !==
      JSON.stringify(Object.keys(state.lastTrafficSnapshot.connections || {}).sort());
    const needsStateUpdate = state.associated !== actuallyAssociated || snapshotChanged;
    if (needsStateUpdate) {
      if (state.associated !== actuallyAssociated) {
        console.log(`State mismatch detected. Stored: ${state.associated}, Actual: ${actuallyAssociated}`);
      }
      if (snapshotChanged) {
        console.log('Traffic snapshot changed, updating state');
      }
      const updatedState: VpnState = {
        associated: actuallyAssociated,
        lastActivity: state.lastActivity, // Keep original lastActivity
        lastTrafficSnapshot: currentSnapshot // Update traffic snapshot
      };
      await stateStore.writeState(updatedState);
    }

    const status: VpnStatus = {
      associated: actuallyAssociated,
      associationState: associationState as 'associated' | 'associating' | 'disassociating' | 'disassociated' | 'failed',
      activeConnections,
      activeConnectionDetails,
      trafficSummary,
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