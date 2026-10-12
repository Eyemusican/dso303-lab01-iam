#!/usr/bin/env bash
# usms-resource-label.sh - build the ALBRequestCountPerTarget ResourceLabel from the API.
# Usage: usms-resource-label.sh [load-balancer-name] [target-group-name]
#        defaults: usms-enrolment-alb usms-enrolment-tg
# Read-only. Prints the label and exits 0, or prints a reason and exits 1.
# It deliberately does NOT read configs/lab-05.env for the ARNs: the point is deriving them,
# and a script that reads the answer from a file it helped write proves nothing.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/configs/course.env"

LB_NAME="${1:-usms-enrolment-alb}"
TG_NAME="${2:-usms-enrolment-tg}"

LB_ARN=$(aws elbv2 describe-load-balancers --names "$LB_NAME" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
TG_ARN=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)

case "$LB_ARN" in arn:*:loadbalancer/app/*) ;; *) echo "no application load balancer named $LB_NAME" >&2; exit 1 ;; esac
case "$TG_ARN" in arn:*:targetgroup/*)        ;; *) echo "no target group named $TG_NAME" >&2; exit 1 ;; esac

# The two suffixes are cut differently, and that is how AWS specifies ResourceLabel:
#   load balancer ARN  ...:loadbalancer/app/usms-enrolment-alb/7ebb...
#     -> the label wants what comes AFTER "loadbalancer/", so the word loadbalancer is dropped:
#        remove the shortest prefix up to and including ":loadbalancer/"   (${var#pattern})
#   target group ARN   ...:targetgroup/usms-enrolment-tg/25e7...
#     -> the label KEEPS the word "targetgroup", so only cut up to the last colon:
#        remove the longest prefix ending in ":"                           (${var##pattern})
LB_SUFFIX="${LB_ARN#*:loadbalancer/}"
TG_SUFFIX="${TG_ARN##*:}"
LABEL="${LB_SUFFIX}/${TG_SUFFIX}"

# Validate before printing: both names present, exactly six segments, first segment "app".
IFS='/' read -r -a SEG <<< "$LABEL"
if [ "${#SEG[@]}" -ne 6 ] || [ "${SEG[0]}" != "app" ] || [ "${SEG[1]}" != "$LB_NAME" ] \
   || [ "${SEG[3]}" != "targetgroup" ] || [ "${SEG[4]}" != "$TG_NAME" ]; then
  echo "implausible ResourceLabel: $LABEL" >&2
  exit 1
fi

echo "$LABEL"
