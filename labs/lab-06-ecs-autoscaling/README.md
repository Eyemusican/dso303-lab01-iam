# Lab 6: ECS Service Auto Scaling

Tenzin Namgay (02230307), DSO303

## Where to find everything

- **Report:** [report.md](report.md)
- **Exercises 1 to 5:** [exercises.md](exercises.md)
- **Notes and review questions:** in the `notes` folder at the repo root, [notes/lab-06-notes.md](../../notes/lab-06-notes.md). The support path, every step's notes and Floci limitations, the Section 11 observed versus conceptual list and the seven review questions are all there.
- **Screenshots:** in the `screenshots` folder at the repo root. All Lab 6 screenshots start with `lab06-`, for example `lab06-step12-scaling-activities.png` and `lab06-checkpoint7.png`. [Open the screenshots folder](../../screenshots)

## Result

verify-lab-06.sh: PASS=39 FAIL=3. All three failures are the scheduled action checks. PutScheduledAction and DescribeScheduledActions return UnsupportedOperation on my Floci build, which Section 8 lists as a benign failure. This is explained in the notes under Step 11 and Section 8.1.

verify-lab-05.sh gives the same output as before this lab (PASS=47 FAIL=2, an empty diff).

The service has a scalable target (min 2, max 10), two target tracking policies (CPU 50, requests 1000), and a step policy driven by usms-enrolment-queue-high. In Step 12 the alarm fired by itself and scaled the service from 2 to 10, and the scaling activity's Cause names both the alarm and the policy. Everything survived a Floci restart (PERSISTENCE PROVEN).

## Files in this lab

- `../../configs/lab-06.env`: every name, ARN and number for later labs (24 exports after Exercise 5)
- `../../templates/lab-06-target-tracking-cpu.json`: CPU target tracking at 50
- `../../templates/lab-06-target-tracking-requests.json`: ALBRequestCountPerTarget at 1000 with the ResourceLabel
- `../../templates/lab-06-step-scaling-out.json`: +1 / +3 step scaling
- `../../templates/lab-06-suspended-state.json`: the scale in suspension runbook document
- `../../templates/lab-06-target-tracking-memory.json` and `lab-06-step-scaling-in.json`: Exercise 1 and 2 practice configs (objects removed)
- `../../scripts/utilities/verify-lab-06.sh`: checks 42 things about this lab
- `../../scripts/utilities/usms-scaling-report.sh`: scaling decision table with a verdict (Exercise 3)
- `../../scripts/utilities/usms-scaling-history.sh`: exports the whole scaling configuration and history as JSON (Exercise 5)
- `../../scripts/cleanup/lab-06-cleanup.sh`: end of course only, not run
- `../../scripts/cleanup/lab-05-cleanup.sh`: stale cleanup order hints repaired (Step 17)

## Floci support path

Path A for the scaling loop: the alarm evaluated by itself, invoked the step policy and changed desiredCount, with the activity recorded. Scheduled scaling stayed conceptual because my build does not support it.
