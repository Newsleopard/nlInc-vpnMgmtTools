# VPN Cost-Saving Automation – Security & Compliance Guide

_Last updated: 2025-06-13_

## 1  Threat Model

| Asset | Threat | Counter-measure |
|-------|--------|-----------------|
| Slack command | Forged request | HMAC-SHA256 signature validation (`X-Slack-Signature`) |
| Lambda IAM role | Privilege escalation | Scoped policy to `arn:aws:ssm:*:*:parameter/vpn/*` and `ec2:DisassociateClientVpnTargetNetwork` only |
| Parameter Store secrets | Leakage | `SecureString` + KMS default key, least-priv read from Lambda |
| VPN endpoint | Abuse by idle association | `vpn-monitor` auto-disassociate after `IDLE_MINUTES` |
| Logs | PII in messages | No user payload stored; redact email/user before log |

## 2  Secrets Management

| Secret | Storage | Access |
|--------|---------|--------|
| `signing_secret` | `/vpn/slack/signing_secret` (SecureString) | `slack-handler` read-only |
| `bot_token` | `/vpn/slack/bot_token` (SecureString) | `slack.ts` read-only |
| Slack webhook | `/vpn/slack/webhook` (SecureString) | `vpn-control`, `vpn-monitor` post-only |

Rotate secrets via `aws ssm put-parameter --overwrite`.

## 3  IAM Policy Snippets

### 3.1  Lambda Execution Role

```json
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"VpnOps",
      "Effect":"Allow",
      "Action":[
        "ec2:DescribeClientVpnConnections",
        "ec2:DisassociateClientVpnTargetNetwork",
        "ec2:AssociateClientVpnTargetNetwork"
      ],
      "Resource":"*"
    },
    {
      "Sid":"ParameterRead",
      "Effect":"Allow",
      "Action":[
        "ssm:GetParameter",
        "ssm:PutParameter"
      ],
      "Resource":"arn:aws:ssm:*:*:parameter/vpn/*"
    },
    {
      "Sid":"Metrics",
      "Effect":"Allow",
      "Action":"cloudwatch:PutMetricData",
      "Resource":"*"
    }
  ]
}
```

### 3.2  Slack Verification Lambda

```json
{
  "Action":["ssm:GetParameter"],
  "Resource":"arn:aws:ssm:*:*:parameter/vpn/slack/*",
  "Effect":"Allow"
}
```

_No EC2 privileges._

## 4  Audit Logging

| Source | Log Group | Sensitive? |
|--------|-----------|------------|
| API Gateway access | `/aws/apigw/vpn-automation` | includes IP, command text |
| Lambda stdout | `/aws/lambda/*` | no secrets |
| Slack notifications | Slack channel history | treat as confidential |

Enable **CloudTrail Lake** query on `DisassociateClientVpnTargetNetwork` for compliance.

## 5  Compliance Checklist

- [x] IAM roles use least privilege
- [x] Secrets stored encrypted at rest
- [x] All Internet-facing APIs (API Gateway) require HMAC verification
- [x] Logs have 30-day retention cap
- [x] Lambda runs in dedicated VPC subnets (optional – enable if network isolation required)

## 6  Certificate Lifecycle

| Cert | Validity | Rotation |
|------|----------|----------|
| Server cert | 365 days | `aws_vpn_admin.sh` renew + update endpoint |
| Client CA | 5 years | rotate 12 months before expiry |
| Client/user | 180 days | auto-reissue via CSR workflow |

## 7  Production Change Control

1. Update CloudFormation/CDK change set
2. Security review sign-off
3. Window announcement
4. Deploy with `--require-approval never`
5. Post-deploy verification `/vpn check production`
6. Close change record

---
