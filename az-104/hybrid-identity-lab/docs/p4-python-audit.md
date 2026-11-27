# P4: Python Audit

**Goal:** one report that shows who has access to `rg-hybrid-lab`, where each identity
comes from (synced from AD or cloud-only), and whether the access is direct or through a group.

## How it signs in

- The script uses `AzureCliCredential`, which borrows the `az login` session.
- Runs as `hiadmin` with Reader on `rg-hybrid-lab` only. Directory reads use the default
  member rights in Entra. Resource reads use an Azure RBAC role.

![hiadmin with Reader on the resource group](../screenshots/p4-python-audit/p4-01-hiadmin-reader.png)

## What it does

1. Lists users from Microsoft Graph with `$select` for the `onPremises*` fields, and keeps the ones synced from `lab.internal`.
2. Lists assignments on the rg from ARM, including inherited ones and ones on resources inside.
3. Resolves in one `getByIds` call, looks up role names, and expands group members.
4. Groups the results by scope, no object, tenant, or subscription IDs are printed.

![RBAC report](../screenshots/p4-python-audit/p4-03-rbac-report.png)

![Synced users](../screenshots/p4-python-audit/p4-02-synced-users.png)

Full run: [output/audit.txt](../output/audit.txt)

## My checks

- The report matches what P3 created.
- No secret in the source ([screenshot](../screenshots/p4-python-audit/p4-04-source-in-editor.png)).
- The first run showed the group with no members. See [troubleshooting](troubleshooting.md).
