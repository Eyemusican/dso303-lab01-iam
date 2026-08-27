#!/usr/bin/env bash
# Prints PUBLIC / PRIVATE / ISOLATED for every subnet in usms-vpc,
# derived only from each subnet's actual route table, never from name or tags.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/configs/course.env"

VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=usms-vpc" \
  --query 'Vpcs[0].VpcId' --output text)

SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].SubnetId' --output text)

for s in $SUBNET_IDS; do
  name=$(aws ec2 describe-subnets --subnet-ids "$s" \
          --query 'Subnets[0].Tags[?Key==`Name`]|[0].Value' --output text)
  cidr=$(aws ec2 describe-subnets --subnet-ids "$s" \
          --query 'Subnets[0].CidrBlock' --output text)
  az=$(aws ec2 describe-subnets --subnet-ids "$s" \
          --query 'Subnets[0].AvailabilityZone' --output text)

  rt=$(aws ec2 describe-route-tables \
        --filters "Name=association.subnet-id,Values=$s" \
        --query 'RouteTables[0].RouteTableId' --output text)

  gateway=$(aws ec2 describe-route-tables --route-table-ids "$rt" \
        --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId | [0]' \
        --output text)
  nat=$(aws ec2 describe-route-tables --route-table-ids "$rt" \
        --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].NatGatewayId | [0]' \
        --output text)

  if [[ "$gateway" == igw-* ]]; then
    printf '%-24s%-14s%-14s%-9s via %s\n' "$name" "$cidr" "$az" "PUBLIC" "$gateway"
  elif [[ "$nat" == nat-* ]]; then
    printf '%-24s%-14s%-14s%-9s via %s\n' "$name" "$cidr" "$az" "PRIVATE" "$nat"
  else
    printf '%-24s%-14s%-14s%-9s no default route\n' "$name" "$cidr" "$az" "ISOLATED"
  fi
done