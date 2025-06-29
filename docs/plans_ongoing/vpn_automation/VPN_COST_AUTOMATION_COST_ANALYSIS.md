# VPN Cost-Saving Automation – Cost Analysis & Optimisation

_Last updated: 2025-06-13_

## 1  Cost Components for AWS Client-VPN

| Item | AWS Price (us-east-1) | Charged When |
|------|----------------------|--------------|
| **Endpoint association** | **USD 0.10 / hour** | For every hour _any_ subnet is associated with the endpoint (24×7 if always-on). |
| **Active connection** | **USD 0.05 / hour / connection** | Only while a client session is connected. |
| **Elastic IP** (if public) | USD 0.005 / hour | While ENI has an attached EIP. |
| **CloudWatch Logs** | USD 0.50 / GB ingest + retention | If connection logging enabled. |
| **Lambda + CW metrics** | negligible | <USD 1 / month for typical usage. |

## 2  Always-On vs Automation

| Scenario | Monthly Endpoint Hours | Monthly Endpoint $ | Notes |
|----------|-----------------------|--------------------|-------|
| Two env, always associated | 24 h × 30 d × 2 = **1 440 h** | **USD 144** | Baseline (no automation) |
| Two env, auto-close (idle 18 h/day) | 6 h × 30 d × 2 = **360 h** | **USD 36** | 75 % saving |
| One env, always-on | 720 h | USD 72 | Legacy single env |
| One env, auto-close (8 h/day) | 240 h | USD 24 | 67 % saving |

Connection cost depends on usage; automation _does not_ change it but allows **shorter session windows**.

## 3  ROI Calculator

```bash
#!/usr/bin/env bash
# quick_cost.sh <users> <hours_per_day> <work_days>
users=${1:-5}
hours=${2:-5}
days=${3:-20}

conn_cost=$(echo "$users*$hours*$days*0.05" | bc)  # connection fee
base_endpoint=144
auto_endpoint=36
savings=$(echo "$base_endpoint - $auto_endpoint" | bc)

echo "Active connection cost : \$${conn_cost}"
echo "Endpoint cost (legacy) : \$${base_endpoint}"
echo "Endpoint cost (auto)   : \$${auto_endpoint}"
echo "Monthly saving         : \$${savings}"
```

> Break-even: Lambda stack < **USD 5** / month → payback in first week.

## 4  Monitoring Cost Metrics

1. **Custom metric** `IdleSubnetDisassociations`
   - spike = automated close event
2. **CloudWatch Alarm**
   ```bash
   aws cloudwatch put-metric-alarm \
     --alarm-name "VPN Endpoint Running > 12h" \
     --metric-name IdleSubnetDisassociations \
     --namespace VpnAutomation \
     --statistic Sum \
     --period 43200 \
     --evaluation-periods 1 \
     --comparison-operator LessThanThreshold \
     --threshold 1 \
     --alarm-actions <SNS_ARN>
   ```
   *If no idle close in 12 h the alarm fires.*

3. **Cost Explorer Tag**  
   Tag the endpoint `Project=ClientVPN` → use CE daily report.

## 5  Optimisation Checklist

- [x] **Enable split-tunnel** → only AWS CIDRs route via VPN.
- [x] **Lower idle threshold** (`IDLE_MINUTES`) if usage is bursty.
- [x] **Schedule forced close** (e.g. 02:00) using EventBridge rule.
- [ ] **Consolidate endpoints** – a single endpoint can host both staging & prod with different security groups.
- [ ] **Log retention** – set 30-day retention on `/aws/clientvpn/*`.

## 6  Forecasting Future Demand

Use `ActiveConnections` + business growth ratio.  
For each extra 5 users @ 5 h/day → +USD 25 / month connection fee.  
Endpoint cost stays constant with automation.

---
