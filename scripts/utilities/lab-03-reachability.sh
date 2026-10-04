#!/usr/bin/env bash
# Lab 03 Exercise 3: reachability report for every running USMS instance.
# The verdict comes from route tables, public addresses and security groups only,
# never from instance names or tags.
#
# set -e is deliberately NOT used. Many lookups here can legitimately return nothing
# (no public address, no explicit route table association), and with -e one empty
# or failing lookup would stop the whole report halfway through. Instead every value
# is checked, and None is treated as "absent".
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/configs/course.env"

# Prints the internet gateway ID the subnet's default route uses, or None.
route_to_igw() {
  local subnet="$1" vpc="$2" rt
  rt=$(aws ec2 describe-route-tables \
        --filters "Name=association.subnet-id,Values=$subnet" \
        --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null)
  if [ -z "$rt" ] || [ "$rt" = "None" ]; then
    # No explicit association: the subnet uses the VPC's main route table.
    rt=$(aws ec2 describe-route-tables \
          --filters "Name=vpc-id,Values=$vpc" "Name=association.main,Values=true" \
          --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null)
  fi
  if [ -z "$rt" ] || [ "$rt" = "None" ]; then echo None; return; fi
  aws ec2 describe-route-tables --route-table-ids "$rt" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0` && starts_with(GatewayId || ``, `igw-`)].GatewayId | [0]' \
    --output text 2>/dev/null || echo None
}

# Exit 0 if any of the given security groups allows tcp/80 from 0.0.0.0/0.
sg_allows_80() {
  aws ec2 describe-security-groups --group-ids "$@" --output json 2>/dev/null \
    | tr -d '\r' \
    | jq -e '[.SecurityGroups[].IpPermissions[]
              | select((.IpProtocol == "tcp" and .FromPort <= 80 and .ToPort >= 80)
                       or .IpProtocol == "-1")
              | .IpRanges[]?
              | select(.CidrIp == "0.0.0.0/0")] | length > 0' >/dev/null
}

printf '%-20s %-12s %-15s %-12s %s\n' "NAME" "PRIVATE" "PUBLIC" "VERDICT" "REASON"

while read -r name id priv pub subnet vpc sgs <&3; do
  [ -z "${id:-}" ] && continue

  if [ "$vpc" = "None" ]; then
    vpc=$(aws ec2 describe-subnets --subnet-ids "$subnet" \
            --query 'Subnets[0].VpcId' --output text 2>/dev/null)
  fi

  # A public address is either the instance's own field or an associated Elastic IP.
  if [ "$pub" = "None" ]; then
    pub=$(aws ec2 describe-addresses \
            --query "Addresses[?InstanceId=='$id'].PublicIp | [0]" --output text 2>/dev/null)
    [ -z "$pub" ] && pub=None
  fi

  igw=$(route_to_igw "$subnet" "$vpc")
  [ -z "$igw" ] && igw=None

  if [ "$igw" = "None" ]; then
    verdict="UNREACHABLE"; reason="no igw route on subnet"
  elif [ "$pub" = "None" ]; then
    verdict="NO-ADDRESS";  reason="igw route present but no public address"
  elif sg_allows_80 ${sgs//,/ }; then
    verdict="REACHABLE";   reason="igw route + sg allows 80/tcp from 0.0.0.0/0"
  else
    verdict="BLOCKED";     reason="igw route + public address, but sg does not allow 80/tcp from 0.0.0.0/0"
  fi

  [ "$pub" = "None" ] && pub="-"
  printf '%-20s %-12s %-15s %-12s %s\n' "$name" "$priv" "$pub" "$verdict" "$reason"
done 3< <(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=USMS" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value, InstanceId, PrivateIpAddress, PublicIpAddress, SubnetId, VpcId, join(`,`, SecurityGroups[].GroupId)]' \
  --output text | tr -d '\r')