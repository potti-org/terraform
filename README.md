# Potti Infrastructure

Terraform configuration for the Potti application infrastructure hosted on OVHcloud Public Cloud.

## Architecture Overview

```
                                              ┌─────────────────────────────────────────────────────────────────┐
                                              │                         INTERNET                                │
                                              └──────────────────────────────┬──────────────────────────────────┘
                                                                             │
              ┌──────────────────────────────────────┬────────────────────────┼────────────────────────────────────┐
              │                                      │                        │                                    │
              ▼                                      ▼                        ▼                                    ▼
       ┌─────────────┐                     ┌──────────────────┐      ┌──────────────────┐              ┌─────────────────────┐
       │  Cloudflare │                     │   Load Balancer  │      │    Developers    │              │    Laravel Forge    │
       │     DNS     │                     │  (Floating IP)   │      │                  │              │                     │
       └──────┬──────┘                     └────────┬─────────┘      └────────┬─────────┘              │  159.203.150.232    │
              │                                     │                         │                        │  45.55.124.124      │
              │                                     │ HTTPS :443              │ SSH :22                │  159.203.150.216    │
              │                                     │ HTTP :80 → redirect     │                        │  165.227.248.218    │
              │                                     │                         │                        └──────────┬──────────┘
              │                                     │                         │                                   │
              │                                     │                         │                                   │ SSH :22
              │                                     │                         │                                   │ (Whitelisted IPs)
              │                                     │                         │                                   │
              │                                     ▼                         │                                   │
              │                          ┌────────────────────┐               │                                   │
              │                          │    Round Robin     │               │                                   │
              │                          │    Pool (HTTPS)    │               │                                   │
              │                          └─────────┬──────────┘               │                                   │
              │                                    │                          │                                   │
    ┌─────────┴────────────────────────────────────┼──────────────────────────┼───────────────────────────────────┼─────────┐
    │                                              │                          │                                   │         │
    │                               PRIVATE NETWORK (vRack) - 10.101.0.0/16   │                                   │         │
    │                                              │                          │                                   │         │
    │    ┌────────────────┐       ┌────────────────┴──────────────────────────┴───────────────────────────────────┴───┐     │
    │    │                │       │                                                                                   │     │
    │    │    Bastion     │       │            ┌───────────────────────┐        ┌───────────────────────┐             │     │
    │    │  (The Bastion) │       │            │      App Server       │        │      App Server       │             │     │
    │    │                │       │            │       PAR-A-1         │        │       PAR-B-1         │             │     │
    │    │  10.101.3.50   │──SSH──│            │                       │        │                       │             │     │
    │    │                │       │            │  Private: 10.101.1.x  │        │  Private: 10.101.2.x  │             │     │
    │    │  + Ext-Net IP  │       │            │  + Floating IP        │        │  + Floating IP        │             │     │
    │    └───────┬────────┘       │            │  (Ext-Net :22 only)   │        │  (Ext-Net :22 only)   │             │     │
    │            │                │            └───────────────────────┘        └───────────────────────┘             │     │
    │            │                │                        │                              │                           │     │
    │            │                │                        └──────────────┬───────────────┘                           │     │
    │            │                │                                       │                                           │     │
    │            │                └───────────────────────────────────────┼───────────────────────────────────────────┘     │
    │            │                                                        │                                                 │
    │            │                                                        │                                                 │
    │    ┌───────┴────────┐                          ┌────────────────────┴────────────────┐                                │
    │    │                │                          │                                     │                                │
    │    │   CI Server    │                          │                                     │                                │
    │    │                │                          ▼                                     ▼                                │
    │    │  10.101.3.60   │               ┌──────────────────┐                  ┌──────────────────┐                        │
    │    │                │               │    PostgreSQL    │                  │      Valkey      │                        │
    │    └────────────────┘               │    (Managed)     │                  │     (Cache)      │                        │
    │                                     │    v18 - HA      │                  │    v8.1 - HA     │                        │
    │                                     └──────────────────┘                  └──────────────────┘                        │
    │                                                                                                                       │
    └───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

    ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
    │                                                                                                                       │
    │                                         OVH OBJECT STORAGE                                                            │
    │                                                                                                                       │
    │         ┌──────────────────────────────┐                    ┌──────────────────────────────┐                          │
    │         │     S3 Primary Bucket        │    Replication     │     S3 Replica Bucket        │                          │
    │         │      EU-WEST-PAR             │ ──────────────────▶│         GRA (Backup)         │                          │
    │         │                              │                    │                              │                          │
    │         │  • Versioning enabled        │                    │  • Auto-created by OVH       │                          │
    │         │  • SSE-S3 encryption         │                    │  • Cross-region DR           │                          │
    │         │  • CORS for web uploads      │                    │                              │                          │
    │         └──────────────────────────────┘                    └──────────────────────────────┘                          │
    │                       ▲                                                                                               │
    │                       │ S3 API (HTTPS)                                                                                │
    │                       │                                                                                               │
    └───────────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────┘
                            │
                            │
              ┌─────────────┴─────────────┐
              │       App Servers         │
              │  (File uploads/downloads) │
              └───────────────────────────┘


    ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
    │                                                                                                                       │
    │                                    OVH LOGS DATA PLATFORM (LDP)                                                       │
    │                                    Centralized Observability                                                          │
    │                                                                                                                       │
    │         ┌─────────────────────────────────────────────────────────────────────────────────────────────┐               │
    │         │                                                                                             │               │
    │         │   • Application logs (Laravel)          • System logs (syslog)                              │               │
    │         │   • Nginx access/error logs             • PostgreSQL logs                                   │               │
    │         │   • Bastion audit logs                  • Security events                                   │               │
    │         │                                                                                             │               │
    │         └─────────────────────────────────────────────────────────────────────────────────────────────┘               │
    │                       ▲                    ▲                    ▲                    ▲                                 │
    │                       │                    │                    │                    │                                 │
    └───────────────────────┼────────────────────┼────────────────────┼────────────────────┼─────────────────────────────────┘
                            │                    │                    │                    │
                   ┌────────┴────────┐  ┌────────┴────────┐  ┌────────┴────────┐  ┌────────┴────────┐
                   │   App Servers   │  │     Bastion     │  │    CI Server    │  │   PostgreSQL    │
                   └─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────────┘
```

### Network Access Summary

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    EXTERNAL ACCESS (Ext-Net)                                │
├─────────────────────┬───────────────────────────────────────────────────────────────────────┤
│  Load Balancer      │  :80 (→ redirect), :443 (HTTPS) ← ANY                                 │
│  Bastion            │  :22 (SSH) ← Developers                                               │
│  App Servers        │  :22 (SSH) ← Laravel Forge IPs only (159.203.150.232, etc.)           │
└─────────────────────┴───────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                  INTERNAL ACCESS (Private vRack)                            │
├─────────────────────┬───────────────────────────────────────────────────────────────────────┤
│  App Servers        │  :22 (SSH) ← Bastion (10.101.3.50)                                    │
│  App Servers        │  :443 (HTTPS) ← Load Balancer pool                                    │
│  CI Server          │  :22 (SSH) ← Bastion (10.101.3.50)                                    │
│  PostgreSQL         │  :5432 ← Private network CIDR only                                    │
│  Valkey             │  :6379 ← Private network CIDR only                                    │
└─────────────────────┴───────────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Description | Configuration |
|-----------|-------------|---------------|
| **Load Balancer** | OVHcloud Load Balancer with floating IP | HTTP→HTTPS redirect, Round Robin, Health checks on `/up` |
| **App Servers** | Ubuntu 24.04 application servers | Distributed across PAR-A and PAR-B availability zones |
| **Bastion** | SSH jump host running [The Bastion](https://github.com/ovh/the-bastion) | Dual-homed (private + public network) |
| **CI Server** | Continuous integration runner | Private network only, accessed via bastion |
| **PostgreSQL** | OVH Managed PostgreSQL 18 | Production plan, 2-node HA cluster |
| **Valkey** | OVH Managed Valkey 8.1 (Redis-compatible cache) | Production plan, 2-node HA cluster |
| **S3 Storage** | OVH Object Storage | Primary in EU-WEST-PAR, replicated to GRA for backup |
| **DNS** | Cloudflare DNS | Proxied for load balancer, direct for bastion |
| **Logs Data Platform** | OVH LDP | Centralized logging and observability |

## Network Architecture

### Private Network (vRack)

- **CIDR**: `10.101.0.0/16`
- **VLAN ID**: 101
- **DHCP**: Enabled
- **Gateway**: Router connected to Ext-Net

### IP Addressing Scheme

| Host Type | IP Range |
|-----------|----------|
| DHCP Pool | 10.101.0.10 - 10.101.0.99 |
| App Servers (Zone A) | 10.101.1.x |
| App Servers (Zone B) | 10.101.2.x |
| Bastion | 10.101.3.50 |
| CI Server | 10.101.3.60 |

---

## Access Control & Security

### SSH Access Model

This infrastructure implements a **zero-trust SSH access model** using [OVH The Bastion](https://github.com/ovh/the-bastion).

```
┌──────────────┐         ┌──────────────────────┐         ┌──────────────────┐
│              │   SSH   │                      │   SSH   │                  │
│  Developer   │────────▶│   Bastion Server     │────────▶│   Target Server  │
│              │         │   (The Bastion)      │         │                  │
└──────────────┘         └──────────────────────┘         └──────────────────┘
                                    │
                                    │ Provides:
                                    │ • Authentication
                                    │ • Authorization  
                                    │ • Full session recording
                                    │ • Audit logging
```

#### Key Features of The Bastion

- **Authentication**: Users authenticate to the bastion with their personal SSH keys
- **Authorization**: Fine-grained access control - users can only reach servers they're explicitly granted access to
- **Traceability**: Every command and session is recorded with `ttyrec`
- **Auditability**: All access attempts (allowed/denied) are logged via syslog
- **Protocol Break**: Ingress and egress connections are separated, preventing protocol-based attacks

#### Connecting via Bastion

```bash
# Direct connection through bastion
ssh -J bastion.potti.fr user@target-server

# Or using The Bastion's native commands
ssh user@bastion.potti.fr -t -- user@target-server
```

### Security Groups

| Security Group | Purpose | Rules |
|----------------|---------|-------|
| `bastion_access_secgroup` | SSH from bastion | Ingress TCP/22 from 10.101.3.50/32 |
| `forge_access_secgroup` | Laravel Forge SSH access | Ingress TCP/22 from Forge IPs |
| `web_access_secgroup` | Internal HTTPS traffic | Ingress TCP/443 from 10.101.0.0/16 |

### Database Security

- PostgreSQL and Valkey are restricted to the private network CIDR (`10.101.0.0/16`)
- No public endpoints exposed
- Deletion protection enabled
- High-availability with 2-node clusters

---

## Application Server Management

Application servers are provisioned and managed using **[Laravel Forge](https://forge.laravel.com/)**.

### What Forge Manages

- **Server provisioning**: Initial Ubuntu setup, PHP, Nginx, etc.
- **Deployments**: Git-based deployments with zero-downtime
- **SSL certificates**: Automatic Let's Encrypt certificate management
- **Queue workers**: Supervisor configuration for Laravel queues
- **Scheduled tasks**: Cron job management
- **Database backups**: Automated backup scheduling
- **Monitoring**: Server health and resource monitoring

### Forge Access

Forge connects to app servers via SSH using whitelisted IP addresses:

```
159.203.150.232
45.55.124.124
159.203.150.216
165.227.248.218
```

These IPs are configured in the `bastion_access_secgroup` security group to allow Forge's deployment and management operations.

### Access Hierarchy

| Access Type | Method | Purpose |
|-------------|--------|---------|
| **Developer SSH** | Via The Bastion | Debugging, maintenance, emergency access |
| **Forge Automated** | Direct SSH (whitelisted IPs) | Deployments, server management |
| **Application Traffic** | Via Load Balancer | Production web traffic |

---

## Object Storage (S3)

Application servers use OVH Object Storage for file uploads, media assets, and application data.

### Storage Architecture

| Bucket | Region | Purpose |
|--------|--------|---------|
| **Primary** | EU-WEST-PAR | Main storage bucket used by app servers |
| **Replica** | GRA | Backup/DR - automatically replicated from primary |

### Features

- **Cross-region replication**: All objects are automatically replicated to GRA datacenter for disaster recovery
- **Versioning**: Enabled to protect against accidental deletions
- **Encryption**: Server-side encryption (SSE-S3) for data at rest
- **CORS**: Configured to allow direct browser uploads from `potti.co` and `staging.potti.co`

### Access

App servers access S3 via HTTPS using dedicated IAM credentials with least-privilege permissions:

```
Endpoint: https://s3.eu-west-par.io.cloud.ovh.net
```

---

## Observability & Logging

All infrastructure components ship logs to **[OVH Logs Data Platform (LDP)](https://help.ovhcloud.com/csm/fr-documentation-observability-logs-data-platform)** for centralized observability.

### Log Sources

| Source | Log Types |
|--------|-----------|
| **App Servers** | Laravel application logs, Nginx access/error logs |
| **Bastion** | SSH session logs, audit trails, access attempts |
| **CI Server** | Build logs, deployment logs |
| **PostgreSQL** | Query logs, slow queries, connection logs |
| **Valkey** | Cache operations, connection logs |

### Benefits

- **Centralized search**: Query logs across all services from a single interface
- **Retention**: Configurable log retention policies
- **Alerting**: Set up alerts on error patterns or anomalies
- **Compliance**: Audit trail for security and compliance requirements
- **Correlation**: Trace requests across services using correlation IDs

---

## DNS Configuration

| Record | Type | Target | Proxied |
|--------|------|--------|---------|
| `bastion.potti.fr` | A | Bastion public IP | No |
| `staging.potti.fr` | A | Load Balancer floating IP | Yes (Cloudflare) |

---

## Terraform Resources

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
| `ci.tf` | CI server instance |
| `load-balancer.tf` | Load balancer, listeners, pools, health checks |
| `database.tf` | Managed PostgreSQL cluster |
| `cache.tf` | Managed Valkey cluster |
| `s3.tf` | Object storage bucket and credentials |
| `dns.tf` | Cloudflare DNS records |
| `ssh.tf` | SSH keypairs |
| `outputs.tf` | Terraform outputs |

### Usage

```bash
# Initialize Terraform
terraform init

# Copy and configure variables
cp my_vars.tfvarexample my_vars.tfvars
# Edit my_vars.tfvars with your credentials

# Plan changes
terraform plan -var-file=my_vars.tfvars

# Apply changes
terraform apply -var-file=my_vars.tfvars
```

---

## High Availability

| Component | HA Strategy |
|-----------|-------------|
| App Servers | Multiple instances across availability zones (PAR-A, PAR-B) |
| Load Balancer | OVHcloud managed with health checks |
| PostgreSQL | 2-node cluster with automatic failover |
| Valkey | 2-node cluster with automatic failover |
| Bastion | Single instance (manual recovery) |

---

## Monitoring & Health Checks

- **Load Balancer**: HTTP health check on `/up` endpoint every 10 seconds
- **Forge**: Server monitoring and alerting
- **The Bastion**: Session recording and audit logs

---

## References

- [OVH The Bastion](https://github.com/ovh/the-bastion) - SSH access gateway
- [Laravel Forge](https://forge.laravel.com/) - Server management platform
- [OVHcloud Public Cloud](https://www.ovhcloud.com/en/public-cloud/) - Cloud infrastructure
- [OVH Logs Data Platform](https://help.ovhcloud.com/csm/fr-documentation-observability-logs-data-platform) - Centralized logging
- [Cloudflare](https://www.cloudflare.com/) - DNS and CDN
