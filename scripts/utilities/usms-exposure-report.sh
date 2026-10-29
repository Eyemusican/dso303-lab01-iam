#!/usr/bin/env bash
# USMS exposure report. One line per network interface in usms-vpc:
#   name, private IP, public IP, verdict, reason.
# The verdict is COMPUTED from three facts about the interface and nothing else:
#   1. does its subnet's route table send 0.0.0.0/0 to an internet gateway
#   2. does it have a public address
#   3. what its security groups admit from 0.0.0.0/0
# Never from names, tags or descriptions (those are only used to LABEL a line).
#
# Read-only. Runs from any directory, takes no arguments, hard-codes no IDs.
#
# set -uo pipefail but NOT -e, on purpose: one interface whose lookup fails (a lingering
# interface of a terminated instance, a group that was deleted) must not stop the report
# for every other interface. Each lookup has its own fallback instead.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
# shellcheck disable=SC1090
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true
# shellcheck disable=SC1090
source "$REPO_ROOT/configs/lab-02.env" 2>/dev/null || true

VPC="${USMS_VPC_ID:-}"
if [ -z "$VPC" ]; then
  VPC=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=usms-vpc" \
          --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
fi
[ -n "$VPC" ] && [ "$VPC" != "None" ] || { echo "cannot find usms-vpc" >&2; exit 2; }

python3 - "$VPC" "outputs/lab-09-exposure.json" << 'PY'
import json, subprocess, sys

vpc, out_path = sys.argv[1], sys.argv[2]

def aws(*args):
    r = subprocess.run(["aws", *args, "--output", "json"], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        return {}
    try:
        return json.loads(r.stdout)
    except ValueError:
        return {}

vf = ["--filters", f"Name=vpc-id,Values={vpc}"]
enis    = aws("ec2", "describe-network-interfaces", *vf).get("NetworkInterfaces", [])
groups  = {g["GroupId"]: g for g in aws("ec2", "describe-security-groups", *vf).get("SecurityGroups", [])}
rtables = aws("ec2", "describe-route-tables", *vf).get("RouteTables", [])
names   = {}
for res in aws("ec2", "describe-instances", *vf).get("Reservations", []):
    for i in res.get("Instances", []):
        tags = {t["Key"]: t["Value"] for t in i.get("Tags", [])}
        names[i["InstanceId"]] = (tags.get("Name", i["InstanceId"]), i.get("State", {}).get("Name", "?"))

# subnet -> route table; a subnet with no explicit association uses the VPC's main table
by_subnet, main_rt = {}, None
for rt in rtables:
    for a in rt.get("Associations", []):
        if a.get("Main"):
            main_rt = rt
        elif a.get("SubnetId"):
            by_subnet[a["SubnetId"]] = rt

def igw_route(subnet):
    rt = by_subnet.get(subnet, main_rt)
    if not rt:
        return False, "no route table found"
    for r in rt.get("Routes", []):
        if r.get("DestinationCidrBlock") == "0.0.0.0/0" and str(r.get("GatewayId", "")).startswith("igw-"):
            return True, ""
    return False, ""

def group(gid):
    if gid not in groups:                       # not in the VPC listing: fetch it on its own
        g = aws("ec2", "describe-security-groups", "--group-ids", gid).get("SecurityGroups", [])
        groups[gid] = g[0] if g else None
    return groups[gid]

def open_ports(gids):
    """Ports the groups admit from 0.0.0.0/0, and whether they have ANY ingress rule."""
    ports, any_rule, unknown = [], False, []
    for gid in gids:
        g = group(gid)
        if g is None:
            unknown.append(gid)
            continue
        for p in g.get("IpPermissions", []):
            any_rule = True
            if any(r.get("CidrIp") == "0.0.0.0/0" for r in p.get("IpRanges", [])):
                lo = p.get("FromPort")
                ports.append("all" if lo is None else str(lo))
    return ports, any_rule, unknown

rows = []
for e in enis:
    att = e.get("Attachment") or {}
    iid = att.get("InstanceId")
    if iid and iid in names:
        label = names[iid][0] + ("" if names[iid][1] != "terminated" else " (terminated)")
    elif iid:
        label = f"{iid} (instance gone)"
    else:
        label = e.get("Description") or e.get("InterfaceType") or e["NetworkInterfaceId"]
    private = e.get("PrivateIpAddress", "-")
    public = (e.get("Association") or {}).get("PublicIp")
    gids = [g["GroupId"] for g in e.get("Groups", [])]
    igw, rt_note = igw_route(e.get("SubnetId", ""))
    ports, any_rule, unknown = open_ports(gids)

    if not igw:
        verdict, why = "ISOLATED", rt_note or "no igw route on subnet"
    elif not public:
        verdict, why = "NO-ADDRESS", "igw route, but no public address to send to"
    elif ports:
        verdict, why = "EXPOSED", f"igw route + public address + sg allows {','.join(ports)} from 0.0.0.0/0"
    elif not gids or not any_rule:
        # Decision: a public address on a public subnet with no ingress rule is not EXPOSED,
        # because nothing admits a new connection, but it is one rule away from it.
        verdict, why = "ADDRESSABLE", "igw route + public address, but no ingress rule at all"
    else:
        verdict, why = "RESTRICTED", "igw route + public address, sg admits only named sources"
    if unknown:
        why += f" (could not read {','.join(unknown)})"
    rows.append({"name": label, "interface": e["NetworkInterfaceId"], "subnet": e.get("SubnetId"),
                 "private": private, "public": public, "groups": gids,
                 "verdict": verdict, "reason": why})

for r in sorted(rows, key=lambda x: (x["verdict"], x["name"])):
    print(f"{r['name'][:24]:<24} {r['private']:<15} {(r['public'] or '-'):<15} {r['verdict']:<12} {r['reason']}")
print()
print(f"interfaces={len(rows)}  " + "  ".join(
    f"{v}={sum(1 for r in rows if r['verdict'] == v)}"
    for v in ("EXPOSED", "ADDRESSABLE", "RESTRICTED", "NO-ADDRESS", "ISOLATED")))
json.dump({"vpc": vpc, "interfaces": rows}, open(out_path, "w"), indent=2)
PY
