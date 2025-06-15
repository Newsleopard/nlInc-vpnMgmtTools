# VPN Cost-Saving Automation – Architecture

_Last updated: 2025-06-13_

## 1  Component Map

```mermaid
flowchart TD
    Slack[/Slack Workspace/]
    subgraph AWS
        APIGW[(API Gateway)]
        LH[slack-handler λ]
        VC[vpn-control λ]
        VM[vpn-monitor λ]
        SSM[(SSM Parameter<br/>/vpn/{env}/state)]
        EC2[(AWS EC2<br/>Client-VPN APIs)]
        CW>CloudWatch<br/>Metrics+Logs]
    end
    Slack -- slash cmd --> APIGW
    APIGW --> LH
    LH --> VC
    VM --> VC
    VC -- read/write --> SSM
    VC -- call --> EC2
    VM -- putMetric --> CW
    VC -- putMetric --> CW
    LH -- postMessage --> Slack
```

## 2  Data Flow Scenarios

### 2.1  `/vpn open staging`

| Step | Actor | Action |
|------|-------|--------|
| 1 | Slack command | `/vpn open staging` |
| 2 | `slack-handler` | Verify signature, JSON-parse text |
| 3 | `vpn-control` | `associateSubnets(env)` &rarr; EC2 `AssociateClientVpnTargetNetwork` |
| 4 | `vpn-control` | `stateStore.write` `{associated:true,lastActivity:now}` |
| 5 | `vpn-control` | Metric `VpnManualOp=1` |
| 6 | `slack-handler` | Post success message back |

### 2.2  Idle Auto-Close

| Min| Actor | Action |
|----|-------|--------|
| 0  | `vpn-monitor` | for **each env** fetch status |
|+5 |        | if `activeConnections==0` & `idle>60 min` then `disassociateSubnets()` |
|    |        | Update state, emit Slack alert, metric `IdleSubnetDisassociations` |

## 3  Networks

| Element | Notes |
|---------|-------|
| VPN Endpoint | *Single* endpoint with **two** associated subnet groups (staging / production) or two endpoints – depends on legacy setup. |
| Lambda → EC2 | Uses **private** NAT if deployed inside VPC; otherwise public endpoint. |
| Slack → API GW | HTTPS, signed requests. |

## 4  IAM Roles

| Role | Attached Policies |
|------|-------------------|
| `SlackHandlerRole` | `ssm:GetParameter`, minimal CloudWatch logs |
| `VpnControlRole` | `ec2:*ClientVpn*`, `ssm:*Parameter*`, `cloudwatch:PutMetricData` |
| `VpnMonitorRole` | same as `VpnControlRole` |

_Principle of least privilege_: SSM keys are prefixed `/vpn/`, Lambda policy scopes to `arn:aws:ssm:*:*:parameter/vpn/*`.

## 5  Parameter Store Schema

```
/vpn/
  ├─ staging/
  │   ├─ state            {"associated":true,"lastActivity":"2025-06-13T15:22:10Z"}
  │   └─ endpoint_id      cvpn-endpoint-xxxxxxxx
  └─ production/
      ├─ state            {...}
      └─ endpoint_id      cvpn-endpoint-yyyyyyyy
/vpn/slack/
  ├─ signing_secret
  └─ webhook
```

## 6  Metrics

| Namespace | Metric | Unit | Source |
|-----------|--------|------|--------|
| `VpnAutomation` | `IdleSubnetDisassociations` | Count | `vpn-monitor` |
| `VpnAutomation` | `ManualSubnetAssociations` | Count | `vpn-control` |
| `AWS/EC2VPN` | `ActiveConnections` | **Standard** | EC2 service |

Dashboards combine `ActiveConnections` and custom metrics to visualise savings.

## 7  Logging

| Stream | Produced by | Retention |
|--------|-------------|-----------|
| `/aws/lambda/slack-handler` | Slack entry | 7 days |
| `/aws/lambda/vpn-control` | Manual ops | 30 days |
| `/aws/lambda/vpn-monitor` | Scheduler | 30 days |

## 8  Extensibility

*Add new commands* by extending `lambda/slack-handler/router.ts`.  
*Change idle threshold* via env var `IDLE_MINUTES` in `vpn-monitor` (CDK parameter).  
*Multi-region*: deploy stack per region; Slack command can route by argument.

---
