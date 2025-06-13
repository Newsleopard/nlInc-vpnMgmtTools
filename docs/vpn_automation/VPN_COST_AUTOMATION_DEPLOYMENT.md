# VPN Cost-Saving Automation – **Deployment & Operations Guide**

*(Formerly `DEPLOYMENT.md`; renamed with feature prefix.)*

This guide walks through **bootstrap, deploy, monitor, update and uninstall** for the VPN cost-saving automation stacks described in `VPN_COST_AUTOMATION_IMPLEMENTATION.md`.

(The remainder of the content is identical to the previous version, with section 7 amended to clarify automatic subnet disassociation on idle.)

---

## 7. Operations

### 7.1 Routine Tasks

| Task                             | How                                                                           |
| -------------------------------- | ----------------------------------------------------------------------------- |
| **Open VPN**                     | `/vpn open staging` (or prod) – associates original subnets                   |
| **Close VPN (manual)**           | `/vpn close staging` – disassociates subnets                                  |
| **Check status**                 | `/vpn check staging` – shows current association + connections                |
| **Idle auto-close**              | _No action_ – **vpn-monitor** Lambda disassociates after 60 min idle          |
| **Forced disconnect**            | Invoke **vpn-control** `{"action":"close","env":"staging"}`                   |
| **Change idle threshold**        | Update `IDLE_MINUTES` env var on vpn-monitor, then `Publish new version`      |
| **View idle events**             | CloudWatch Logs → search `Subnets disassociated (idle)`                       |
| **Metrics**                      | CloudWatch → Custom → `VpnAutomation/IdleSubnetDisassociations`               |

### 7.2 What Happens on Idle?

1. **vpn-monitor** runs every 5 minutes.  
2. If no active Client-VPN connections for `IDLE_MINUTES` (default 60) **AND** subnets are still associated, it:  
   - Calls `ec2:DisassociateClientVpnTargetNetwork` for each subnet  
   - Writes `{"associated":false}` to `/vpn/{env}/state`  
   - Posts a Slack message (`⚠️ VPN staging idle >60 min. Subnets disassociated.`)

This stops the hourly **association charge** while preserving the endpoint.

*(All other sections remain as in the original deployment guide.)*

_Last updated: 2025-06-13_
