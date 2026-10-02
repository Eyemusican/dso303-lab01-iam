# Lab 03 Notes

## Step 11: The bucket that does not exist yet

The policy USMSStudentDataReadWrite gives usms-web-01 access to arn:aws:s3:::usms-student-data, but that bucket does not exist yet. This is not a mistake. An IAM policy only talks about ARNs, not real objects, so it is valid to allow access to something that has not been created. Right now the permission does nothing. Once the bucket is created in a later lab, the policy starts working straight away and usms-web-01 can read and write student data without any access key stored on the machine.