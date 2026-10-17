#!/usr/bin/env bash
# usms-scaling-history.sh - export the enrolment service's complete scaling configuration
# and history as ONE JSON document: outputs/lab-06-scaling-history.json
# Read-only. No arguments. Every identifier is discovered from the API: the resource ID
# comes from the ECS service ARN, the policies and alarms from describe calls.
# Later labs (Lab 10 first) can call this unchanged.
#
# set -uo pipefail and not -e: on some builds one section (scheduled actions on my Floci)
# is unsupported. That section is recorded as {"unavailable": "<error>"} instead of
# aborting the whole export.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env"
export MSYS_NO_PATHCONV=1

python3 - <<'PY'
import datetime, json, subprocess

def aws(*args):
    """Return (parsed JSON, None) on success or (None, error text) on failure."""
    r = subprocess.run(["aws", *args, "--output", "json"], capture_output=True, text=True)
    if r.returncode != 0:
        return None, (r.stderr.strip().splitlines() or ["exit %d" % r.returncode])[-1]
    try:
        return (json.loads(r.stdout) if r.stdout.strip() else {}), None
    except ValueError as e:
        return None, str(e)

def section(data, err, key):
    return data.get(key, []) if data is not None else {"unavailable": err}

# The only fixed strings: the usms- prefix and the enrolment service's name fragment.
clusters, err = aws("ecs", "list-clusters")
cluster_arn = next((c for c in (clusters or {}).get("clusterArns", [])
                    if c.split("/")[-1].startswith("usms-")), None)
if not cluster_arn:
    raise SystemExit("no usms- cluster found")
services, err = aws("ecs", "list-services", "--cluster", cluster_arn)
svc_arn = next((s for s in (services or {}).get("serviceArns", []) if "enrolment" in s.split("/")[-1]), None)
if not svc_arn:
    raise SystemExit("no enrolment service found in " + cluster_arn)

rid = svc_arn.split(":")[-1]               # service/<cluster>/<service>, derived from the ARN
if rid.count("/") == 1:                    # old-format ARN without the cluster name
    rid = "service/%s/%s" % (cluster_arn.split("/")[-1], rid.split("/")[-1])

tg, e1 = aws("application-autoscaling", "describe-scalable-targets",
             "--service-namespace", "ecs", "--resource-ids", rid)
pol, e2 = aws("application-autoscaling", "describe-scaling-policies",
              "--service-namespace", "ecs", "--resource-id", rid)
sch, e3 = aws("application-autoscaling", "describe-scheduled-actions",
              "--service-namespace", "ecs", "--resource-id", rid)
act, e4 = aws("application-autoscaling", "describe-scaling-activities",
              "--service-namespace", "ecs", "--resource-id", rid,
              "--include-not-scaled-activities")
if act is None:                            # builds that do not know the flag
    act, e4 = aws("application-autoscaling", "describe-scaling-activities",
                  "--service-namespace", "ecs", "--resource-id", rid)

policies = section(pol, e2, "ScalingPolicies")
policy_arns = {p["PolicyARN"] for p in policies} if isinstance(policies, list) else set()

# Every alarm involved: the managed ones each target tracking policy lists, plus any alarm
# whose AlarmActions names one of this target's policies (the step policy's own alarm).
alarms_all, e5 = aws("cloudwatch", "describe-alarms")
involved = []
if alarms_all is not None:
    listed = {a["AlarmName"] for p in (policies if isinstance(policies, list) else [])
              for a in (p.get("Alarms") or [])}
    for a in alarms_all.get("MetricAlarms", []):
        if a["AlarmName"] in listed or policy_arns.intersection(a.get("AlarmActions") or []):
            involved.append(a)

doc = {
    "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "resourceId": rid,
    "serviceArn": svc_arn,
    "scalableTarget": (section(tg, e1, "ScalableTargets") or [None])[0]
                      if tg is not None else {"unavailable": e1},
    "scalingPolicies": policies,
    "scheduledActions": section(sch, e3, "ScheduledActions"),
    "alarms": involved if alarms_all is not None else {"unavailable": e5},
    "scalingActivities": section(act, e4, "ScalingActivities"),
}

with open("outputs/lab-06-scaling-history.json", "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, default=str)

print("resourceId        ", rid)
print("policies          ", len(policies) if isinstance(policies, list) else policies)
print("scheduled actions ", len(doc["scheduledActions"]) if isinstance(doc["scheduledActions"], list) else doc["scheduledActions"])
print("alarms            ", len(involved))
print("activities        ", len(doc["scalingActivities"]) if isinstance(doc["scalingActivities"], list) else doc["scalingActivities"])
print("written           ", "outputs/lab-06-scaling-history.json")
PY
