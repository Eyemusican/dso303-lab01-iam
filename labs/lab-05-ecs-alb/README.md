# Lab 5: Putting the ECS Service Behind an Application Load Balancer

Tenzin Namgay (02230307), DSO303

## Where to find everything

- **Report:** [report.md](report.md)
- **Exercises 1 to 5:** [exercises.md](exercises.md)
- **Notes and review questions:** in the `notes` folder at the repo root, [notes/lab-05-notes.md](../../notes/lab-05-notes.md). The Floci support path is at the top, and the Section 12.1 observed versus conceptual list and the seven review questions are at the end.
- **Screenshots:** in the `screenshots` folder at the repo root. All Lab 5 screenshots start with `lab05-`, for example `lab05-step16-persistence-proven.png` and `lab05-ex5-label-verified.png`. [Open the screenshots folder](../../screenshots)

## Result

verify-lab-05.sh: PASS=47 FAIL=2. Both failures come from one Floci limitation (the health check grace period is never stored) and are explained in the notes under Step 10 and Section 9.

After Exercise 2, verify-lab-04.sh: PASS=39 FAIL=0.

The service runs 2 tasks on usms-enrolment:4 behind usms-enrolment-alb. After the Step 13 cutover, usms-enrolment-sg admits tcp 80 only from usms-alb-sg, and everything survived a Floci restart (PERSISTENCE PROVEN).

## Files in this lab

- `../../configs/lab-05.env`: load balancer, target group, listener and service values for Lab 06 (16 exports, including USMS_ALB_RESOURCE_LABEL)
- `../../policies/usms-alb-sg-ingress.json`: tcp 80 from 0.0.0.0/0 for the load balancer
- `../../policies/usms-alb-sg-ingress-443.json`: tcp 443 from 0.0.0.0/0 (Step 4 Your turn)
- `../../policies/usms-enrolment-sg-ingress-alb.json`: tcp 80 into the tasks from usms-alb-sg only
- `../../templates/lab-05-listener-default-actions.json`: listener default action, forward to usms-enrolment-tg
- `../../templates/lab-05-rule-conditions.json` and `lab-05-rule-actions.json`: the /alb-health rule
- `../../templates/lab-05-service-load-balancers.json`: the service's loadBalancers entry
- `../../templates/lab-05-ex1-results-conditions.json` and `lab-05-ex1-results-actions.json`: Exercise 1 practice rule (objects removed in Exercise 4)
- `../../scripts/utilities/verify-lab-05.sh`: checks 49 things about this lab
- `../../scripts/utilities/usms-lb-report.sh`: load balancer decision table report (Exercise 3)
- `../../scripts/utilities/usms-resource-label.sh`: builds the ALBRequestCountPerTarget ResourceLabel from the API (Exercise 5)
- `../../scripts/cleanup/lab-05-cleanup.sh`: end of course only, not run

## Floci support path

Path A for the control plane and health checks, path B for the client data path: every object was created and the targets went healthy, but the load balancer's DNS name did not resolve from my shell, so I never got a 200 through it.
