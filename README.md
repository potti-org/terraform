<p align="center">
  <img src="https://img.shields.io/badge/Terraform-v1.0+-623CE4?style=for-the-badge&logo=terraform" alt="Terraform">
  <img src="https://img.shields.io/badge/OVHcloud-Public_Cloud-123F6D?style=for-the-badge&logo=ovh" alt="OVHcloud">
  <img src="https://img.shields.io/badge/Security-Zero_Trust-00A86B?style=for-the-badge&logo=shield" alt="Security">
</p>

# 🏗️ Potti Infrastructure

> Enterprise-grade Terraform configuration for the Potti application infrastructure hosted on OVHcloud Public Cloud with defense-in-depth security architecture.
>
> Agents: start with `AGENTS.md`. The CI runner fleet on Azure is a separate stack in `azure-runners/`.

---

## 📋 Table of Contents

- [Architecture Overview](#-architecture-overview)
- [Security Architecture](#-security-architecture)
- [Network Topology](#-network-topology)
- [Components](#-components)
- [Data Flow](#-data-flow)
- [High Availability](#-high-availability)
- [Terraform Resources](#-terraform-resources)
- [Quick Start](#-quick-start)
- [Compliance](#-compliance)

---

## 🏛️ Architecture Overview

### High-Level System Architecture

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                         🌐 INTERNET                                                   ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝
                    │                           │                           │
                    │                           │                           │
         ┌──────────▼──────────┐     ┌──────────▼──────────┐     ┌──────────▼──────────┐
         │    ☁️ CLOUDFLARE     │     │   👤 DEVELOPERS      │     │   🔧 LARAVEL FORGE   │
         │        DNS          │     │   (French IPs)       │     │   (Whitelisted)     │
         │   potti.co → LB     │     │                      │     │   159.203.150.x     │
         └──────────┬──────────┘     └──────────┬──────────┘     └──────────┬──────────┘
                    │                           │                           │
                    │ :443 HTTPS                │ :22 SSH                   │ :22 SSH
                    │                           │                           │
╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                    🔒 OVHcloud PUBLIC CLOUD                                           ║
║                                       EU-WEST-PAR Region                                              ║
╠══════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                       ║
║    ┌─────────────────────────────────────────────────────────────────────────────────────────────┐   ║
║    │                           ⚖️ LOAD BALANCER (Floating IP)                                     │   ║
║    │                                                                                              │   ║
║    │    HTTP :80 ─────────────────────────────────────────────────────────▶ HTTPS :443 Redirect  │   ║
║    │    HTTPS :443 ──────────────────────────────────────────────────────▶ Round Robin Pool      │   ║
║    │    TCP :49984 (IoT) ────────────────────────────────────────────────▶ Round Robin Pool      │   ║
║    └─────────────────────────────────────────────────────────────────────────────────────────────┘   ║
║                                              │                                                        ║
║    ╔════════════════════════════════════════════════════════════════════════════════════════════╗    ║
║    ║                         🔐 PRIVATE NETWORK (vRack) - 10.101.0.0/16                          ║    ║
║    ║                                        VLAN 101                                             ║    ║
║    ╠════════════════════════════════════════════════════════════════════════════════════════════╣    ║
║    ║                                                                                             ║    ║
║    ║   ┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐                 ║    ║
║    ║   │  🛡️ BASTION       │      │  💻 APP SERVER    │      │  💻 APP SERVER    │                 ║    ║
║    ║   │  (The Bastion)   │      │     PAR-A-1      │      │     PAR-B-1      │                 ║    ║
║    ║   │                  │      │                  │      │                  │                 ║    ║
║    ║   │  10.101.3.50     │─SSH─▶│  10.101.1.x      │      │  10.101.2.x      │                 ║    ║
║    ║   │  + Ext-Net IP    │      │  + Floating IP   │      │  + Floating IP   │                 ║    ║
║    ║   │                  │      │                  │      │                  │                 ║    ║
║    ║   │  🇫🇷 French IPs   │      │  Ubuntu 24.04   │      │  Ubuntu 24.04   │                 ║    ║
║    ║   │  Only Access     │      │  Laravel + Nginx │      │  Laravel + Nginx │                 ║    ║
║    ║   └────────┬─────────┘      └────────┬─────────┘      └────────┬─────────┘                 ║    ║
║    ║            │                         │                         │                           ║    ║
║    ║            │                         └────────────┬────────────┘                           ║    ║
║    ║            │                                      │                                        ║    ║
║    ║   ┌────────▼─────────┐                           │                                        ║    ║
║    ║   │  🔄 CI SERVER     │                           │                                        ║    ║
║    ║   │                  │                           │                                        ║    ║
║    ║   │  10.101.3.60     │                           │                                        ║    ║
║    ║   │  Private Only    │                           │                                        ║    ║
║    ║   └──────────────────┘                           │                                        ║    ║
║    ║                                                  │                                        ║    ║
║    ║                           ┌──────────────────────┴──────────────────────┐                 ║    ║
║    ║                           │                                             │                 ║    ║
║    ║                  ┌────────▼─────────┐                       ┌───────────▼────────┐        ║    ║
║    ║                  │  🐘 POSTGRESQL    │                       │  ⚡ VALKEY          │        ║    ║
║    ║                  │  (Managed HA)    │                       │  (Managed HA)      │        ║    ║
║    ║                  │                  │                       │                    │        ║    ║
║    ║                  │  v18 Production  │                       │  v8.1 Production   │        ║    ║
║    ║                  │  2-Node Cluster  │                       │  2-Node Cluster    │        ║    ║
║    ║                  │  🔒 Private Only  │                       │  🔒 Private Only    │        ║    ║
║    ║                  └──────────────────┘                       └────────────────────┘        ║    ║
║    ║                                                                                           ║    ║
║    ╚═══════════════════════════════════════════════════════════════════════════════════════════╝    ║
║                                                                                                       ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                    📦 OVH OBJECT STORAGE (S3)                                         ║
╠══════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                       ║
║   ┌─────────────────────────────────┐                   ┌─────────────────────────────────┐          ║
║   │     🗂️ PRIMARY BUCKET            │    Replication    │     🗂️ REPLICA BUCKET            │          ║
║   │        EU-WEST-PAR              │ ═══════════════▶  │         GRA (Backup)            │          ║
║   │                                 │                   │                                 │          ║
║   │   ✅ Versioning Enabled         │                   │   ✅ Auto-created by OVH        │          ║
║   │   ✅ SSE-S3 Encryption          │                   │   ✅ Cross-region DR            │          ║
║   │   ✅ CORS Configured            │                   │   ✅ Disaster Recovery          │          ║
║   └─────────────────────────────────┘                   └─────────────────────────────────┘          ║
║                     ▲                                                                                 ║
║                     │ S3 API (HTTPS)                                                                  ║
║                     │                                                                                 ║
║            ┌────────┴────────┐                                                                        ║
║            │   App Servers   │                                                                        ║
║            └─────────────────┘                                                                        ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗
║                                📊 OVH LOGS DATA PLATFORM (LDP)                                        ║
║                                   Centralized Observability                                           ║
╠══════════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                       ║
║   ┌────────────────────────────────────────────────────────────────────────────────────────────────┐ ║
║   │                                                                                                 │ ║
║   │   📝 Application Logs (Laravel)     📝 System Logs (syslog)      📝 Security Events           │ ║
║   │   📝 Nginx Access/Error Logs        📝 PostgreSQL Logs           📝 Bastion Audit Logs        │ ║
║   │                                                                                                 │ ║
║   └────────────────────────────────────────────────────────────────────────────────────────────────┘ ║
║                 ▲                    ▲                    ▲                    ▲                      ║
║                 │                    │                    │                    │                      ║
║        ┌────────┴────┐      ┌────────┴────┐      ┌────────┴────┐      ┌────────┴────┐                ║
║        │ App Servers │      │   Bastion   │      │  CI Server  │      │  PostgreSQL │                ║
║        └─────────────┘      └─────────────┘      └─────────────┘      └─────────────┘                ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

---

## 🔒 Security Architecture

### Defense-in-Depth Model

```
╔═══════════════════════════════════════════════════════════════════════════════════════════╗
║                              🛡️ SECURITY LAYERS                                            ║
╠═══════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                            ║
║   LAYER 1: PERIMETER                                                                       ║
║   ┌────────────────────────────────────────────────────────────────────────────────────┐  ║
║   │  ☁️ Cloudflare DDoS Protection  │  🌍 Geo-restriction (French IPs for SSH)         │  ║
║   │  🔐 TLS 1.3 Encryption          │  🚫 Rate Limiting                                │  ║
║   └────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                            ║
║   LAYER 2: NETWORK                                                                         ║
║   ┌────────────────────────────────────────────────────────────────────────────────────┐  ║
║   │  🔒 Private vRack Network       │  🛡️ Security Groups (Firewall)                   │  ║
║   │  🚪 Bastion-only SSH Access     │  📍 IP Whitelisting (Forge)                      │  ║
║   └────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                            ║
║   LAYER 3: APPLICATION                                                                     ║
║   ┌────────────────────────────────────────────────────────────────────────────────────┐  ║
║   │  🔑 SSH Key Authentication      │  👤 Role-based Access (The Bastion)              │  ║
║   │  📝 Session Recording           │  🔍 Full Audit Trail                             │  ║
║   └────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                            ║
║   LAYER 4: DATA                                                                            ║
║   ┌────────────────────────────────────────────────────────────────────────────────────┐  ║
║   │  🔐 Encryption at Rest (SSE-S3) │  🔒 Encryption in Transit (TLS)                  │  ║
║   │  🗄️ Database IP Restrictions    │  💾 Automated Encrypted Backups                  │  ║
║   └────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                            ║
╚═══════════════════════════════════════════════════════════════════════════════════════════╝
```

### Network Access Matrix

```
╔═══════════════════════════════════════════════════════════════════════════════════════════╗
║                              🌐 EXTERNAL ACCESS (Ext-Net)                                  ║
╠═════════════════════╦═════════════════════════════════════════════════════════════════════╣
║  Component          ║  Access Rules                                                       ║
╠═════════════════════╬═════════════════════════════════════════════════════════════════════╣
║  ⚖️ Load Balancer    ║  :80 → HTTPS redirect | :443 HTTPS | :49984 IoT TCP ← ANY          ║
║  🛡️ Bastion          ║  :22 SSH ← 🇫🇷 French IP Ranges Only                                ║
║  💻 App Servers      ║  :22 SSH ← Laravel Forge IPs (159.203.150.x, 45.55.124.124)        ║
║  💻 App Servers      ║  :80/:443 HTTP/S ← ANY (via Floating IP)                           ║
╚═════════════════════╩═════════════════════════════════════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════════════════════════════════╗
║                           🔐 INTERNAL ACCESS (Private vRack)                               ║
╠═════════════════════╦═════════════════════════════════════════════════════════════════════╣
║  Component          ║  Access Rules                                                       ║
╠═════════════════════╬═════════════════════════════════════════════════════════════════════╣
║  💻 App Servers      ║  :22 SSH ← Bastion (10.101.3.50/32)                                 ║
║  💻 App Servers      ║  :443 HTTPS ← Load Balancer Pool (10.101.0.0/16)                   ║
║  💻 App Servers      ║  :49984 IoT TCP ← Load Balancer Pool (10.101.0.0/16)               ║
║  🔄 CI Server        ║  :22 SSH ← Bastion (10.101.3.50/32)                                 ║
║  🐘 PostgreSQL       ║  :20184 ← Private Network CIDR Only (10.101.0.0/16)                ║
║  ⚡ Valkey           ║  :20185 ← Private Network CIDR Only (10.101.0.0/16)                ║
╚═════════════════════╩═════════════════════════════════════════════════════════════════════╝
```

---

## 🧩 Components

| Component | Description | Configuration | Security |
|-----------|-------------|---------------|----------|
| **⚖️ Load Balancer** | OVHcloud Load Balancer with floating IP | HTTP→HTTPS redirect, IoT TCP :49984, Round Robin | TLS termination, Health checks |
| **💻 App Servers** | Ubuntu 24.04 application servers | Multi-AZ (PAR-A, PAR-B), Laravel + Nginx | Security groups, Bastion SSH |
| **🛡️ Bastion** | [The Bastion](https://github.com/ovh/the-bastion) SSH gateway | Dual-homed (private + public) | French IPs only, Session recording |
| **🔄 CI Server** | Continuous integration runner | Private network only | Bastion-only access |
| **🐘 PostgreSQL** | OVH Managed PostgreSQL 18 | 2-node HA, Production plan | Private network, Deletion protection |
| **⚡ Valkey** | OVH Managed Valkey 8.1 (Redis-compatible) | 2-node HA, Production plan | Private network, Deletion protection |
| **📦 S3 Storage** | OVH Object Storage | EU-WEST-PAR → GRA replication | SSE-S3 encryption, Versioning |
| **☁️ DNS** | Cloudflare DNS | Direct for bastion, Proxied for LB | DDoS protection |
| **📊 LDP** | OVH Logs Data Platform | Centralized logging | Audit trails |

---

## 🌐 Network Topology

### Private Network (vRack)

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║                    PRIVATE NETWORK CONFIGURATION                               ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                                ║
║   Network CIDR:     10.101.0.0/16                                              ║
║   VLAN ID:          101                                                        ║
║   DHCP:             Enabled (10.101.0.10 - 10.101.0.99)                        ║
║   Gateway:          Router connected to Ext-Net                                ║
║                                                                                ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

### IP Addressing Scheme

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║                         IP ADDRESS ALLOCATION                                  ║
╠════════════════════════════════╦══════════════════════════════════════════════╣
║  Host Type                     ║  IP Range / Address                          ║
╠════════════════════════════════╬══════════════════════════════════════════════╣
║  📋 DHCP Pool                   ║  10.101.0.10 - 10.101.0.99                   ║
║  💻 App Servers (Zone A)        ║  10.101.1.x                                  ║
║  💻 App Servers (Zone B)        ║  10.101.2.x                                  ║
║  🛡️ Bastion                     ║  10.101.3.50                                 ║
║  🔄 CI Server                   ║  10.101.3.60                                 ║
╚════════════════════════════════╩══════════════════════════════════════════════╝
```

---

## 🔐 Access Control & Security

### Zero-Trust SSH Access Model

This infrastructure implements a **zero-trust SSH access model** using [OVH The Bastion](https://github.com/ovh/the-bastion).

```
╔═══════════════════════════════════════════════════════════════════════════════════════════╗
║                              SSH ACCESS FLOW                                               ║
╠═══════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                            ║
║   ┌──────────────────┐         ┌──────────────────────────┐         ┌──────────────────┐  ║
║   │                  │   SSH   │                          │   SSH   │                  │  ║
║   │   👤 Developer    │ ───────▶│   🛡️ Bastion Server       │ ───────▶│   💻 Target Server│  ║
║   │   (French IP)    │         │   (The Bastion)          │         │                  │  ║
║   └──────────────────┘         └──────────────────────────┘         └──────────────────┘  ║
║                                          │                                                 ║
║                                          │ Provides:                                       ║
║                                          │                                                 ║
║                                          ├─▶ 🔑 Authentication (SSH Keys)                  ║
║                                          ├─▶ 🔒 Authorization (Fine-grained ACL)           ║
║                                          ├─▶ 📹 Session Recording (ttyrec)                 ║
║                                          ├─▶ 📝 Audit Logging (syslog)                     ║
║                                          └─▶ 🛡️ Protocol Break (Security)                  ║
║                                                                                            ║
╚═══════════════════════════════════════════════════════════════════════════════════════════╝
```

#### Connecting via Bastion

```bash
# Direct connection through bastion (ProxyJump)
ssh -J bastion.potti.fr user@target-server

# Using The Bastion's native commands
ssh user@bastion.potti.fr -t -- user@target-server
```

### Security Groups

| Security Group | Purpose | Rules |
|----------------|---------|-------|
| `bastion_access_secgroup` | SSH from bastion | Ingress TCP/22 from 10.101.3.50/32 |
| `bastion_french_only_secgroup` | Geo-restricted bastion access | Ingress TCP/22 from French IP ranges |
| `forge_access_secgroup` | Laravel Forge SSH access | Ingress TCP/22 from Forge IPs |
| `web_access_secgroup` | Internal web & IoT traffic | Ingress TCP/443, TCP/49984 from 10.101.0.0/16 |
| `app_tcp_direct_secgroup` | Direct app server access | Ingress TCP/80, TCP/443 from 0.0.0.0/0 |
| `tailscale_secgroup` | Tailscale VPN | UDP/41641, UDP/3478 from 0.0.0.0/0 |

### Database Security

- ✅ PostgreSQL and Valkey restricted to private network CIDR (`10.101.0.0/16`)
- ✅ No public endpoints exposed
- ✅ Deletion protection enabled
- ✅ High-availability with 2-node clusters
- ✅ Automated backups to multiple regions (EU-WEST-PAR, GRA)

---

## 🔧 Application Server Management

Application servers are provisioned and managed using **[Laravel Forge](https://forge.laravel.com/)**.

### What Forge Manages

| Capability | Description |
|------------|-------------|
| 🖥️ **Server Provisioning** | Initial Ubuntu setup, PHP, Nginx configuration |
| 🚀 **Deployments** | Git-based deployments with zero-downtime |
| 🔐 **SSL Certificates** | Automatic Let's Encrypt management |
| ⚙️ **Queue Workers** | Supervisor configuration for Laravel queues |
| ⏰ **Scheduled Tasks** | Cron job management |
| 💾 **Database Backups** | Automated backup scheduling |
| 📊 **Monitoring** | Server health and resource monitoring |

### Forge Access

Forge connects to app servers via SSH using whitelisted IP addresses:

```
159.203.150.232  │  45.55.124.124  │  159.203.150.216  │  165.227.248.218
```

### Access Hierarchy

| Access Type | Method | Purpose |
|-------------|--------|---------|
| **👤 Developer SSH** | Via The Bastion | Debugging, maintenance, emergency access |
| **🤖 Forge Automated** | Direct SSH (whitelisted IPs) | Deployments, server management |
| **🌐 Application Traffic** | Via Load Balancer | Production web traffic |

---

## 📦 Object Storage (S3)

### Storage Architecture

```
╔═══════════════════════════════════════════════════════════════════════════════════════════╗
║                              S3 STORAGE ARCHITECTURE                                       ║
╠═══════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                            ║
║   ┌─────────────────────────────────┐    Cross-Region     ┌─────────────────────────────┐ ║
║   │     🗂️ PRIMARY BUCKET            │    Replication      │     🗂️ REPLICA BUCKET        │ ║
║   │        EU-WEST-PAR              │ ═══════════════════▶│         GRA                 │ ║
║   │                                 │                     │                             │ ║
║   │   ✅ Versioning: Enabled        │                     │   ✅ Storage: STANDARD_IA   │ ║
║   │   ✅ Encryption: AES256         │                     │   ✅ Auto-managed by OVH    │ ║
║   │   ✅ CORS: potti.co domains     │                     │   ✅ Disaster Recovery      │ ║
║   │   ✅ Delete Markers: Replicated │                     │                             │ ║
║   └─────────────────────────────────┘                     └─────────────────────────────┘ ║
║                                                                                            ║
╚═══════════════════════════════════════════════════════════════════════════════════════════╝
```

### Features

| Feature | Configuration |
|---------|---------------|
| **Cross-region Replication** | EU-WEST-PAR → GRA for disaster recovery |
| **Versioning** | Enabled - protects against accidental deletions |
| **Encryption** | Server-side encryption (SSE-S3/AES256) |
| **CORS** | Configured for `potti.co` and `staging.potti.co` |

### S3 Endpoint

```
https://s3.eu-west-par.io.cloud.ovh.net
```

---

## 📊 Observability & Logging

All infrastructure components ship logs to **[OVH Logs Data Platform (LDP)](https://help.ovhcloud.com/csm/fr-documentation-observability-logs-data-platform)**.

### Log Sources

| Source | Log Types |
|--------|-----------|
| **💻 App Servers** | Laravel application logs, Nginx access/error logs |
| **🛡️ Bastion** | SSH session logs, audit trails, access attempts |
| **🔄 CI Server** | Build logs, deployment logs |
| **🐘 PostgreSQL** | Query logs, slow queries, connection logs |
| **⚡ Valkey** | Cache operations, connection logs |

### Benefits

- 🔍 **Centralized Search**: Query logs across all services from a single interface
- 📅 **Retention**: Configurable log retention policies
- 🚨 **Alerting**: Set up alerts on error patterns or anomalies
- ✅ **Compliance**: Audit trail for security and compliance requirements
- 🔗 **Correlation**: Trace requests across services using correlation IDs

---

## 🌍 DNS Configuration

| Record | Type | Target | Proxied |
|--------|------|--------|---------|
| `bastion.potti.fr` | A | Bastion public IP | ❌ No |
| `potti.co` | A | Load Balancer floating IP | ❌ No |

---

## 📁 Terraform Resources

### Files Overview

| File | Purpose |
|------|---------|
| `provider.tf` | OVH, OpenStack, and Cloudflare provider configuration |
| `variable.tf` | Input variables and defaults |
| `locals.tf` | Computed local values |
| `network.tf` | Private network, subnet, router |
| `rules.tf` | Security groups and firewall rules |
| `bastion.tf` | Bastion server instance |
| `instance.tf` | Application server instances |
| `azure-runners/` | Separate stack: Azure AKS runner fleet for GitHub Actions — see `azure-runners/README.md` |
| `load-balancer.tf` | Load balancer, listeners, pools, health checks |
| `database.tf` | Managed PostgreSQL cluster |
| `cache.tf` | Managed Valkey cluster |
| `s3.tf` | Object storage bucket and credentials |
| `dns.tf` | Cloudflare DNS records |
| `ssh.tf` | SSH keypairs |
| `outputs.tf` | Terraform outputs |

---

## 🚀 Quick Start

```bash
# 1. Initialize Terraform
terraform init

# 2. Copy and configure variables
cp my_vars.tfvarexample my_vars.tfvars
# Edit my_vars.tfvars with your credentials

# 3. Plan changes
terraform plan -var-file=my_vars.tfvars

# 4. Apply changes
terraform apply -var-file=my_vars.tfvars
```

---

## 🔄 High Availability

| Component | HA Strategy | RTO |
|-----------|-------------|-----|
| **💻 App Servers** | Multiple instances across AZs (PAR-A, PAR-B) | < 30s |
| **⚖️ Load Balancer** | OVHcloud managed with health checks | Automatic |
| **🐘 PostgreSQL** | 2-node cluster with automatic failover | < 60s |
| **⚡ Valkey** | 2-node cluster with automatic failover | < 60s |
| **📦 S3 Storage** | Cross-region replication (PAR → GRA) | N/A |
| **🛡️ Bastion** | Single instance (manual recovery) | Manual |

---

## 📡 Monitoring & Health Checks

| Component | Check Type | Interval | Timeout | Retries |
|-----------|------------|----------|---------|---------|
| **Load Balancer HTTPS** | HTTP `/up` | 10s | 5s | 3 |
| **Load Balancer IoT** | TCP :49984 | 10s | 5s | 3 |
| **Forge** | Server metrics | Continuous | - | - |
| **The Bastion** | Session recording | Real-time | - | - |

---

## 📡 IoT Sensor Integration

### Configuration

| Setting | Value |
|---------|-------|
| **Protocol** | TCP |
| **Port** | 49984 |
| **Load Balancing** | Round Robin |
| **Health Check** | TCP (10s interval, 5s timeout, 3 retries) |

### Architecture

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║                          IoT DATA INGESTION FLOW                               ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                                ║
║   ┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐    ║
║   │                  │ TCP  │                  │ TCP  │                  │    ║
║   │   📡 IoT Sensors  │─────▶│   ⚖️ Load Balancer│─────▶│   💻 App Servers  │    ║
║   │                  │:49984│                  │:49984│                  │    ║
║   └──────────────────┘      └──────────────────┘      └──────────────────┘    ║
║                                                                                ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

### Connection

```
<load-balancer-floating-ip>:49984
```

---

## ✅ Compliance

For detailed data policies and compliance documentation, see **[DATA_POLICIES.md](./DATA_POLICIES.md)**.

---

## 📚 References

- [OVH The Bastion](https://github.com/ovh/the-bastion) - SSH access gateway
- [Laravel Forge](https://forge.laravel.com/) - Server management platform
- [OVHcloud Public Cloud](https://www.ovhcloud.com/en/public-cloud/) - Cloud infrastructure
- [OVH Logs Data Platform](https://help.ovhcloud.com/csm/fr-documentation-observability-logs-data-platform) - Centralized logging
- [Cloudflare](https://www.cloudflare.com/) - DNS and CDN
