# Lab 4: Amazon ECS and Deploying the USMS Enrolment Service

**Student Name:** Tenzin Namgay

**Student ID:** 02230307

**Module:** DSO303 : Cloud Native Infrastructure

**Practical:** Lab 4 : ECS

## 1. Aim / Objective

The aim of this lab was to move the USMS enrolment service from a hand run EC2 server onto Amazon ECS with Fargate, inside the network from Lab 2, using Floci and the AWS CLI. This included creating an ECS cluster, a log group with retention, separate task execution and task roles (reusing the Lab 1 S3 policy), a security group sourced from the web tier's group, a task definition, and a service that keeps two tasks running across two private subnets. The service was built at a fixed size on purpose, so that Lab 05 can add a load balancer and Lab 06 can add auto scaling on top of it.

## 2. Introduction

Amazon ECS runs containers. It is built from four objects: a cluster (a logical boundary), a task definition (an immutable, versioned recipe for a container), a task (one running copy of that recipe), and a service (which keeps a chosen number of tasks running and replaces any that stop). Fargate is the launch type where AWS provides the compute, so there are no EC2 instances to choose, patch or scale. Each task gets two IAM roles: the execution role, which ECS uses to pull the image and write logs, and the task role, which the application inside the container uses. ECS matters for USMS because enrolment week brings a huge spike of traffic for a short time, and a service whose task count can be changed is the foundation for handling that.

## 3. Use Case

- Running the USMS enrolment API as containers in private subnets, reachable only from the web tier
- Keeping two copies running, one per Availability Zone, so losing one zone does not stop enrolment
- Giving the enrolment containers access to student transcripts in S3 through a task role, with no access key in the image or on disk
- Changing the application safely by registering a new task definition revision and pointing the service at it
- Preparing a service whose desiredCount can later be changed automatically for enrolment week

## 4. System Architecture / Design

The ECS cluster usms-ecs-cluster holds one service, usms-enrolment-svc. It runs 2 Fargate tasks from the task definition family usms-enrolment, spread over usms-private-subnet-a (10.0.3.0/24) and usms-private-subnet-b (10.0.4.0/24), with no public IP. Each task carries usms-enrolment-sg, which only allows tcp 80 from usms-app-sg, the group on usms-web-01 from Lab 3. The tasks have no route to the internet gateway and reach the internet only through usms-nat from Lab 2, which is how they pull their image. The execution role usms-ecs-exec-role pulls the image and writes to the log group /usms/ecs/enrolment (7 day retention). The task role usms-ecs-task-role carries USMSStudentDataReadWrite, the same policy that usms-ec2-app-role carries in Lab 3.

    usms-web-01 [usms-app-sg]  (Lab 3, public subnet a)
          |
          | tcp 80, allowed by group reference
          v
    usms-ecs-cluster
     usms-enrolment-svc   desiredCount 2, FARGATE, assignPublicIp DISABLED
       task in usms-private-subnet-a  [usms-enrolment-sg]
       task in usms-private-subnet-b  [usms-enrolment-sg]
          |
          | image pull and outbound only via usms-nat (Lab 2)
          |
     execution role usms-ecs-exec-role -> USMSECSTaskExecution -> /usms/ecs/enrolment logs
     task role usms-ecs-task-role      -> USMSStudentDataReadWrite (Lab 1) -> usms-student-data

## 5. Implementation Procedure

### Part A: Getting ready

I loaded the env files from Labs 1 to 3 and checked that Labs 2 and 3 were still intact. verify-lab-02.sh gave PASS=32 FAIL=1 and verify-lab-03.sh gave PASS=34 FAIL=2, the known failures from those labs. The two checks this lab depends on, the private route table having no internet gateway route and usms-web-01 carrying usms-app-sg, both passed.

![Environment loaded](../../screenshots/lab04-step01-env-loaded.png)
![Labs 2 and 3 verify part 1](../../screenshots/lab04-step02-verify-lab02-03a.png)
![Labs 2 and 3 verify part 2](../../screenshots/lab04-step02-verify-lab02-03b.png)

I probed what this Floci build supports. Two lines first said "not available", so I checked the real errors. describe-services returned ClusterNotFoundException, which is expected because the probe uses a fake cluster, so ECS is supported. describe-scheduled-actions returned UnsupportedOperation, so scheduled actions are really missing. My path is Path A with one gap, which only affects Lab 06.

![Floci probe](../../screenshots/lab04-step03-probe.png)
![Probe errors](../../screenshots/lab04-step03-probe-errors.png)

### Part B: Cluster, logs and roles

I assumed usms-developer-role and created the cluster as that role, then dropped back to my normal identity. assume-role returned the session name lab04-ecs-build, but get-caller-identity showed floci-session, so Floci ignores the session name there. The cluster came back ACTIVE with Container Insights enabled.

![Assumed developer role](../../screenshots/lab04-step04-assume-role.png)
![Cluster created](../../screenshots/lab04-step04-cluster-created.png)
![Cluster verified](../../screenshots/lab04-step04-cluster-verify.png)

I created the log group /usms/ecs/enrolment with 7 day retention, so logs are not kept and charged forever.

![Log group](../../screenshots/lab04-step05-log-group.png)

I created the execution role with a trust policy for ecs-tasks.amazonaws.com and my own least privilege policy, USMSECSTaskExecution, which can pull images and write only to my one log group. Then I created the task role and attached the Lab 1 policy USMSStudentDataReadWrite, unchanged. Reading the policy back showed exactly the same document Lab 3 Step 11 printed.

![Execution role](../../screenshots/lab04-step06-exec-role.png)
![Execution policy](../../screenshots/lab04-step06-exec-policy.png)
![Execution role verified](../../screenshots/lab04-step06-exec-role-verify.png)
![Task role](../../screenshots/lab04-step07-task-role.png)
![Task role policy, same as Lab 3](../../screenshots/lab04-step07-task-role-policy.png)

### Part C: Security group and task definition

I created usms-enrolment-sg with one inbound rule, tcp 80 from usms-app-sg by group reference. Reading it back showed FromGroup sg-53dba8db862ba5440 and FromCIDR null, so this time Floci kept the group reference that it dropped on usms-db-sg in Lab 2.

![Enrolment security group](../../screenshots/lab04-step08-enrolment-sg.png)
![Enrolment security group verified](../../screenshots/lab04-step08-enrolment-sg-verify.png)

I wrote the task definition as a JSON template with awsvpc networking, FARGATE, cpu 256, memory 512, both roles and the awslogs settings, checked it had no unexpanded variables, and registered it. It came out as revision 2 because the register command ran twice, and revision 1 is the same document.

![Task definition written](../../screenshots/lab04-step09-taskdef-written.png)
![Task definition registered](../../screenshots/lab04-step09-taskdef-registered.png)
![Task definition verified](../../screenshots/lab04-step09-taskdef-verify.png)

### Part D: The service, and fixing the crashing tasks

I created usms-enrolment-svc with desiredCount 2 in both private subnets, with no public IP. runningCount stayed at 0. Floci's logs showed it did start real containers, but each one crashed with "exec format error", and the service kept replacing them.

![Service created](../../screenshots/lab04-step10-service-created.png)
![runningCount stayed at 0](../../screenshots/lab04-step10-service-stable-check.png)
![exec format error in the Floci logs](../../screenshots/lab04-step10-exec-format-error.png)

Following the lab's troubleshooting section, I read the stopped task's reason, "Essential container in task exited". Running the image directly with docker run gave the same error, and testing showed every Alpine based nginx image fails on my Docker Desktop while the Debian based nginx:stable works, even though both are amd64.

![Running the image directly also failed](../../screenshots/lab04-step10-image-corrupted.png)
![Image test](../../screenshots/lab04-step10-image-test.png)
![Stopped reason](../../screenshots/lab04-step10-stopped-reason.png)

Because a revision cannot be edited, I copied the template, changed only the image, registered usms-enrolment:3, and pointed the service at it. The service reached desired=2 running=2 with two real containers.

![Revision 3](../../screenshots/lab04-step10-revision3.png)
![Service running](../../screenshots/lab04-step10-service-running.png)

### Part E: Reading it back, scaling by hand, and recording it

I read the service back: ACTIVE, desired 2, running 2, pending 0, FARGATE, two private subnets, public IP DISABLED. list-tasks without a status filter returned 282 tasks, which was 2 running plus 280 stopped from the crash loop. Then I scaled to 3 and back to 2 by hand and watched the tasks follow.

![Service details](../../screenshots/lab04-step11-service-details.png)
![Task counts](../../screenshots/lab04-step11-tasks-count.png)
![Scaling by hand](../../screenshots/lab04-step11-scale-by-hand.png)

I wrote configs/lab-04.env by looking every value up, checked the role credentials file is git ignored, wrote the verify and cleanup scripts, and committed.

![lab-04.env](../../screenshots/lab04-step12-env-file.png)
![Credentials file ignored](../../screenshots/lab04-step13-ignored.png)
![Verify PASS=38 FAIL=0](../../screenshots/lab04-verify.png)
![Commit](../../screenshots/lab04-step13-commit.png)

## 6. Results and Evidence

### 6.1 CLI / SDK Evidence

All screenshots are referenced in Section 5. verify-lab-04.sh reports PASS=38 FAIL=0. The five exercises are in labs/lab-04-ecs/exercises.md and the review questions are in notes/lab-04-notes.md.

### 6.2 AWS Management Console Verification

Floci has no graphical console, so all verification was done through the CLI.

## 7. Analysis and Discussion

Everything the lab asked for is in place and verify-lab-04.sh passes all 38 checks. These are the things that did not go as the lab expected.

**Floci limitations:**
1. describe-scheduled-actions returned UnsupportedOperation. Scheduled scaling is not available on this build, which matters for Lab 06.
2. get-caller-identity always showed the session name floci-session, even though assume-role returned lab04-ecs-build.
3. Service events came back as None, so the service gives no history of what it did.
4. list-tasks without --desired-status returned stopped tasks too. Real AWS returns only running tasks by default.
5. The container log streams were created under /ecs/usms-enrolment, not under my log group /usms/ecs/enrolment, so Floci ignored the awslogs-group option.
6. In Exercise 5, the instance.group-id filter on describe-instances was ignored. A made up group still returned every running instance.

**Docker issue on my laptop:** every Alpine based nginx image crashed with "exec format error", including a fresh download, while nginx:stable worked. The crash loop created and stopped 280 tasks in about 15 minutes and froze Docker Desktop once. I fixed it the ECS way, with revision 3 and update-service. On real AWS the lab's image would run normally.

**Windows issues:** I added MSYS_NO_PATHCONV=1 where a name starts with /, like the log group, and tr -d '\r' where a loop compares CLI output. My lab-01.env stores two values as full ARNs, so I used them directly instead of building ARNs the way the lab's commands do.

**A bug in the verify script:** the "no secret is tracked by git" check failed on outputs/.gitkeep, which the lab itself says must be tracked. I changed it to ignore .gitkeep and still fail on anything else.

## 8. Reflection

**What did I learn about this AWS service?**
I learned that ECS is really four separate objects, and that the service is the one that does the work of keeping tasks running. I also learned why there are two roles: one for ECS to start the container and one for the app inside it, and that both can use the same trust policy while having completely different permissions.

**What challenges did I encounter?**
The hardest part was the crashing containers. At first I guessed it was a chip mismatch and then a corrupted download, and both guesses were wrong. Testing images directly with docker run is what found the real cause. The crash loop also showed me how fast a service keeps retrying a broken task.

**How would I apply this in a real world cloud environment?**
I would keep containers in private subnets and only let the callers that need them in, by security group reference. I would give each service its own task role with least privilege, and change images by registering a new revision instead of editing anything in place.

**What additional concepts would I like to explore?**
I want to see how a load balancer attaches to this service in Lab 05 and how auto scaling changes desiredCount in Lab 06.

## 9. Conclusion

This lab moved the USMS enrolment service onto ECS Fargate: a cluster, a log group, two separate roles, a security group sourced from the web tier, a task definition and a service running two tasks across two private subnets. The task role reuses the Lab 1 policy unchanged, so the EC2 web server and the enrolment containers now share one permission through two mechanisms. verify-lab-04.sh passes all 38 checks, and all five exercises are done. The objectives were achieved, and the service is ready for a load balancer in Lab 05 and auto scaling in Lab 06.

## 10. Appendix (Optional)

- GitHub repository: https://github.com/Eyemusican/dso303-lab01-iam
- Exercises: labs/lab-04-ecs/exercises.md
- Notes and review questions: notes/lab-04-notes.md
- Task definitions: templates/lab-04-taskdef.json, lab-04-taskdef-v3.json, lab-04-taskdef-v4.json
- Policies: policies/trust-ecs-tasks.json, policies/usms-ecs-task-execution-policy.json, policies/usms-enrolment-sg-ingress.json
- Scripts: scripts/utilities/verify-lab-04.sh, scripts/utilities/lab-04-ecs-inventory.sh, scripts/cleanup/lab-04-cleanup.sh