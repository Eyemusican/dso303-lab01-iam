#!/usr/bin/env bash
# Draft the bucket policy the S3 configuration lab will apply to the transcripts bucket.
# Reads the Lab 09 identity inventory and the policies that name the bucket, and writes:
#   outputs/lab-09-bucket-policy-draft.json   the draft resource policy (NOT applied)
#   outputs/lab-09-lab10-readiness.txt        what Lab 10 needs to know
# Works whether or not the bucket exists. Applies nothing. Touches no credentials.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
# shellcheck disable=SC1090
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true

INV=outputs/lab-09-identity-inventory-ex2.json
[ -f "$INV" ] || INV=outputs/lab-09-identity-inventory.json
[ -f "$INV" ] || { echo "no inventory - run Lab 09 Step 4 part 2 first" >&2; exit 2; }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# The bucket name comes from Lab 01's policy document, never typed by hand.
RW_ARN=$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='USMSStudentDataReadWrite'].Arn | [0]" --output text)
RW_VER=$(aws iam get-policy --policy-arn "$RW_ARN" --query 'Policy.DefaultVersionId' --output text)
BUCKET_ARN=$(aws iam get-policy-version --policy-arn "$RW_ARN" --version-id "$RW_VER" \
  --query 'PolicyVersion.Document' --output json | python3 -c "
import json, sys
d = json.load(sys.stdin)
sts = d['Statement'] if isinstance(d['Statement'], list) else [d['Statement']]
for s in sts:
    for r in (s['Resource'] if isinstance(s['Resource'], list) else [s['Resource']]):
        if r.startswith('arn:aws:s3:::') and '/' not in r:
            print(r); sys.exit(0)
sys.exit(1)")
[ -n "$BUCKET_ARN" ] || { echo "no bucket ARN found in USMSStudentDataReadWrite" >&2; exit 2; }

# Shell parameter expansion: strip everything up to ':::' to get the bare bucket name,
# then strip any '/...' suffix. No python and no extra API call needed for a string cut.
BUCKET=${BUCKET_ARN##*:::}
BUCKET=${BUCKET%%/*}

python3 - "$INV" "$BUCKET" "$ACCOUNT" \
  outputs/lab-09-bucket-policy-draft.json outputs/lab-09-lab10-readiness.txt << 'PY'
import json, sys
inv_path, bucket, account, draft_path, ready_path = sys.argv[1:6]
b_arn, o_arn = f"arn:aws:s3:::{bucket}", f"arn:aws:s3:::{bucket}/*"

def as_list(x):
    return [] if x is None else (x if isinstance(x, list) else [x])

roles = json.load(open(inv_path))
grants, naming = {}, set()          # role ARN -> s3 actions ; policies that name the bucket
for r in roles:
    docs = [(p["name"], p.get("document")) for p in r.get("attachedPolicies", [])]
    docs += [(p["name"], p.get("document")) for p in r.get("inlinePolicies", [])]
    for pname, doc in docs:
        if isinstance(doc, str):
            doc = json.loads(doc)
        for s in as_list((doc or {}).get("Statement")):
            res = as_list(s.get("Resource"))
            if not any(x in (b_arn, o_arn) for x in res):
                continue
            naming.add(pname)
            if s.get("Effect") != "Allow":
                continue
            acts = [a for a in as_list(s.get("Action")) if a.lower().startswith("s3:")]
            if acts:
                grants.setdefault(r["arn"], set()).update(acts)

root = f"arn:aws:iam::{account}:root"
statements = []
for i, (arn, acts) in enumerate(sorted(grants.items()), 1):
    statements.append({"Sid": f"AllowWhatThisRoleAlreadyHas{i}", "Effect": "Allow",
                       "Principal": {"AWS": arn}, "Action": sorted(acts),
                       "Resource": [b_arn, o_arn]})
statements.append({"Sid": "DenyAnyRequestNotOverTls", "Effect": "Deny", "Principal": "*",
                   "Action": "s3:*", "Resource": [b_arn, o_arn],
                   "Condition": {"Bool": {"aws:SecureTransport": "false"}}})
statements.append({"Sid": "DenyEveryoneElse", "Effect": "Deny",
                   "NotPrincipal": {"AWS": sorted(grants) + [root]},
                   "Action": "s3:*", "Resource": [b_arn, o_arn]})
draft = {"Version": "2012-10-17", "Statement": statements}
json.dump(draft, open(draft_path, "w"), indent=2)

# mechanical checks
text = json.dumps(draft)
ok = True
for s in statements:
    p = s.get("Principal")
    if p == "*":
        good = s["Sid"] == "DenyAnyRequestNotOverTls"
    elif p is None:
        good = all(a.startswith("arn:aws:iam::") for a in as_list(s["NotPrincipal"]["AWS"]))
    else:
        good = all(a.startswith("arn:aws:iam::") for a in as_list(p["AWS"]))
    ok &= good
    print(f"  {'ok  ' if good else 'FAIL'} principal check  {s['Sid']}")
both = f'"{b_arn}"' in text and f'"{o_arn}"' in text
ok &= both
print(f"  {'ok  ' if both else 'FAIL'} bucket ARN appears with and without /*")

with open(ready_path, "w") as f:
    f.write(f"bucket (from USMSStudentDataReadWrite): {bucket}\n")
    f.write(f"policies naming it: {', '.join(sorted(naming))}\n")
    f.write(f"role ARNs granted s3 on it: {', '.join(sorted(grants))}\n")
    f.write(f"principal count: {len(grants)}\n")
    f.write(f"what changes when Lab 10 runs create-bucket: the {len(grants)} roles above stop "
            f"getting NoSuchBucket and their identity policies start to apply, while this draft "
            f"stays unapplied until the S3 configuration lab adds it as the bucket policy.\n")
print(f"policies naming the bucket: {len(naming)}  principals: {len(grants)}")
sys.exit(0 if ok else 1)
PY
