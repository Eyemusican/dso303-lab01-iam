# Lab 2: Virtual Private Cloud and Networking

Tenzin Namgay (02230307), DSO303

## Where to find everything

- **Report:** [report.md](report.md)
- **Exercises 1 to 5:** [exercises.md](exercises.md)
- **Notes and review questions:** in the `notes` folder at the repo root, [notes/lab-02-notes.md](../../notes/lab-02-notes.md)
- **Screenshots:** in the `screenshots` folder at the repo root, [open the screenshots folder](../../screenshots). Each screenshot is linked in the report and exercises at the step where it was taken. Exercise 5 screenshots start with `lab02-exercise5-`.

## Files in this lab

- `../../configs/lab-02.env`: VPC, subnet, security group and NAT IDs used by Lab 3
- `../../policies/usms-db-sg-ingress.json`: the database security group ingress rule
- `../../scripts/utilities/verify-lab-02.sh`: checks 33 things about the network
- `../../scripts/utilities/lab-02-network-report.sh`: network report script (Exercise 3)
- `../../scripts/utilities/floci-storage-check.sh`: storage check, with the Windows path fix I made in this lab
- `../../scripts/cleanup/lab-02-cleanup.sh`: end of course only, not run
- `../../templates/create-vpc-skeleton.json`: the skeleton I generated for aws ec2 create-vpc with --generate-cli-skeleton in Lab 1 Step 24, ready for this lab. It stands in for the lab-02-subnet-skeleton.json name in the directory structure, because no step in Lab 2 generates a separate subnet skeleton.

## Result

verify-lab-02.sh: PASS=32 FAIL=1. The one failure is Floci dropping group referenced security group rules, explained with evidence in Section 7 of the report.