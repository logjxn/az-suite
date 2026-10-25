#!/usr/bin/env bash
# Deletes everything build-lab.sh created.
# NetworkWatcherRG is deleted too: this subscription holds only this lab.
set -euo pipefail

az group delete -n rg-net-lab --yes
az group delete -n NetworkWatcherRG --yes
az group list -o table