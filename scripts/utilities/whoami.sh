#!/usr/bin/env bash
# Quick identity check against Floci.
set -Eeuo pipefail
aws --endpoint-url=http://localhost:4566 --profile floci sts get-caller-identity