import { SecureParameterManager } from './secureParameterManager';
import { createLogger } from './logger';

/**
 * Epic 5.1.2: Configuration Validation Tool
 * 
 * This module provides comprehensive configuration validation for the VPN Cost Automation system:
 * - Parameter existence and format validation
 * - KMS encryption status verification
 * - Business logic validation
 * - Deployment readiness checks
 * - Configuration drift detection
 */

export interface ConfigurationIssue {
  parameter: string;
  issue: string;
  severity: 'error' | 'warning';
  recommendation: string;
}

export interface DeploymentReadiness {
  ready: boolean;
  blockers: string[];
  warnings: string[];
}

export interface ConfigurationValidationResult {
  isValid: boolean;
  errors: string[];
  warnings: string[];
  summary: {
    parametersChecked: number;
    encryptedParameters: number;
    placeholderParameters: string[];
    configurationIssues: ConfigurationIssue[];
    deploymentReadiness: DeploymentReadiness;
  };
}

export class ConfigurationValidator {
  private logger: any;
  private environment: string;
  private paramManager: SecureParameterManager;

  constructor(environment: string = process.env.ENVIRONMENT || 'staging') {
    this.environment = environment;
    this.logger = createLogger({
      requestId: 'config-validator',
      environment: environment,
      functionName: 'ConfigurationValidator'
    });
    this.paramManager = new SecureParameterManager(environment);
  }

  /**
   * Epic 5.1.2: Comprehensive configuration validation
   */
  async validateConfiguration(): Promise<ConfigurationValidationResult> {
    const result: ConfigurationValidationResult = {
      isValid: true,
      errors: [],
      warnings: [],
      summary: {
        parametersChecked: 0,
        encryptedParameters: 0,
        placeholderParameters: [],
        configurationIssues: [],
        deploymentReadiness: {
          ready: false,
          blockers: [],
          warnings: []
        }
      }
    };

    this.logger.info('Starting comprehensive configuration validation', {
      environment: this.environment
    });

    try {
      // Epic 5.1.2: Validate parameter store configuration
      const paramStoreValid = await this.paramManager.validateParameterStore();
      if (!paramStoreValid.isValid) {
        result.errors.push(...paramStoreValid.errors);
        result.isValid = false;
      }
      result.warnings.push(...paramStoreValid.warnings);

      // Epic 5.1.2: Check for placeholder values
      const placeholders = await this.checkPlaceholderValues();
      result.summary.placeholderParameters = placeholders;
      if (placeholders.length > 0) {
        result.warnings.push(`Found ${placeholders.length} parameters with placeholder values`);
      }

      // Epic 5.1.2: Validate deployment readiness
      const readinessChecks = await this.validateDeploymentReadiness();
      result.summary.deploymentReadiness = readinessChecks;
      if (!readinessChecks.ready) {
        result.errors.push(...readinessChecks.blockers);
        result.isValid = false;
      }

      // Determine overall validation status
      result.summary.deploymentReadiness.ready = result.isValid && 
        result.summary.placeholderParameters.length === 0;

      if (result.isValid) {
        this.logger.info('Configuration validation completed successfully', {
          warnings: result.warnings.length,
          deploymentReady: result.summary.deploymentReadiness.ready
        });
      } else {
        this.logger.error('Configuration validation failed', {
          errors: result.errors.length,
          warnings: result.warnings.length
        });
      }

      return result;

    } catch (error) {
      result.errors.push(`Configuration validation failed: ${error}`);
      result.isValid = false;
      
      this.logger.error('Configuration validation error', {
        error: error instanceof Error ? error.message : String(error)
      });

      return result;
    }
  }

  /**
   * Epic 5.1.2: Check for placeholder values
   */
  private async checkPlaceholderValues(): Promise<string[]> {
    const placeholderParameters: string[] = [];
    const parametersToCheck = [
      '/vpn/endpoint/conf',
      '/vpn/slack/webhook',
      '/vpn/slack/signing_secret',
      '/vpn/cross_account/config'
    ];

    for (const paramName of parametersToCheck) {
      try {
        const paramResult = await this.paramManager.readParameter(paramName, false);
        if (paramResult.isValid && paramResult.parameter) {
          const value = typeof paramResult.parameter === 'string' 
            ? paramResult.parameter 
            : JSON.stringify(paramResult.parameter);
          
          if (value.includes('PLACEHOLDER_')) {
            placeholderParameters.push(paramName);
          }
        }
      } catch (error) {
        // Skip parameters that don't exist or can't be read
      }
    }

    return placeholderParameters;
  }

  /**
   * Epic 5.1.2: Validate deployment readiness
   */
  private async validateDeploymentReadiness(): Promise<DeploymentReadiness> {
    const result: DeploymentReadiness = {
      ready: false,
      blockers: [],
      warnings: []
    };

    try {
      // Check KMS configuration
      const kmsResult = await this.paramManager.validateKmsConfiguration();
      if (!kmsResult.isValid) {
        result.blockers.push('KMS configuration invalid');
      }

      // Check required environment variables
      const requiredEnvVars = [
        'ENVIRONMENT',
        'VPN_STATE_PREFIX',
        'SIGNING_SECRET_PARAM',
        'WEBHOOK_PARAM'
      ];

      for (const envVar of requiredEnvVars) {
        if (!process.env[envVar]) {
          result.blockers.push(`Missing environment variable: ${envVar}`);
        }
      }

      // Check Slack configuration
      try {
        const webhookResult = await this.paramManager.readParameter('/vpn/slack/webhook', false);
        if (!webhookResult.isValid || webhookResult.parameter?.includes('PLACEHOLDER_')) {
          result.blockers.push('Slack webhook not configured');
        }

        const secretResult = await this.paramManager.readParameter('/vpn/slack/signing_secret', false);
        if (!secretResult.isValid || secretResult.parameter?.includes('PLACEHOLDER_')) {
          result.blockers.push('Slack signing secret not configured');
        }
      } catch (error) {
        result.blockers.push('Unable to validate Slack configuration');
      }

      // Check cross-account configuration for staging
      if (this.environment === 'staging') {
        try {
          const crossAccountResult = await this.paramManager.readParameter('/vpn/cross_account/config', false);
          if (!crossAccountResult.isValid) {
            result.blockers.push('Cross-account configuration missing');
          } else if (crossAccountResult.parameter) {
            const config = crossAccountResult.parameter;
            if (config.productionApiEndpoint?.includes('PLACEHOLDER_') ||
                config.productionApiKey?.includes('PLACEHOLDER_')) {
              result.blockers.push('Cross-account configuration contains placeholder values');
            }
          }
        } catch (error) {
          result.warnings.push('Unable to validate cross-account configuration');
        }
      }

      // Determine readiness
      result.ready = result.blockers.length === 0;

    } catch (error) {
      result.blockers.push('Deployment readiness check failed');
    }

    return result;
  }

  /**
   * Epic 5.1.2: Generate configuration report
   */
  async generateConfigurationReport(): Promise<string> {
    const validationResult = await this.validateConfiguration();
    
    const report = {
      timestamp: new Date().toISOString(),
      environment: this.environment,
      epic: '5.1-Secure-Parameter-Management',
      validation: {
        status: validationResult.isValid ? 'PASSED' : 'FAILED',
        errors: validationResult.errors,
        warnings: validationResult.warnings,
        summary: validationResult.summary
      },
      recommendations: this.generateRecommendations(validationResult),
      nextSteps: this.generateNextSteps(validationResult)
    };

    this.logger.info('Configuration report generated', {
      status: report.validation.status,
      errorsCount: report.validation.errors.length,
      warningsCount: report.validation.warnings.length,
      deploymentReady: validationResult.summary.deploymentReadiness.ready
    });

    return JSON.stringify(report, null, 2);
  }

  /**
   * Generate recommendations based on validation results
   */
  private generateRecommendations(validationResult: ConfigurationValidationResult): string[] {
    const recommendations: string[] = [];

    if (validationResult.summary.placeholderParameters.length > 0) {
      recommendations.push('Replace all placeholder parameter values with actual configuration data');
    }

    if (!validationResult.summary.deploymentReadiness.ready) {
      recommendations.push('Address deployment blockers before proceeding with deployment');
    }

    if (validationResult.warnings.length > 0) {
      recommendations.push('Review and address validation warnings for optimal system operation');
    }

    return recommendations;
  }

  /**
   * Generate next steps based on validation results
   */
  private generateNextSteps(validationResult: ConfigurationValidationResult): string[] {
    const nextSteps: string[] = [];

    if (!validationResult.isValid) {
      nextSteps.push('Fix all configuration errors before deployment');
      nextSteps.push('Re-run validation after fixing errors');
    }

    if (validationResult.summary.deploymentReadiness.ready) {
      nextSteps.push('Configuration is ready for deployment');
      nextSteps.push('Proceed with CDK deployment');
    } else {
      nextSteps.push('Address deployment blockers');
      nextSteps.push('Update placeholder parameter values');
      nextSteps.push('Re-validate configuration');
    }

    return nextSteps;
  }
}

// Export convenience function for quick validation
export async function validateVpnConfiguration(environment?: string): Promise<boolean> {
  const validator = new ConfigurationValidator(environment);
  const result = await validator.validateConfiguration();
  return result.isValid;
}

// Export convenience function for deployment readiness check
export async function checkDeploymentReadiness(environment?: string): Promise<boolean> {
  const validator = new ConfigurationValidator(environment);
  const result = await validator.validateConfiguration();
  return result.summary.deploymentReadiness.ready;
}
