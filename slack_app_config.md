# Slack App Configuration for VPN Management

## Issue: dispatch_unknown_error

The "dispatch_unknown_error" occurs when Slack cannot reach your endpoint or receives an unexpected response.

## Required Slack App Configuration

### 1. Slash Command URL Configuration

In your Slack App settings (https://api.slack.com/apps/[YOUR_APP_ID]/slash-commands):

**For the `/vpn` command, set the Request URL to:**
```
https://ouyi2hof24.execute-api.us-east-1.amazonaws.com/prod/slack
```

### 2. Verify Slack App Settings

1. Go to your Slack App management page
2. Navigate to "Slash Commands"
3. Find the `/vpn` command
4. Ensure the Request URL matches exactly (including /prod/slack at the end)
5. Save changes

### 3. Current API Gateway Endpoints

- **Staging Slack Endpoint**: `https://ouyi2hof24.execute-api.us-east-1.amazonaws.com/prod/slack`
- **Production Slack Endpoint**: `https://fuycmaqdc1.execute-api.us-east-1.amazonaws.com/prod/slack`

### 4. Troubleshooting Steps

1. **Check Slack App URL**: The most common cause is an incorrect URL in Slack app settings
2. **Verify HTTPS**: Slack requires HTTPS endpoints
3. **Check Path**: Ensure the path ends with `/slack` not just the base API URL
4. **SSL Certificate**: API Gateway provides valid SSL certificates automatically

### 5. Test the Configuration

After updating the Slack app URL:
1. Wait 1-2 minutes for Slack to update
2. Try the command again: `/vpn check stage`
3. If it still fails, check the URL configuration again

## Important Notes

- The endpoint URL must be HTTPS
- The path must include `/prod/slack` at the end
- Do not include any authentication headers in Slack app config
- Slack will send its own signature for verification