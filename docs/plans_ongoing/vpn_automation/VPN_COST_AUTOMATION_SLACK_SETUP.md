# VPN Cost-Saving Automation – **Slack Bot Configuration Guide**

*(Formerly `SLACK_SETUP.md`; renamed with feature prefix.)*

This guide walks through creating and configuring the Slack App that powers the `/vpn` slash-command used by the cost-saving automation.

---

## 1. Create the Slack App

1. Navigate to <https://api.slack.com/apps> → **Create New App** → **From scratch**  
2. App name: **VPN Automation Bot**  
3. Select your workspace → **Create App**

---

## 2. App Basics

| Setting           | Suggested Value                                  |
| ----------------- | ------------------------------------------------ |
| Display Name      | **VPN Bot**                                      |
| Default Icon      | 🔒 (or custom)                                   |
| Short Description | “Manage AWS Client-VPN from Slack”               |

---

## 3. OAuth & Permissions

### 3.1 Scopes

**OAuth & Permissions → Bot Token Scopes**

Add:

| Scope        | Purpose                      |
| ------------ | ---------------------------- |
| `commands`   | Receive `/vpn` slash command |
| `chat:write` | Post messages to channels    |

Click **Save Changes**.

### 3.2 Install the App

1. **Install to Workspace**  
2. Authorize. Copy the **Bot User OAuth Token** (`xoxb-***`) for later.

---

## 4. Slash Command

**Features → Slash Commands → Create New Command**

| Field        | Value                                                            |
| ------------ | ---------------------------------------------------------------- |
| Command      | `/vpn`                                                           |
| Request URL  | `https://{api-id}.execute-api.{region}.amazonaws.com/prod/slack` (from CDK output) |
| Short Desc   | “Manage AWS VPN”                                                 |
| Usage Hint   | <code>open&#124;close&#124;check &lt;stage&#124;prod&gt;</code>  |

Save.

---

## 5. Signature Verification

Slack signs each request:

- `X-Slack-Signature`
- `X-Slack-Request-Timestamp`

### Retrieve Signing Secret

**Basic Information → App Credentials → Signing Secret**. Copy the value.

### Store Secrets in AWS SSM Parameter Store

```bash
aws ssm put-parameter \
  --name /vpn/slack/signing_secret \
  --type SecureString \
  --value "<SIGNING_SECRET>" \
  --overwrite

aws ssm put-parameter \
  --name /vpn/slack/bot_token \
  --type SecureString \
  --value "xoxb-XXXXXXXXXX" \
  --overwrite
```

The Lambda layer `slack.ts` reads these parameters on cold start.

---

## 6. Invite the Bot

```slack
/invite @VPN Bot
```

Create channels such as `#vpn-staging` and `#vpn-production` if desired.

---

## 7. End-to-End Test

1. In Slack, type:

   ```
   /vpn check staging
   ```

2. Expected:

   - Immediate ephemeral “Processing…” reply.
   - Within 2 seconds, bot posts status JSON.
3. Force idle auto-close test:

   ```
   /vpn open staging
   # wait 65 minutes with no connections
   # vpn-monitor Lambda should disassociate subnets and post a Slack alert
   ```

---

## 8. Troubleshooting

| Symptom                           | Checklist / Fix                                           |
| -------------------------------- | --------------------------------------------------------- |
| Slash command timeout             | API Gateway or slack-handler Lambda timeout too low.      |
| “Invalid signature” error         | Confirm signing secret in SSM matches Slack dashboard.    |
| Bot silent                        | Ensure bot invited to channel; check Lambda CloudWatch logs. |
| Missing slash command parameters  | Verify Usage Hint and command string in Slack settings.   |

---

_Last updated: 2025-06-13_
