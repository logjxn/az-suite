# VNet Peering Lab

Two VNets with a Linux VM in each, no public IPs, built in one session in
Azure Cloud Shell using bash, alongside AZ-104 Learn. Shows how routing changes when VNets are
peered, and how an NSG rule blocks traffic that peering allows.

## Setup

| | |
|---|---|
| Region | `westus2` [why](docs/troubleshooting.md) |
| vnet-web | `10.10.0.0/16`, subnet `snet-web` `10.10.1.0/24`, `vm-web` at `10.10.1.4` |
| vnet-app | `10.20.0.0/16`, subnet `snet-app` `10.20.1.0/24`, `vm-app` at `10.20.1.4` |
| VMs | `Standard_B2ats_v2`, Ubuntu 24.04 |
| Access | Run Command only: no public IPs, no SSH, no Bastion |
| Outbound | None: private subnets (`defaultOutboundAccess = false`) |

## Steps

| Step | What | Result | Screenshot |
|---|---|---|---|
| 1 | Resource group with tags | `env=lab`, `project=vnet-peering` | [01](screenshots/01-rg-tags.png) |
| 2 | NSGs and VNets | Both subnets private | [02](screenshots/02-subnet-private.png) |
| 3 | VMs with no public IP | Private IPs only | [03](screenshots/03-vm-no-public-ip.png) |
| 4 | Web server on vm-app with Run Command | `active`: Run Command works in a private subnet | [04](screenshots/04-run-command-web.png) |
| 5 | curl before peering | Fails: `10.20.1.4` matches `10.0.0.0/8` → `None` | [05a](screenshots/05a-curl-fail.png), [05b](screenshots/05b-routes-before.png) |
| 6 | Peer both directions | `Connected`, curl works, `10.20.0.0/16` → `VNetPeering` | [06a](screenshots/06a-peering-connected.png), [06b](screenshots/06b-curl-ok.png), [06c](screenshots/06c-routes-after.png) |
| 7 | NSG deny on port 80 from snet-web | curl fails, IP flow verify: `Deny` by `deny-web-http` | [07a](screenshots/07a-nsg-deny-rule.png), [07b](screenshots/07b-ip-flow-verify.png) |

Build commands: [scripts/build-lab.sh](scripts/build-lab.sh).
Teardown: [scripts/teardown-lab.sh](scripts/teardown-lab.sh).
Problems hit along the way: [troubleshooting](docs/troubleshooting.md)

## Design choices

- **Private subnets:** nothing is reachable from the internet, and it matches
  the default for new VNets
- **Run Command:** no inbound ports at all
- **`python3 -m http.server` instead of nginx:** with no outbound access, `apt` can't install packages;
  Python ships with Ubuntu
- **NSGs on subnets (`--nsg ""`):** one NSG per subnet to manage
- **CLI-only screenshots via `--query`:** shorter output and no resource IDs, which contain
  the subscription ID