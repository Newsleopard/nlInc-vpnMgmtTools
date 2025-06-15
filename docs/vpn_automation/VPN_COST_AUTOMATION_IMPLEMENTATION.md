# VPN Cost-Saving Automation – **Implementation Guide**

*(Formerly `IMPLEMENTATION.md`; renamed with feature prefix.)*

## 1. Scope

This document explains **HOW** the cost-saving automation and Slack integration are implemented on top of the existing **Client-VPN dual-environment tool-chain**.  
It is aimed at engineers who will maintain or extend the solution.

```
Project root
├── docs/vpn_automation
│   ├── VPN_COST_AUTOMATION_IMPLEMENTATION.md   ← (this file)
│   ├── VPN_COST_AUTOMATION_DEPLOYMENT.md
│   └── VPN_COST_AUTOMATION_SLACK_SETUP.md
├── cdklib/                      ← CDK stacks (TS)
├── lambda/                      ← All Lambda source (TS)
│   ├── shared/                  ← Re-usable library layer
│   ├── slack-handler/           ← API Gateway entry
│   ├── vpn-control/             ← Core VPN ops
│   └── vpn-monitor/             ← Scheduler driven
└── scripts/                     ← Helper bash scripts
```

---

## 2. High-Level Architecture

```text
Slack Slash Cmd  ─▶ API GW ─▶  slack-handler λ
                                   │ calls
                                   ▼
                            vpn-control λ  ──▶ EC2 Client-VPN APIs
                                   ▲
                 CloudWatch Events │ every 5-min
                                   ▼
                       vpn-monitor λ  ──▶ SSM Parameter Store (state)
                                         └─▶ auto-disassociate subnets if idle
```

| Lambda        | Trigger / Timeout | Purpose                                                                                                   | IAM Requirements                          |
| ------------- | ----------------- | --------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| slack-handler | API Gateway (3 s) | Verify Slack signature & route `/vpn *` commands                                                          | `ssm:GetParameter` read-only              |
| vpn-control   | Direct invoke     | *open* / *close* / *check* = associate / **disassociate** / status query                                  | `ec2:*ClientVpn*`, `ssm:*Parameter*`      |
| vpn-monitor   | CloudWatch 5 min  | Detect idle > 60 min → **automatically disassociate all subnets** (close VPN) & send Slack notification   | same as vpn-control + `cloudwatch:Put*`   |

A **shared Lambda layer** (`lambda/shared/`) hosts common utilities:
- `vpnManager.ts`  encapsulates EC2 Client-VPN calls
- `stateStore.ts`  thin wrapper around AWS Systems Manager Parameter Store
- `slack.ts`       helpers for verifying signatures and posting messages

---

## 3. Parameter Store Schema

_Key names unchanged; still under `/vpn/{env}/…`._

| Key                                  | Type | Example Value                                   |
| ------------------------------------ | ---- | ----------------------------------------------- |
| `/vpn/staging/state`                 | String (JSON) | `{"associated":true,"lastActivity":"2025-06-13T14:03:22Z"}` |
| `/vpn/production/state`              | String (JSON) | — same —                                        |
| `/vpn/slack/webhook` _(encrypted)_   | SecureString   | Slack Incoming Webhook URL                      |

Reads are free (standard parameters).  
Writes use `PutParameter` with `overwrite=true`.

---

## 4. Lambda Package Layout (TypeScript)

```text
lambda/
├── shared/
│   ├── vpnManager.ts      ← EC2 logic (associate / disassociate / stats)
│   ├── stateStore.ts      ← ParameterStore wrapper
│   ├── slack.ts           ← verify signature, post message
│   └── types.ts
├── slack-handler/index.ts
├── vpn-control/index.ts
└── vpn-monitor/index.ts
```

### 4.1 `vpnManager.ts`
```ts
export async function associateSubnets(env: EnvName): Promise<void> { /* … */ }
export async function disassociateSubnets(env: EnvName): Promise<void> { /* … */ }
export async function fetchStatus(env: EnvName): Promise<VpnStatus> { /* … */ }
```

### 4.2 `vpn-monitor/index.ts` (idle logic)

```ts
const IDLE_MINUTES = Number(process.env.IDLE_MINUTES ?? 60);

export const handler = async (): Promise<void> => {
  for (const env of ['staging', 'production'] as const) {
    const status = await vpnManager.fetchStatus(env);
    if (status.activeConnections === 0 &&
        Date.now() - status.lastActivity > IDLE_MINUTES * 60_000) {
      await vpnManager.disassociateSubnets(env);      // <─ key change
      await stateStore.write(env, { associated: false, lastActivity: status.lastActivity });
      await slack.notify(`#vpn-${env}`, `⚠️ VPN ${env} idle >${IDLE_MINUTES} min. Subnets disassociated.`);
    }
  }
};
```

---

## 5. CDK Stacks (`cdklib/`)

_No change to stack composition.  Update environment variable `IDLE_MINUTES` defaults to 60 in vpn-monitor function._

---

## 6. IAM Roles

Unchanged; auto-disassociate still uses `ec2:DisassociateClientVpnTargetNetwork`.

---

## 7. Error Handling & Observability
- Custom metric `IdleSubnetDisassociations` increments on each automated close.

---

## 8. Testing
Add test case: simulate idle state → expect `disassociateSubnets` called and Slack notification sent.

### 8.1 Unit Tests (Jest)

```bash
cd lambda
npm test          # runs jest --coverage
```

* `vpnManager.test.ts` – mocks EC2 SDK to verify associate/disassociate logic  
* `slack-handler.test.ts` – verifies signature validation and router dispatch  
* `vpn-monitor.test.ts` – fuzzes idle thresholds with fake Date.now()

### 8.2 Integration Tests

| Scenario | Tool | Assertion |
|----------|------|-----------|
| Open VPN via Slack stub | `curl` to API Gateway with signed body | `state.associated == true` |
| Idle auto-close | step-function test harness | CloudWatch metric increment |

### 8.3 End-to-End Smoke

```bash
scripts/e2e/smoke.sh staging   # open → wait 2m → check
```

Outputs human-readable status and exits non-zero on failure.

---

## 9. Configuration & Environment Variables

| Variable | Default | Used By | Description |
|----------|---------|---------|-------------|
| `IDLE_MINUTES` | `60` | vpn-monitor | Idle threshold before auto close |
| `SIGNING_SECRET_PARAM` | `/vpn/slack/signing_secret` | slack-handler | SSM path to HMAC secret |
| `WEBHOOK_PARAM` | `/vpn/slack/webhook` | shared/slack.ts | SSM path to Slack incoming webhook |
| `VPN_STATE_PREFIX` | `/vpn/` | shared/stateStore.ts | Prefix for per-env keys |

All variables are set in `cdklib/stack.ts`.

---

## 10. Local Development Workflow

```bash
npm i -g aws-cdk esbuild
cd lambda
npm ci
npm run watch     # esbuild --watch → dist/*
sam local invoke vpn-control -e events/open.json
```

* **esbuild** bundles TypeScript instantly  
* **sam local** plus `aws-vault` profile for live testing  
* Use `scripts/hot-reload.sh` to sync changes to a dev stage.

---

## 11. Monitoring & Observability

```ts
metrics.addMetric('IdleSubnetDisassociations', {
  unit: MetricUnit.Count,
  value: 1,
});
```

A CloudWatch dashboard JSON lives in `cdklib/monitoring/dashboard.json` and includes:
- ActiveConnections (per env)
- IdleSubnetDisassociations
- Lambda p95 duration

Enable X-Ray in CDK: `lambdaFn.addEnvironment('AWS_XRAY_SDK_ENABLED','true')`.

---

## 12. Extension Points

1. **Add new Slack command**:  
   - Edit `lambda/slack-handler/router.ts` switch-case  
   - Implement action in `lambda/vpn-control`  
2. **Custom metrics**: push via `cloudwatch:PutMetricData`.  
3. **Additional environments**: add env name to `EnvName` union and Parameter Store.

---

## 13. Troubleshooting

| Symptom | Possible Cause | Fix |
|---------|----------------|-----|
| 403 from API GW | Bad Slack signature | Check signing secret in SSM |
| Idle close never triggers | `lastActivity` stale | Ensure `vpn-control` writes after every open/close |
| `Client.VpnEndpointId.NotFound` | Endpoint recreated manually | Update `/vpn/{env}/endpoint_id` or redeploy CDK |

---

---

_Last updated: 2025-06-13_
