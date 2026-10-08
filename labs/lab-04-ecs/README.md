# Lab 4: Amazon ECS and Deploying the USMS Enrolment Service

Tenzin Namgay (02230307), DSO303

## Where to find everything

- **Report:** [report.md](report.md)
- **Exercises 1 to 5:** [exercises.md](exercises.md)
- **Notes and review questions:** in the `notes` folder at the repo root, [notes/lab-04-notes.md](../../notes/lab-04-notes.md). The Floci support path is at the top.
- **Screenshots:** in the `screenshots` folder at the repo root. All Lab 4 screenshots start with `lab04-`, for example `lab04-verify.png` and `lab04-ex5-linkage.png`. [Open the screenshots folder](../../screenshots)
- **Exercise 5 linkage file:** [lab-04-lab03-linkage.txt](lab-04-lab03-linkage.txt) (a committed copy of outputs/lab-04-lab03-linkage.txt, IDs only)

## Files in this lab

- `../../configs/lab-04.env`: cluster, service, task definition, role and security group values for Lab 5 and Lab 6
- `../../policies/trust-ecs-tasks.json`: trust policy shared by both ECS roles
- `../../policies/usms-ecs-task-execution-policy.json`: least privilege execution role policy
- `../../policies/usms-enrolment-sg-ingress.json`: tcp 80 from usms-app-sg only
- `../../templates/lab-04-taskdef.json`: original task definition (revisions 1 and 2)
- `../../templates/lab-04-taskdef-v3.json`: revision 3, image changed to nginx:stable (see report Section 7)
- `../../templates/lab-04-taskdef-v4.json`: revision 4, memory 1024 and USMS_LOG_LEVEL (Exercise 2)
- `../../scripts/utilities/verify-lab-04.sh`: checks 38 things about this lab
- `../../scripts/utilities/lab-04-ecs-inventory.sh`: ECS drift report (Exercise 3)
- `../../scripts/cleanup/lab-04-cleanup.sh`: end of course only, not run

## Result

verify-lab-04.sh: PASS=38 FAIL=0. The service runs 2 tasks on usms-enrolment:4 across both private subnets with no public IP.