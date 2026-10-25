#!/usr/bin/env bash
# Builds the vnet-peering-lab. Run in Azure Cloud Shell (Bash).
set -euo pipefail

RG=rg-net-lab
RG_LOC=eastus          # resource group metadata only
LOC=westus2            # where the resources go
SIZE=Standard_B2ats_v2
IMAGE=Ubuntu2404

# Run a shell command on a VM and print only stdout/stderr
rc() {
  az vm run-command invoke -g "$RG" -n "$1" --command-id RunShellScript \
    --scripts "$2" --query "value[0].message" -o tsv
}

# vm-web's effective routes
routes() {
  az network nic show-effective-route-table -g "$RG" -n vm-webVMNic \
    --query "value[?starts_with(addressPrefix[0], '10.') || nextHopType!='None'].{Source:source, Prefix:addressPrefix[0], NextHop:nextHopType}" \
    -o table
}

echo "== 1. Resource group"
az group create -n "$RG" -l "$RG_LOC" --tags env=lab project=vnet-peering -o none
az group show -n "$RG" \
  --query "{Name:name, Location:location, Env:tags.env, Project:tags.project}" -o table

echo "== 2. NSGs and VNets"
az network nsg create -g "$RG" -n nsg-web -l "$LOC" -o none
az network nsg create -g "$RG" -n nsg-app -l "$LOC" -o none

az network vnet create -g "$RG" -n vnet-web -l "$LOC" \
  --address-prefix 10.10.0.0/16 \
  --subnet-name snet-web --subnet-prefixes 10.10.1.0/24 \
  --network-security-group nsg-web -o none

az network vnet create -g "$RG" -n vnet-app -l "$LOC" \
  --address-prefix 10.20.0.0/16 \
  --subnet-name snet-app --subnet-prefixes 10.20.1.0/24 \
  --network-security-group nsg-app -o none

az network vnet list -g "$RG" \
  --query "[].{VNet:name, Subnet:subnets[0].name, Prefix:subnets[0].addressPrefix, DefaultOutbound:subnets[0].defaultOutboundAccess}" \
  -o table

echo "== 3. VMs (no public IP, no NIC-level NSG)"
for side in web app; do
  az vm create -g "$RG" -n "vm-$side" -l "$LOC" --image "$IMAGE" --size "$SIZE" \
    --vnet-name "vnet-$side" --subnet "snet-$side" \
    --public-ip-address "" --nsg "" \
    --admin-username azureuser --generate-ssh-keys -o none
done
az vm list-ip-addresses -g "$RG" -o table

WEB_IP=$(az vm list-ip-addresses -g "$RG" -n vm-web \
  --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)
APP_IP=$(az vm list-ip-addresses -g "$RG" -n vm-app \
  --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)

echo "== 4. Web server on vm-app (Run Command)"
rc vm-app "systemd-run --unit=web /usr/bin/python3 -m http.server 80 --directory /tmp"
rc vm-app "systemctl is-active web"

echo "== 5. Before peering: expect CURL_FAILED and no 10.20.0.0/16 route"
rc vm-web "curl -s -m 5 http://$APP_IP || echo CURL_FAILED"
routes

echo "== 6. Peer both directions: expect Connected, HTML, VNetPeering route"
az network vnet peering create -g "$RG" -n web-to-app \
  --vnet-name vnet-web --remote-vnet vnet-app --allow-vnet-access -o none
az network vnet peering create -g "$RG" -n app-to-web \
  --vnet-name vnet-app --remote-vnet vnet-web --allow-vnet-access -o none

for v in vnet-web vnet-app; do
  az network vnet peering list -g "$RG" --vnet-name "$v" \
    --query "[].{Name:name, State:peeringState, Sync:peeringSyncLevel}" -o table
done
rc vm-web "curl -s -m 5 http://$APP_IP | head -5"
routes

echo "== 7. NSG deny: expect CURL_FAILED and Deny by deny-web-http"
az network nsg rule create -g "$RG" --nsg-name nsg-app -n deny-web-http \
  --priority 100 --direction Inbound --access Deny --protocol Tcp \
  --source-address-prefixes 10.10.1.0/24 --destination-port-ranges 80 -o none

az network nsg rule list -g "$RG" --nsg-name nsg-app --include-default \
  --query "[?direction=='Inbound'].{Name:name, Priority:priority, Source:sourceAddressPrefix, Port:destinationPortRange, Access:access}" \
  -o table
rc vm-web "curl -s -m 5 http://$APP_IP || echo CURL_FAILED"
az network watcher test-ip-flow -g "$RG" --vm vm-app --direction Inbound \
  --protocol TCP --local "$APP_IP:80" --remote "$WEB_IP:60000" -o table

echo "== Done. Run teardown-lab.sh when finished."