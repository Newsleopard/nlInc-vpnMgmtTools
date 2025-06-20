import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';
import { Lambda } from 'aws-sdk';
import * as querystring from 'querystring';

// Import shared utilities from Lambda Layer
import { SlackCommand, VpnCommandRequest, VpnCommandResponse, CrossAccountRequest } from '/opt/types';
import * as slack from '/opt/slack';
import * as stateStore from '/opt/stateStore';

const lambda = new Lambda();
const ENVIRONMENT = process.env.ENVIRONMENT || 'staging';

export const handler = async (
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> => {
  console.log('Slack Handler Lambda invoked', {
    requestId: context.awsRequestId,
    environment: ENVIRONMENT,
    httpMethod: event.httpMethod,
    headers: event.headers
  });

  try {
    // Verify this is a POST request
    if (event.httpMethod !== 'POST') {
      return {
        statusCode: 405,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Method not allowed' })
      };
    }

    // Parse Slack request body (URL-encoded)
    const body = event.body || '';
    const slackData = querystring.parse(body) as any;
    
    // Verify Slack signature for security
    const signature = event.headers['X-Slack-Signature'] || event.headers['x-slack-signature'] || '';
    const timestamp = event.headers['X-Slack-Request-Timestamp'] || event.headers['x-slack-request-timestamp'] || '';
    
    try {
      const signingSecret = await stateStore.readSlackSigningSecret();
      const isValidSignature = slack.verifySlackSignature(body, signature, timestamp, signingSecret);
      
      if (!isValidSignature) {
        console.error('Invalid Slack signature');
        return {
          statusCode: 401,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ error: 'Unauthorized' })
        };
      }
    } catch (signatureError) {
      console.error('Failed to verify Slack signature:', signatureError);
      return {
        statusCode: 500,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Authentication configuration error' })
      };
    }

    // Parse Slack command
    const slackCommand: SlackCommand = {
      token: slackData.token,
      team_id: slackData.team_id,
      team_domain: slackData.team_domain,
      channel_id: slackData.channel_id,
      channel_name: slackData.channel_name,
      user_id: slackData.user_id,
      user_name: slackData.user_name,
      command: slackData.command,
      text: slackData.text || '',
      response_url: slackData.response_url,
      trigger_id: slackData.trigger_id
    };

    console.log('Received Slack command:', {
      command: slackCommand.command,
      text: slackCommand.text,
      user: slackCommand.user_name,
      channel: slackCommand.channel_name
    });

    // Parse VPN command from Slack text
    let vpnCommand: VpnCommandRequest;
    try {
      vpnCommand = slack.parseSlackCommand(slackCommand);
    } catch (parseError) {
      console.error('Failed to parse VPN command:', parseError);
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          response_type: 'ephemeral',
          text: '❌ Invalid command format',
          attachments: [{
            color: 'danger',
            fields: [{
              title: 'Error',
              value: parseError.message,
              short: false
            }, {
              title: 'Usage',
              value: '`/vpn <action> <environment>`\n' +
                     'Actions: `open`, `close`, `check`\n' +
                     'Environments: `staging`, `production`\n\n' +
                     'Examples:\n' +
                     '• `/vpn open staging`\n' +
                     '• `/vpn close production`\n' +
                     '• `/vpn check staging`',
              short: false
            }]
          }]
        })
      };
    }

    console.log('Parsed VPN command:', vpnCommand);

    // Route command based on environment
    let response: VpnCommandResponse;
    
    if (vpnCommand.environment === ENVIRONMENT) {
      // Local command - invoke vpn-control Lambda directly
      console.log(`Processing local command for ${ENVIRONMENT} environment`);
      response = await invokeLocalVpnControl(vpnCommand);
      
    } else {
      // Cross-account command - call production API Gateway via HTTPS
      console.log(`Processing cross-account command for ${vpnCommand.environment} environment`);
      response = await invokeProductionViaAPIGateway(vpnCommand);
    }

    // Format response for Slack
    const slackResponse = slack.formatSlackResponse(response, vpnCommand);
    
    console.log('Sending Slack response:', slackResponse);
    
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(slackResponse)
    };

  } catch (error) {
    console.error('Unexpected error in Slack Handler Lambda:', error);
    
    // Send alert about handler failure
    await slack.sendSlackAlert(
      `Slack Handler Lambda error: ${error.message}`,
      ENVIRONMENT,
      'critical'
    );

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        response_type: 'ephemeral',
        text: '❌ Internal error processing VPN command',
        attachments: [{
          color: 'danger',
          fields: [{
            title: 'Error',
            value: 'An unexpected error occurred. The development team has been notified.',
            short: false
          }]
        }]
      })
    };
  }
};

// Invoke local vpn-control Lambda function
async function invokeLocalVpnControl(command: VpnCommandRequest): Promise<VpnCommandResponse> {
  try {
    console.log('Invoking local vpn-control Lambda');
    
    const result = await lambda.invoke({
      FunctionName: `VpnAutomationStack-${ENVIRONMENT}-VpnControl`, // Function name from CDK
      InvocationType: 'RequestResponse',
      Payload: JSON.stringify({
        httpMethod: 'POST',
        body: JSON.stringify(command),
        headers: { 'Content-Type': 'application/json' }
      })
    }).promise();

    if (!result.Payload) {
      throw new Error('No response from vpn-control Lambda');
    }

    const lambdaResponse = JSON.parse(result.Payload.toString());
    
    if (lambdaResponse.statusCode !== 200) {
      const errorResponse = JSON.parse(lambdaResponse.body);
      throw new Error(errorResponse.error || 'VPN operation failed');
    }

    return JSON.parse(lambdaResponse.body);
    
  } catch (error) {
    console.error('Failed to invoke local vpn-control:', error);
    return {
      success: false,
      error: `Local VPN operation failed: ${error.message}`
    };
  }
}

// Invoke production API Gateway via HTTPS for cross-account calls with retry logic
async function invokeProductionViaAPIGateway(command: VpnCommandRequest): Promise<VpnCommandResponse> {
  const maxRetries = 3;
  const retryDelay = 1000; // 1 second
  
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const productionAPIEndpoint = process.env.PRODUCTION_API_ENDPOINT;
      const apiKey = process.env.PRODUCTION_API_KEY || '';
      
      if (!productionAPIEndpoint) {
        throw new Error('Production API endpoint not configured');
      }

      console.log(`Calling production API Gateway (attempt ${attempt}/${maxRetries}):`, productionAPIEndpoint);
      
      const requestBody: CrossAccountRequest = {
        command: command,
        requestId: command.requestId,
        sourceAccount: 'staging'
      };

      // Add timeout to fetch request
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 30000); // 30 second timeout
      
      try {
        const response = await fetch(productionAPIEndpoint, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': apiKey,
            'User-Agent': 'VPN-Automation-Slack-Handler/1.0'
          },
          body: JSON.stringify(requestBody),
          signal: controller.signal
        });

        clearTimeout(timeoutId);

        if (!response.ok) {
          const errorText = await response.text();
          throw new Error(`Production API error: ${response.status} ${response.statusText} - ${errorText}`);
        }

        const result = await response.json();
        console.log('Production API response:', result);
        
        return result;
        
      } catch (fetchError) {
        clearTimeout(timeoutId);
        if (fetchError.name === 'AbortError') {
          throw new Error('Request timeout - production API did not respond within 30 seconds');
        }
        throw fetchError;
      }
      
    } catch (error) {
      console.error(`Attempt ${attempt} failed:`, error);
      
      // If this is the last attempt or a configuration error, don't retry
      if (attempt === maxRetries || error.message.includes('not configured')) {
        return {
          success: false,
          error: `Cross-account VPN operation failed after ${attempt} attempts: ${error.message}`
        };
      }
      
      // Wait before retrying
      if (attempt < maxRetries) {
        console.log(`Retrying in ${retryDelay}ms...`);
        await new Promise(resolve => setTimeout(resolve, retryDelay));
      }
    }
  }
  
  // This should never be reached, but just in case
  return {
    success: false,
    error: 'Cross-account VPN operation failed: Maximum retries exceeded'
  };
}