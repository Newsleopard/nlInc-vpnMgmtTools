import { SSMClient, GetParameterCommand, PutParameterCommand } from '@aws-sdk/client-ssm';
import { VpnConfig, VpnState } from './types';
import { SecureParameterManager, readSecureParameter, writeSecureParameter } from './secureParameterManager';

const ssm = new SSMClient({});

/**
 * Epic 5.1: Enhanced State Store with Secure Parameter Management
 * 
 * This updated version uses the SecureParameterManager for:
 * - Automatic encryption/decryption of sensitive parameters
 * - Parameter validation and format checking
 * - Enhanced security logging and audit trails
 * - KMS encryption for sensitive configuration data
 */

// Epic 5.1.1: Read VPN endpoint configuration from Parameter Store with validation
export async function readConfig(): Promise<VpnConfig> {
  try {
    const config = await readSecureParameter('/vpn/endpoint/conf');
    return config as VpnConfig;
  } catch (error) {
    console.error('Failed to read VPN configuration:', error);
    throw new Error(`Unable to read VPN configuration: ${error}`);
  }
}

// Epic 5.1.1: Read VPN state information from Parameter Store with validation
export async function readState(): Promise<VpnState> {
  try {
    const state = await readSecureParameter('/vpn/endpoint/state');
    return state as VpnState;
  } catch (error) {
    console.error('Failed to read VPN state:', error);
    throw new Error(`Unable to read VPN state: ${error}`);
  }
}

// Epic 5.1.1: Write VPN state information to Parameter Store with validation
export async function writeState(state: VpnState): Promise<void> {
  try {
    await writeSecureParameter('/vpn/endpoint/state', state);
    console.log('Successfully updated VPN state:', state);
  } catch (error) {
    console.error('Failed to write VPN state:', error);
    throw new Error(`Unable to update VPN state: ${error}`);
  }
}

// Epic 5.1.1: Write VPN configuration to Parameter Store with validation
export async function writeConfig(config: VpnConfig): Promise<void> {
  try {
    await writeSecureParameter('/vpn/endpoint/conf', config);
    console.log('Successfully updated VPN configuration:', config);
  } catch (error) {
    console.error('Failed to write VPN configuration:', error);
    throw new Error(`Unable to update VPN configuration: ${error}`);
  }
}

// Epic 5.1.1: Read Slack webhook URL (encrypted parameter with KMS)
export async function readSlackWebhook(): Promise<string> {
  try {
    const environment = process.env.ENVIRONMENT || 'staging';
    const webhook = await readSecureParameter(`/vpn/${environment}/slack/webhook`);
    
    if (typeof webhook !== 'string') {
      throw new Error('Slack webhook parameter is not a string');
    }
    
    // Epic 5.1.2: Check for placeholder values
    if (webhook.includes('PLACEHOLDER_')) {
      throw new Error('Slack webhook URL is still a placeholder value. Please configure with actual webhook URL.');
    }
    
    return webhook;
  } catch (error) {
    console.error('Failed to read Slack webhook:', error);
    throw new Error(`Unable to read Slack webhook: ${error}`);
  }
}

// Epic 5.1.1: Read Slack signing secret (encrypted parameter with KMS)
export async function readSlackSigningSecret(): Promise<string> {
  try {
    // Use environment-specific parameter path
    const environment = process.env.ENVIRONMENT || 'staging';
    const parameterName = process.env.SIGNING_SECRET_PARAM || `/vpn/${environment}/slack/signing_secret`;
    
    // Direct SSM call to ensure we get the raw string value
    const result = await ssm.send(new GetParameterCommand({
      Name: parameterName,
      WithDecryption: true
    }));
    
    const secret = result.Parameter?.Value;
    
    if (!secret) {
      throw new Error('Slack signing secret not found');
    }
    
    if (typeof secret !== 'string') {
      throw new Error('Slack signing secret parameter is not a string');
    }
    
    // Epic 5.1.2: Check for placeholder values
    if (secret.includes('PLACEHOLDER_')) {
      throw new Error('Slack signing secret is still a placeholder value. Please configure with actual signing secret.');
    }
    
    return secret;
  } catch (error) {
    console.error('Failed to read Slack signing secret:', error);
    throw new Error(`Unable to read Slack signing secret: ${error}`);
  }
}

// Epic 5.1.1: Read Slack bot token (encrypted parameter with KMS)
export async function readSlackBotToken(): Promise<string> {
  try {
    const environment = process.env.ENVIRONMENT || 'staging';
    const token = await readSecureParameter(`/vpn/${environment}/slack/bot_token`);
    
    if (typeof token !== 'string') {
      throw new Error('Slack bot token parameter is not a string');
    }
    
    // Epic 5.1.2: Check for placeholder values
    if (token.includes('PLACEHOLDER_')) {
      throw new Error('Slack bot token is still a placeholder value. Please configure with actual bot token.');
    }
    
    return token;
  } catch (error) {
    console.error('Failed to read Slack bot token:', error);
    throw new Error(`Unable to read Slack bot token: ${error}`);
  }
}

// Epic 5.1.1: Read cost optimization configuration (encrypted parameter)
export async function readCostOptimizationConfig(): Promise<any> {
  try {
    const config = await readSecureParameter('/vpn/cost/optimization_config');
    return config;
  } catch (error) {
    console.error('Failed to read cost optimization config:', error);
    // Return default configuration if parameter doesn't exist
    return {
      idleTimeoutMinutes: 54,
      cooldownMinutes: 30,
      businessHoursProtection: true,
      businessHoursTimezone: 'UTC',
      businessHoursStart: '09:00',
      businessHoursEnd: '18:00',
      regionalPricingEnabled: true,
      cumulativeSavingsTracking: true
    };
  }
}

// Epic 5.1.1: Write cost optimization configuration
export async function writeCostOptimizationConfig(config: any): Promise<void> {
  try {
    await writeSecureParameter('/vpn/cost/optimization_config', config);
    console.log('Successfully updated cost optimization configuration');
  } catch (error) {
    console.error('Failed to write cost optimization config:', error);
    throw new Error(`Unable to update cost optimization config: ${error}`);
  }
}

// Epic 5.1.1: Read admin overrides (encrypted for audit security)
export async function readAdminOverrides(): Promise<any> {
  try {
    const overrides = await readSecureParameter('/vpn/admin/overrides');
    return overrides;
  } catch (error) {
    console.error('Failed to read admin overrides:', error);
    // Return default structure if parameter doesn't exist
    return {
      activeOverrides: {},
      overrideHistory: [],
      lastUpdated: new Date().toISOString()
    };
  }
}

// Epic 5.1.1: Write admin overrides with audit trail
export async function writeAdminOverrides(overrides: any): Promise<void> {
  try {
    // Add timestamp to override data
    overrides.lastUpdated = new Date().toISOString();
    await writeSecureParameter('/vpn/admin/overrides', overrides);
    console.log('Successfully updated admin overrides');
  } catch (error) {
    console.error('Failed to write admin overrides:', error);
    throw new Error(`Unable to update admin overrides: ${error}`);
  }
}

// Epic 5.1.1: Read cost metrics (encrypted business data)
export async function readCostMetrics(): Promise<any> {
  try {
    const metrics = await readSecureParameter('/vpn/cost/metrics');
    return metrics;
  } catch (error) {
    console.error('Failed to read cost metrics:', error);
    // Return default structure if parameter doesn't exist
    return {
      totalSavings: 0,
      monthlyStats: {},
      lastCalculated: new Date().toISOString(),
      regionPricing: {
        'us-east-1': 0.05,
        'us-west-2': 0.05,
        'eu-west-1': 0.05,
        'ap-southeast-1': 0.05
      }
    };
  }
}

// Epic 5.1.1: Write cost metrics with timestamp
export async function writeCostMetrics(metrics: any): Promise<void> {
  try {
    // Add timestamp to metrics data
    metrics.lastCalculated = new Date().toISOString();
    await writeSecureParameter('/vpn/cost/metrics', metrics);
    console.log('Successfully updated cost metrics');
  } catch (error) {
    console.error('Failed to write cost metrics:', error);
    throw new Error(`Unable to update cost metrics: ${error}`);
  }
}

// Epic 5.1.2: Read cross-account configuration (staging only)
export async function readCrossAccountConfig(): Promise<any> {
  const environment = process.env.ENVIRONMENT || 'staging';
  
  if (environment !== 'staging') {
    return null; // Cross-account config only needed for staging
  }
  
  try {
    const config = await readSecureParameter('/vpn/cross_account/config');
    
    // Epic 5.1.2: Check for placeholder values
    if (config.productionApiEndpoint?.includes('PLACEHOLDER_') ||
        config.productionApiKey?.includes('PLACEHOLDER_')) {
      throw new Error('Cross-account configuration contains placeholder values. Please configure with actual production endpoint and API key.');
    }
    
    return config;
  } catch (error) {
    console.error('Failed to read cross-account config:', error);
    throw new Error(`Unable to read cross-account config: ${error}`);
  }
}

// Epic 5.1.2: Write cross-account configuration
export async function writeCrossAccountConfig(config: any): Promise<void> {
  try {
    await writeSecureParameter('/vpn/cross_account/config', config);
    console.log('Successfully updated cross-account configuration');
  } catch (error) {
    console.error('Failed to write cross-account config:', error);
    throw new Error(`Unable to update cross-account config: ${error}`);
  }
}

// Generic function to read any parameter (backward compatibility)
export async function readParameter(paramName: string, encrypted: boolean = false): Promise<string | null> {
  try {
    if (encrypted) {
      const result = await readSecureParameter(paramName);
      return typeof result === 'string' ? result : JSON.stringify(result);
    } else {
      // Use direct SSM for non-encrypted parameters
      const result = await ssm.send(new GetParameterCommand({ Name: paramName }));
      return result.Parameter?.Value || null;
    }
  } catch (error: any) {
    if (error.code === 'ParameterNotFound') {
      return null;
    }
    console.error(`Failed to read parameter ${paramName}:`, error);
    return null;
  }
}

// Generic function to write any parameter (backward compatibility)
export async function writeParameter(paramName: string, value: string, encrypted: boolean = false): Promise<void> {
  try {
    if (encrypted) {
      await writeSecureParameter(paramName, value);
    } else {
      // Use direct SSM for non-encrypted parameters
      await ssm.send(new PutParameterCommand({
        Name: paramName,
        Value: value,
        Type: 'String',
        Overwrite: true
      }));
    }
    console.log(`Successfully wrote parameter ${paramName}`);
  } catch (error) {
    console.error(`Failed to write parameter ${paramName}:`, error);
    throw new Error(`Unable to write parameter: ${error}`);
  }
}

// Epic 5.1.2: Enhanced parameter store validation using SecureParameterManager
export async function validateParameterStore(): Promise<boolean> {
  try {
    const manager = new SecureParameterManager();
    const result = await manager.validateConfiguration();
    
    if (!result.isValid) {
      console.error('Parameter store validation failed:', result.errors);
      return false;
    }
    
    if (result.warnings.length > 0) {
      console.warn('Parameter store validation warnings:', result.warnings);
    }
    
    console.log('Parameter store validation completed successfully');
    return true;
  } catch (error) {
    console.error('Parameter store validation failed:', error);
    return false;
  }
}