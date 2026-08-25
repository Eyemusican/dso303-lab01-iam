# Lab 01 Notes

## Exercise 4 — Backup operator design decision

I went with a role for the backup operator, not a user or group, since this is an automated nightly job with nobody typing commands. A role only hands out temporary credentials when the job actually runs, so there's no permanent access key sitting on a server or inside a script that could leak. Same reasoning as usms-ec2-app-role in Step 28, a role is the right call whenever a service or scheduled process needs to act, not a person.

### Three ways this policy could still be abused

1. The archive bucket could be used to move data out. The role can copy anything from usms-student-data into usms-archive, so if the archive bucket itself is readable by anything outside this role's intended use, student data effectively leaves its controlled location. I would close this by putting a bucket policy on usms-archive that only allows access from this specific role.

2. The logging permission covers the whole log group, not one stream. If another process also had write access to the same log group, it could write fake completion log entries that look like they came from the backup job. I would close this by giving each run its own timestamped log stream and scoping the policy tighter, or adding a Condition on logs:PutLogEvents that checks the stream name pattern.

3. The trust policy trusts all of ec2.amazonaws.com, so any EC2 instance profile in the account could assume this role, not just the one running the actual backup job. I would close this with a Condition on the trust policy using aws:SourceArn to restrict which specific instance or instance profile is allowed to assume it.