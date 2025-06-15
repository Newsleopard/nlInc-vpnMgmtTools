# VPN Cost-Saving Automation – Operations Runbook

_Last updated: 2025-06-13_

> All timestamps in UTC. Use `aws --profile <env> --region <region>` consistently.

---

## 1  Routine Checks

| Frequency | Task | Command / Console |
|-----------|------|-------------------|
| Daily 09:00 | Verify both env endpoints closed outside office | `/vpn check staging` and `/vpn check production` (Slack) |
| Daily 18:30 | Confirm idle shutdown triggered | CloudWatch → metric graph `IdleSubnetDisassociations` |
| Weekly Mon | Rotate Lambda log groups (7d/30d) | none (retention auto) |
| Weekly Fri | Review active connection hours in Cost Explorer | AWS Console → CE group by UsageType |
| Monthly 1st | Patch Lambda runtime versions (`cdklib/` deploy) | `npx cdk deploy` |

---

## 2  Standard Operating Procedures (SOP)

### 2.1  Manual Open / Close

```slack
/vpn open staging        # associate subnets
/vpn close staging       # disassociate
```

If Slack unavailable:

```bash
aws lambda invoke \
  --function-name vpn-control \
  --payload '{"action":"open","env":"staging"}' /tmp/out.json
```

### 2.2  Adjust Idle Threshold

1. CDK:
   ```bash
   npx cdk deploy VpnMonitorStack \
     -c idleMinutes=30
   ```
2. Confirm env var on Lambda console.

### 2.3  Emergency Disable Automation

```bash
aws lambda update-function-configuration \
  --function-name vpn-monitor \
  --environment "Variables={ENABLED=false}"
```

### 2.4  Rotate Slack Signing Secret

1. Generate new secret in Slack ➜ Basics.  
2. Put to SSM:
   ```bash
   aws ssm put-parameter --name /vpn/slack/signing_secret \
     --value '<NEWSECRET>' --type SecureString --overwrite
   ```
3. **No redeploy needed** – `slack.ts` fetches on cold-start.

---

## 3  Incident Response

| Severity | Example Symptom | Immediate Action |
|----------|-----------------|------------------|
| P1 | Prod endpoint stuck associated >12 h | Run `/vpn close production`, check Lambda logs, escalate |
| P2 | Slack automation down, manual open needed | Use Lambda invoke CLI, open via `aws_vpn_admin.sh` |
| P3 | Idle close too aggressive | Increase `IDLE_MINUTES`, redeploy |

### 3.1  Debug Checklist

1. `aws logs tail /aws/lambda/vpn-control --since 15m`
2. Verify SSM `/vpn/{env}/state`
3. `aws ec2 describe-client-vpn-endpoints --endpoint-ids ...`
4. Test IAM role policy simulator if access denied.

---

## 4  Maintenance

| Task | Schedule | Script |
|------|----------|--------|
| CDK dependencies upgrade | Quarterly | `npm update && npx cdk diff` |
| Lambda runtime patch | AWS auto or quarterly | redeploy |
| Cost review | Monthly | CE report, tag filters |

---

## 5  Capacity Planning

- **Endpoint association fee** independent of connections.  
- Default CVPN limit: 250 concurrent. Request limit increase at ~70 % utilisation.

---

## 6  DR & Backup

| Asset | Backup Strategy |
|-------|-----------------|
| Parameter Store keys | Daily AWS Backup plan (parameter type) |
| CDK source | Git repository |
| Slack signing secret | 1Password vault |

Restore steps: deploy CDK, re-import keys, update secrets.

---
