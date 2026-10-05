# Lab 04 Notes

## Floci support path

**Path A (full), with one gap.**

I ran the Step 3 probe. ECS (list-clusters, register-task-definition, describe-services) and Application Auto Scaling (describe-scalable-targets, describe-scaling-policies) are supported, and so are CloudWatch and CloudWatch Logs.

Two probe lines first said "not available", so I checked the real errors:
- ecs describe-services returned ClusterNotFoundException. That is expected, because the probe uses a cluster called "probe" that does not exist, so ECS is supported.
- application-autoscaling describe-scheduled-actions returned UnsupportedOperation. This one is really missing from this Floci build.

Nothing in this lab uses scheduled actions, so Lab 4 is not affected. In Lab 6, scheduled scaling (for example scaling up before enrolment week) will not work on this build, and I will need the documented fallback there.


## Step 7: One policy, two kinds of compute

I attached USMSStudentDataReadWrite, the same policy Lab 1 made for the EC2 role, to the new ECS task role usms-ecs-task-role. When I read the policy back, it was exactly the same document Lab 3 Step 11 printed: list the bucket, get, put and delete objects inside it, and a Deny on DeleteBucket, all on arn:aws:s3:::usms-student-data.

So usms-web-01 (through the instance profile and usms-ec2-app-role) and the enrolment task (through taskRoleArn and usms-ecs-task-role) now hold the same permission through two different mechanisms. Neither has an access key on disk, and the policy did not need any change. Both will start working at the same moment a later lab creates the usms-student-data bucket.

Small note: my lab-01.env stores USMS_POLICY_S3_RW and USMS_ROLE_DEVELOPER as full ARNs, not just names, so I used the variables directly instead of building the ARN the way the lab's commands do.



## Step 10: Tasks crashing, and switching to revision 3

After creating usms-enrolment-svc, runningCount stayed at 0 with desiredCount 2. The Floci logs showed it did start real Docker containers for both tasks, but each one crashed straight away with "exec /docker-entrypoint.sh: exec format error". The service kept starting new tasks that crashed again, and this loop froze Docker Desktop once, so I had to restart it.

I followed the lab's troubleshooting section. The service events came back as None, because Floci does not record them, and the stopped task's stoppedReason was "Essential container in task exited", which matches essential=true in the task definition.

To find the real cause I ran the image directly with docker run, without Floci. The lab's image nginx:stable-alpine failed with the same error, and so did a freshly downloaded nginx:alpine from the Docker library. The Debian based nginx:stable worked (nginx/1.30.5, exit code 0). Both images and my laptop are amd64, so it was not a chip mismatch. Alpine based nginx images just do not run on my Docker Desktop setup.

Since a task definition revision cannot be edited, I copied the template to templates/lab-04-taskdef-v3.json, changed only the image to public.ecr.aws/nginx/nginx:stable, registered it as usms-enrolment:3, and pointed the service at it with update-service. The original template stays as it was, because it produced revisions 1 and 2. After the update the service reached desired=2 running=2, with two real containers running.

Revision 2 instead of 1 happened because the register command ran twice. Revision 1 is the same document as revision 2.


## Verify script: a bug in the git check

The first run gave PASS=37 FAIL=1. The failing check was "no secret is tracked by git", which ran git ls-files | grep -q '^outputs/'. git ls-files outputs/ only listed outputs/.gitkeep, so no secret was tracked. The check fails on any file in outputs/, including .gitkeep, which has to be there to keep the folder in Git, and the lab's own Step 13 says git ls-files outputs/ should list exactly outputs/.gitkeep. So on a correct repository this check can never pass. I changed it to ignore .gitkeep and fail on anything else: git ls-files outputs/ | grep -vx 'outputs/.gitkeep' | grep -q . After that the script gave PASS=38 FAIL=0.

I also added export MSYS_NO_PATHCONV=1 at the top of the script, because Git Bash on Windows turns /usms/ecs/enrolment into a Windows path, which would make the log group checks fail for no real reason.