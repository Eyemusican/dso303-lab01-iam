# Lab 03 Notes

## Step 11: The bucket that does not exist yet

The policy USMSStudentDataReadWrite gives usms-web-01 access to arn:aws:s3:::usms-student-data, but that bucket does not exist yet. This is not a mistake. An IAM policy only talks about ARNs, not real objects, so it is valid to allow access to something that has not been created. Right now the permission does nothing. Once the bucket is created in a later lab, the policy starts working straight away and usms-web-01 can read and write student data without any access key stored on the machine.

## Review Questions

### 1. What if one of the five inputs to run-instances had been wrong?
- **Subnet (Lab 2):** if the variable was empty or the ID did not exist, run-instances fails straight away with InvalidSubnetID.NotFound or MissingParameter. If it was a real but wrong subnet, like the private one, it fails silently: the instance launches fine but gets no public address and nobody can reach it.
- **Security group (Lab 2):** a missing ID fails immediately with InvalidGroup.NotFound. A wrong but valid group, like default, fails silently, because the instance runs with the wrong firewall and nothing warns you.
- **Instance profile (Lab 1):** if the profile does not exist, it fails immediately with InvalidParameterValue on iamInstanceProfile.name. If it is a real profile with the wrong role, it fails silently and only shows up later as AccessDenied when the instance calls S3.
- **Key pair (Lab 3):** a missing key pair fails immediately with InvalidKeyPair.NotFound. Losing the private key file is silent until the day someone tries to SSH in, and it cannot be recovered.
- **User data script (Lab 3):** always silent. run-instances accepts any text, so a syntax error or a variable expanded too early only fails at boot, and the only evidence is a log file on a machine you might not be able to log in to. That is why I ran bash -n before launching and proved the stored copy was byte identical in Step 12.

### 2. Why is a policy for a bucket that does not exist valid?
An IAM policy is a statement about ARNs, not a link to real objects, so USMSStudentDataReadWrite can name arn:aws:s3:::usms-student-data before that bucket exists. AWS only checks it when a request is made. Right now it does nothing for usms-web-01, because any S3 call to that name just fails with Not Found, which is what my head-bucket check in Exercise 5 showed (exit code 254, 404). The moment a later lab runs create-bucket, the same policy starts working with no change to the instance, the profile or the role. usms-web-01 can then list the bucket and read, write and delete objects inside it, while DeleteBucket stays denied, and it does all of this with temporary credentials from the instance profile and no access key on the disk.

### 3. Why does "restart to redeploy" with user data not work?
User data runs only once, on the first boot of the instance. Stopping and starting or rebooting does not run it again, so a restart would just bring back the old version of the app. Two approaches that do work:
1. Bake the app into an AMI, like the golden AMI from Step 20, and deploy by launching new instances from the new image and removing the old ones. With a launch template and an Auto Scaling group this can be done one instance at a time.
2. Use a deployment tool that runs on demand, like AWS Systems Manager Run Command or CodeDeploy, which pushes the new version to running instances whenever you deploy, not only at first boot.

### 4. Auto assigned public IP vs Elastic IP
- **Who owns it:** an auto assigned address is lent to the instance from AWS's pool. An Elastic IP belongs to my account until I release it.
- **When it changes:** the auto assigned one is replaced every time the instance stops and starts. The Elastic IP never changes. In Step 18 my Elastic IP 54.178.200.69 stayed linked to usms-web-01 after a stop and start.
- **What it costs:** since February 2024 every public IPv4 address costs $0.005 per hour, about $3.65 a month. An Elastic IP keeps costing that even when it is not attached to anything, which is easy to forget.
- **When the instance stops:** the auto assigned one is released and gone. The Elastic IP stays allocated and associated.

A failover only possible because of the difference: if usms-web-01 fails, I can move the Elastic IP to a standby instance with associate-address --allow-reassociation. The DNS record keeps pointing at the same address, so users are moved without any DNS change. I actually did a reassociation in the verify section and got a new association ID while the address stayed the same.

### 5. What the EBS Availability Zone rule tells me
An EBS volume lives in the storage of one Availability Zone, so it can only be attached to an instance in that same zone. When I tried to attach a volume from us-east-1b to usms-web-01 in us-east-1a, it was refused. A snapshot is stored at the region level, in S3, so it can be restored into any zone in the region. This means a single volume is a single zone risk. To survive losing one zone I would take regular snapshots so I can rebuild the volume in another zone, and for the database I would keep a copy running in a second zone, for example RDS with a standby in another zone, instead of relying on one volume.

### 6. Are the six configuration checks enough?
I think they are a good substitute, but not a complete one. The six checks cover every part of the path that AWS controls: instance state, route to the internet gateway, gateway attached, security group, public address and NACL. Most "I cannot reach my instance" problems are one of those, so checking them catches most real mistakes. What they cannot detect is anything inside the instance, the seventh link: nginx not running, the app crashing, the user data failing at boot, or an OS level firewall blocking port 80. All six checks can be correct and the site can still be down. Also, on Floci the configuration is only read back, not enforced, so even a correct security group is not proof that traffic would be blocked or allowed.

### 7. Every difference between usms-web-01 and usms-db-01
| Difference | web-01 | db-01 | Property of |
| --- | --- | --- | --- |
| Subnet | usms-public-subnet-a | usms-private-subnet-a | the instance (chosen at launch) |
| Private IP range | 10.0.1.0/24 | 10.0.3.0/24 | the subnet's CIDR |
| Auto assigned public IP | yes | no | the subnet (MapPublicIpOnLaunch) |
| Elastic IP | usms-web-eip | none | the instance (associated to it) |
| Route to the internet | through the internet gateway | through the NAT gateway only | the subnet's route table |
| Network ACL | default NACL | usms-private-nacl | the subnet |
| Security group | usms-app-sg | usms-db-sg | the instance (its network interface) |
| Instance profile | usms-ec2-app-profile | none | the instance |
| User data | user-data.sh | none | the instance |
| Data volume | usms-web-data-vol attached | none | the instance |
| Tier tag | web | data | the instance |

What they share comes from the VPC: the 10.0.0.0/16 range, DNS support and the internet gateway being attached at all. Floci note: db-01 showed 172.18.0.3 as its private IP, which is the Docker container address. On real AWS it would be inside 10.0.3.0/24.