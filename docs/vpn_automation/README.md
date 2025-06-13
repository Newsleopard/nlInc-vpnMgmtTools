# VPN Cost-Saving Automation – Documentation Hub  

_Last updated: 2025-06-13_

Welcome! This directory contains all documents for the **AWS Client-VPN cost-saving automation** feature that rides on top of the dual-environment VPN tool-chain.  
Use the table below as a jump-off point. Each entry is a clickable link with an expanded explanation of what you will find inside.

---

## 📚 Document Index

| Document | What You’ll Learn |
|----------|-------------------|
| **[Implementation Guide](VPN_COST_AUTOMATION_IMPLEMENTATION.md)** | Deep-dive into the TypeScript Lambda code, shared layer utilities, Parameter Store schema and high-level architecture overview. Ideal for **developers** extending the solution. |
| **[Deployment Guide](VPN_COST_AUTOMATION_DEPLOYMENT.md)** | Bootstrap, CDK deploy, update, rollback and uninstall procedures. Includes troubleshooting of common deployment issues. Targeted at **DevOps / infra engineers**. |
| **[Slack Setup Guide](VPN_COST_AUTOMATION_SLACK_SETUP.md)** | Step-by-step creation of the Slack App, slash-command, scopes, signing secret storage and end-to-end test. For **workspace admins**. |
| **[Integration Guide](VPN_COST_AUTOMATION_INTEGRATION_GUIDE.md)** | How the serverless stack integrates with legacy bash scripts (`admin-tools/`), mapping of env files to SSM keys, migration & CI/CD patterns. Required reading when you already run the old tool-chain. |
| **[Architecture](VPN_COST_AUTOMATION_ARCHITECTURE.md)** | Detailed component diagrams (Mermaid), data-flow & control-flow, IAM roles, network paths, metric streams. Useful for **design reviews & audits**. |
| **[Cost Analysis](VPN_COST_AUTOMATION_COST_ANALYSIS.md)** | AWS pricing breakdown, ROI calculator script, optimisation checklist and monitoring tips. Helps **finance & optimisation teams** justify savings. |
| **[Operations Runbook](VPN_COST_AUTOMATION_OPERATIONS_RUNBOOK.md)** | Daily/weekly checks, incident SOP, maintenance tasks, DR & backup. The go-to manual for **on-call operators**. |
| **[Security & Compliance](VPN_COST_AUTOMATION_SECURITY.md)** | Threat model, secrets management, IAM snippets, certificate lifecycle, change-control checklist. Reference for **security reviewers**. |
| **[API Reference](VPN_COST_AUTOMATION_API_REFERENCE.md)** | Complete spec of slash-command grammar, API Gateway endpoint, Lambda payloads, state schema and custom metrics. Needed when **integrating external systems**. |

---

## 🚀 Quick Start

| Role | Start Here | Then Read |
|------|-----------|-----------|
| Developer | Implementation Guide | Architecture → API Reference |
| DevOps / Infra | Deployment Guide | Operations Runbook → Integration Guide |
| Security | Security & Compliance | Architecture → Cost Analysis |
| Finance | Cost Analysis | Deployment Guide (cost impact) |
| Slack Admin | Slack Setup Guide | Operations Runbook |

---

### Prerequisites

* AWS CDK v2, Node 20, AWS CLI v2  
* Existing dual-environment VPN constructed with `aws_vpn_admin.sh` **or** fresh infra access  
* Slack workspace with permission to install custom apps

---

### How the Docs Fit Together

```
Integration ─┐
             ├─▶ Architecture ─▶ Implementation
Deployment ──┤                       ▲
             ├─▶ Operations Runbook──┘
             └─▶ Security / Cost / API
```

Start with **Deployment** if you are installing from scratch, or **Integration** if retro-fitting an existing setup.

---

> Need something else? Check the root-level `vpn_connection_manual.md` for the broader dual-environment VPN suite.  
> Found an issue? Open a pull request or file it in **#vpn-docs**.
