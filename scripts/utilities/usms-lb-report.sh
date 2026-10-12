#!/usr/bin/env bash
# usms-lb-report.sh - print the full decision table of every usms- Application Load Balancer.
# Read-only. Takes no arguments. Everything is discovered from the API, nothing is hard-coded
# except the usms- name prefix.
# Also writes the same data as JSON to outputs/lab-05-lb-report.json.
#
# Why set -uo pipefail and NOT -e:
#   this is a report, not a change. If one describe call fails (a target group deleted while
#   the report runs, a listener with no rules) the right behaviour is to print what failed on
#   that row and carry on with the rest, not to stop half way with no output. Each AWS call is
#   checked individually inside the Python part instead.
set -uo pipefail

# Resolve the repo from the script's own location so it works from any directory.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env"
export MSYS_NO_PATHCONV=1

# Four levels of nesting (load balancer -> listener -> rule -> target group) are easier to
# get right in Python than in nested bash loops, so bash stops here and Python calls the
# AWS CLI with --output json at each level and does the formatting.
python3 - <<'PY'
import json, subprocess, sys

def aws(*args):
    """Run one AWS CLI call and return parsed JSON, or None if the call failed."""
    r = subprocess.run(["aws", *args, "--output", "json"], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout) if r.stdout.strip() else {}
    except ValueError:
        return None

tg_cache = {}
def tg_summary(arn):
    """Name, total targets and healthy targets for one target group, cached."""
    if arn in tg_cache:
        return tg_cache[arn]
    d = aws("elbv2", "describe-target-groups", "--target-group-arns", arn)
    name = d["TargetGroups"][0]["TargetGroupName"] if d and d.get("TargetGroups") else arn.split("/")[-2]
    h = aws("elbv2", "describe-target-health", "--target-group-arn", arn)
    descs = (h or {}).get("TargetHealthDescriptions", [])
    healthy = sum(1 for t in descs if t.get("TargetHealth", {}).get("State") == "healthy")
    tg_cache[arn] = {"name": name, "targets": len(descs), "healthy": healthy}
    return tg_cache[arn]

def action_summary(actions):
    """One line per action type. A non-forward action prints its own summary."""
    if not actions:
        return "(no action)"
    a = sorted(actions, key=lambda x: x.get("Order", 0))[-1]   # the terminal action
    t = a.get("Type")
    if t == "forward":
        arns = []
        if a.get("TargetGroupArn"):
            arns.append(a["TargetGroupArn"])
        for g in (a.get("ForwardConfig") or {}).get("TargetGroups", []):
            if g.get("TargetGroupArn") and g["TargetGroupArn"] not in arns:
                arns.append(g["TargetGroupArn"])
        parts = []
        for arn in arns:
            s = tg_summary(arn)
            parts.append(f"{s['name']} ({s['targets']} targets, {s['healthy']} healthy)")
        return " + ".join(parts) if parts else "forward (no target group)"
    if t == "fixed-response":
        c = a.get("FixedResponseConfig") or {}
        return f"fixed-response {c.get('StatusCode', '?')}"
    if t == "redirect":
        c = a.get("RedirectConfig") or {}
        return f"redirect {c.get('StatusCode', '?')} to {c.get('Protocol', '#{protocol}')}://{c.get('Host', '#{host}')}{c.get('Path', '#{path}')}"
    return t or "(unknown action)"

def condition_summary(conds):
    """Field name and its values, for any condition type."""
    if not conds:
        return "-", ""
    c = conds[0]
    field = c.get("Field", "?")
    values = list(c.get("Values") or [])
    if not values:
        # Floci (and newer AWS responses) keep the values only inside <Field>Config.Values
        for k, v in c.items():
            if k.endswith("Config") and isinstance(v, dict) and v.get("Values"):
                values = list(v["Values"])
                break
    return field, ",".join(values)

def rule_order(rule):
    # Priority is a STRING, and the default action's priority is the literal word "default".
    # Sorting the raw strings would be alphabetical ("10" < "5"), so numbers are sorted as
    # integers and "default" is forced last, because that is the order the listener evaluates.
    p = rule.get("Priority", "default")
    return (1, 0) if rule.get("IsDefault") or p == "default" else (0, int(p))

lbs = aws("elbv2", "describe-load-balancers",
          "--query", "LoadBalancers[?Type=='application' && starts_with(LoadBalancerName, 'usms-')]")
if lbs is None:
    print("could not list load balancers - is Floci up and the profile loaded?")
    sys.exit(1)

report = []
if not lbs:
    print("no Application Load Balancers whose name starts with usms-")

for lb in sorted(lbs, key=lambda x: x["LoadBalancerName"]):
    entry = {
        "name": lb["LoadBalancerName"], "scheme": lb.get("Scheme"), "type": lb.get("Type"),
        "state": (lb.get("State") or {}).get("Code"),
        "azs": len(lb.get("AvailabilityZones") or []), "sgs": len(lb.get("SecurityGroups") or []),
        "listeners": [],
    }
    print(f"{entry['name']:<20} {entry['scheme']}  {entry['type']}  {entry['state']}  AZs={entry['azs']}  SGs={entry['sgs']}")

    ls = aws("elbv2", "describe-listeners", "--load-balancer-arn", lb["LoadBalancerArn"])
    listeners = (ls or {}).get("Listeners", [])
    if not listeners:
        print("  (no listeners - this load balancer answers nothing)")
    for lst in sorted(listeners, key=lambda x: x.get("Port", 0)):
        print(f"  {lst.get('Protocol')}:{lst.get('Port')}")
        lentry = {"protocol": lst.get("Protocol"), "port": lst.get("Port"), "rules": []}
        rs = aws("elbv2", "describe-rules", "--listener-arn", lst["ListenerArn"])
        rules = (rs or {}).get("Rules", [])
        if rs is None:
            print("    (describe-rules failed for this listener)")
        for r in sorted(rules, key=rule_order):
            field, values = condition_summary(r.get("Conditions"))
            outcome = action_summary(r.get("Actions"))
            prio = "default" if rule_order(r)[0] == 1 else r.get("Priority")
            print(f"    prio  {prio:<8} {field:<13} {values:<28} -> {outcome}")
            lentry["rules"].append({"priority": prio, "field": field, "values": values, "outcome": outcome})
        entry["listeners"].append(lentry)
    report.append(entry)

with open("outputs/lab-05-lb-report.json", "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
PY
