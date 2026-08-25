# Lab 01 — Independent Lab Exercises

## Exercise 1 — The QA identity

For this exercise I had to create a new group called usms-qa and a user usms-qa-01 inside it, then attach the existing USMSDeveloperBase policy to the group instead of making a new one.

I created the group first, then made the user with tags Role=QA and Project=USMS, capturing the user's ARN into a variable the same way I did back in Step 19. After that I added the user to the group and attached USMSDeveloperBase to the group, not directly to the user.

```bash
aws iam create-group --group-name usms-qa

QA_ARN=$(aws iam create-user \
  --user-name usms-qa-01 \
  --tags Key=Role,Value=QA Key=Project,Value=USMS \
  --query 'User.Arn' \
  --output text)

aws iam add-user-to-group --group-name usms-qa --user-name usms-qa-01

aws iam attach-group-policy \
  --group-name usms-qa \
  --policy-arn "$USMS_POLICY_DEV_BASE"
```

![Group and user created](../../screenshots/exercise1-create-attach.png)

Group and user got created fine and the ARN was captured correctly.

Then I ran the three verify commands from the lab to check everything worked.

```bash
aws iam get-group --group-name usms-qa
aws iam list-attached-group-policies --group-name usms-qa
aws iam list-attached-user-policies --user-name usms-qa-01
```

![Verification of QA group and policy](../../screenshots/exercise1-verify.png)

get-group shows usms-qa-01 is inside the group, list-attached-group-policies shows USMSDeveloperBase is attached to the group, and list-attached-user-policies on the user comes back empty. That confirms no policy is attached directly to the user, it only comes through the group.

## Exercise 2 — The read-only reporting policy

For this exercise I had to write a new customer managed policy called USMSReportingReadOnly that only lets someone list the bucket and read objects under the transcripts/ prefix, and explicitly denies any Put or Delete action on the bucket.

I wrote the policy with three statements. One allows s3:ListBucket on the bucket itself, one allows s3:GetObject scoped to arn:aws:s3:::usms-student-data/transcripts/*, and the last one is an explicit Deny on s3:Put* and s3:Delete* covering both the bucket and the objects inside it.

```bash
aws iam create-policy \
  --policy-name USMSReportingReadOnly \
  --description "Read-only access to transcripts prefix; explicit deny on writes and deletes" \
  --policy-document file://usms-reporting-readonly-policy.json \
  --query 'Policy.Arn' \
  --output text
```

![Policy JSON validated](../../screenshots/exercise2-json-valid.png)

I validated the JSON with py -m json.tool before creating the policy since python3 doesn't work on my system, but py does.

![Policy created in IAM](../../screenshots/exercise2-policy-created.png)

Policy got created with the ARN arn:aws:iam::000000000000:policy/USMSReportingReadOnly.

![Policy verified](../../screenshots/exercise2-verify.png)

I checked it with the same command the lab gave as the expected outcome, and it confirms the policy exists with DefaultVersionId v1 and AttachmentCount 0, since the exercise only asked me to create it, not attach it anywhere yet.



## Exercise 3 — Problem solving: the third-party analytics role

For this one I had to design a role for a partner university's analytics service that can only be assumed by usms-audit-01, holds a session of at most 30 minutes, and can only read objects under the reports/ prefix.

I split the trust policy and the permissions policy into two separate files like the exercise asked. trust-analytics-partner.json says usms-audit-01 is allowed to assume the role, and usms-analytics-partner-permissions.json only allows s3:GetObject scoped to arn:aws:s3:::usms-student-data/reports/*.

One thing I ran into: AWS does not let MaxSessionDuration go below 3600 seconds when creating the role, even though the requirement says 30 minutes. So I created the role with the minimum allowed ceiling of 3600, then requested the actual 30 minute credential separately using --duration-seconds 1800 when calling assume-role. That gives a real 30 minute session even though the role's own ceiling is 1 hour.

```bash
aws iam create-role \
  --role-name usms-analytics-partner-role \
  --description "Read-only access to reports for partner analytics, assumed by usms-audit-01" \
  --assume-role-policy-document file://trust-analytics-partner.json \
  --max-session-duration 3600 \
  --tags Key=Project,Value=USMS Key=External,Value=true \
  --query 'Role.Arn' \
  --output text

aws iam create-policy \
  --policy-name USMSAnalyticsPartnerReports \
  --policy-document file://usms-analytics-partner-permissions.json \
  --query 'Policy.Arn' \
  --output text

aws iam attach-role-policy \
  --role-name usms-analytics-partner-role \
  --policy-arn "$ANALYTICS_POLICY_ARN"
```

![Role created](../../screenshots/exercise3-role-created.png)

Role got created fine.

```bash
aws iam get-role --role-name usms-analytics-partner-role \
  --query 'Role.{MaxSession:MaxSessionDuration,Trust:AssumeRolePolicyDocument.Statement[0].Principal}' \
  --output json

aws iam list-attached-role-policies --role-name usms-analytics-partner-role
```

![Role verified](../../screenshots/exercise3-role-verify.png)

This confirms MaxSessionDuration is 3600, the trust policy names usms-audit-01, and USMSAnalyticsPartnerReports is attached to the role.

Then I obtained temporary credentials for the role, asking for the actual 30 minute duration:

```bash
aws sts assume-role \
  --role-arn "$ANALYTICS_ROLE_ARN" \
  --role-session-name usms-audit-01-analytics \
  --duration-seconds 1800 \
  --profile floci
```

![Temporary credentials obtained](../../screenshots/exercise3-assume-role.png)

The Expiration came back as 2026-08-25T16:56:42, which is 30 minutes after the call was made, so the duration request worked correctly. I called assume-role using my normal floci profile rather than actually being logged in as usms-audit-01, same shortcut used in Lab 1 Step 30, since Floci does not actually enforce who is allowed to assume a role.

On the sts:ExternalId question the exercise raises, I would add one in a real deployment since this role is meant for a genuine external partner. Without an ExternalId, anything that discovers the role ARN and happens to have usms-audit-01's credentials could assume it. An ExternalId is an extra shared secret the partner has to supply, which protects against the confused deputy problem where a third party is tricked into assuming a role on someone else's behalf.




## Exercise 4 — Challenge: design a least-privilege policy from a job description

For this exercise I had to design permissions for a nightly backup job that copies everything from the student data bucket into an archive bucket, verifies what it copied, and writes a completion log to CloudWatch. It has to never delete anything, never read IAM, and only ever run in us-east-1.

I decided on a role rather than a user or group since this is an automated job, not a person, same reasoning as usms-ec2-app-role. My full justification is in notes/lab-01-notes.md.

I wrote the policy with 4 statements, staying under the 4 statement limit from the exercise. The first two statements handle reading the source bucket and reading/writing/verifying the archive bucket, both locked to us-east-1 with a Condition. The third handles logging, scoped to a specific log group rather than all logs. The fourth is an explicit Deny on delete actions and all IAM actions, which does use Resource *, but the exercise only forbids wildcards on Allow statements so this is fine.

```bash
aws iam create-role \
  --role-name usms-backup-operator-role \
  --description "Nightly backup job: copies student data to archive, verifies, logs completion" \
  --assume-role-policy-document file://trust-backup-operator.json \
  --tags Key=Project,Value=USMS \
  --query 'Role.Arn' \
  --output text

aws iam create-policy \
  --policy-name USMSBackupOperator \
  --policy-document file://usms-backup-operator-policy.json \
  --query 'Policy.Arn' \
  --output text

aws iam attach-role-policy \
  --role-name usms-backup-operator-role \
  --policy-arn "$BACKUP_POLICY_ARN"
```

![Role created](../../screenshots/exercise4-role-created.png)

Role got created with a trust policy for ec2.amazonaws.com, same pattern as Step 28.

```bash
aws iam get-role --role-name usms-backup-operator-role \
  --query 'Role.{Name:RoleName,Trust:AssumeRolePolicyDocument.Statement[0].Principal}' \
  --output json

aws iam list-attached-role-policies --role-name usms-backup-operator-role
```

![Role verified](../../screenshots/exercise4-role-verify.png)

This confirms the trust policy names ec2.amazonaws.com and USMSBackupOperator is attached to the role.

```bash
aws iam get-policy-version \
  --policy-arn "$BACKUP_POLICY_ARN" \
  --version-id "$VER" \
  --query 'PolicyVersion.Document.Statement[*].Condition'
```

![Region condition verified](../../screenshots/exercise4-condition-verify.png)

This confirms all three Allow statements carry the aws:RequestedRegion condition locking them to us-east-1.

Three ways this policy could still be abused, and how I would close each gap, are written up in notes/lab-01-notes.md.


