#!/usr/bin/env bash
# Runs ON usms-web-01. Uploads one transcript to S3 using the instance profile.
# No credentials are stored, read or passed here: the AWS CLI picks up temporary
# credentials for usms-ec2-app-role from the instance metadata service.
#
# Usage: transcript-upload.sh <student-id> <file-path>
set -euo pipefail

BUCKET="usms-student-data"

usage() {
  echo "Usage: $(basename "$0") <student-id> <file-path>" >&2
  echo "Example: $(basename "$0") 02230311 /tmp/transcript.pdf" >&2
}

if [ "$#" -ne 2 ]; then
  echo "ERROR: expected 2 arguments, got $#" >&2
  usage
  exit 2
fi

STUDENT_ID="$1"
FILE_PATH="$2"

if [ -z "$STUDENT_ID" ]; then
  echo "ERROR: student ID is empty" >&2
  usage
  exit 2
fi

if [ ! -f "$FILE_PATH" ]; then
  echo "ERROR: file not found: $FILE_PATH" >&2
  usage
  exit 3
fi

KEY="transcripts/${STUDENT_ID}/$(basename "$FILE_PATH")"

echo "Uploading $FILE_PATH to s3://${BUCKET}/${KEY}"
aws s3 cp "$FILE_PATH" "s3://${BUCKET}/${KEY}"
echo "Done"
