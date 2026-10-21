# Lab 07 Working Notes

## Pre lab checks (Step 1)

- kubectl was already installed: client v1.32.2 on windows/amd64. Docker 28.3.0, aws-cli 2.36.28 and Python 3.14 were also there.
- I created labs/lab-07-eks and the new top level folder manifests/lab-07.
- floci-up.sh started Floci in hybrid mode with the state directory C:/Users/Tenzin/floci-data. whoami.sh showed account 000000000000, and every floci-storage-check.sh line was [ok].
- Subnets for the cluster: public-a subnet-07d92642, public-b subnet-a8243958, private-a subnet-7f8e9295, private-b subnet-f32c9b5a. All four are filled in, so the cluster can span two Availability Zones.

![Floci up and identity](../screenshots/lab07-step01-floci-up.png)
![Storage check](../screenshots/lab07-step01-storage-check.png)

## Step 1 Verify: the usms-db-sg fix

- verify-lab-02 first gave PASS=32 FAIL=1. The failing check was "usms-db-sg is sourced from usms-app-sg (not a CIDR)". It was already FAIL=1 in Lab 06, so this was not caused by Lab 07.
- usms-db-sg had two tcp 5432 rules, and both had an empty UserIdGroupPairs list. So they had no source at all. Real AWS does not allow a rule with no source, so this was Floci losing the source group.
- Floci limitation: revoke-security-group-ingress with --security-group-rule-ids (sgr-115ad5f5d0f7ed16d and sgr-86bd9358f6cc34ece) returned "Return": true, but the rules were still there.
- Revoking by contents worked: --ip-permissions 'IpProtocol=tcp,FromPort=5432,ToPort=5432'. That removed every 5432 rule.
- I added back the original Lab 02 rule from policies/usms-db-sg-ingress.json (tcp 5432 from usms-app-sg sg-53dba8db862ba5440). The new rule ID is sgr-4305912cac650fdf0.
- After the fix usms-db-sg has one rule, 5432 from sg-53dba8db862ba5440, and verify-lab-02 gives PASS=33 FAIL=0.

![usms-db-sg fixed, Lab 02 FAIL=0](../screenshots/lab07-step01-db-sg-fixed.png)

## Lab 07 support path
Probed on 2026-10-21T10:02:30Z
PATH A  - use aws eks throughout

## Step 3: control plane and data plane (Your turn)

"EKS is just ECS with different names" is false because EKS gives me a data plane I own. The nodes are EC2 instances in my account that I have to patch, and that is why EKS needs two IAM roles, a cluster role for the control plane and a node role for the nodes. With ECS on Fargate that side is nearly empty, and Lab 04 only needed task roles.

It is nearly true because in both cases AWS runs the control plane, and both take a declarative description of containers and keep that many copies running inside my VPC. A Deployment is close to an ECS service, and a pod is close to a task.

## Steps 4 and 5: trust and permissions policies

- trust-eks-cluster.json trusts eks.amazonaws.com and trust-eks-node.json trusts ec2.amazonaws.com, both with sts:AssumeRole.
- USMSEKSClusterPolicy has 3 statements (ENIs, load balancers, region Deny). USMSEKSNodePolicy has 5 (describe cluster, VPC CNI, ECR pull, logs only to /usms/eks/*, region Deny).
- Floci limitation: Floci stores these policies but does not enforce them, so I checked them by reading them.

![Trust policies](../screenshots/lab07-step04-trust-policies.png)
![Permissions policies](../screenshots/lab07-step05-permission-policies.png)

## Step 6: cluster role and cluster security group

- usms-eks-cluster-role trusts eks.amazonaws.com and has USMSEKSClusterPolicy attached.
- usms-eks-cluster-sg is sg-f63dbfe3c0ae67966 in usms-vpc vpc-7b4598ab. It allows tcp 443 from 10.0.0.0/16 only.
- My first run failed with NoCredentials and NoRegion because I was in a terminal without the env files sourced. Nothing was created. I sourced course.env and lab-01 to lab-04 again and ran it again.

![Cluster role and SG](../screenshots/lab07-step06-cluster-role-sg.png)

## Step 7: node role

- usms-eks-node-role trusts ec2.amazonaws.com and has USMSEKSNodePolicy and USMSStudentDataReadWrite.
- USMSStudentDataReadWrite now has three holders: usms-ec2-app-role, usms-ecs-task-role and usms-eks-node-role. I did not edit the policy.

![Node role](../screenshots/lab07-step07-node-role.png)

## Step 8: create the cluster

- templates/lab-07-create-cluster.json has version 1.30, usms-eks-cluster-role, all four subnets, usms-eks-cluster-sg and the tag _lb_ports_=8081,8082.
- I assumed usms-developer-role to create the cluster, then unset the three AWS_* variables and whoami.sh showed root again. Floci named the session floci-session, not lab07-eks-build.
- Floci limitation: create-cluster returned Status FAILED. The Floci log showed it was a timing problem. Floci was still pulling the rancher/k3s image, started the cluster a second time, and the second try failed with a 409 Conflict because the container name was already in use. The first try then finished, and the log says "EKS cluster usms-eks-cluster is now ACTIVE". There is one k3s container, floci-floci-course-eks-usms-eks-cluster.
- My endpoint is https://localhost:6500, not 6443 like in the doc.

![Cluster template](../screenshots/lab07-step08-cluster-template.png)
![Create returned FAILED](../screenshots/lab07-step08-create-failed.png)
![Why it said FAILED, now ACTIVE](../screenshots/lab07-step08-why-failed.png)

## Step 9: cluster active

- aws eks wait cluster-active worked straight away. Status ACTIVE, version 1.30, four subnets, vpc-7b4598ab, sg-f63dbfe3c0ae67966. Saved to outputs/lab-07-cluster.json.
- The _lb_ports_ tag reads 8081,8082, so Lab 08 Step 15 will work.
- Your turn: version 1.30 and OIDC issuer https://oidc.eks.us-east-1.amazonaws.com/id/0A9B35F07D504491BD894AFF67D47A7C. My build gives a real issuer URL, not None.
- The OIDC issuer is the cluster's own identity provider, which lets IAM trust Kubernetes service account tokens so a role can be given to selected pods (IRSA).

![Cluster active](../screenshots/lab07-step09-cluster-active.png)
![Version and OIDC issuer](../screenshots/lab07-step09-oidc.png)

## Step 10: node group

- usms-eks-nodes is ACTIVE with min 2, max 4, desired 2, only in private-a subnet-7f8e9295 and private-b subnet-f32c9b5a, node role usms-eks-node-role, labels workload=usms and tier=app. Saved to outputs/lab-07-nodegroup.json.
- Floci limitation: it went ACTIVE straight away because Floci does not launch real t3.small EC2 instances.

![Node group](../screenshots/lab07-step10-nodegroup.png)

## Step 11: kubectl

- update-kubeconfig added the context usms-eks to C:\Users\Tenzin\.kube\config, pointing at https://localhost:6500. No exec plugin or certificate error, so I did not need the fallback.
- cluster-info shows the control plane, CoreDNS and Metrics-server running. auth can-i create deployments says yes.
- Floci limitation: kubectl get nodes shows only one node, d83b245b1dee, the control-plane node of the k3s container. The node group says desired 2 but no worker nodes joined. The doc says to continue in this case.
- Floci limitation: the node runs Kubernetes v1.34.1+k3s1 because Floci uses rancher/k3s:latest. The 1.30 I asked for is only in the AWS record.

![kubectl connected](../screenshots/lab07-step11-kubectl.png)

## Laptop restart during Step 12 (Floci limitation)

- I restarted my laptop before Step 12. After that, floci-up.sh started Floci but the k3s container stayed down, and kubectl got "connection refused" on localhost:6500. describe-cluster said CREATING.
- The k3s log ended with "Failed to start networking: ... failed to find interface with specified node ip". Before the restart the container had the IP 172.18.0.6, and after the Docker restart Docker gave it 172.17.0.2. k3s still expected the old IP and crashed. Floci logged that it "adopted" the crashed container.
- Fix: I removed the crashed container with docker rm, then ran floci-down.sh and floci-up.sh. Floci built a new k3s container for the same cluster, the cluster went back to ACTIVE, and I ran update-kubeconfig again.
- The cluster database survived, so the old node d83b245b1dee was still listed as NotReady next to the new node ebc232042627. I deleted the old node object with kubectl delete node.
- Nothing was deployed yet, so nothing was lost. The AWS side (cluster, node group, roles, SG) was not affected. I did not restart Docker again until after Step 22.

![Cluster recovered after restart](../screenshots/lab07-restart-recovered.png)

## Step 12: namespace usms

- namespace usms is Active with the labels project=usms, tier=app and lab=07. I made it the default namespace for the usms-eks context. kubectl get all showed no resources yet.

![Namespace](../screenshots/lab07-step12-namespace.png)

## Step 13: usms-enrolment

- usms-app-config has 4 keys: APP_ENVIRONMENT laboratory, APP_CAMPUS rtc, APP_VERSION 1.0.0, APP_REGION us-east-1.
- usms-enrolment rolled out 2/2 with ReplicaSet usms-enrolment-6965b8dbbb. Pods 10.42.1.5 and 10.42.1.6, both on node ebc232042627. Service ClusterIP 10.43.47.213 with no external IP, and two endpoints.
- From a busybox pod, wget to usms-enrolment.usms.svc.cluster.local returned JSON with the real pod name usms-enrolment-6965b8dbbb-ql5rx, so the nginx template filled in the variables.
- On Git Bash I used kubectl run with -i instead of -it, because -t needs a real terminal. The output is the same.

![Enrolment deployed](../screenshots/lab07-step13-enrolment-deployed.png)
![Enrolment serves by DNS name](../screenshots/lab07-step13-enrolment-serves.png)

## Step 14: usms-results

- usms-results rolled out 2/2. The custom-columns check shows usms-enrolment with MAXUNAVAIL 0 and usms-results with the default 25%. Each Service has two endpoints (results 10.42.1.8 and 10.42.1.9).

![Results deployed](../screenshots/lab07-step14-results.png)

## Step 15: usms-gateway

- usms-gateway rolled out 1/1. Five pods are Running on node ebc232042627: two enrolment, two results and one gateway (10.42.1.10).
- The gateway log shows nginx worker processes starting and GET /healthz returning 200 from kube-probe, with no emerg lines.

![Gateway deployed](../screenshots/lab07-step15-gateway.png)

## Step 16: service discovery

- nslookup from a busybox pod: usms-enrolment.usms.svc.cluster.local resolves to 10.43.47.213 and usms-results to 10.43.21.186, both answered by CoreDNS at 10.43.0.10. These are the Service ClusterIPs, not pod IPs.
- Through the gateway, / answered as usms-gateway, /enrolment/ reached an enrolment pod and /results/ reached a results pod with campus rtc. The gateway found both backends by name.
- 12 requests through the gateway were answered by two different enrolment pods (4 and 8), so kube-proxy spread the load under one ClusterIP.
- One run printed "couldn't attach to pod/usms-debug, falling back to streaming logs". The pod had finished before kubectl attached, and the output was complete.
- Your turn: I deleted usms-enrolment-6965b8dbbb-ql5rx without touching the gateway. A new pod, usms-enrolment-6965b8dbbb-szqwd, was Running within seconds, and 12 requests through /enrolment/ all worked, 6 each to szqwd and ztgdw.
- The replacement pod was created by the ReplicaSet usms-enrolment-6965b8dbbb (event SuccessfulCreate), not by the Deployment and not by me.

![Service discovery](../screenshots/lab07-step16-discovery.png)
![Pod replaced by the ReplicaSet](../screenshots/lab07-step16-pod-replaced.png)

## Step 17: Secret

- I generated manifests/lab-07/50-secret.yaml with --dry-run=client and applied it. The values are dummies.
- I moved the file to outputs/lab-07-secret.yaml with chmod 600, as the doc allows, because a base64 value committed to Git stays in the history. git check-ignore shows .gitignore:1:outputs/*.
- The token read back as ZmxvY2ktZHVtbXktdG9rZW4tbm90LWEtcmVhbC1zZWNyZXQ= and base64 -d turned it into floci-dummy-token-not-a-real-secret with no key. Base64 is an encoding, not encryption.
- kubectl set env --from=secret rolled out new enrolment pods. My kubectl v1.32 added the secret as two env entries with secretKeyRef instead of an envFrom secretRef like in the doc, so envFrom only lists usms-app-config. describe shows both keys coming from usms-enrolment-secret.
- printenv in the pod shows four APP_ variables and ENROLMENT_API_TOKEN and ENROLMENT_DB_PASSWORD in plain text. A Secret protects the value on the way to the pod, not inside it.

![Secret is only base64](../screenshots/lab07-step17-secret-base64.png)
![Secret inside the pod](../screenshots/lab07-step17-secret-in-pod.png)

## Step 18: rolling update and rollback

- I changed APP_VERSION to 1.1.0 in the ConfigMap. A request to enrolment still returned version 1.0.0, because changing a ConfigMap does not restart pods.
- kubectl annotate on the Deployment returned straight away with no rollout, because it changes the Deployment's own metadata, not the pod template.
- kubectl rollout restart did roll. The new pod usms-enrolment-6f4bcd8ffd-v89wk returned version 1.1.0, and the hash in the pod name changed, so it was a new ReplicaSet.
- rollout history showed revisions 1, 2 and 3: 6965b8dbbb (rev 1) and 7d8557c58d (rev 2) kept at 0 replicas, and 6f4bcd8ffd (rev 3) serving 2.
- rollout undo went back to 7d8557c58d, but the reply still said 1.1.0, because undo restores the pod template and not the ConfigMap. I set the ConfigMap back to 1.0.0, restarted the Deployment and removed the .bak files.
- Your turn: I changed the usms-results image from nginx:1.27-alpine to nginx:1.27, then used rollout undo --to-revision=1. rollout history now shows two revisions, 2 and 3, and the image is nginx:1.27-alpine again.
- The peak during the update was 3 pods (2 old Running and 1 new being created), and there were never fewer than 2 ready. One count line said 4 because it caught an old pod while it was terminating. This was the same shape as usms-enrolment, not different like the doc expected, because with 2 replicas the default 25% rounds to maxSurge 1 and maxUnavailable 0.

![History, undo and restore](../screenshots/lab07-step18-history-undo-restore.png)
![Results image update start](../screenshots/lab07-step18-yourturn-start.png)
![Results image update end and rollback](../screenshots/lab07-step18-yourturn-end.png)

## Step 19: three failures on purpose

- Failure 1: I set usms-results to nginx:this-tag-does-not-exist. The new pod went to ErrImagePull and then ImagePullBackOff. Its Events said "Failed to pull image ... not found". The two old pods stayed 1/1 Running the whole time, so the broken image never replaced them. rollout undo fixed it.
- My first try used describe -l with tail -15, which only showed the last pod, a healthy one. I ran it again and described only the pod that was not Running.
- Failure 2: usms-toobig asked for 64 CPU and 256Gi memory. It stayed Pending, and describe showed FailedScheduling "0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory". I deleted it.
- Failure 3: usms-crasher printed two lines and exited 1. After 25 seconds it showed Error with 2 restarts, and the events show "Back-off restarting failed container", which is CrashLoopBackOff. logs and logs --previous showed "usms-crasher starting" and "fatal: no database configured". Last State was Terminated with Exit Code 1. I deleted it.
- For ImagePullBackOff and Pending the container never started, so the answer was in the describe Events. For CrashLoopBackOff the container did start, so logs was the useful command.

![ImagePullBackOff](../screenshots/lab07-step19-imagepull.png)
![Pending FailedScheduling](../screenshots/lab07-step19-pending.png)
![CrashLoopBackOff and events](../screenshots/lab07-step19-crashloop-events.png)

## Step 20 - ECS and Kubernetes, compared with both running

ECS right now: usms-enrolment-svc desired 2, running 2, task definition usms-enrolment:4, 1 load balancer, 1 deployment. EKS right now: usms-enrolment 2/2, usms-gateway 1/1, usms-results 2/2, each with a ClusterIP Service and no external IP.

| Question | ECS answer | Kubernetes answer |
| --- | --- | --- |
| What holds the container spec? | The task definition (usms-enrolment:4) | The pod template inside the Deployment (manifests/lab-07/20-enrolment.yaml) |
| What keeps N copies alive? | The ECS service scheduler, using desiredCount 2 | The ReplicaSet, which the Deployment owns. In Step 16 it replaced the pod I deleted |
| What gives it a stable name? | The ALB DNS name and target group from Lab 05. In Lab 04 the tasks only had changing private IPs | A Service with a ClusterIP and a DNS name that never changes |
| How does another service find it? | Through the load balancer's DNS name (Lab 05), or Cloud Map which I did not use | Through CoreDNS, for example usms-enrolment.usms.svc.cluster.local |
| What does a rolling update create? | A new ECS deployment with new tasks from a new task definition revision | A new ReplicaSet with a new hash in the pod names |
| Where does rollback state live? | In the old task definition revisions. I point the service back at an older one | In the old ReplicaSets kept at 0 replicas (revisionHistoryLimit 5), used by kubectl rollout undo |
| Which IAM role does the app code use? | The task role usms-ecs-task-role, only for that task | Here the node role usms-eks-node-role, which every pod on the node gets. The proper way is IRSA with a ServiceAccount |
| What would I have to change to move to another cloud? | Almost everything: the task definition, the service, the ALB, the IAM roles and the VPC are all AWS only | The manifests would move as they are, but the IAM roles, the VPC, the node group and any load balancer settings would not |

For USMS I would choose ECS on Fargate, because it is a small set of services and there are no nodes for me to patch, and Labs 05 and 06 already gave it a load balancer and auto scaling. I would only pick EKS if USMS grew into many services or needed to run on more than one cloud.

![ECS and EKS side by side](../screenshots/lab07-step20-ecs-vs-eks.png)

## Step 21: IRSA

- The OIDC issuer is https://oidc.eks.us-east-1.amazonaws.com/id/0A9B35F07D504491BD894AFF67D47A7C, so part 2 ran.
- create-open-id-connect-provider returned arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/0A9B35F07D504491BD894AFF67D47A7C, and list-open-id-connect-providers shows the same ARN.
- I created the ServiceAccount usms-enrolment-sa in namespace usms from manifests/lab-07/60-serviceaccount.yaml. It has no role annotation yet.
- Of the six IRSA steps my build did step 1 (the cluster publishes an issuer) and step 2 (I registered it in IAM). I did not write the web identity role (step 3) or annotate the ServiceAccount (step 4), because the lab does not ask for them.
- Floci limitation: steps 5 and 6 cannot work here. The OIDC document lives on my machine, so real STS cannot reach it, and no pod can swap its token for credentials. So my pods still get S3 access only through the node role, which every pod on the node shares.

![IRSA provider and ServiceAccount](../screenshots/lab07-step21-irsa.png)

## Step 22: persistence after a Floci restart

- Before the restart I saved the cluster (ACTIVE 1.30), the node group (ACTIVE, desired 2), the three Deployments (2, 1, 2 ready) and the three ClusterIPs to outputs/lab-07-before-restart.txt.
- I ran floci-down.sh and floci-up.sh. I added aws eks wait cluster-active before the read back, because after my laptop restart Floci showed CREATING for a while. This time only Floci restarted and Docker did not, so the k3s container kept its IP and there was no crash.
- After the restart, list-clusters gave back usms-eks-cluster (ACTIVE 1.30) and list-nodegroups gave back usms-eks-nodes. Namespace usms was Active, the Deployments were 2, 1 and 2 ready, and the four usms ConfigMaps were there with kube-root-ca.crt.
- diff printed differences, but only because the after list prints different kinds of lines. It adds the namespace and the ConfigMaps and does not print the node group details or the Services again. Every value that is in both lists is the same.

![Before restart](../screenshots/lab07-step22-before.png)
![After restart](../screenshots/lab07-step22-after-restart.png)

## Step 22 follow up: the pods did not really survive the restart

- When I first ran verify-lab-07.sh after Step 22, four Kubernetes checks failed: the three ready replica checks and the endpoint check.
- The Floci restart had made a new k3s container, so there was a new node 69b0596b9728 (Ready) and the old node ebc232042627 was NotReady. All five pods were still assigned to the old node and showed a stale Running status, while the Deployments said 0 ready. So the 2, 1, 2 ready numbers in my Step 22 read back were stale too.
- I deleted the old node object. The pod garbage collector removed the stale pods and the ReplicaSets created five new pods on 69b0596b9728 within about two minutes. The Deployments went back to 2/2, 1/1 and 2/2.
- What survived the restart: the AWS side (cluster, node group, roles, SG) and every Kubernetes object (namespace, Deployments, Services, ConfigMaps, Secret, ServiceAccount). What did not survive: the running pods, which had to be rescheduled onto the new node.

![Pods rescheduled on the new node](../screenshots/lab07-step22-pods-rescheduled.png)

## Section 8: verify script and smoke test

- verify-lab-07.sh first failed "no secret is tracked by git" because outputs/.gitkeep is tracked. It is an empty placeholder, not a secret. I changed the check to ignore only outputs/.gitkeep, the same fix as in Lab 06.
- After the fix and the pod recovery: PASS=30 FAIL=0.
- The smoke test through usms-gateway returned three JSON documents (gateway, enrolment, results) and printed SMOKE TEST PASSED.
- I wrote scripts/cleanup/lab-07-cleanup.sh and checked it with bash -n. I did not run it, because Lab 08 needs this cluster.

![Verify and smoke test](../screenshots/lab07-verify-smoke.png)

## Coming back later (Floci limitation again)

- When I came back, the k3s container had Exited (1) again and the cluster was stuck at CREATING. I removed the container, restarted Floci, ran update-kubeconfig, and deleted the old node 69b0596b9728. The five pods moved to the new node a591b9e29fb6 and the Deployments were back at 2/2, 1/1 and 2/2 with nothing lost.

## Exercise 5 Part 3: what Lab 08 needs from configs/lab-07.env

- USMS_EKS_CLUSTER: every aws eks command in Lab 08 names the cluster, and update-kubeconfig needs it if kubectl loses the context.
- USMS_EKS_NODEGROUP: Lab 08 changes the node group size from the AWS side, which is the node half of scaling.
- USMS_EKS_NAMESPACE: every kubectl command in Lab 08 runs inside usms.
- USMS_EKS_LB_PORTS: Lab 08 exposes the gateway as a LoadBalancer Service, and Floci can only publish it on the host ports in this tag (8081,8082). Without it the cluster would have to be rebuilt.
- USMS_EKS_ENDPOINT: after a restart I can check that kubectl is talking to https://localhost:6500 and not some other cluster.
- USMS_K8S_DEPLOY_ENROLMENT: the HorizontalPodAutoscaler in Lab 08 targets this Deployment.
- USMS_K8S_DEPLOY_GATEWAY: the gateway is the Deployment whose Service gets changed to NodePort, then LoadBalancer, then an Ingress.
- USMS_K8S_CPU_REQUEST: the HPA works out CPU use as a percentage of 50m, so I need it to check the HPA maths myself.
- USMS_EKS_CLUSTER_STATUS: a quick check that the cluster is ACTIVE before I start, since on my build it gets stuck at CREATING after a restart.
- The other 12 (cluster and node role ARNs, the two policy ARNs, the cluster SG, the cluster ARN, the version, the results deployment and the three Service names, and the manifest folder) are records of what this lab built. Lab 08 does not need them to run.

## Section 14: Review questions

**1. The cluster is ACTIVE but every pod is Pending. How can both be true?**

ACTIVE only describes the control plane, which AWS runs: the API server, etcd and the scheduler are up and answering. Pods run on the data plane, the nodes in my account. If no node can take a pod, the scheduler leaves it Pending even though the control plane is healthy. Two setups that cause this: a cluster with no node group at all (or nodes that never joined because the node role trust is wrong), and pods asking for more CPU or memory than any node has, like my usms-toobig pod in Step 19 that stayed Pending with "Insufficient cpu, Insufficient memory". A third one I saw myself in Exercise 4: when the only node is cordoned, the replacement pod has nowhere to go and stays Pending.

**2. What breaks if the cluster role and node role trust policies are swapped, and where would I notice on real AWS?**

The cluster role would trust ec2.amazonaws.com, so the EKS control plane could not assume it, and the node role would trust eks.amazonaws.com, so EC2 instances could not assume it. On real AWS I would notice in Step 8: create-cluster fails straight away because EKS cannot assume the role I passed. If only the node role were wrong, the cluster would go ACTIVE and I would notice in Step 10, where the node group goes to CREATE_FAILED or the nodes never join, and then in Step 11 when kubectl get nodes shows no nodes. On Floci none of this shows up because IAM is stored but not enforced.

**3. Readiness probe versus liveness probe.**

A readiness probe decides if a pod gets traffic. If it fails, the pod stays running but is removed from the Service endpoints. A liveness probe decides if the container is alive. If it fails, the kubelet kills and restarts the container. If I put a slow, load sensitive check on liveness, then under heavy load the check times out and Kubernetes restarts healthy pods, which removes more capacity right when it is needed and can turn into a restart loop. In Exercise 3 I saw the readiness side: the probe on /healthz got 404, so the pods were Running but 0/1, and the Service had no endpoints even after the selector was fixed.

**4. After the rollback the pod still said 1.1.0. Why, and is a Kubernetes rollback really a rollback?**

rollout undo only goes back to an older pod template, meaning an older ReplicaSet. APP_VERSION came from the ConfigMap usms-app-config, which is a separate object and was still at 1.1.0, so the old pod template read the new value when the pods started. So I would say rollback is a real rollback of the Deployment, but it is not a rollback of the whole release. If a release changes a ConfigMap, a Secret and the image, undo only brings back the image and the pod spec. The fix is to version the config with the workload: give each ConfigMap a new name per version (for example usms-app-config-v2) and point the Deployment at it, or keep everything in Git and roll back by applying the older manifests together.

**5. maxUnavailable 0 versus the default for two replicas.**

maxUnavailable 0 with maxSurge 1 means Kubernetes adds one new pod first and only removes an old one when the new one is ready, so there are always 2 ready pods. The default is 25% and 25%, but with 2 replicas Kubernetes rounds maxUnavailable down to 0 and maxSurge up to 1, so in my Step 18 test usms-results behaved the same way, with a peak of 3 pods and never fewer than 2 ready. The difference only shows with more replicas, for example 8 pods could drop to 6 ready under the default. maxUnavailable 0 suits something like enrolment during registration week where no capacity can be lost. The default suits a background service like results, where rolling faster matters more. maxUnavailable 0 is closest to Lab 04's ECS setting of minimumHealthyPercent 100 with maximumPercent 200.

**6. "A Secret is encrypted, so it is fine to commit the manifest."**

That is wrong. In Step 17 I read the token back with kubectl get secret and base64 -d, with no key, and got floci-dummy-token-not-a-real-secret in plain text. A Secret only keeps the value out of the image and out of kubectl describe, and lets RBAC limit who can read it. It is not encrypted in the manifest, and on a cluster it is only encrypted at rest if etcd encryption is turned on. Inside the pod it is plain text, as printenv showed. Anything committed to Git stays in the history. On real EKS I would turn on KMS envelope encryption for Secrets, keep the real values in AWS Secrets Manager or Parameter Store, and give pods access with IRSA, and never commit a Secret manifest. That is why I moved 50-secret.yaml to outputs/.

**7. ECS or Kubernetes for USMS?**

For USMS I would choose ECS on Fargate. The team is small, it is one region, and the load is quiet for eight months and busy for two, which Lab 06's auto scaling already handles with a scalable target, while Fargate means no nodes to patch. Two things this lab made harder than Lab 04: I needed two IAM roles, a node group and kubectl on top of the AWS CLI, and the cluster needed a lot of care (on my build a restart left pods on a dead node and I had to clean up by hand). Debugging also needs more tools, like describe, events and logs. One thing Kubernetes gave me that ECS could not: built in service discovery by DNS name, where the gateway reached usms-enrolment.usms.svc.cluster.local with no load balancer in between, plus manifests I could move to another cloud almost as they are.
