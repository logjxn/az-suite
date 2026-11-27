# Hybrid Identity Lab

An on-prem Active Directory domain in VirtualBox, synced to Microsoft Entra ID
with Entra Cloud Sync. Built phase by phase alongside AZ-104.

## Setup

| Aspect | Decision |
|---|---|
| Domain controller | `DC01`, Windows Server 2022 (Desktop Experience) |
| Forest / domain | `lab.internal` |
| UPN suffix | the tenant's `onmicrosoft.com` domain |
| Lab network | VirtualBox Internal Network `labnet`, `10.0.0.0/24` |
| Internet | Outbound only, no DNS servers, IPv4 only. No Bridged networking |

## Phases

| Phase | What |
|---|---|
| [P1](docs/p1-onprem-ad.md) | On-prem AD: DC, DNS, UPN suffix, scripted users and groups |
| [P2](docs/p2-sync.md) | Sync to Entra ID with Cloud Sync |
| [P3](docs/p3-governance.md) | Azure governance: RG, tags, lock, RBAC, Policy | 
| [P4](docs/p4-python-audit.md) | Python audit: Microsoft Graph + Azure RBAC report | 

## Design choices

- Used Cloud Sync. ran as a lighter agent, auto-updates, and its config lives in the cloud
- Didn't purchase a domain, as the tenant's `onmicrosoft.com` domain is already verified
- Used NAT + internal, so the lab is never reachable from the home network
- Hybrid Identity Administrator that doesn't depend on on-prem AD, so sync stays manageable if my DC breaks
- Set up a sync scope and delete threshold, limited to the lab OU, with a threshold of 3 to catch unexpected deletions at this lab's scale
- Used password hash sync, it's a simple sign-in method, works on Entra ID Free
- Access follows on-prem group membership, so joiners and leavers are handled in AD.
- Focused governance on RG scope. Lock, policy and role assignments all apply to `rg-hybrid-lab` only, so nothing else in the subscription is affected
- No secrets in any script, as they use `AzureCliCredential` and the existing `az login` session
