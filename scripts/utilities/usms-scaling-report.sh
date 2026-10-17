#!/usr/bin/env bash
# usms-scaling-report.sh - print the scaling decision table of every usms- ECS service.
# Read-only. Takes no arguments. Everything is discovered from the API; the only fixed
# string is the usms- prefix of the cluster name.
# Also writes the same data as JSON to outputs/lab-06-scaling-report.json.
#
# Why set -uo pipefail and NOT -e:
#   this is a report, not a change. Some calls are expected to fail on some builds
#   (describe-scheduled-actions is unsupported on my Floci, describe-scaling-activities
#   may be missing elsewhere). With -e the first such call would stop the report half way
#   with no output. Each AWS call is checked on its own inside the Python part instead,
#   and a failed call prints a labelled "unavailable" row rather than a blank one.
set -uo pipefail

# Resolve the repo from the script's own location so it works from any directory.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env"
export MSYS_NO_PATHCONV=1

python3 - <<'PY'
import json, subprocess

def aws(*args):
    """Run one AWS CLI call. Return parsed JSON, or None if the call failed."""
    r = subprocess.run(["aws", *args, "--output", "json"], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout) if r.stdout.strip() else {}
    except ValueError:
        return None

def num(v):
    """1000.0 -> 1000.0, 50 -> 50, None -> '?'"""
    return "?" if v is None else v

def signed(n):
    return f"{int(n):+d}"

def verdict(t, desired, n_policies):
    # Top to bottom, first match wins. The order goes from "cannot move at all" to
    # "can move freely":
    #   PINNED first: with min == max no policy, schedule or switch can change anything,
    #     so every other state is irrelevant.
    #   FROZEN before AT-CEILING: a suspended target is the hazard nobody sees (policies and
    #     alarms look normal). AT-CEILING is visible on any graph and may be fine; a frozen
    #     target at the ceiling is still frozen, and that is the thing someone must act on.
    #   AT-CEILING before AT-FLOOR: running out of room upward is an outage risk, sitting
    #     on the floor is normal for a quiet service.
    #   AT-FLOOR only with more than one policy, because one policy at the floor says
    #     nothing about a disagreement between policies.
    lo, hi = t.get("MinCapacity"), t.get("MaxCapacity")
    s = t.get("SuspendedState") or {}
    if lo is not None and lo == hi:
        return "PINNED"
    if any(s.get(k) is True for k in ("DynamicScalingInSuspended",
                                      "DynamicScalingOutSuspended",
                                      "ScheduledScalingSuspended")):
        return "FROZEN"
    if desired is not None and desired == hi:
        return "AT-CEILING"
    if desired is not None and desired == lo and n_policies > 1:
        return "AT-FLOOR"
    return "ELASTIC"

def short_metric(m):
    names = {"ECSServiceAverageCPUUtilization": "CPU",
             "ECSServiceAverageMemoryUtilization": "Memory",
             "ALBRequestCountPerTarget": "ALBReq"}
    return names.get(m, m or "custom")

def alarm_states(names):
    """One batched describe-alarms call for several alarm names."""
    if not names:
        return {}
    d = aws("cloudwatch", "describe-alarms", "--alarm-names", *names)
    return {a["AlarmName"]: a for a in (d or {}).get("MetricAlarms", [])}

targets = aws("application-autoscaling", "describe-scalable-targets", "--service-namespace", "ecs")
if targets is None:
    print("could not list scalable targets - is Floci up and the profile loaded?")
    raise SystemExit(1)

mine = [t for t in targets.get("ScalableTargets", [])
        if t.get("ResourceId", "").split("/")[1:2] and t["ResourceId"].split("/")[1].startswith("usms-")]
if not mine:
    print("no scalable targets on a usms- cluster")

report = []
for t in sorted(mine, key=lambda x: x["ResourceId"]):
    rid, dim = t["ResourceId"], t["ScalableDimension"]
    _, cluster, service = rid.split("/", 2)

    svc = aws("ecs", "describe-services", "--cluster", cluster, "--services", service)
    s0 = (svc or {}).get("services", [{}])
    s0 = s0[0] if s0 else {}
    desired, running = s0.get("desiredCount"), s0.get("runningCount")

    pols = aws("application-autoscaling", "describe-scaling-policies",
               "--service-namespace", "ecs", "--resource-id", rid)
    policies = sorted((pols or {}).get("ScalingPolicies", []), key=lambda p: p["PolicyName"])

    v = verdict(t, desired, len(policies))
    entry = {"resourceId": rid, "dimension": dim, "min": t.get("MinCapacity"),
             "max": t.get("MaxCapacity"), "desired": desired, "running": running,
             "verdict": v, "suspended": [], "policies": [], "scheduled": [], "lastActivity": None}

    print(f"{rid}   {dim}")
    print(f"  bounds       min={t.get('MinCapacity')}  max={t.get('MaxCapacity')}   "
          f"desired={desired}   running={running}   {v}")

    sus = [k for k, val in (t.get("SuspendedState") or {}).items() if val is True]
    entry["suspended"] = sus
    print(f"  suspended    {', '.join(sus) if sus else 'none'}")

    if pols is None:
        print("  policies     unavailable (describe-scaling-policies failed)")
    elif not policies:
        print("  policies     none")

    # Batch every alarm name across all policies, plus each step policy's own alarm(s).
    tt_alarm_names = [a["AlarmName"] for p in policies for a in (p.get("Alarms") or [])]
    step_arns = {p["PolicyARN"] for p in policies if p.get("PolicyType") == "StepScaling"}
    all_alarms = aws("cloudwatch", "describe-alarms") or {}
    step_alarms = {}
    for a in all_alarms.get("MetricAlarms", []):
        for act in a.get("AlarmActions") or []:
            if act in step_arns:
                step_alarms.setdefault(act, []).append(a)
    states = alarm_states(tt_alarm_names)

    for p in policies:
        name, ptype = p["PolicyName"], p.get("PolicyType")
        pe = {"name": name, "type": ptype}
        if ptype == "TargetTrackingScaling":
            c = p.get("TargetTrackingScalingPolicyConfiguration") or {}
            m = short_metric((c.get("PredefinedMetricSpecification") or {}).get("PredefinedMetricType"))
            flag = "  scale-in OFF" if c.get("DisableScaleIn") else ""
            print(f"  target-track {name:<40} {m}/{num(c.get('TargetValue'))}   "
                  f"out={c.get('ScaleOutCooldown', '?')}  in={c.get('ScaleInCooldown', '?')}{flag}")
            parts = []
            for a in p.get("Alarms") or []:
                an = a["AlarmName"]
                kind = "AlarmHigh" if "AlarmHigh" in an else "AlarmLow" if "AlarmLow" in an else an
                parts.append(f"{kind}={states.get(an, {}).get('StateValue', 'unknown')}")
            print(f"                 alarms  {'  '.join(parts) if parts else 'none listed'}")
            pe.update({"metric": m, "target": c.get("TargetValue"), "alarms": parts})
        elif ptype == "StepScaling":
            c = p.get("StepScalingPolicyConfiguration") or {}
            adj = " / ".join(signed(s["ScalingAdjustment"]) for s in c.get("StepAdjustments", []))
            print(f"  step         {name:<40} {adj or '(no steps)'}   cooldown={c.get('Cooldown', '?')}")
            found = step_alarms.get(p["PolicyARN"], [])
            if not found:
                print("                 alarm   none points at this policy")
            for a in found:
                op = {"GreaterThanOrEqualToThreshold": ">=", "GreaterThanThreshold": ">",
                      "LessThanThreshold": "<", "LessThanOrEqualToThreshold": "<="}.get(
                          a.get("ComparisonOperator"), a.get("ComparisonOperator"))
                print(f"                 alarm   {a['AlarmName']} = {a.get('StateValue')}  "
                      f"({a.get('Namespace')} {a.get('MetricName')} {op} {num(a.get('Threshold'))})")
            pe.update({"steps": adj, "alarms": [a["AlarmName"] for a in found]})
        else:
            print(f"  {ptype or 'policy':<12} {name}")
        entry["policies"].append(pe)

    sch = aws("application-autoscaling", "describe-scheduled-actions",
              "--service-namespace", "ecs", "--resource-id", rid)
    if sch is None:
        print("  scheduled    unavailable (describe-scheduled-actions not supported on this build)")
        entry["scheduled"] = "unavailable"
    elif not sch.get("ScheduledActions"):
        print("  scheduled    none")
    else:
        for a in sorted(sch["ScheduledActions"], key=lambda x: x["ScheduledActionName"]):
            sta = a.get("ScalableTargetAction") or {}
            print(f"  scheduled    {a['ScheduledActionName']:<34} {a.get('Schedule')}  "
                  f"{a.get('Timezone') or 'UTC'}  min={sta.get('MinCapacity', '-')}")
            entry["scheduled"].append(a["ScheduledActionName"])

    act = aws("application-autoscaling", "describe-scaling-activities",
              "--service-namespace", "ecs", "--resource-id", rid, "--max-items", "1")
    if act is None:
        print("  last activity  unavailable (describe-scaling-activities not supported)")
    elif not act.get("ScalingActivities"):
        print("  last activity  none recorded")
    else:
        a = act["ScalingActivities"][0]
        print(f"  last activity  {a.get('StartTime')}  {a.get('StatusCode')}  {a.get('Description')}")
        entry["lastActivity"] = {"start": a.get("StartTime"), "status": a.get("StatusCode"),
                                 "description": a.get("Description")}
    print()
    report.append(entry)

with open("outputs/lab-06-scaling-report.json", "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2, default=str)
PY
