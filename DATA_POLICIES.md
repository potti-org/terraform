<p align="center">
  <img src="https://img.shields.io/badge/Compliance-GDPR-blue?style=for-the-badge" alt="GDPR">
  <img src="https://img.shields.io/badge/Security-ISO_27001-green?style=for-the-badge" alt="ISO 27001">
  <img src="https://img.shields.io/badge/Region-EU--WEST--PAR-orange?style=for-the-badge" alt="EU Region">
</p>

# 📋 Potti Infrastructure - Data Policies & Compliance

> Comprehensive data governance documentation for audit and compliance purposes.  
> **Document Version**: 1.0  
> **Last Updated**: January 2026  
> **Classification**: Internal / Audit

---

## 📑 Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Data Classification](#2-data-classification)
3. [Data Residency & Sovereignty](#3-data-residency--sovereignty)
4. [Encryption Standards](#4-encryption-standards)
5. [Access Control Policies](#5-access-control-policies)
6. [Data Retention & Backup](#6-data-retention--backup)
7. [Audit & Logging](#7-audit--logging)
8. [Incident Response](#8-incident-response)
9. [Compliance Matrix](#9-compliance-matrix)
10. [Contact & Governance](#10-contact--governance)

---

## 1. Executive Summary

### Purpose

This document outlines the data protection policies, security controls, and compliance measures implemented in the Potti infrastructure. It serves as the authoritative reference for:

- **Internal audits** and security assessments
- **External compliance** reviews (GDPR, SOC 2, ISO 27001)
- **Customer due diligence** requests
- **Regulatory inquiries**

### Infrastructure Overview

| Attribute | Value |
|-----------|-------|
| **Cloud Provider** | OVHcloud Public Cloud |
| **Primary Region** | EU-WEST-PAR (Paris, France) |
| **Backup Region** | GRA (Gravelines, France) |
| **Data Sovereignty** | 🇪🇺 European Union |
| **Infrastructure as Code** | Terraform |

### Key Security Highlights

| Control | Implementation |
|---------|----------------|
| ✅ **Encryption at Rest** | AES-256 (SSE-S3) for all stored data |
| ✅ **Encryption in Transit** | TLS 1.3 for all network communications |
| ✅ **Access Control** | Zero-trust SSH via The Bastion |
| ✅ **Geo-Restriction** | SSH access limited to French IP ranges |
| ✅ **Audit Logging** | Complete session recording and centralized logs |
| ✅ **High Availability** | Multi-AZ deployment with automated failover |
| ✅ **Disaster Recovery** | Cross-region replication (PAR → GRA) |

---

## 2. Data Classification

### Classification Levels

| Level | Description | Examples | Controls |
|-------|-------------|----------|----------|
| **🔴 Confidential** | Highly sensitive business data | API keys, credentials, PII | Encrypted, restricted access, audit logged |
| **🟠 Internal** | Business operational data | Application logs, metrics | Encrypted, role-based access |
| **🟢 Public** | Non-sensitive information | Marketing content, public docs | Standard protection |

### Data Categories

| Category | Classification | Storage Location | Encryption |
|----------|----------------|------------------|------------|
| User Personal Data (PII) | 🔴 Confidential | PostgreSQL | AES-256 |
| Authentication Credentials | 🔴 Confidential | PostgreSQL / Vault | AES-256 |
| Session Data | 🟠 Internal | Valkey (Redis) | In-transit TLS |
| Application Logs | 🟠 Internal | OVH LDP | AES-256 |
| File Uploads | 🟠 Internal | S3 Object Storage | SSE-S3 (AES-256) |
| IoT Sensor Data | 🟠 Internal | PostgreSQL | AES-256 |
| System Logs | 🟠 Internal | OVH LDP | AES-256 |

---

## 3. Data Residency & Sovereignty

### Geographic Distribution

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║                        🇪🇺 EUROPEAN UNION DATA RESIDENCY                        ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                                ║
║   ┌─────────────────────────────────┐    ┌─────────────────────────────────┐  ║
║   │     🏢 PRIMARY DATACENTER        │    │     🏢 BACKUP DATACENTER         │  ║
║   │        EU-WEST-PAR              │    │          GRA                    │  ║
║   │        Paris, France            │    │     Gravelines, France          │  ║
║   │                                 │    │                                 │  ║
║   │   • Compute Instances           │    │   • S3 Replica Bucket           │  ║
║   │   • PostgreSQL Primary          │    │   • PostgreSQL Backup           │  ║
║   │   • Valkey Primary              │    │   • Valkey Backup               │  ║
║   │   • S3 Primary Bucket           │    │   • Disaster Recovery           │  ║
║   │   • Load Balancer               │    │                                 │  ║
║   └─────────────────────────────────┘    └─────────────────────────────────┘  ║
║                                                                                ║
║   🔒 All data remains within EU jurisdiction                                   ║
║   🔒 No data transfer outside European Economic Area                           ║
║   🔒 OVHcloud is a European company subject to EU regulations                  ║
║                                                                                ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

### Data Sovereignty Guarantees

| Guarantee | Implementation |
|-----------|----------------|
| **EU Data Residency** | All data stored in France (EU-WEST-PAR, GRA) |
| **No US Cloud Act Exposure** | OVHcloud is EU-headquartered, not subject to US jurisdiction |
| **GDPR Compliance** | Infrastructure designed for GDPR requirements |
| **Data Portability** | Standard formats (PostgreSQL, S3-compatible) enable portability |

### Cross-Border Data Flows

| Flow Type | Source | Destination | Justification |
|-----------|--------|-------------|---------------|
| Replication | EU-WEST-PAR | GRA | Disaster recovery (same jurisdiction) |
| Backups | EU-WEST-PAR | GRA | Business continuity (same jurisdiction) |
| User Access | Global | EU-WEST-PAR | Service delivery |

---

## 4. Encryption Standards

### Encryption at Rest

| Component | Encryption Method | Key Management |
|-----------|-------------------|----------------|
| **S3 Object Storage** | SSE-S3 (AES-256) | OVH Managed |
| **PostgreSQL** | Transparent Data Encryption | OVH Managed |
| **Valkey** | At-rest encryption | OVH Managed |
| **Compute Volumes** | Block storage encryption | OVH Managed |

### Encryption in Transit

| Connection | Protocol | Certificate |
|------------|----------|-------------|
| **Client → Load Balancer** | TLS 1.3 | Let's Encrypt |
| **Load Balancer → App Servers** | TLS 1.3 | Internal CA |
| **App Servers → PostgreSQL** | TLS 1.3 | OVH Managed |
| **App Servers → Valkey** | TLS 1.3 | OVH Managed |
| **App Servers → S3** | HTTPS (TLS 1.3) | OVH Managed |
| **SSH Connections** | SSH Protocol v2 | Ed25519 Keys |

### Key Management

| Key Type | Rotation Policy | Storage |
|----------|-----------------|---------|
| SSH Keys | Manual (on compromise) | The Bastion |
| TLS Certificates | Auto (90 days via Let's Encrypt) | Nginx |
| Database Credentials | Manual (quarterly recommended) | Terraform State (encrypted) |
| API Keys | Manual (on compromise) | Environment Variables |

---

## 5. Access Control Policies

### Identity & Access Management

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║                         ACCESS CONTROL MODEL                                   ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                                ║
║   LAYER 1: NETWORK PERIMETER                                                   ║
║   ┌────────────────────────────────────────────────────────────────────────┐  ║
║   │  🌍 Geo-Restriction: SSH only from French IP ranges                    │  ║
║   │  🔥 Firewall: Security groups with explicit allow rules                │  ║
║   │  📍 IP Whitelisting: Laravel Forge IPs for deployment                  │  ║
║   └────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                ║
║   LAYER 2: AUTHENTICATION                                                      ║
║   ┌────────────────────────────────────────────────────────────────────────┐  ║
║   │  🔑 SSH Key Authentication: No password-based access                   │  ║
║   │  🛡️ The Bastion: Centralized SSH gateway with MFA capability           │  ║
║   │  👤 Individual Accounts: No shared credentials                         │  ║
║   └────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                ║
║   LAYER 3: AUTHORIZATION                                                       ║
║   ┌────────────────────────────────────────────────────────────────────────┐  ║
║   │  🔒 Least Privilege: Users granted minimum required access             │  ║
║   │  📋 Role-Based Access: Defined roles for different access levels       │  ║
║   │  ⏰ Time-Limited Access: Temporary access grants when needed           │  ║
║   └────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                ║
║   LAYER 4: MONITORING                                                          ║
║   ┌────────────────────────────────────────────────────────────────────────┐  ║
║   │  📹 Session Recording: All SSH sessions recorded via ttyrec            │  ║
║   │  📝 Audit Logs: All access attempts logged to centralized system       │  ║
║   │  🚨 Alerting: Real-time alerts on suspicious activity                  │  ║
║   └────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

### Access Roles

| Role | Access Level | Servers | Capabilities |
|------|--------------|---------|--------------|
| **Infrastructure Admin** | Full | All | Full system access, security configuration |
| **Developer** | Limited | App Servers | Application deployment, debugging |
| **DBA** | Database | PostgreSQL | Database management, query optimization |
| **Auditor** | Read-Only | Logs | Log review, compliance verification |
| **Forge (Automated)** | Deployment | App Servers | Automated deployments only |

### Access Review Schedule

| Review Type | Frequency | Responsible |
|-------------|-----------|-------------|
| User Access Review | Quarterly | Security Team |
| Privilege Escalation Review | Monthly | Infrastructure Admin |
| SSH Key Audit | Quarterly | Security Team |
| Security Group Review | Monthly | Infrastructure Admin |

---

## 6. Data Retention & Backup

### Retention Policies

| Data Type | Retention Period | Justification |
|-----------|------------------|---------------|
| **Application Data** | Indefinite (until user deletion) | Business requirement |
| **User PII** | Until account deletion + 30 days | GDPR compliance |
| **Application Logs** | 90 days | Troubleshooting, security |
| **Audit Logs** | 1 year minimum | Compliance requirement |
| **Session Recordings** | 90 days | Security investigation |
| **Database Backups** | 30 days | Disaster recovery |
| **S3 Versioning** | 90 days | Accidental deletion recovery |

### Backup Strategy

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║                          BACKUP ARCHITECTURE                                   ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                                ║
║   ┌─────────────────────────────────────────────────────────────────────────┐ ║
║   │                        POSTGRESQL BACKUPS                                │ ║
║   ├─────────────────────────────────────────────────────────────────────────┤ ║
║   │  📅 Schedule:        Daily at 02:00 UTC                                 │ ║
║   │  📍 Primary Region:  EU-WEST-PAR                                        │ ║
║   │  📍 Backup Region:   GRA (cross-region)                                 │ ║
║   │  🔐 Encryption:      AES-256                                            │ ║
║   │  ⏱️ Retention:       30 days                                            │ ║
║   │  🔄 Type:            Automated (OVH Managed)                            │ ║
║   └─────────────────────────────────────────────────────────────────────────┘ ║
║                                                                                ║
║   ┌─────────────────────────────────────────────────────────────────────────┐ ║
║   │                         VALKEY BACKUPS                                   │ ║
║   ├─────────────────────────────────────────────────────────────────────────┤ ║
║   │  📅 Schedule:        Daily at 02:00 UTC                                 │ ║
║   │  📍 Primary Region:  EU-WEST-PAR                                        │ ║
║   │  📍 Backup Region:   GRA (cross-region)                                 │ ║
║   │  🔐 Encryption:      AES-256                                            │ ║
║   │  ⏱️ Retention:       30 days                                            │ ║
║   └─────────────────────────────────────────────────────────────────────────┘ ║
║                                                                                ║
║   ┌─────────────────────────────────────────────────────────────────────────┐ ║
║   │                      S3 OBJECT STORAGE                                   │ ║
║   ├─────────────────────────────────────────────────────────────────────────┤ ║
║   │  🔄 Replication:     Real-time to GRA region                            │ ║
║   │  📜 Versioning:      Enabled (90-day retention)                         │ ║
║   │  🗑️ Delete Markers:  Replicated to backup region                        │ ║
║   │  🔐 Encryption:      SSE-S3 (AES-256)                                   │ ║
║   └─────────────────────────────────────────────────────────────────────────┘ ║
║                                                                                ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

### Recovery Objectives

| Metric | Target | Component |
|--------|--------|-----------|
| **RPO** (Recovery Point Objective) | < 24 hours | Database |
| **RPO** (Recovery Point Objective) | Near real-time | S3 Storage |
| **RTO** (Recovery Time Objective) | < 4 hours | Full infrastructure |
| **RTO** (Recovery Time Objective) | < 1 hour | Database failover |

---

## 7. Audit & Logging

### Log Collection Architecture

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║                    CENTRALIZED LOGGING ARCHITECTURE                            ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                                ║
║                          ┌─────────────────────────────┐                       ║
║                          │   📊 OVH Logs Data Platform  │                       ║
║                          │        (Centralized)        │                       ║
║                          └─────────────────────────────┘                       ║
║                                       ▲                                        ║
║                                       │                                        ║
║           ┌───────────────────────────┼───────────────────────────┐            ║
║           │                           │                           │            ║
║   ┌───────┴───────┐           ┌───────┴───────┐           ┌───────┴───────┐   ║
║   │ 💻 App Servers │           │ 🛡️ Bastion    │           │ 🐘 PostgreSQL  │   ║
║   │               │           │               │           │               │   ║
║   │ • Laravel logs│           │ • SSH sessions│           │ • Query logs  │   ║
║   │ • Nginx logs  │           │ • Audit trail │           │ • Slow queries│   ║
║   │ • System logs │           │ • Access logs │           │ • Connections │   ║
║   └───────────────┘           └───────────────┘           └───────────────┘   ║
║                                                                                ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

### Audit Events Captured

| Event Category | Events Logged | Retention |
|----------------|---------------|-----------|
| **Authentication** | Login success/failure, SSH key usage | 1 year |
| **Authorization** | Permission grants/denials, role changes | 1 year |
| **Data Access** | Database queries, S3 access | 90 days |
| **System Changes** | Configuration changes, deployments | 1 year |
| **Security Events** | Firewall blocks, intrusion attempts | 1 year |

### SSH Session Recording

The Bastion provides complete session recording:

| Feature | Implementation |
|---------|----------------|
| **Recording Format** | ttyrec (terminal recording) |
| **Storage** | Centralized on Bastion server |
| **Retention** | 90 days |
| **Playback** | `ttyplay` command |
| **Tamper Protection** | Read-only storage, integrity checks |

---

## 8. Incident Response

### Incident Classification

| Severity | Description | Response Time | Examples |
|----------|-------------|---------------|----------|
| **🔴 Critical** | Service outage, data breach | < 15 minutes | Database compromise, DDoS attack |
| **🟠 High** | Partial outage, security alert | < 1 hour | Single server failure, suspicious access |
| **🟡 Medium** | Performance degradation | < 4 hours | High latency, disk space warning |
| **🟢 Low** | Minor issues | < 24 hours | Log warnings, minor configuration issues |

### Response Procedures

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║                       INCIDENT RESPONSE WORKFLOW                               ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                                ║
║   1️⃣ DETECTION                                                                 ║
║   ┌────────────────────────────────────────────────────────────────────────┐  ║
║   │  • Automated monitoring alerts                                         │  ║
║   │  • Log analysis triggers                                               │  ║
║   │  • User reports                                                        │  ║
║   └────────────────────────────────────────────────────────────────────────┘  ║
║                              ▼                                                 ║
║   2️⃣ TRIAGE                                                                    ║
║   ┌────────────────────────────────────────────────────────────────────────┐  ║
║   │  • Classify severity                                                   │  ║
║   │  • Identify affected systems                                           │  ║
║   │  • Notify relevant personnel                                           │  ║
║   └────────────────────────────────────────────────────────────────────────┘  ║
║                              ▼                                                 ║
║   3️⃣ CONTAINMENT                                                               ║
║   ┌────────────────────────────────────────────────────────────────────────┐  ║
║   │  • Isolate affected systems                                            │  ║
║   │  • Preserve evidence                                                   │  ║
║   │  • Block malicious actors                                              │  ║
║   └────────────────────────────────────────────────────────────────────────┘  ║
║                              ▼                                                 ║
║   4️⃣ REMEDIATION                                                               ║
║   ┌────────────────────────────────────────────────────────────────────────┐  ║
║   │  • Apply fixes                                                         │  ║
║   │  • Restore services                                                    │  ║
║   │  • Verify resolution                                                   │  ║
║   └────────────────────────────────────────────────────────────────────────┘  ║
║                              ▼                                                 ║
║   5️⃣ POST-INCIDENT                                                             ║
║   ┌────────────────────────────────────────────────────────────────────────┐  ║
║   │  • Root cause analysis                                                 │  ║
║   │  • Documentation                                                       │  ║
║   │  • Process improvements                                                │  ║
║   └────────────────────────────────────────────────────────────────────────┘  ║
║                                                                                ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

### Data Breach Notification

In accordance with GDPR Article 33:

| Notification | Timeline | Recipient |
|--------------|----------|-----------|
| **Supervisory Authority** | Within 72 hours | CNIL (France) |
| **Affected Data Subjects** | Without undue delay | Users (if high risk) |
| **Internal Stakeholders** | Immediately | Management, Legal |

---

## 9. Compliance Matrix

### Regulatory Compliance

| Regulation | Status | Key Controls |
|------------|--------|--------------|
| **🇪🇺 GDPR** | ✅ Compliant | Data residency, encryption, access controls, breach notification |
| **🇫🇷 CNIL Guidelines** | ✅ Compliant | French data protection authority requirements |
| **PCI DSS** | 🟡 Partial | Encryption, access control (if processing payments) |
| **SOC 2 Type II** | 🟡 Ready | Security controls in place, audit pending |
| **ISO 27001** | 🟡 Aligned | Controls aligned, certification pending |

### GDPR Compliance Details

| GDPR Article | Requirement | Implementation |
|--------------|-------------|----------------|
| **Art. 5** | Data Processing Principles | Documented purposes, minimal data collection |
| **Art. 17** | Right to Erasure | User deletion workflow implemented |
| **Art. 25** | Privacy by Design | Security controls built into infrastructure |
| **Art. 32** | Security of Processing | Encryption, access controls, monitoring |
| **Art. 33** | Breach Notification | Incident response procedures |
| **Art. 35** | DPIA | Risk assessment conducted |

### Security Controls Summary

| Control Domain | Controls Implemented |
|----------------|---------------------|
| **Access Control** | SSH key auth, bastion, geo-restriction, RBAC |
| **Cryptography** | TLS 1.3, AES-256, SSE-S3 |
| **Network Security** | Security groups, private networks, firewalls |
| **Logging & Monitoring** | Centralized logs, session recording, alerting |
| **Business Continuity** | Multi-AZ, HA clusters, cross-region backups |
| **Physical Security** | OVHcloud datacenter certifications |

---

## 10. Contact & Governance

### Data Protection Contacts

| Role | Responsibility | Contact |
|------|----------------|---------|
| **Data Protection Officer** | GDPR compliance oversight | dpo@potti.co |
| **Security Team** | Security incidents | security@potti.co |
| **Infrastructure Team** | Technical operations | infra@potti.co |

### Document Governance

| Attribute | Value |
|-----------|-------|
| **Document Owner** | Infrastructure Team |
| **Review Frequency** | Quarterly |
| **Next Review Date** | April 2026 |
| **Approval Authority** | CTO |

### Change History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | January 2026 | Infrastructure Team | Initial release |

---

## 📎 Appendices

### A. OVHcloud Certifications

OVHcloud maintains the following certifications for their infrastructure:

- ISO 27001 (Information Security)
- ISO 27017 (Cloud Security)
- ISO 27018 (Cloud Privacy)
- SOC 1 Type II
- SOC 2 Type II
- HDS (Health Data Hosting - France)
- PCI DSS

### B. Terraform Security Configuration

Key security configurations defined in Terraform:

```hcl
# Database deletion protection
deletion_protection = true

# Private network restrictions
ip_restrictions {
  ip = "10.101.0.0/16"  # Private network only
}

# S3 encryption
encryption_algorithm = "AES256"
versioning_enabled   = true

# Cross-region replication
replication_enabled = true
replication_region  = "GRA"
```

### C. French IP Ranges (Bastion Access)

SSH access to the bastion is restricted to French IP ranges:

| ISP | CIDR Ranges |
|-----|-------------|
| Orange France | 90.0.0.0/8, 86.192.0.0/11, 81.248.0.0/14 |
| Free (Iliad) | 82.64.0.0/11, 88.160.0.0/11, 78.192.0.0/11 |
| SFR | 92.128.0.0/10, 109.0.0.0/11 |
| Bouygues Telecom | 176.128.0.0/11, 89.80.0.0/12 |

---

<p align="center">
  <em>This document is maintained as part of the Potti Infrastructure repository.</em><br>
  <em>For questions or updates, contact the Infrastructure Team.</em>
</p>
