# Lab 09: Securing the USMS Application with IAM Roles and Security Groups

Tenzin Namgay (02230307), DSO303

## Where to find everything

- Report: [report.md](report.md)
- Exercises 1 to 5: [exercises.md](exercises.md)
- Notes and review questions: [../../notes/lab-09-notes.md](../../notes/lab-09-notes.md)
- Screenshots: [../../screenshots/](../../screenshots/) (all files start with lab09-)
- Architecture diagram: [../../diagrams/lab09-architecture.png](../../diagrams/lab09-architecture.png)

## Result

I reviewed the USMS system from Labs 1 to 6 on both axes, who can call what (IAM) and what can reach what (security groups and routing), with read only audit scripts, and then fixed what they found.

- Identity: a read only transcripts policy and role, confused deputy conditions on the ECS task, ECS execution and Lambda trust policies, a deploy role with iam:PassRole scoped to three named roles and a permissions boundary, a session policy whose intersection I worked out, a rotated access key for usms-dev-01, and a break glass role that needs MFA and an ExternalId.
- Network: written egress on usms-alb-sg, usms-enrolment-sg, usms-db-sg and usms-app-sg, and SSH to the web tier only from usms-bastion-sg instead of the whole VPC.
- Proof: usms-db-01 is unreachable from the internet by five independent controls, PERSISTENCE PROVEN after a Floci stop and start, and NOTHING BROKE in the five earlier verify scripts.
- verify-lab-09.sh: PASS=48 FAIL=2. The two failures are the course Known Issue for Lab 09 (permissions boundary and IMDSv2 not stored).
- I wrote the cleanup script but did not run it.

## Files in this lab

- [../../policies/usms-student-data-ro-policy.json](../../policies/usms-student-data-ro-policy.json)
- [../../policies/trust-ecs-tasks-scoped.json](../../policies/trust-ecs-tasks-scoped.json)
- [../../policies/usms-permissions-boundary.json](../../policies/usms-permissions-boundary.json)
- [../../policies/usms-deploy-policy.json](../../policies/usms-deploy-policy.json)
- [../../policies/trust-deploy.json](../../policies/trust-deploy.json)
- [../../policies/usms-egress-allow-all.json](../../policies/usms-egress-allow-all.json) (the undo)
- [../../policies/usms-enrolment-sg-egress.json](../../policies/usms-enrolment-sg-egress.json)
- [../../policies/usms-alb-sg-egress.json](../../policies/usms-alb-sg-egress.json)
- [../../policies/usms-db-sg-egress.json](../../policies/usms-db-sg-egress.json)
- [../../policies/usms-app-sg-ssh-bastion.json](../../policies/usms-app-sg-ssh-bastion.json)
- [../../policies/usms-app-sg-egress.json](../../policies/usms-app-sg-egress.json) (Exercise 1)
- [../../policies/trust-breakglass.json](../../policies/trust-breakglass.json) and [../../policies/usms-breakglass-policy.json](../../policies/usms-breakglass-policy.json) (Exercise 2)
- [../../policies/trust-lambda-scoped.json](../../policies/trust-lambda-scoped.json) (Exercise 2)
- [../../configs/lab-09.env](../../configs/lab-09.env) (17 exports, no secrets)
- [../../configs/iam-accepted-findings.txt](../../configs/iam-accepted-findings.txt) (Exercise 2)
- [../../scripts/utilities/usms-iam-audit.sh](../../scripts/utilities/usms-iam-audit.sh)
- [../../scripts/utilities/usms-sg-audit.sh](../../scripts/utilities/usms-sg-audit.sh)
- [../../scripts/utilities/usms-reachability-matrix.sh](../../scripts/utilities/usms-reachability-matrix.sh)
- [../../scripts/utilities/usms-exposure-report.sh](../../scripts/utilities/usms-exposure-report.sh) (Exercise 3)
- [../../scripts/utilities/usms-bucket-policy-draft.sh](../../scripts/utilities/usms-bucket-policy-draft.sh) (Exercise 5)
- [../../scripts/utilities/student-fallback-demo.py](../../scripts/utilities/student-fallback-demo.py) (course Known Issues fallback)
- [../../scripts/utilities/verify-lab-09.sh](../../scripts/utilities/verify-lab-09.sh)
- [../../scripts/cleanup/lab-09-cleanup.sh](../../scripts/cleanup/lab-09-cleanup.sh) (written, not run)

## Floci support path

I was on Path B (roles, policies and rules can be created and read), with simulate-principal-policy also answering. Floci enforces no IAM and carries no traffic, so every control here is proved by reading it, not by seeing a request fail.

What did not work and what I did instead:

- Permissions boundaries are accepted but not stored (get-role shows null), and modify-instance-metadata-options returns UnsupportedOperation. This is the course Known Issue for Lab 09, so I ran the course fallback student-fallback-demo.py security, recorded both as not demonstrated, and wrote what real AWS would do.
- revoke-security-group-egress and revoke by rule ID return True but describe-security-group-rules keeps showing the rule. describe-security-groups is correct, so I checked every rule there, which is also what the verify script reads.
- Several commands in the doc had bugs that I fixed and recorded in the notes: queries missing SecurityGroups[0]., IpProtocol compared to the number -1, a bastion lookup that returned nothing, /tmp paths inside python3 -c on Windows, and two verify checks with broken quoting.
- Floci does not create network interfaces for the load balancer, the NAT or the Fargate tasks, and gave usms-web-01 no public address, so the exposure report only shows the instances.
