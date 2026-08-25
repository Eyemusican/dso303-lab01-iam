# Lab 01 Notes



## Exercise 4 — Backup operator design decision



I chose a role for the USMS backup operator instead of a user or a group. This is an automated nightly job with no person typing commands, so it should not have a permanent access key sitting on a server or inside a script where it could leak. A role only hands out temporary credentials when the job actually runs, which is the same reasoning behind usms-ec2-app-role in Step 28. A role is the right choice whenever a service or a scheduled process, not a human, needs to act.



### Three ways this policy could still be abused



1. **The archive bucket could be used to exfiltrate data.** The role can copy anything from usms-student-data into usms-archive. If someone with access to the archive bucket from outside this role's intended use could read it, student data effectively leaves its controlled location. I would close this by adding a bucket policy on usms-archive that only allows access from this specific role, and nothing else.



2. **Log group access is broader than one log stream.** The Resource for the logging statement is scoped to the log group /usms/backup-operator, but not to a single log stream inside it. If another process also had permission to write to that same log group, it could inject false completion log entries that look like they came from the backup job. I would close this by having each run generate a unique, timestamped log stream name that the policy could reference more strictly, or by using a Condition on logs:PutLogEvents that checks the log stream name pattern.



3. **The role can be assumed by anything running as an EC2 instance in the account, not just the backup job's specific instance.** The trust policy trusts the whole ec2.amazonaws.com service, so any EC2 instance profile pointed at this role could assume it, not only the one actually running the nightly backup. I would close this by adding a Condition on the trust policy using aws:SourceArn or a similar key to restrict which specific EC2 resource, or which specific instance profile, is allowed to assume the role.

