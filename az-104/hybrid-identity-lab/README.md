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
| Internet | Separate NAT adapter, outbound only: static `10.0.2.15`, no DNS servers, IPv4 only ([why](docs/troubleshooting.md)). No Bridged networking |

## Phases

| Phase | What | Status |
|---|---|---|
| [P1](docs/p1-onprem-ad.md) | On-prem AD: DC, DNS, UPN suffix, scripted users and groups | ✅ |
| [P2](docs/p2-sync.md) | Sync to Entra ID with Cloud Sync | ✅ |
| [P3](docs/p3-governance.md) | Azure governance: RG, tags, lock, RBAC, Policy | ✅ |
| [P4](docs/p4-python-audit.md) | Python audit: Microsoft Graph + Azure RBAC report | ✅ |

Problems hit along the way and how they were fixed: [troubleshooting](docs/troubleshooting.md)

## Design choices

- **Cloud Sync, not Connect Sync:** lighter agent, auto-updates, config lives in the cloud
- **`lab.internal`, not `.local`:** `.internal` is reserved for private use; `.local` clashes with mDNS
- **No purchased domain:** the tenant's `onmicrosoft.com` domain is already verified
- **NAT + internal network, no Bridged:** the lab is never reachable from the home network
- **Cloud-only `hiadmin` for sync admin:** Hybrid Identity Administrator that doesn't depend on
  on-prem AD, so sync stays manageable if my DC breaks. The signup account is an external Microsoft account and
  can’t run setup.
- **Sync scoped to `OU=Lab`, delete threshold 3:** only lab objects leave the domain, and the default
  of 500 would never trip at this scale
- **Password hash sync:** simplest sign-in method, works on Entra ID Free
- **Agent on the DC:** supported by Microsoft, but it makes the DC a sync server too. In a real setup,
  this would be a dedicated hardened server. This is for lab purposes
- **Roles to synced groups:** access follows on-prem group membership,
  so joiners and leavers are handled in AD.
- **Governance at resource-group scope:** the lock, the policy and the roles all apply to
  `rg-hybrid-lab` only, so nothing else in the subscription is affected.
- **No secrets in the audit script:** it signs in with `AzureCliCredential`, which borrows the
  `az login` session, so no app registration or client secret exists.