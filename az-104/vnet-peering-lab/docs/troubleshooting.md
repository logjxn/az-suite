## 2026-10-24: VM sizes not available for this subscription

**Issue:** `az vm create` failed with `SkuNotAvailable` in `eastus` for multiple SKUs.

**Cause:** subscription-level restriction.
`az vm list-skus --all` showed every B-series size as `NotAvailableForSubscription` in my region.

**How I fixed it:** re-created the NSGs and VNets in `westus2`, and created
the VMs without `--zone`. The resource group stays in `eastus`, as it doesn't
limit where the resources can deploy.

**Checked:** both VMs created in `westus2` (`10.10.1.4` and `10.20.1.4`).

![SKU restrictions](../screenshots/ts-01-sku-restrictions.png)
