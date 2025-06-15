# VPN Cost-Saving Automation – API Reference

_Last updated: 2025-06-13_

---

## 1  Slack Slash-Command Grammar

```
/vpn <action> <environment>
```

| Action | Alias | Effect |
|--------|-------|--------|
| `open` | `up`, `associate` | Associate subnets to VPN for the env |
| `close`| `down`, `disassociate` | Disassociate subnets |
| `check`| `status` | Return JSON status `{associated, activeConnections, lastActivity}` |

Examples:

```
/vpn open staging
/vpn check production
```

The command body is sent as `application/x-www-form-urlencoded` field `text`.

---

## 2  API Gateway Endpoint

```
POST https://{apiId}.execute-api.{region}.amazonaws.com/prod/slack
Headers:
  X-Slack-Signature: v0=…
  X-Slack-Request-Timestamp: 1718300000
Body: token=…&team_id=…&text=open%20staging&…
```

Timeout: 3 s (extendable). Returns HTTP 200 with ephemeral JSON response.

---

## 3  Lambda: slack-handler

```ts
export interface SlackEvent {
  text: string;  // "open staging"
  user_id: string;
  channel_id: string;
}
```

Environment:

| Var | Example | Description |
|-----|---------|-------------|
| `SIGNING_SECRET_PARAM` | `/vpn/slack/signing_secret` | SSM key |
| `WEBHOOK_PARAM` | `/vpn/slack/webhook` | SSM key |
| `VPN_CONTROL_FN` | `vpn-control` | Function name to invoke |

Result:

```
{
  "response_type": "in_channel",
  "text": "VPN staging associated ✅"
}
```

---

## 4  Lambda: vpn-control

### Request Payload

```jsonc
{
  "action": "open" | "close" | "check",
  "env": "staging" | "production"
}
```

### Response

```jsonc
// open / close
{
  "ok": true,
  "message": "Associated 2 subnets"
}
// check
{
  "env": "staging",
  "associated": true,
  "activeConnections": 3,
  "lastActivity": "2025-06-13T14:03:22Z"
}
```

Errors:

| Code | Message |
|------|---------|
| 400  | `Invalid action` |
| 404  | `Unknown environment` |
| 503  | `EC2 API error` |

---

## 5  Lambda: vpn-monitor

Environment:

| Var | Default | Purpose |
|-----|---------|---------|
| `IDLE_MINUTES` | `60` | Threshold to auto-disassociate |
| `ENABLED` | `true` | Set `false` to pause automation |

Scheduler: EventBridge cron `rate(5 minutes)`

---

## 6  State Store Schema

Parameter `/vpn/{env}/state`

```json
{
  "associated": true,
  "lastActivity": "2025-06-13T14:03:22Z"
}
```

---

## 7  Metrics

| Metric | Dimension | Description |
|--------|-----------|-------------|
| `IdleSubnetDisassociations` | `Environment` | Incremented by vpn-monitor on idle close |
| `ManualSubnetAssociations` | `Environment` | Incremented by vpn-control on open |

Namespace: `VpnAutomation`.

---

## 8  CDK Outputs

| Stack | Output | Description |
|-------|--------|-------------|
| `SlackApiStack` | `SlackEndpointUrl` | Paste into Slack slash-command `Request URL` |
| `VpnMonitorStack` | `MonitorFnArn` | For ops reference |

---

## 9  Version Compatibility

| Component | Version |
|-----------|---------|
| Node.js runtime | `nodejs20.x` |
| CDK | `^2.135.0` |
| Slack API | `v2` |

---
