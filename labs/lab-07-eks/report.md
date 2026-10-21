# Lab 07 Report: Deploying a Microservices Application on Amazon EKS

## 1. Aim / Objective

- To create an EKS cluster and a managed node group inside my Lab 02 VPC, each with its own IAM role.
- To point kubectl at the cluster and deploy three USMS microservices (usms-gateway, usms-enrolment and usms-results) from declarative manifests.
- To prove that the services find each other by DNS name, and to do a rolling update, a rollback and three deliberate failure diagnoses.
- To use a ConfigMap and a Secret, and show what a Secret does not protect.
- To check what survives a Floci restart and save the cluster identifiers to configs/lab-07.env for Lab 08.

## 2. Introduction

Amazon Elastic Kubernetes Service (EKS) is AWS's managed Kubernetes service. AWS runs the control plane (the API server, etcd, the scheduler and the controllers) and I run the data plane, which is the worker nodes and my pods. Its key features are managed node groups, IAM integration through a cluster role, a node role and IRSA, the VPC CNI that gives pods VPC addresses, and the standard Kubernetes objects such as Deployments, Services, ConfigMaps and Secrets. It matters in cloud computing because Kubernetes is the most common way to run containers across many providers, so manifests written for EKS can move to other clusters with few changes. It is typically used for microservice applications, internal platforms shared by many teams, and workloads that need to run on more than one cloud.

## 3. Use Case

The USMS student portal is being split into small services. When a student clicks "Register for this module", the request reaches usms-gateway, an nginx reverse proxy. The gateway forwards /enrolment/ to usms-enrolment and /results/ to usms-results. Nothing in the gateway's configuration contains an IP address; it only has the DNS names usms-enrolment.usms.svc.cluster.local and usms-results.usms.svc.cluster.local, and the cluster keeps those names pointing at healthy pods. The same idea fits any organisation that wants to run several small services side by side, scale them separately and replace failed pods automatically.

## 4. System Architecture / Design

My aws CLI talks to Floci on localhost:4566, and Floci created the EKS cluster as a k3s container. kubectl talks to the cluster's own API server on https://localhost:6500, not to Floci. The cluster uses all four Lab 02 subnets and the security group usms-eks-cluster-sg (tcp 443 from 10.0.0.0/16). The node group usms-eks-nodes is in the two private subnets only. Inside the namespace usms, usms-gateway (1 pod) reaches usms-enrolment (2 pods) and usms-results (2 pods) through their ClusterIP Services by DNS name. usms-eks-cluster-role trusts eks.amazonaws.com and usms-eks-node-role trusts ec2.amazonaws.com, and the node role also carries Lab 01's USMSStudentDataReadWrite.

![Lab 7 architecture](../../diagrams/lab07-architecture.png)

I drew this diagram in Cloud Architecture Lab. The tool works out subnet ranges by itself, so I wrote my real /24 ranges in the subnet names.

## 5. Implementation Procedure

1. Started Floci in hybrid mode, sourced the env files and checked the earlier labs. verify-lab-02 had FAIL=1 because usms-db-sg had two rules with no source; I removed them and added the Lab 02 rule back, which gave FAIL=0.
2. Ran eks-support-probe.sh. The verdict was Path A, so I followed the aws eks steps.
3. Wrote my answer on the control plane and data plane split.
4. Wrote the two trust policies, one for eks.amazonaws.com and one for ec2.amazonaws.com.
5. Wrote the two permissions policies, USMSEKSClusterPolicy and USMSEKSNodePolicy, as local stand ins for the AWS managed policies.
6. Created usms-eks-cluster-role with its policy, and usms-eks-cluster-sg in usms-vpc allowing tcp 443 from 10.0.0.0/16.
7. Created usms-eks-node-role with USMSEKSNodePolicy and Lab 01's USMSStudentDataReadWrite, which now has three holders.
8. Built templates/lab-07-create-cluster.json with the _lb_ports_ tag and created the cluster while holding usms-developer-role credentials, then unset them.
9. Waited for the cluster to be ACTIVE, checked the subnets, VPC and _lb_ports_ tag, and printed the version and OIDC issuer.
10. Created the managed node group usms-eks-nodes in the private subnets with min 2, max 4, desired 2.
11. Ran update-kubeconfig and checked kubectl cluster-info, the nodes and auth can-i.
12. Created the namespace usms from a manifest and made it the default.
13. Deployed usms-app-config and usms-enrolment (ConfigMap, Deployment with probes and CPU requests, ClusterIP Service) and tested it from a busybox pod.
14. Deployed usms-results, which has no liveness probe and uses the default rolling update strategy.
15. Deployed usms-gateway, which proxies to the two services by DNS name.
16. Proved DNS discovery and load spreading from inside the cluster, then deleted a pod and watched the ReplicaSet replace it.
17. Created a Secret, decoded it with base64 -d, and added it to the enrolment pods.
18. Changed the ConfigMap, used rollout restart, read the history, used rollout undo, and did an image based update and rollback of usms-results.
19. Produced ImagePullBackOff, Pending with FailedScheduling, and CrashLoopBackOff on purpose and diagnosed each.
20. Compared ECS and Kubernetes with both running.
21. Registered the cluster's OIDC issuer in IAM and created the ServiceAccount usms-enrolment-sa.
22. Recorded the state, restarted Floci and read everything back from the API.
23. Wrote configs/lab-07.env with 21 exports.
24. Wrote and ran verify-lab-07.sh (PASS=30 FAIL=0), ran the smoke test, and wrote the cleanup script without running it.

## 6. Results and Evidence

### 6.1 CLI / SDK Output

Step 1: Floci up in hybrid mode, account 000000000000.

![Floci up](../../screenshots/lab07-step01-floci-up.png)
![Storage check](../../screenshots/lab07-step01-storage-check.png)

Step 1: usms-db-sg fixed, Lab 02 at FAIL=0, and the four subnets present.

![usms-db-sg fixed](../../screenshots/lab07-step01-db-sg-fixed.png)
![Earlier labs verified](../../screenshots/lab07-step01-verify.png)

Step 2: the probe gave Path A, and I recorded it in my notes.

![Support probe](../../screenshots/lab07-step02-probe.png)
![Path recorded](../../screenshots/lab07-step02-notes.png)

Steps 4 and 5: the trust and permissions policies.

![Trust policies](../../screenshots/lab07-step04-trust-policies.png)
![Permissions policies](../../screenshots/lab07-step05-permission-policies.png)

Steps 6 and 7: the cluster role, the cluster security group and the node role.

![Cluster role and SG](../../screenshots/lab07-step06-cluster-role-sg.png)
![Node role](../../screenshots/lab07-step07-node-role.png)

Step 8: the cluster template, create-cluster returning FAILED, and the Floci log showing why.

![Cluster template](../../screenshots/lab07-step08-cluster-template.png)
![Create returned FAILED](../../screenshots/lab07-step08-create-failed.png)
![Why it said FAILED](../../screenshots/lab07-step08-why-failed.png)

Step 9: the cluster ACTIVE with the _lb_ports_ tag, and the version and OIDC issuer.

![Cluster active](../../screenshots/lab07-step09-cluster-active.png)
![Version and OIDC issuer](../../screenshots/lab07-step09-oidc.png)

Step 10: the node group ACTIVE in the private subnets.

![Node group](../../screenshots/lab07-step10-nodegroup.png)

Step 11: kubectl connected to https://localhost:6500.

![kubectl connected](../../screenshots/lab07-step11-kubectl.png)

After my laptop restart: the cluster recovered on a new k3s container.

![Cluster recovered](../../screenshots/lab07-restart-recovered.png)

Step 12: the namespace usms.

![Namespace](../../screenshots/lab07-step12-namespace.png)

Steps 13 to 15: the three microservices deployed.

![Enrolment deployed](../../screenshots/lab07-step13-enrolment-deployed.png)
![Enrolment serves](../../screenshots/lab07-step13-enrolment-serves.png)
![Results deployed](../../screenshots/lab07-step14-results.png)
![Gateway deployed](../../screenshots/lab07-step15-gateway.png)

Step 16: DNS discovery, load spreading, and a deleted pod replaced by the ReplicaSet.

![Service discovery](../../screenshots/lab07-step16-discovery.png)
![Pod replaced](../../screenshots/lab07-step16-pod-replaced.png)

Step 17: the Secret is only base64, and it is plain text inside the pod.

![Secret base64](../../screenshots/lab07-step17-secret-base64.png)
![Secret in the pod](../../screenshots/lab07-step17-secret-in-pod.png)

Step 18: the rolling update, history, rollback and restore, and the results image update.

![ConfigMap change did not restart pods](../../screenshots/lab07-step18-configmap-no-change.png)
![Rollout to 1.1.0](../../screenshots/lab07-step18-rollout-1.1.0.png)
![History, undo and restore](../../screenshots/lab07-step18-history-undo-restore.png)
![Results image update start](../../screenshots/lab07-step18-yourturn-start.png)
![Results image update end](../../screenshots/lab07-step18-yourturn-end.png)

Step 19: the three failures.

![ImagePullBackOff](../../screenshots/lab07-step19-imagepull.png)
![Pending](../../screenshots/lab07-step19-pending.png)
![CrashLoopBackOff and events](../../screenshots/lab07-step19-crashloop-events.png)

Steps 20 and 21: ECS and EKS side by side, and the IRSA provider and ServiceAccount.

![ECS and EKS](../../screenshots/lab07-step20-ecs-vs-eks.png)
![IRSA](../../screenshots/lab07-step21-irsa.png)

Step 22: before and after the Floci restart, and the pods rescheduled on the new node.

![Before restart](../../screenshots/lab07-step22-before.png)
![After restart](../../screenshots/lab07-step22-after-restart.png)
![Pods rescheduled](../../screenshots/lab07-step22-pods-rescheduled.png)

Step 23 and Section 8: the env file, the verify script with the smoke test, and the cleanup script.

![lab-07.env](../../screenshots/lab07-step23-env.png)
![Verify and smoke test](../../screenshots/lab07-verify-smoke.png)
![Cleanup script](../../screenshots/lab07-cleanup-script.png)

### 6.2 AWS Management Console Verification

Floci has no web console, so I verified every resource with describe and get commands, the same as in my earlier labs.

- aws eks describe-cluster shows usms-eks-cluster ACTIVE, version 1.30, four subnets in vpc-7b4598ab and the tag _lb_ports_=8081,8082 (Step 9 screenshot).
- aws eks describe-nodegroup shows usms-eks-nodes ACTIVE in the two private subnets with min 2, max 4, desired 2 (Step 10 screenshot).
- aws iam get-role and list-attached-role-policies show both roles with the right trust and policies (Steps 6 and 7 screenshots).
- kubectl get deploy,svc shows the Deployments ready and the ClusterIP Services (Step 20 screenshot).
- verify-lab-07.sh checks 30 things across Floci, IAM, EKS, Kubernetes and Git and gives PASS=30 FAIL=0.

![Section 15 clean up, six pods running](../../screenshots/lab07-section15-cleanup.png)

## 7. Analysis and Discussion

**What was achieved:** I created the cluster and node group with their roles and security group, deployed three microservices plus usms-timetable from Exercise 1, proved DNS discovery and load spreading, did a rolling update and rollback, diagnosed three failures, used a ConfigMap and a Secret, wrote configs/lab-07.env and passed verify-lab-07.sh with 30 out of 30.

**Did the results match:** the Kubernetes half matched the doc closely. Some results differed and I recorded them:

- My endpoint was https://localhost:6500, not 6443.
- My build gave a real OIDC issuer URL and let me register the provider in IAM, while the doc expected None on most builds.
- My kubectl added the Secret as two secretKeyRef entries instead of an envFrom secretRef, with the same result inside the pod.
- usms-results rolled the same way as usms-enrolment, because with two replicas the default 25% rounds to maxSurge 1 and maxUnavailable 0.

**Errors and how I fixed them:**

- Lab 02's usms-db-sg had two rules with an empty source. Revoking by rule ID returned true but removed nothing, so I revoked by protocol and port and added the Lab 02 rule back.
- My first Step 6 run failed with NoCredentials because the env files were not sourced in that terminal.
- create-cluster returned FAILED. The Floci log showed it had started the k3s container twice while pulling the image and the second start hit a 409 Conflict. The first start finished and the cluster went ACTIVE.
- After a laptop restart, and again after coming back later, the k3s container had crashed because Docker gave it a new IP and k3s still expected the old one. Floci was stuck at CREATING. I removed the container, restarted Floci, ran update-kubeconfig and deleted the old node object.
- After the Step 22 Floci restart, verify-lab-07.sh first showed four Kubernetes failures. Floci had made a new k3s container, and all the pods were still on the old, dead node, so the 2, 1, 2 ready numbers in my Step 22 read back were stale. Deleting the old node let the ReplicaSets recreate the pods on the new node.
- The verify check for tracked files under outputs/ failed on outputs/.gitkeep, so I changed it to ignore only that file, the same as in Lab 06.
- On Git Bash I used kubectl run -i instead of -it, and MSYS_NO_PATHCONV=1 for kubectl get --raw.

**Observations:**

- Only one node joined, not the two the node group asks for, and it runs Kubernetes 1.34 even though the AWS record says 1.30. So t3.small, the AMI type and the node count are only recorded.
- IAM policies are stored but not enforced.
- What I observed for real: the Kubernetes object model, DNS discovery, rollouts and rollbacks, the three failures and the PodDisruptionBudget.
- What was only recorded: the IAM policies, the node group sizing and the security group.
- What is conceptual on Floci: IRSA past registering the provider, KMS encryption of Secrets, access entries and control plane logging.

## 8. Reflection

**1. What did you learn about this AWS service?**

I learned that EKS is split into a control plane that AWS runs and a data plane that I run, and that is why it needs two IAM roles. I learned how a Deployment, a ReplicaSet, a pod and a Service fit together, and that the ReplicaSet, not the Deployment, replaces a deleted pod. I also learned that services can find each other by DNS name through CoreDNS, that a rollback only restores the pod template and not the ConfigMap, and that a Secret is only base64 encoded.

**2. What challenges did you encounter?**

Most of my problems came from Floci, not from Kubernetes. The cluster said FAILED when it was really starting, the k3s container crashed after every Docker restart, and after a Floci restart the pods were stuck on a dead node. I had to read the Floci and k3s logs and compare node names to understand what was going on. Small Windows things also caught me, like -it in Git Bash, localhost going to IPv6 inside a pod, and Git Bash changing /apis/... into a Windows path.

**3. How would you apply this service in a real-world cloud environment?**

For a project with many services, or one that might move between clouds, I would use EKS with managed node groups in private subnets, a public load balancer in front, IRSA for each workload instead of putting permissions on the node role, KMS encryption for Secrets, and PodDisruptionBudgets and topology spread rules so a node drain or a node failure does not take a service down. For something small like USMS, I would still choose ECS on Fargate because there are fewer moving parts.

**4. What additional concepts or features would you like to explore?**

I would like to finish IRSA on real AWS so a single pod can read the usms-student-data bucket, try the HorizontalPodAutoscaler and Cluster Autoscaler in Lab 08, expose the gateway with a LoadBalancer Service and an Ingress, and look at NetworkPolicies so a namespace can actually be isolated.

## 9. Conclusion

The objectives of this lab were achieved. I created an EKS cluster and node group in my Lab 02 VPC with the right roles, deployed three microservices that find each other by DNS name, and practised rolling updates, rollbacks and failure diagnosis with describe, events and logs. The key concepts were the control plane and data plane split, declarative manifests, Services and CoreDNS, ReplicaSets, probes, and the difference between encoding and encryption for Secrets.

I developed skills in writing Kubernetes manifests, using kubectl to inspect and debug a cluster, and working out which problems came from the emulator and which from my own configuration. EKS is important because it brings Kubernetes, which runs the same way on any cloud, into the AWS world with IAM and VPC integration. This lab also showed me that it needs more care than ECS.

## 10. Appendix

- Manifests: manifests/lab-07/ (00-namespace, 10-configmap-app, 20-enrolment, 30-results, 40-gateway, 60-serviceaccount, 70-timetable)
- Policies: policies/trust-eks-cluster.json, policies/trust-eks-node.json, policies/usms-eks-cluster-policy.json, policies/usms-eks-node-policy.json
- Templates: templates/lab-07-create-cluster.json, templates/lab-07-create-nodegroup.json
- Config: configs/lab-07.env
- Scripts: scripts/utilities/eks-support-probe.sh, scripts/utilities/verify-lab-07.sh, scripts/cleanup/lab-07-cleanup.sh (not run)
- Exercises: [exercises.md](exercises.md)
- Notes and review questions: [notes/lab-07-notes.md](../../notes/lab-07-notes.md)
