"""Audits the lab: synced users and Azure RBAC

Auth: borrows the Azure CLI sign-in through AzureCliCredential
No stored secrets

    az login --tenant <tenant>
    $env:AZURE_SUBSCRIPTION_ID = (az account show --query id -o tsv)

Usage:
    python audit_hybrid_identity.py
    python audit_hybrid_identity.py --save output/raw/audit.txt
"""

import argparse
import os
import sys
import uuid
from pathlib import Path

import requests
from azure.core.exceptions import ClientAuthenticationError
from azure.identity import AzureCliCredential, CredentialUnavailableError

GRAPH = "https://graph.microsoft.com"
ARM = "https://management.azure.com"
ARM_API = "2022-04-01"
RESOURCE_GROUP = "rg-hybrid-lab"
TIMEOUT = 30

USER_FIELDS = (
    "id,displayName,userPrincipalName,userType,accountEnabled,"
    "onPremisesSyncEnabled,onPremisesSamAccountName,"
    "onPremisesDistinguishedName,onPremisesDomainName"
)
MEMBER_FIELDS = "displayName,userType,accountEnabled,onPremisesSyncEnabled,onPremisesDomainName"


# Output 

_lines = []


def out(text=""):
    """Print a line and keep it for --save"""
    print(text)
    _lines.append(text)


# Auth helper 

credential = AzureCliCredential()
_subscription_id = ""


class ApiError(Exception):
    pass


def _redact(url):
    """Hide the subscription ID if a URL ends up in an error message"""
    if _subscription_id:
        return url.replace(_subscription_id, "{subscription}")
    return url


def _check(resp, method, url):
    if resp.ok:
        return
    try:
        err = resp.json().get("error", {})
        code, message = err.get("code", ""), err.get("message", "")
    except ValueError:
        code, message = "", resp.text[:200]
    raise ApiError(_redact(f"{method} {url}\n  HTTP {resp.status_code} {code}: {message}"))


def get(url, resource):
    token = credential.get_token(f"{resource}/.default").token
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url, headers=headers, timeout=TIMEOUT)
    _check(resp, "GET", url)
    return resp.json()


def post(url, resource, body):
    token = credential.get_token(f"{resource}/.default").token
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.post(url, headers=headers, json=body, timeout=TIMEOUT)
    _check(resp, "POST", url)
    return resp.json()


def get_all(url, resource):
    """GET every page"""
    items = []
    while url:
        page = get(url, resource)
        items.extend(page.get("value", []))
        url = page.get("@odata.nextLink") or page.get("nextLink")
    return items


# Subscription ID 

def read_subscription_id():
    value = os.environ.get("AZURE_SUBSCRIPTION_ID", "").strip()
    if not value:
        sys.exit(
            "AZURE_SUBSCRIPTION_ID is not set. Set it for this session:\n"
            "  $env:AZURE_SUBSCRIPTION_ID = (az account show --query id -o tsv)"
        )
    try:
        uuid.UUID(value)
    except ValueError:
        sys.exit("AZURE_SUBSCRIPTION_ID is not a GUID. Set it again with the command above.")
    return value


# Synced users 

def list_users():
    return get_all(f"{GRAPH}/v1.0/users?$select={USER_FIELDS}", GRAPH)


def report_synced_users(users):
    synced = [u for u in users if u.get("onPremisesSyncEnabled") is True]
    out(f"== Synced users ({len(synced)} of {len(users)} users in the tenant) ==")
    for u in sorted(synced, key=lambda u: u.get("displayName") or ""):
        out()
        out(u.get("displayName") or "(no display name)")
        for field in (
            "accountEnabled",
            "onPremisesSyncEnabled",
            "onPremisesSamAccountName",
            "onPremisesDomainName",
            "onPremisesDistinguishedName",
        ):
            out(f"  {field:<28} {u.get(field)}")
    if not synced:
        out("  (none)")
    out()


# RBAC report

def resolve_principals(ids):
    """Object ID -> directory object"""
    if not ids:
        return {}
    result = post(f"{GRAPH}/v1.0/directoryObjects/getByIds", GRAPH, {"ids": list(ids)})
    return {obj["id"]: obj for obj in result.get("value", [])}


_role_names = {}


def role_name(role_definition_id, rg_scope):
    """roleDefinitionId -> role name, cached."""
    if role_definition_id not in _role_names:
        try:
            data = get(f"{ARM}{role_definition_id}?api-version={ARM_API}", ARM)
        except ApiError as e:
            if "HTTP 403" not in str(e):
                raise
            # Reader on the RG only
            guid = role_definition_id.rstrip("/").split("/")[-1]
            url = f"{ARM}{rg_scope}/providers/Microsoft.Authorization/roleDefinitions/{guid}?api-version={ARM_API}"
            data = get(url, ARM)
        _role_names[role_definition_id] = data["properties"]["roleName"]
    return _role_names[role_definition_id]


def group_members(group_id):
    return get_all(f"{GRAPH}/v1.0/groups/{group_id}/members?$select={MEMBER_FIELDS}", GRAPH)


def describe_user(u):
    if u.get("onPremisesSyncEnabled") is True:
        tag = f"synced from {u.get('onPremisesDomainName') or 'on-prem'}"
    elif u.get("userType") == "Guest":
        tag = "guest"
    else:
        tag = "cloud-only"
    disabled = " [disabled]" if u.get("accountEnabled") is False else ""
    return f"{u.get('displayName')} ({tag}){disabled}"


def scope_label(scope, sub_id):
    """Turn a scope path into (section, label) without printing any IDs."""
    s = scope.lower().rstrip("/")
    sub = f"/subscriptions/{sub_id}".lower()
    rg = f"{sub}/resourcegroups/{RESOURCE_GROUP}".lower()
    if s == rg:
        return "at", RESOURCE_GROUP
    if s.startswith(rg + "/"):
        return "child", f"{RESOURCE_GROUP}/{scope.rstrip('/').split('/')[-1]}"
    if s == sub:
        return "inherited", "subscription"
    return "inherited", "other scope"

def report_rbac(sub_id, users_by_id):
    rg_scope = f"/subscriptions/{sub_id}/resourceGroups/{RESOURCE_GROUP}"
    url = f"{ARM}{rg_scope}/providers/Microsoft.Authorization/roleAssignments?api-version={ARM_API}"
    assignments = [a["properties"] for a in get_all(url, ARM)]

    principals = resolve_principals({a["principalId"] for a in assignments})
    members_cache = {}
    sections = {"at": [], "inherited": [], "child": []}

    for a in assignments:
        role = role_name(a["roleDefinitionId"], rg_scope)
        section, where = scope_label(a["scope"], sub_id)
        obj = principals.get(a["principalId"])
        kind = (obj or {}).get("@odata.type", "")

        if obj is None:
            sections[section].append(
                f"unknown {a.get('principalType', 'principal')} (deleted or not visible) → {role} → {where}"
            )
        elif kind == "#microsoft.graph.user":
            # getByIds returns few user fields, use the /users data for sync status
            user = users_by_id.get(obj["id"], obj)
            sections[section].append(f"{describe_user(user)} → {role} → {where}")
        elif kind == "#microsoft.graph.group":
            group = obj.get("displayName")
            if obj["id"] not in members_cache:
                members_cache[obj["id"]] = group_members(obj["id"])
            members = members_cache[obj["id"]]
            if not members:
                sections[section].append(f"(no members) → {role} via {group} → {where}")
            for m in members:
                if m.get("@odata.type") == "#microsoft.graph.group":
                    sections[section].append(
                        f"{m.get('displayName')} (nested group, not expanded) → {role} via {group} → {where}"
                    )
                else:
                    sections[section].append(f"{describe_user(m)} → {role} via {group} → {where}")
        elif kind == "#microsoft.graph.servicePrincipal":
            sections[section].append(f"{obj.get('displayName')} (service principal) → {role} → {where}")
        else:
            sections[section].append(f"{obj.get('displayName')} ({kind or 'object'}) → {role} → {where}")

    out(f"== RBAC on {RESOURCE_GROUP} ({len(assignments)} role assignments) ==")
    headings = {
        "at": f"Assigned at {RESOURCE_GROUP}",
        "inherited": "Inherited from above (applies to the RG too)",
        "child": f"Assigned on resources inside {RESOURCE_GROUP}",
    }
    for key in ("at", "inherited", "child"):
        out()
        out(f"-- {headings[key]} --")
        for line in sorted(sections[key]) or ["(none)"]:
            out(f"  {line}")
    out()


# Main 

def main():
    global _subscription_id
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--save", metavar="PATH", help="also write the report to this file (UTF-8)")
    args = parser.parse_args()

    # Windows consoles and redirects may not default to UTF-8
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    sub_id = read_subscription_id()
    _subscription_id = sub_id

    try:
        users = list_users()
        report_synced_users(users)
        report_rbac(sub_id, {u["id"]: u for u in users if "id" in u})
    except (CredentialUnavailableError, ClientAuthenticationError) as e:
        sys.exit(f"Azure CLI sign-in not available: {e}\nRun: az login --tenant logsazlaboutlook.onmicrosoft.com")
    except ApiError as e:
        if "HTTP 403" in str(e):
            sys.exit(f"Access denied. The CLI token or the role does not allow this call:\n{e}")
        sys.exit(f"API call failed:\n{e}")
    except requests.RequestException as e:
        sys.exit(f"Network error: {e.__class__.__name__}")

    if args.save:
        path = Path(args.save)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(_lines) + "\n", encoding="utf-8")
        print(f"Saved to {path}")


if __name__ == "__main__":
    main()
