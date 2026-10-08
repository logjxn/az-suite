# Hybrid Identity Lab

An on-prem Active Directory domain in VirtualBox, synced to Microsoft Entra ID
with Entra Cloud Sync. Built phase by phase alongside AZ-104.

## Setup

| | |
|---|---|
| Domain controller | `DC01`, Windows Server 2022 (Desktop Experience) |
| Forest / domain | `lab.internal` |
| UPN suffix | the tenant's `onmicrosoft.com` domain |
| Lab network | VirtualBox Internal Network `labnet`, `10.0.0.0/24` |
| Internet | Separate NAT adapter, outbound only. No Bridged networking |

## Phases

| Phase | What | Status |
|---|---|---|
| [P1](docs/p1-onprem-ad.md) | On-prem AD: DC, DNS, UPN suffix, scripted users and groups | ✅ |
| P2 | Sync to Entra ID with Cloud Sync | ⏳ next |
| P3 | Azure governance: RG, tags, lock, RBAC, Policy | |
| P4 | Python audit: Microsoft Graph + Azure RBAC report | |
| P5 | Source of authority: synced user → cloud-managed | |
| P6 | Domain-joined Windows 11 client + Group Policy | |

Problems hit along the way and how they were fixed: [troubleshooting](docs/troubleshooting.md)

## Design choices

- **Cloud Sync, not Connect Sync:** lighter agent, auto-updates, config lives in the cloud
- **`lab.internal`, not `.local`:** `.internal` is reserved for private use; `.local` clashes with mDNS
- **No purchased domain:** the tenant's `onmicrosoft.com` domain is already verified
- **NAT + internal network, no Bridged:** the lab is never reachable from the home network
