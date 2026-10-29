# Lab 09 Working Notes

**Path: B (management only), with simulate-principal-policy also answering.** Roles, policies and security group rules can be created, read and changed. get-account-authorization-details, get-credential-report and Access Analyzer are not available. Floci enforces no IAM and carries no traffic, so every control in this lab is judged by reading it.

**The transcripts bucket usms-student-data did not exist yet during this lab:** head-bucket returned 404 (exit code 254). Lab 10 creates it. IAM policies name ARNs, so I could review them before the bucket exists.

## Section 2 and Step 1: resume and load seven env files

- Floci is up in hybrid storage mode (C:/Users/Tenzin/floci-data). jq, python3 and docker are installed, and floci-storage-check.sh gave 5 [ok] and 0 [FAIL]. My version of the script has no PASS/FAIL summary line, so I counted its [ok] and [FAIL] lines.
- The usms-dev profile still answers as arn:aws:iam::000000000000:user/usms-dev-01, so Step 10 can rotate its key. outputs/usms-app-key.pem is there; on Windows it shows -rw-r--r-- because Git Bash cannot set chmod 600.
- AWS_PROFILE was empty in a new terminal, so Errata 01 is not in my bash profile. Sourcing configs/course.env sets it to floci.
- All 17 values are non-empty. My lab-01.env stores USMS_ROLE_EC2, USMS_ROLE_LAMBDA and USMS_ROLE_DEVELOPER as full ARNs, but Lab 09 uses them as role names (--role-name, and it builds arn:...:role/NAME itself). I cut them down to the names in this terminal with ${VAR##*/} and left lab-01.env unchanged, because earlier labs read it.

![Step 1 env values](../screenshots/lab09-step01-env.png)

## Step 2: security baseline

- outputs/lab-09-pre-verify.txt: lab-02 PASS=33 FAIL=0, lab-03 PASS=34 FAIL=2, lab-04 PASS=39 FAIL=0, lab-05 PASS=47 FAIL=2, lab-06 PASS=39 FAIL=3.
- The doc's tail -1 did not work for lab-05 and lab-06, because when a check fails those scripts print a REMEDY help text after the summary. I picked out the PASS= FAIL= line with grep instead and rebuilt the file. Step 18 will use the same method.
- Every failure is one I recorded in an earlier lab, not something new. Lab 03: the private key cannot be chmod 600 on Windows, and usms-web-01 has no public address on Floci. Lab 05: healthCheckGracePeriodSeconds is not stored, so lab-05.env has USMS_SVC_GRACE_PERIOD=None. Lab 06: PutScheduledAction is not supported, so the three scheduled action checks fail. Lab 04 is FAIL=0 because I did Lab 05 Exercise 2.
- These are the same numbers my Lab 06 notes recorded, so nothing broke between labs. Step 18 has to give the same lines.

![Step 2 baseline](../screenshots/lab09-step02-baseline.png)

## Step 2: security baseline

- outputs/lab-09-pre-verify.txt: lab-02 PASS=33 FAIL=0, lab-03 PASS=34 FAIL=2, lab-04 PASS=39 FAIL=0, lab-05 PASS=47 FAIL=2, lab-06 PASS=39 FAIL=3.
- The doc's tail -1 did not work for lab-05 and lab-06, because when a check fails those scripts print a REMEDY help text after the summary. I picked out the PASS= FAIL= line with grep instead and rebuilt the file. Step 18 will use the same method.
- Every failure is one I recorded in an earlier lab, not something new. Lab 03: the private key cannot be chmod 600 on Windows, and usms-web-01 has no public address on Floci. Lab 05: healthCheckGracePeriodSeconds is not stored, so lab-05.env has USMS_SVC_GRACE_PERIOD=None. Lab 06: PutScheduledAction is not supported, so the three scheduled action checks fail. Lab 04 is FAIL=0 because I did Lab 05 Exercise 2.
- These are the same numbers my Lab 06 notes recorded, so nothing broke between labs. Step 18 has to give the same lines.

![Step 2 baseline](../screenshots/lab09-step02-baseline.png)

## Step 3: what this Floci build supports

- SUPPORTED: list-roles, list-policies --scope Local, get-role, list-attached-role-policies, update-assume-role-policy, create-role with a boundary, put-role-permissions-boundary, simulate-principal-policy, sts assume-role with a session policy, list-access-keys, get-access-key-last-used, describe-security-group-rules, authorize and revoke egress, describe-prefix-lists, describe-network-interfaces, modify-instance-metadata-options and MetadataOptions in describe-instances.
- not available: get-account-authorization-details, accessanalyzer list-analyzers and get-credential-report.
- Unlike the doc's example, simulate-principal-policy answered, so I am on Path B with simulation as a bonus. Path A needs everything to answer, and three calls did not. The skel probes only prove the CLI knows the operation, not that Floci implements it.
- An API call is decided by IAM and fails with an error naming an action; a packet is decided by routing, security groups and NACLs and fails with a timeout. Floci does neither, so I must not wait for an AccessDenied as proof.

![Step 3 probe](../screenshots/lab09-step03-probe.png)

## Step 4: inventory of every identity

- 10 roles: usms-analytics-partner-role, usms-backup-operator-role, usms-developer-role, usms-ec2-app-role, usms-ecs-exec-role, usms-ecs-task-role, usms-eks-cluster-role, usms-eks-node-role, usms-lambda-exec-role, and the Lab 06 service linked role AWSServiceRoleForEcsApplicationAutoscaling. All have a MaxSession of 3600.
- 4 users. Only usms-dev-01 has an access key (1). usms-admin-01, usms-audit-01 and usms-qa-01 have none.
- 10 customer managed policies. USMSStudentDataReadWrite is attached 3 times: usms-ec2-app-role, usms-ecs-task-role and, since Lab 07, usms-eks-node-role. That is the finding Step 6 pulls on.
- USMSReportingReadOnly has an attachment count of 0, so it is a leftover from Lab 01 and not attached to anything. USMSDeveloperBase is on version v3 with 4 attachments.

![Roles](../screenshots/lab09-step04-roles.png)
![Users and policies](../screenshots/lab09-step04-users-policies.png)
- outputs/lab-09-identity-inventory.json is valid JSON with 10 roles. Each one has its trust policy, its attached and inline policy documents and its boundary. Every role shows boundary=-, so no role in this account has a permissions boundary. Step 8 fixes that for one role.
- usms-eks-node-role has 2 policies (USMSEKSNodePolicy and USMSStudentDataReadWrite). The service linked role has 0, because AWS manages its permissions.

![Inventory](../screenshots/lab09-step04-inventory.png)

**Your turn: two trust policies side by side.** usms-ec2-app-role trusts a Service principal (ec2.amazonaws.com), so the credentials go to whatever EC2 instance is launched with this role's instance profile, which means anyone who can launch an instance and pass the role gets them, not a named person. usms-developer-role trusts an AWS principal (user/usms-dev-01), so only that one IAM user can get the credentials, by calling sts assume-role with their own signed access key.

![Two trust policies](../screenshots/lab09-step04-trust.png)

## Step 5: IAM audit script

- scripts/utilities/usms-iam-audit.sh reads the Step 4 inventory and changes nothing. It checks four things: wildcard actions, Resource "*" on a changing action, iam:PassRole with no resource scope, and a service trust policy with no Condition. It exits 1 if there is any HIGH finding. bash -n says the syntax is OK.
- Result: HIGH=8 MED=33 roles=10, exit code 1. The full report is in outputs/lab-09-iam-findings.txt. The doc's example has HIGH=4 MED=5 because it has only 5 roles.
- All 8 HIGH findings are the same mistake: a service principal in the trust policy with no Condition (the confused deputy). They are on usms-ec2-app-role, usms-ecs-task-role, usms-ecs-exec-role, usms-lambda-exec-role, usms-eks-cluster-role, usms-eks-node-role, usms-backup-operator-role and the service linked role. It is a convention we copied from lab to lab, not 8 separate errors. Steps 7 and 8 fix some of them and Exercise 2 deals with the rest.
- MED: all 10 roles have no permissions boundary, and 23 lines are changing actions on Resource "*", like ec2:CreateNetworkInterface, ec2:CreateVpc and elasticloadbalancing:CreateLoadBalancer, from the EKS and developer policies. No role has Action "*" or an unscoped iam:PassRole.
- My first on screen summary used grep -B3 and put some HIGH lines under the wrong role name, so I printed it again with awk, which keeps the role name with each line.

![IAM audit](../screenshots/lab09-step05-iam-audit.png)

## Step 6: the transcripts policy

- USMSStudentDataReadWrite default version v1 (saved to outputs/lab-09-transcripts-rw.json). Statement 1: s3:ListBucket and s3:GetBucketLocation on the bucket ARN arn:aws:s3:::usms-student-data. Statement 2: s3:GetObject, s3:PutObject and s3:DeleteObject on the object ARN usms-student-data/*. Statement 3: an explicit Deny on s3:DeleteBucket, which wins over any Allow.
- list-entities-for-policy shows 3 roles carry it: usms-ec2-app-role, usms-ecs-task-role and, since Lab 07, usms-eks-node-role. No users or groups.
- Two write verbs reach roles that only read. My Lab 01 version has s3:DeleteObject as well as s3:PutObject, so it has one more extra verb than the doc's version.
- head-bucket returned 404 Not Found with exit code 254, because Lab 10 creates the bucket. A policy is a statement about ARNs, not a link to a real object.
- Floci authorises nothing, so I cannot show PutObject failing. The proof that a policy is right is reading it.

**Your turn: what each workload needs.**
- The enrolment API showing a transcript needs: s3:GetObject and s3:ListBucket. ListBucket is there so a missing transcript comes back as 404 NoSuchKey instead of 403 AccessDenied.
- The registry's upload workflow storing a transcript needs: s3:GetObject, s3:ListBucket and s3:PutObject.
- The one action in the second list and not the first is s3:PutObject. s3:DeleteObject and s3:GetBucketLocation are in my Lab 01 policy but in neither list, so nobody needs DeleteObject at all.

![Transcripts policy](../screenshots/lab09-step06-policy.png)
![Who carries it, and no bucket yet](../screenshots/lab09-step06-carriers-bucket.png)

## Step 7: the read-only policy and the role that carries it

- policies/usms-student-data-ro-policy.json: s3:ListBucket on the bucket ARN, s3:GetObject on usms-student-data/*, and an explicit Deny on s3:PutObject, s3:DeleteObject, s3:DeleteBucket and s3:PutBucketPolicy. It is valid JSON with 0 dollar signs, because I used a quoted heredoc and the bucket name is a literal, the same as Lab 01.
- The Deny adds nothing today, because nothing in this policy allows a write. I kept it because it still wins if someone later attaches a broader policy to the same role, so a reviewer should not delete it as redundant.
- create-policy made USMSStudentDataReadOnly (arn:aws:iam::000000000000:policy/USMSStudentDataReadOnly).
- policies/trust-ecs-tasks-scoped.json keeps the principal ecs-tasks.amazonaws.com but adds two conditions: aws:SourceAccount equals 000000000000 and aws:SourceArn is like arn:aws:ecs:us-east-1:000000000000:*. That stops the confused deputy, where ECS could assume the role for someone in another account. I used an unquoted heredoc here on purpose so the account and region were filled in now; the file has 0 dollar signs left.

![Read-only policy and scoped trust](../screenshots/lab09-step07-policy-trust.png)
- Part 4: created usms-transcripts-reader-role (arn:aws:iam::000000000000:role/usms-transcripts-reader-role) with the scoped ecs-tasks trust and MaxSession 3600, and attached USMSStudentDataReadOnly. This is added next to the old setup, so USMSStudentDataReadWrite stays on usms-ecs-task-role for Lab 10.
- Part 5: update-assume-role-policy replaces the whole trust document, it does not merge. So first I saved the old trust (ecs-tasks.amazonaws.com, Sid AllowEcsTasksToAssumeThisRole, no Condition) to outputs/lab-09-ecs-task-role-trust-before.json as the undo, then I applied the scoped trust to usms-ecs-task-role.
- Part 6: before [ecs-tasks, False], after [ecs-tasks, True], SAME PRINCIPAL, NEW CONDITION. Who may assume the role did not change, only the circumstances. usms-ec2-app-role is still unconditioned, because EC2 does not send aws:SourceArn for instance profiles (Exercise 2).

![New role and rewritten trust](../screenshots/lab09-step07-roles.png)

## Step 8: scoped iam:PassRole and a permissions boundary

- policies/usms-permissions-boundary.json is a ceiling, not a grant. It allows only what a USMS deployment touches (ec2:Describe*, ecs:*, elasticloadbalancing:*, logs:*, s3:Get*/List*/PutObject, iam:PassRole, iam:Get*/List*), denies every way to change identities (CreateUser, CreateAccessKey, AttachRolePolicy, UpdateAssumeRolePolicy, CreatePolicyVersion, DeleteRolePermissionsBoundary and more), and denies deleting the course VPC, subnets, IGW and NAT. I created it as USMSPermissionsBoundary and attached it to nothing.
- Resource "*" is right for a ceiling, because the boundary never grants anything by itself; it only limits what the identity policy grants.
- policies/usms-deploy-policy.json (USMSDeployBase): statement 1 is what a pipeline does on ECS, ELB, scaling and logs. Statement 2 allows iam:PassRole only on usms-ecs-exec-role, usms-ecs-task-role and usms-transcripts-reader-role, and only when iam:PassedToService is ecs-tasks.amazonaws.com. Statement 3 explicitly denies passing any role to EC2. That closes the escalation path (launch an instance with an admin role, then read its credentials from metadata) at the PassRole step. ecs:UpdateService on Resource "*" is still a real MED finding (Exercise 2).
- policies/trust-deploy.json trusts only user/usms-admin-01 in my own account, so it is not a confused deputy risk. Its hardening would be MFA.
- usms-deploy-role was created with --permissions-boundary and has USMSDeployBase attached. All three JSON files were valid, and the two unquoted heredocs had 0 dollar signs.
- Floci limitation (course Known Issues, Lab 09): get-role shows PermissionsBoundary null after create-role. put-role-permissions-boundary exited 0 but get-role still shows null, so my build accepts the boundary and does not store it. On real AWS the role's effective permissions would be the intersection of USMSDeployBase and USMSPermissionsBoundary. I record boundary enforcement as not demonstrated and use the course fallback model below.

![Step 8 create](../screenshots/lab09-step08-create.png)
- Course fallback (known-issues page, student-fallback-demo.py security, made with the page's own heredoc): the identity allows GetObject and PutObject, the boundary allows only GetObject, and DeleteObject is explicitly denied. Result GetObject ALLOW, PutObject DENY, DeleteObject DENY. PutObject is allowed by the identity policy but outside the boundary, so it is denied: the effective permission is the intersection, and an explicit deny wins. Its token gate gave HTTP 401 without a token and 200 with one. This proves the logic only; it is a model, not IAM.
- Part 5 read back: usms-deploy-role has MaxSession 3600, Principal user/usms-admin-01 and USMSDeployBase attached, but Boundary null (the Known Issue). The PassRole Allow names exactly 3 roles and only for ecs-tasks.amazonaws.com, and the Deny covers passing anything to ec2.amazonaws.com. USMSPermissionsBoundary is attached to no role, user or group, which is correct for a boundary. It looks like an orphan policy, so nobody should delete it while tidying up.

![Fallback model](../screenshots/lab09-step08-fallback.png)
![Step 8 verify](../screenshots/lab09-step08-verify.png)
![PassRole and boundary not attached](../screenshots/lab09-step08-passrole.png)

## Step 9: session policy and the intersection

- A session policy is set by the caller on one assume-role call and can only narrow; it never grants. effective = identity policy AND boundary AND session policy.
- outputs/lab-09-session-policy.json allows only ec2:DescribeVpcs, ec2:DescribeSubnets, ec2:DescribeSecurityGroups and sts:GetCallerIdentity. It is in outputs/ because it is an argument to one call, not part of the account's setup.
- usms-dev assumed usms-developer-role with that session policy for 900 seconds. Floci returned assumed-role/usms-developer-role/floci-session (it ignored my session name lab05-scoped-review) and describe-vpcs returned 2. Floci does not enforce the session policy.
- My first hand calculation showed all four actions ALLOWED, because USMSDeveloperBase v3 already allows sts:GetCallerIdentity. The doc's substitute s3:ListAllMyBuckets would also be allowed, because my policy has s3:List*. So I swapped in ecs:ListServices, which my developer policy does not have, and ran it again: the three ec2 Describe actions ALLOWED, ecs:ListServices NOT in the identity policy, so denied. The session allowed it, but a session policy cannot add what the role never had.
- Second opinion from simulate-principal-policy (Step 3 found it supported): ec2:DescribeVpcs allowed, sts:GetCallerIdentity allowed, ecs:ListServices implicitDeny, iam:CreateUser explicitDeny. The explicit deny comes from USMSDeveloperBase, which denies aws-portal:*, iam:AttachUserPolicy, iam:CreateAccessKey, iam:CreateUser, iam:DeleteUser, iam:PutUserPolicy and organizations:*. I used both the Python reading and the simulator.
- Part 4: I unset the three session variables, whoami.sh showed root again, and I deleted outputs/lab-09-scoped-session.json straight away.

![Assume with a session policy](../screenshots/lab09-step09-assume.png)
![Back to root, and the simulator](../screenshots/lab09-step09-restore-simulate.png)
![The intersection](../screenshots/lab09-step09-intersection.png)

## Step 10: rotating the access key

- Order: create a second key, move every user of the old key to the new one, deactivate the old key (can be undone), and only then delete it (cannot be undone). Deactivating first is what makes it safe.
- Part 1: usms-dev-01 had exactly one key, AKIAG612UGS5FV67J078, Active, created 2026-08-21 in Lab 01. get-access-key-last-used gave N/A, which is normal on Floci.
- Part 2: create-access-key wrote the new key straight into outputs/usms-dev-01-access-key-new.json, so the secret never appeared on screen. git check-ignore named .gitignore:1:outputs/*. New key AKIAQXQKHH64S63NAJHS.
- Part 3: I pointed the usms-dev profile at the new key. It still answered as user/usms-dev-01 and aws configure get showed the new key ID.
- Part 4: the old key went Inactive and the profile still worked, so nothing depended on it. On a real system I would wait a day or a week at this point; the lab compresses that wait.
- Part 5: I deleted the inactive key. usms-dev-01 now has exactly one key, AKIAQXQKHH64S63NAJHS, created today, and the profile still answers. The only key file in outputs/ is the new one, which is git-ignored, and git ls-files outputs/ shows only .gitkeep.
- On a real account I would not keep a long-lived key at all. People would sign in through IAM Identity Center or federation and get temporary credentials, and workloads would use roles. The course keeps one key because Lab 02's assume-role needs a named user.

![Rotate: create, move, deactivate](../screenshots/lab09-step10-rotate.png)
![Delete the old key](../screenshots/lab09-step10-delete.png)

## Step 11: IMDSv2 on usms-web-01

- Before: HttpTokens optional, hop limit 1, endpoint enabled (outputs/lab-09-imds-before.json). Optional means IMDSv1 still works, so an SSRF bug in the app could GET http://169.254.169.254/latest/meta-data/iam/security-credentials/ and hand back usms-ec2-app-role's credentials.
- Floci limitation (course Known Issues, Lab 09): modify-instance-metadata-options returned UnsupportedOperation on my build, so nothing was applied and the readback still said optional. The doc's check printed NOT APPLIED. The course fallback is the token gate in student-fallback-demo.py security (Step 8): HTTP 401 without a token and 200 with one. That is a model, not IMDSv2.
- What real AWS would do: --http-tokens required makes the metadata service refuse a plain GET. Getting a token needs a PUT with a header, which an SSRF bug normally cannot send, so the credentials are safe. --http-put-response-hop-limit 1 stops a different attack: a container on the instance is one more network hop away, so it cannot reach the metadata service and borrow the host's role. Rollout order: first watch the MetadataNoToken metric until it is zero (Lab 03's user-data.sh already uses the token flow), then require tokens, otherwise old SDKs break.
- Your turn, usms-db-01: it has no instance profile (None), so the metadata service has no credentials to protect. The stronger setting is --http-endpoint disabled, which turns the metadata service off completely. Floci rejected that call too (UnsupportedOperation) and db-01 still reads enabled and optional. If I disabled the endpoint on usms-web-01, its app and user-data.sh could no longer get usms-ec2-app-role's credentials from the metadata service, so every AWS call from that instance would fail.

![IMDS](../screenshots/lab09-step11-imds.png)

## Step 12: security group audit script

- scripts/utilities/usms-sg-audit.sh asks four questions of every group in usms-vpc: who can reach me, what can I reach, is the source a group or an address, and is the group attached to anything. It changes nothing and exits 1 on HIGH findings (exit code 1). Full report: outputs/lab-09-sg-findings-before.txt.
- Result: HIGH=4 MED=11 LOW=8 groups=8. The doc's example has 3/6/1 over 5 groups.
- usms-alb-sg: tcp/80 and tcp/443 from 0.0.0.0/0 (HIGH). Accepted risk: it is the internet-facing load balancer, argued in Lab 05. The 443 rule is from my Lab 05 exercise.
- usms-app-sg: tcp/80 and tcp/443 from 0.0.0.0/0 (HIGH). Open finding, because the web instance is a second internet entry point from before the load balancer (Exercise 4). tcp/22 from 10.0.0.0/16 (MED): any compromised machine anywhere in the VPC can reach SSH, fixed in Step 16. It also has a second tcp/22 rule with no source at all (from <none>), a broken rule left over from an earlier lab, which I deal with in Step 16 too.
- usms-db-sg: tcp/5432 only from sg:usms-app-sg, a group reference, which is good. usms-enrolment-sg: tcp/80 only from sg:usms-alb-sg, also good.
- Extra groups in my VPC: usms-bastion-sg (Lab 02 Exercise 2, SSH from 203.0.113.10/32), usms-eks-cluster-sg (Lab 07, tcp/443 from 10.0.0.0/16) and usms-exam-sg, which is not part of the lab design and has a source of 10.10.0.0/16, which is not even my VPC range.
- Every one of the 8 groups still has the default allow-all egress (MED). Steps 13 to 15 fix it for enrolment, the load balancer and the database, and Exercise 1 for usms-app-sg.
- Floci limitation: describe-network-interfaces returned 0 for every group, so all 8 got LOW "attached to no network interface", even though usms-web-01, usms-db-01, the ALB and the tasks use these groups. Floci does not model the interfaces, so I cannot trust that count here.
- The audit cannot tell an accepted 0.0.0.0/0 (the ALB) from a real finding (the web instance). An audit tool gives findings, not verdicts.

![SG audit part 1](../screenshots/lab09-step12-sg-audit-1.png)
![SG audit part 2](../screenshots/lab09-step12-sg-audit-2.png)

## Step 13: egress rules for the enrolment tasks

- The tasks only need to start outward connections to the container registry (image pull), CloudWatch Logs (the awslogs driver) and S3 (Lab 10's transcripts), all on tcp/443. Not the database, not the web instance, nothing on other ports. tcp/443 to everywhere is still wide, but it blocks DNS exfiltration, SSH, database ports, mail and random command and control ports.
- describe-prefix-lists found the S3 prefix list pl-63a5400a from my Lab 02 gateway endpoint, so policies/usms-enrolment-sg-egress.json has tcp/443 to pl-63a5400a (S3 stays inside the AWS network) and tcp/443 to 0.0.0.0/0 (image pull and logs; on real AWS I would narrow it with interface endpoints). Valid JSON, 0 dollar signs, and every rule has a Description.
- I wrote policies/usms-egress-allow-all.json first as the undo, then authorised the two new rules (sgr-f5b07430d12cf5095 and sgr-5c953e50bdfb8cac5), then revoked the default.
- Floci quirk: revoke returned True, but describe-security-group-rules kept listing the -1 rule (sgr-703986c3a88780d87), even after I also revoked it by rule ID and by contents without a Description. describe-security-groups (IpPermissionsEgress) shows the -1 rule is gone and only the two tcp/443 rules are left. So the rule list view is stale on my build. The doc's checks read IpPermissionsEgress, so I go by that view.
- My first by ID attempt used IpProtocol==`-1` with backticks, which JMESPath reads as the number -1, so it matched nothing and Floci still answered True to revoking "None". Floci does not check what it is asked to delete.
- Ingress on usms-enrolment-sg is unchanged: tcp/80 from usms-alb-sg (sg-43a4d32b229ced732).
- Bug in the doc's usms-sg-audit.sh on Windows: the inline python3 -c opened /tmp/... written inside the Python code, which Git Bash does not translate for Windows Python, so it failed (No such file) and every group showed 0 interfaces. The script also ended with rm, so it always exited 0. I changed it to pass the file as an argument and to exit with Python's code. Now usms-app-sg shows 1 interface and usms-db-sg 2, and the exit code is 1. So the interface counts in outputs/lab-09-sg-findings-before.txt are wrong (the rules in it are right); the fixed run is outputs/lab-09-sg-findings-step13.txt. The ALB and the Fargate tasks still show 0, because Floci does not model their interfaces.

![Enrolment egress, two views](../screenshots/lab09-step13-egress.png)

## Step 14: the load balancer's egress names a group

- policies/usms-alb-sg-egress.json: tcp/80 to usms-enrolment-sg only. A group reference is a rule about a role in the design, so it stays right as Lab 06 scales the tasks up and down; an address would only be right for a moment.
- I authorised it (sgr-6df2efdb3b9e072d7) and then revoked the default. Readback: In tcp/80 and tcp/443 from 0.0.0.0/0, Out tcp/80 with ToGroup sg-b011f7193ccc66627 (usms-enrolment-sg) and CIDR null. Anyone may open HTTP to the load balancer, and it may open HTTP to exactly one thing.

![ALB egress](../screenshots/lab09-step14-alb-egress.png)

## Step 15: the data tier's egress

- policies/usms-db-sg-egress.json: only tcp/443 out, for OS updates through usms-nat. DNS out, SSH out, database connections, SMTP and HTTP on 80 are now blocked. I authorised it (sgr-226e8dc00a3567d64) and revoked the default.
- tcp/443 to 0.0.0.0/0 still lets an attacker POST data out over HTTPS. Stopping that needs filtering by hostname, with AWS Network Firewall or a proxy (Exercise 4).
- On real AWS this breaks dnf update, because it also needs DNS. The Amazon resolver is 10.0.0.2 inside the VPC, so the full rule set would add UDP and TCP 53 to 10.0.0.0/16. Floci has no resolver, so it is left for Exercise 1.
- Verify: 0 allow-all egress rules left on usms-enrolment-sg, usms-alb-sg and usms-db-sg.
- Two bugs in the doc's verify loop. It used length(IpPermissionsEgress[...]) without SecurityGroups[0]., so length() got null and failed on every group. And IpProtocol==`-1` with backticks compares to the number -1, so it would always print 0 even if the rule were there. I fixed the path and also checked with IpProtocol=='-1' as text. Both gave 0 for all three groups.

![Three zeros](../screenshots/lab09-step15-verify.png)

## Step 16: SSH narrowed to a bastion group

- Before, usms-app-sg allowed tcp/22 from 10.0.0.0/16, so every address in the VPC could reach SSH on the web tier, including every Fargate task. Now only things wearing usms-bastion-sg can. No jump host exists; the group names a role in the design.
- Bug in the doc's Part 1 lookup: SecurityGroups[0].GroupId | [0] applies [0] to a single string and returns nothing. So the script said the group did not exist, create-security-group failed with InvalidGroup.Duplicate, BASTION_SG was empty, and Part 2 added a tcp/22 rule with an empty source. I fixed the query to SecurityGroups[0].GroupId, which found my Lab 02 Exercise 2 group sg-f2639784fb4f0529e.
- The old tcp/22 from <none> rule that my Step 12 audit showed was the same kind of empty-source rule, almost certainly left by the same lookup in Lab 02 Exercise 2. Empty-source rules allow nothing, but they are wrong, so I revoked both.
- Revoke by rule ID returned True but only changed describe-security-group-rules. Revoke by contents (tcp 22 from 10.0.0.0/16, and tcp 22 with no source) is what removed them from describe-security-groups. Same Floci quirk as Step 13.
- Then I added the real rule: tcp/22 from sg-f2639784fb4f0529e (sgr-025fa2683c9c0a5b0), with policies/usms-app-sg-ssh-bastion.json now holding the real group ID.
- Result: tcp/80 and tcp/443 from 0.0.0.0/0 (unchanged, Exercise 4), tcp/22 only from usms-bastion-sg, and the 10.0.0.0/16 SSH rule is gone. A compromised enrolment task can no longer reach SSH on the web tier.

![SSH from the bastion group only](../screenshots/lab09-step16-ssh-bastion.png)

## Step 17: reachability matrix and proving two negatives

- scripts/utilities/usms-reachability-matrix.sh works out who may reach what from the rules only, never from names, tags or descriptions. It only reads and always exits 0. Output: outputs/lab-09-reachability.txt.
- Two groups admit the internet: usms-alb-sg (tcp/80 and tcp/443, argued in Lab 05) and usms-app-sg (tcp/80 and tcp/443, never argued, which is Exercise 4). So the web instance is a second internet entry point next to the load balancer.
- usms-db-sg admits only usms-app-sg on 5432, and usms-enrolment-sg admits only usms-alb-sg on 80. usms-app-sg's SSH now comes only from usms-bastion-sg.
- Egress matches Steps 13 to 15: usms-alb-sg tcp/80 to usms-enrolment-sg, usms-db-sg tcp/443, usms-enrolment-sg tcp/443 to pl-63a5400a and to 0.0.0.0/0. usms-app-sg and usms-bastion-sg still have the default (Exercise 1 for app-sg; a jump host's job is to start SSH).
- Single point of control: usms-bastion-sg, usms-db-sg, usms-eks-cluster-sg, usms-enrolment-sg and usms-exam-sg are each protected by exactly one ingress rule, so one mistake in that rule is the whole protection. usms-alb-sg is not on my list because it has two rules (80 and 443). The matrix only models security groups, so it understates the other controls like private subnets, routes and the NACL.
- Instances: usms-web-01, usms-db-01 and an extra usms-db-02 all show public=NONE. On Floci even usms-web-01 has no public address (the same limitation that fails Lab 03's verify), and the db instances show 172.18.0.3, which is Floci's Docker network address, not an address in my 10.0.3.0/24 subnet.

![Matrix, ingress](../screenshots/lab09-step17-matrix-1.png)
![Matrix, egress, instances and single points of control](../screenshots/lab09-step17-matrix-2.png)
- Negative proof for usms-db-01 (outputs/lab-09-negative-proof.txt), all five controls correct: 1. no public address (None). 2. usms-private-subnet-a does not auto-assign one (False). 3. its route table sends 0.0.0.0/0 to nat-b133915237ae2f79f and has no internet gateway route. 4. usms-db-sg admits only 5432 from sg-53dba8db862ba5440 (usms-app-sg), no CIDR. 5. usms-private-nacl (acl-5d56215445d40c55e) is associated, not the default NACL.
- You cannot test a negative, so I listed the controls that would each have to fail. Take any one away and the claim still holds.
- Review Question 5: if control 3 failed and the private route table got an internet gateway route, the database would still have no public address for the internet to send to, and usms-db-sg would still only admit usms-app-sg. If control 4 failed and usms-db-sg allowed 0.0.0.0/0, packets from the internet still could not arrive, because there is no public address and no internet gateway route, and usms-private-nacl would still deny anything its rules do not allow.

![Negative proof](../screenshots/lab09-step17-negative-proof.png)

## Step 18: persistence and nothing broken

- Part 1 recorded 10 facts in outputs/lab-09-pre-restart.txt: usms-ecs-task-role's trust condition has 2 keys, usms-deploy-role boundary None, usms-transcripts-reader-role exists with USMSStudentDataReadOnly, usms-dev-01 has 1 access key, 0 allow-all egress rules on usms-alb-sg, usms-enrolment-sg and usms-db-sg, 0 CIDR sources on usms-app-sg's SSH, and usms-web-01 HttpTokens optional.
- Part 2: floci-down.sh (docker compose stop, so state is kept) and floci-up.sh, then I sourced the env files again and cut the role ARNs down to names.
- Part 3: I looked up all 5 IDs again from the API (sg-43a4d32b229ced732, sg-b011f7193ccc66627, sg-9ffe4a3fff505ea08, sg-53dba8db862ba5440, i-00d916c5e2de6fcf8) and read the same 10 facts into outputs/lab-09-post-restart.txt. diff printed PERSISTENCE PROVEN.
- Honest limit: the boundary (None) and IMDS (optional) were already the Known Issue values before the restart, so for those two "unchanged" only shows Floci still does not store them. The other 8 facts are real controls that survived.
- Changes from the doc's commands: its egress and SSH queries were missing SecurityGroups[0]. (the same bug as Step 15) and compared IpProtocol to the number -1, so I used the fixed path and '-1' as text. The doc found three groups by tag Name, which my groups may not have, so I found all four by group name, which is still a fresh lookup from the API.

![Persistence proven](../screenshots/lab09-step18-persistence.png)
- Part 4: I ran verify-lab-02 to 06 again into outputs/lab-09-post-verify.txt, using the same grep for the PASS= FAIL= line as in Step 2. lab-02 PASS=33 FAIL=0, lab-03 PASS=34 FAIL=2, lab-04 PASS=39 FAIL=0, lab-05 PASS=47 FAIL=2, lab-06 PASS=39 FAIL=3. The diff with Step 2 printed NOTHING BROKE: no property an earlier lab checks has changed. It does not say this lab's own changes are correct; Section 8 checks that.

![Nothing broke](../screenshots/lab09-step18-nothing-broke.png)

## Step 19: configs/lab-09.env

- 16 exports, all looked up live (unquoted heredoc), so a filled-in value is proof the resource exists: the ARNs of USMSStudentDataReadOnly, USMSDeployBase, USMSPermissionsBoundary, usms-transcripts-reader-role and usms-deploy-role, usms-bastion-sg sg-f2639784fb4f0529e, prefix list pl-63a5400a, imds tokens optional, dev key created 2026-10-29T06:22:17, allow-all egress left 0 and review date 2026-10-29.
- No secrets, and grep -c AKIA gives 0, so not even the access key ID is in the file. It records the rotation date instead; the key ID lives only in outputs/, which git ignores.
- imds tokens is honestly optional, because Step 11 did not take on Floci. The doc allows that.
- The doc's USMS_EGRESS_ALLOW_ALL_REMAINING had the same missing SecurityGroups[0]. bug, and its || echo 0 would hide the error and always write 0. I used the doc's own alternative and worked out REMAINING first with a fixed query (0). I also looked up the S3 prefix list again, because Floci had been restarted.

![lab-09.env](../screenshots/lab09-step19-env.png)

## Section 8.1: verify-lab-09.sh

- I wrote the doc's script exactly as given and ran it once: PASS=39 FAIL=11. Then I fixed the script's own bugs and ran it again.
- Fixes, all in the checks and not in my work: (1) allowall() and the two "egress is tcp/443 only" checks and the SSH CIDR check queried IpPermissionsEgress/IpPermissions without SecurityGroups[0]., so length() got null (the same bug as Steps 15 and 18). (2) allowall() compared IpProtocol to the number -1; I used '-1' as text. (3) "no secret is tracked by git" failed on outputs/.gitkeep, the same one line fix as Labs 06 to 08. (4) "the boundary is attached to NOTHING" failed because the \\\" quoting inside eval broke its query, even though AttachmentCount is 0 and list-entities-for-policy shows no roles, users or groups. The doc says to confirm this case with list-entities-for-policy, so the check now counts roles with it. (5) "no policies/ document contains an unexpanded variable" flagged Lab 01's usms-self-manage-credentials.json, which uses ${aws:username}. That is an IAM policy variable that AWS fills in per user and must stay (the doc's own Step 7 note says so). All 10 Lab 09 documents had no $ at all. The check now ignores ${aws:...} but still fails on a real leftover shell variable (I tested it with ${USMS_X}).
- The script still has 50 checks. Final result: PASS=48 FAIL=2.
- The two failures are the doc's known benign ones and the course Known Issue for Lab 09: "usms-deploy-role HAS a permissions boundary" (Floci does not store it) and "usms-web-01 requires IMDSv2" (Floci rejects modify-instance-metadata-options).
- All three negatives that must stay true passed: usms-db-01 has no public address, the private subnet does not auto-assign one, and the private route table has no internet gateway route.

![Doc version](../screenshots/lab09-verify-doc-run.png)
![Fixed run part 1](../screenshots/lab09-verify-1.png)
![Fixed run part 2](../screenshots/lab09-verify-2.png)
![Diagnosing the last two](../screenshots/lab09-verify-diagnose.png)
![Final PASS=48 FAIL=2](../screenshots/lab09-verify-final.png)

## Section 8.2: cleanup script

- scripts/cleanup/lab-09-cleanup.sh is the doc's version. bash -n says the syntax is OK and I did NOT run it. It deletes the Lab 09 roles, policies and usms-bastion-sg and puts back the allow-all egress and the 10.0.0.0/16 SSH rule, after you type UNDO USMS SECURITY REVIEW. It does not undo the key rotation or IMDSv2, because a teardown should never leave the account less secure. It runs first, before lab-06-cleanup.sh, at the end of the course only.

![Cleanup script syntax](../screenshots/lab09-cleanup-syntax.png)

## Section 14: Review questions

**1. Why NOTHING BROKE is a strong result.** Five scripts written before this lab, checking more than 200 properties of Labs 2 to 6, gave exactly the same lines after I changed trust policies, egress on three groups and the SSH rule. So I added controls without changing what the system does. A plausible break would have been a Lab 02 or Lab 04 check that asserts usms-app-sg allows SSH from 10.0.0.0/16, or that a group still has its default egress. If that had happened I would read the check, decide whether it describes the old design (like Lab 05 Step 13), and update the check with a note saying why, instead of undoing the security fix.

**2. Attaching the boundary as an ordinary policy.** It stops being a ceiling and becomes a grant. Upwards, usms-deploy-role would get everything in it on Resource "*": ecs:*, elasticloadbalancing:*, logs:*, cloudwatch:*, s3 Get, List and PutObject, and iam:PassRole on any role with no condition. Downwards, the role has no ceiling any more, so a later broad policy is not capped, although the Deny statements still apply as identity denies. It is dangerous straight away, because iam:PassRole on "*" is the escalation path from Step 8. The Section 8 check "the boundary is attached to NOTHING as an ordinary policy" catches it, and the IAM audit would also flag the PassRole.

**3. A breach with every ingress rule correct.** An attacker uses a bug in the web app through the allowed tcp/80 or 443 on usms-web-01, makes the app fetch the instance's role credentials from the metadata service (IMDSv1 is still on), downloads transcripts with s3:GetObject and sends them out over HTTPS. Steps 13 to 15 narrow it only a little: db and enrolment can now only start HTTPS, so DNS tunnelling, SSH and odd ports are gone, and Exercise 1 did the same for the web tier, but tcp/443 to 0.0.0.0/0 is still open, so the data can still leave. Preventing it fully needs egress filtering by hostname (AWS Network Firewall or a proxy), IMDSv2, and a bucket policy that only accepts requests through the VPC endpoint. This course cannot build it, because Floci has no Network Firewall, carries no traffic and the bucket does not exist yet.

**4. An attacker calling sts:AssumeRole from their own machine.** usms-ecs-task-role and usms-transcripts-reader-role trust a service principal, ecs-tasks.amazonaws.com, so a call signed with the attacker's own credentials never matches the principal and is denied whatever the conditions say. The conditions protect the other path, ECS acting for a different account. usms-deploy-role trusts the user usms-admin-01, so anyone holding that user's keys can assume it from anywhere, and then only the boundary and the scoped PassRole limit what they do. The answers differ because only the service can become a service principal, but anyone with a user's keys can act as that user.

**5. Five controls against one.** The five controls on usms-db-01 (no public address, no auto assign, no internet gateway route, a group-only security group, a custom NACL) are mostly independent, so one mistake rarely breaks them all. But they are not five times better, because one person with ec2:* could change the route table and the security group in the same bad change, or launch a new public instance with usms-db-sg. usms-enrolment-sg looks like a single point only because the matrix models security groups. The tasks also sit in private subnets with no public address and no internet gateway route, so they are well protected on the network axis; the single rule only decides which internal source can reach port 80.

**6. The two extra rotation steps.** Moving every user of the key to the new one before touching the old key protects against an outage, for example a deployment that fails at night with InvalidClientTokenId because it still used the old key. Deactivating before deleting protects against a user I did not know about: if a forgotten job breaks, one update-access-key --status Active brings it back, while a deleted key is gone for good. A long lived key is a compromise because it never expires, so a key leaked in git or on a laptop works until someone notices. A real system gives people IAM Identity Center or federation with MFA and temporary credentials, and gives workloads roles: instance profiles, task roles or IRSA.

**7. Is reading enough instead of testing?** Not on its own, but on Floci it is the only proof available. Reading catches things testing cannot show here, like a trust policy with no condition or a Deny that adds nothing today but will matter after the next attachment, because on Floci every call succeeds anyway. Testing catches things reading misses, like a condition on a key the service never sends (aws:SourceArn for EC2 instance profiles), which reads as correct but denies everything at run time. For student transcripts I would want reading first, because it finds too much access, which is what causes a breach, and then a real test on AWS before going live.

## Section 15: keep and clean up

- outputs/lab-09-scoped-session.json and Lab 01's outputs/usms-dev-01-access-key.json are both gone. The only key file is usms-dev-01-access-key-new.json, which git ignores.
- USMSPermissionsBoundary is still there with 0 attachments. It looks like an orphan but it is the ceiling for usms-deploy-role, so I kept it.
- The evidence files in outputs/ (pre and post restart, pre and post verify, IMDS before and after) stay until my report is submitted, as the doc says, and are not committed. I did not run any cleanup script.

![Section 15 checks](../screenshots/lab09-section15.png)
