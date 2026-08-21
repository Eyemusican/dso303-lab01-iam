# Lab 01 — IAM — completed

## What exists after this lab
- Environment: Floci via docker-compose.yml, FLOCI_STORAGE_MODE=hybrid,
  bind-mounted to ~/floci-data, persistence proven in Step 14
- Groups: usms-admins, usms-developers, usms-auditors
- Users: usms-admin-01, usms-dev-01, usms-audit-01
- Customer managed policies: USMSDeveloperBase (v2), USMSStudentDataReadWrite,
  USMSAssumeAppRoles, USMSLambdaBasic
- Inline policy: USMSSelfManageCredentials on usms-dev-01
- Roles: usms-ec2-app-role, usms-lambda-exec-role, usms-developer-role
- Instance profile: usms-ec2-app-profile

## Reproduce
    source ~/aws-floci-course/configs/course.env
    ./scripts/setup/floci-up.sh
    source ~/aws-floci-course/configs/lab-01.env
    ./scripts/utilities/verify-lab-01.sh

## Evidence
- [ ] whoami.sh output showing account 000000000000
- [ ] floci-storage-check.sh output, all [ok]
- [ ] Step 14 persistence proof (user survived a restart)
- [ ] verify-lab-01.sh with FAIL=0

## Problems I hit and how I fixed them

1. Floci CLI kept downloading corrupted

I carried out the installation of the Floci CLI using the official PowerShell script three separate times, but every time it resulted in a different file size (31MB, 3.7MB, and 41MB), which Windows rejected as "not a valid application for this operating system." I found the underlying reason was that my regular internet connection was corrupting the download. The problem was resolved when I switched to a mobile hotspot for the next attempt.

2. AWS CLI could not communicate with Floci — missing endpoint_url

After I completed the configuration of the floci profile, the aws iam list-users command resulted in an error stating InvalidClientTokenId, indicating that AWS CLI was attempting to connect to real AWS instead of the local emulator. I examined ~/.aws/config and found the endpoint_url parameter was missing entirely. I added it manually, which resolved the error.


3. PowerShell Cannot Run Shell Scripts

Every work script (floci-up.sh, whoami.sh) either failed silently or crashed unexpectedly when I tried running them in PowerShell, since PowerShell does not understand bash  lines. I had to switch to Git Bash to get anything script-based working, while continuing to use PowerShell for the Windows installers.

4. Absence of Python During Step 27

This step expected a Python script to programmatically add two new actions to an existing policy file. Neither python and also python3 was recognized on my system, and my attempts to install Python (via winget, then the official installer) didn't fully register. I worked around this by manually editing the policy JSON in a text editor instead same final result, just without automation.

5. chmod 600 did not have any effect on Windows/NTFS

When I generated a real access key file, I attempted to restrict its permissions using chmod 600 (owner-only access) as instructed by the lab. However, on Windows' NTFS file system, the command runs without errors but doesn't actually do anything, since NTFS doesn't use Unix-style permission bits. The file's permissions stayed at the default setting, though Git's .gitignore filtering still worked correctly and protected the secret file from being versioned.