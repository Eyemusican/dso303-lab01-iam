#!/usr/bin/env bash
# Lab 04 Exercise 3: ECS configuration drift report for every service in the cluster.
# Verdicts are computed from the service and its task definition, never from names or tags.
#
# set -e is deliberately NOT used. Some lookups can legitimately return nothing (for example a
# service with no networkConfiguration, like an EC2 launch type service). With -e, one empty or
# failing lookup would stop the report halfway and silently hide every service after it.
# Instead every value is checked, and missing data is printed explicitly as N/A.
set -uo pipefail
# Windows Git Bash: stop paths starting with / being rewritten.
export MSYS_NO_PATHCONV=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/configs/course.env"
source "$REPO_ROOT/configs/lab-04.env" 2>/dev/null || true
CLUSTER="${USMS_ECS_CLUSTER:-usms-ecs-cluster}"
OUT_JSON="$REPO_ROOT/outputs/lab-04-ecs-inventory.json"

# jq on Windows can add a hidden \r to each line, so strip it from every result.
jqr() { jq -r "$@" | tr -d '\r'; }

records="[]"
svc_arns=$(aws ecs list-services --cluster "$CLUSTER" --output json | jqr '.serviceArns[]')

if [ -z "$svc_arns" ]; then
  echo "no services found in $CLUSTER"
fi

for arn in $svc_arns; do
  svc=$(aws ecs describe-services --cluster "$CLUSTER" --services "$arn" --output json | tr -d '\r' | jq '.services[0]')
  name=$(jqr '.serviceName // "N/A"' <<< "$svc")
  desired=$(jqr '.desiredCount // "N/A"' <<< "$svc")
  running=$(jqr '.runningCount // "N/A"' <<< "$svc")
  td_arn=$(jqr '.taskDefinition // ""' <<< "$svc")
  assign=$(jqr '.networkConfiguration.awsvpcConfiguration.assignPublicIp // ""' <<< "$svc")

  case "$assign" in
    ENABLED)  publicip=RISK ;;
    DISABLED) publicip=OK ;;
    *)        publicip=N/A ;;
  esac

  taskdef=N/A; roles=N/A
  if [ -n "$td_arn" ]; then
    td=$(aws ecs describe-task-definition --task-definition "$td_arn" --output json 2>/dev/null | tr -d '\r' | jq '.taskDefinition')
    if [ -n "$td" ] && [ "$td" != "null" ]; then
      taskdef=$(jqr '"\(.family):\(.revision)"' <<< "$td")
      exec_role=$(jqr '.executionRoleArn // ""' <<< "$td")
      task_role=$(jqr '.taskRoleArn // ""' <<< "$td")
      if [ -z "$exec_role" ] || [ -z "$task_role" ]; then roles=N/A
      elif [ "$exec_role" = "$task_role" ]; then roles=SAME
      else roles=SEPARATE; fi
    fi
  fi

  printf '%-22s desired=%-3s running=%-3s taskdef=%-18s roles=%-9s publicip=%s\n' \
    "$name" "$desired" "$running" "$taskdef" "$roles" "$publicip"

  records=$(jq --arg n "$name" --arg d "$desired" --arg r "$running" --arg t "$taskdef" \
    --arg ro "$roles" --arg p "$publicip" \
    '. + [{service:$n, desired:$d, running:$r, taskdef:$t, roles:$ro, publicip:$p}]' <<< "$records" | tr -d '\r')
done

printf '%s\n' "$records" | jq '.' | tr -d '\r' > "$OUT_JSON"
