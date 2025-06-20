import { SSM } from 'aws-sdk';
import { VpnConfig, VpnState } from './types';

const ssm = new SSM();

// Read VPN endpoint configuration from Parameter Store
export async function readConfig(): Promise<VpnConfig> {
  const paramName = `/vpn/endpoint/conf`;
  
  try {
    const result = await ssm.getParameter({ Name: paramName }).promise();
    
    if (!result.Parameter?.Value) {
      throw new Error(`Parameter ${paramName} has no value`);
    }
    
    return JSON.parse(result.Parameter.Value);
  } catch (error) {
    console.error(`Failed to read config from ${paramName}:`, error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(`Unable to read VPN configuration: ${errorMessage}`);
  }
}

// Read VPN state information from Parameter Store
export async function readState(): Promise<VpnState> {
  const paramName = `/vpn/endpoint/state`;
  
  try {
    const result = await ssm.getParameter({ Name: paramName }).promise();
    
    if (!result.Parameter?.Value) {
      throw new Error(`Parameter ${paramName} has no value`);
    }
    
    return JSON.parse(result.Parameter.Value);
  } catch (error) {
    console.error(`Failed to read state from ${paramName}:`, error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(`Unable to read VPN state: ${errorMessage}`);
  }
}

// Write VPN state information to Parameter Store
export async function writeState(state: VpnState): Promise<void> {
  const paramName = `/vpn/endpoint/state`;
  
  try {
    await ssm.putParameter({
      Name: paramName,
      Value: JSON.stringify(state),
      Type: 'String',
      Overwrite: true,
      Description: 'VPN endpoint state (associated status and last activity)'
    }).promise();
    
    console.log(`Successfully updated state in ${paramName}:`, state);
  } catch (error) {
    console.error(`Failed to write state to ${paramName}:`, error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(`Unable to update VPN state: ${errorMessage}`);
  }
}

// Write VPN configuration to Parameter Store
export async function writeConfig(config: VpnConfig): Promise<void> {
  const paramName = `/vpn/endpoint/conf`;
  
  try {
    await ssm.putParameter({
      Name: paramName,
      Value: JSON.stringify(config),
      Type: 'String',
      Overwrite: true,
      Description: 'VPN endpoint configuration (endpoint ID and subnet ID)'
    }).promise();
    
    console.log(`Successfully updated config in ${paramName}:`, config);
  } catch (error) {
    console.error(`Failed to write config to ${paramName}:`, error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(`Unable to update VPN configuration: ${errorMessage}`);
  }
}

// Read Slack webhook URL (encrypted parameter)
export async function readSlackWebhook(): Promise<string> {
  const paramName = `/vpn/slack/webhook`;
  
  try {
    const result = await ssm.getParameter({ 
      Name: paramName, 
      WithDecryption: true 
    }).promise();
    
    if (!result.Parameter?.Value) {
      throw new Error(`Parameter ${paramName} has no value`);
    }
    
    return result.Parameter.Value;
  } catch (error) {
    console.error(`Failed to read Slack webhook from ${paramName}:`, error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(`Unable to read Slack webhook: ${errorMessage}`);
  }
}

// Read Slack signing secret (encrypted parameter)
export async function readSlackSigningSecret(): Promise<string> {
  const paramName = `/vpn/slack/signing_secret`;
  
  try {
    const result = await ssm.getParameter({ 
      Name: paramName, 
      WithDecryption: true 
    }).promise();
    
    if (!result.Parameter?.Value) {
      throw new Error(`Parameter ${paramName} has no value`);
    }
    
    return result.Parameter.Value;
  } catch (error) {
    console.error(`Failed to read Slack signing secret from ${paramName}:`, error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(`Unable to read Slack signing secret: ${errorMessage}`);
  }
}

// Generic function to read any parameter (returns null if not found)
export async function readParameter(paramName: string, encrypted: boolean = false): Promise<string | null> {
  try {
    const result = await ssm.getParameter({ 
      Name: paramName, 
      WithDecryption: encrypted 
    }).promise();
    
    return result.Parameter?.Value || null;
  } catch (error: any) {
    // Return null for parameter not found, rather than throwing
    if (error.code === 'ParameterNotFound') {
      return null;
    }
    console.error(`Failed to read parameter ${paramName}:`, error);
    return null;
  }
}

// Generic function to write any parameter
export async function writeParameter(paramName: string, value: string, encrypted: boolean = false): Promise<void> {
  try {
    await ssm.putParameter({
      Name: paramName,
      Value: value,
      Type: encrypted ? 'SecureString' : 'String',
      Overwrite: true
    }).promise();
    
    console.log(`Successfully wrote parameter ${paramName}`);
  } catch (error) {
    console.error(`Failed to write parameter ${paramName}:`, error);
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(`Unable to write parameter: ${errorMessage}`);
  }
}

// Check if all required parameters exist
export async function validateParameterStore(): Promise<boolean> {
  const requiredParams = [
    '/vpn/endpoint/conf',
    '/vpn/endpoint/state',
    '/vpn/slack/webhook',
    '/vpn/slack/signing_secret'
  ];
  
  try {
    for (const paramName of requiredParams) {
      await ssm.getParameter({ Name: paramName }).promise();
    }
    return true;
  } catch (error) {
    console.error('Parameter Store validation failed:', error);
    return false;
  }
}