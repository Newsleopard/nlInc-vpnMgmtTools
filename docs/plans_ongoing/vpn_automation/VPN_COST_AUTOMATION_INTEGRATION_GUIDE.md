# VPN Cost-Saving Automation – Integration Guide  
*(How the serverless automation meshes with the existing bash tool-chain)*

## 1  Overview

The cost-saving automation is an **add-on** to the original dual-environment VPN management suite (bash scripts + libraries).  
Nothing in the legacy workflow is removed; the Lambda stack simply takes over the repetitive “open / close / monitor” operations.

```
┌──────────────┐  slash cmd   ┌──────────────┐
│   Slack UI   │─────────────▶│ slack-handler│
└──────────────┘              └──────┬───────┘
                                     │invoke
                                     ▼
                             ┌────────────────┐
                             │  vpn-control   │  ← existing AWS APIs wrapped
                             └──────┬─────────┘
      idle scan (5 min)             │update state + metrics
          CloudWatch                ▼
                             ┌────────────────┐
                             │  ParameterStore│
                             └────────────────┘
```

The bash tool-chain keeps **administrative** control—certificate management, endpoint creation, multi-VPC routing—while automation handles **runtime costs**.

## 2  Responsibilities Split

| Area | Bash Tools (`admin-tools/`) | Lambda Automation (`lambda/*`) |
|------|----------------------------|--------------------------------|
| Endpoint creation / deletion | `aws_vpn_admin.sh` | — |
| Cert / CSR workflow | `cert_management.sh`, `team_member_setup.sh` | — |
| Open / close on demand | `aws_vpn_admin.sh` _or_ Slack `/vpn` | `vpn-control` |
| Idle shutdown | — | `vpn-monitor` |
| Cost metrics | manual CloudWatch queries | custom metric `IdleSubnetDisassociations` |
| Dual-env state | `configs/{env}` files | SSM Parameter `/vpn/{env}/state` |
| Notifications | shell echo / logs | Slack webhook |

## 3  Environment Mapping

| Bash Variable | Parameter Store Key | Used By |
|---------------|--------------------|---------|
| `VPN_ENDPOINT_ID` in `configs/{env}.env` | `/vpn/{env}/endpoint_id` *(optional mirror)* | Lambda (read) |
| `LAST_SWITCHED_TIME` (bash current env) | `/vpn/{env}/state.lastActivity` | `vpn-monitor` |

The Lambda layer `stateStore.ts` hides the difference. When you run `admin-tools/aws_vpn_admin.sh delete …`, it also purges the Parameter Store keys to keep both worlds consistent.

## 4  Migrating an Existing Deployment

1. **Tag** existing Parameter Store keys  
   ```
   aws ssm put-parameter \
     --name /vpn/staging/state --type String \
     --value '{"associated":true,"lastActivity":"2025-06-13T00:00:00Z"}'
   ```
2. **Deploy** CDK stack (`cdklib/`) – it will *not* recreate the endpoint if `VPN_ENDPOINT_ID` already exists.
3. **Grant** the Lambda role permission to the existing endpoint:  
   `ec2:AssociateClientVpnTargetNetwork`, `ec2:DisassociateClientVpnTargetNetwork`.
4. **Verify** by running:  
   `curl -XPOST https://…/prod/slack --data "text=check staging"`

## 5  CI/CD Notes

```
name: Deploy VPN Cost Automation
on:
  push:
    paths: [cdklib/**, lambda/**]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: {node-version: 20}
      - run: npm ci
        working-directory: cdklib
      - run: npx cdk synth
        working-directory: cdklib
      - run: npx cdk deploy --require-approval never
        working-directory: cdklib
```

Set environment variables:
- `CDK_DEFAULT_ACCOUNT`, `CDK_DEFAULT_REGION`
- Slack webhook secrets in AWS SSM beforehand.

## 6  Common Pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| Slash command replies “timeout” | API Gateway timeout <3 s | Increase to 10 s |
| Monitor never closes VPN | `lastActivity` never updates | Ensure `vpn-control` writes after every “open/close” |
| Bash tool shows associated but Lambda state says false | Out-of-band subnet association | Run `vpn-control check` to resync |

## 7  References

- Implementation details: `VPN_COST_AUTOMATION_IMPLEMENTATION.md`
- Deployment guide: `VPN_COST_AUTOMATION_DEPLOYMENT.md`
- Slack setup: `VPN_COST_AUTOMATION_SLACK_SETUP.md`

_Last updated: 2025-06-13_
