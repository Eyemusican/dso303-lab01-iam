# Lab 3: Amazon EC2 and Deploying the USMS Application

Tenzin Namgay (02230307), DSO303

## Where to find everything

- **Report:** [report.md](report.md)
- **Exercises 1 to 5:** [exercises.md](exercises.md)
- **Notes and review questions:** in the `notes` folder at the repo root, [notes/lab-03-notes.md](../../notes/lab-03-notes.md)
- **Screenshots:** in the `screenshots` folder at the repo root. All Lab 3 screenshots start with `lab03-`, for example `lab03-step12-userdata-proven.png` and `lab03-ex3-reachability.png`. [Open the screenshots folder](../../screenshots)

## Files in this lab

- `user-data.sh`: bootstrap script for usms-web-01
- `user-data-db.sh`: idempotent bootstrap script for the data tier (Exercise 2)
- `transcript-upload.sh`: S3 upload script for usms-web-01, no access keys (Exercise 5)
- `../../configs/lab-03.env`: IDs for Lab 4
- `../../templates/lab-03-run-instances.json`: launch request for usms-web-01
- `../../scripts/utilities/verify-lab-03.sh`: checks 36 things about this lab
- `../../scripts/utilities/lab-03-reachability.sh`: reachability report (Exercise 3)
- `../../scripts/cleanup/lab-03-cleanup.sh`: end of course only, not run

## Result

verify-lab-03.sh: PASS=34 FAIL=2. Both failures are explained with evidence in Section 7 of the report (a Floci limitation with the public IP field, and chmod 600 not working on Windows NTFS).