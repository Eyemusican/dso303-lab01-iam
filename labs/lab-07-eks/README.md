# Lab 7: Deploying a Microservices Application on Amazon EKS

Tenzin Namgay (02230307), DSO303

## Where to find everything

- **Report:** [report.md](report.md)
- **Exercises 1 to 5:** [exercises.md](exercises.md)
- **Notes and review questions:** in the `notes` folder at the repo root, [notes/lab-07-notes.md](../../notes/lab-07-notes.md). The support path, every step's notes and Floci limitations, the Step 20 ECS and Kubernetes comparison table, the Exercise 5 Part 3 list and the seven review questions are all there.
- **Screenshots:** in the `screenshots` folder at the repo root. All Lab 7 screenshots start with `lab07-`, for example `lab07-step16-discovery.png` and `lab07-ex4-drain.png`. [Open the screenshots folder](../../screenshots)

## Result

verify-lab-07.sh: PASS=30 FAIL=0. I changed one check so it ignores outputs/.gitkeep, the same fix as in Lab 06. The smoke test through usms-gateway printed SMOKE TEST PASSED.

Before building, verify-lab-02.sh was PASS=32 FAIL=1 because usms-db-sg had two rules with no source. After I removed them and added the Lab 02 rule back it was PASS=33 FAIL=0. verify-lab-04.sh was PASS=39 FAIL=0.

usms-eks-cluster is ACTIVE across all four Lab 02 subnets with the _lb_ports_ tag, and usms-eks-nodes is in the two private subnets. In namespace usms, usms-gateway (1 pod) reaches usms-enrolment (2 pods) and usms-results (2 pods) by DNS name only, and usms-timetable (1 pod) was added in Exercise 1. After a Floci restart every AWS and Kubernetes object came back, but the pods had to be rescheduled onto the new k3s node, which is explained in the notes under Step 22.

## Files in this lab

- `../../configs/lab-07.env`: cluster, node group, role, policy, security group and Kubernetes names for Lab 08 (21 exports)
- `../../policies/trust-eks-cluster.json`: trust policy for eks.amazonaws.com
- `../../policies/trust-eks-node.json`: trust policy for ec2.amazonaws.com
- `../../policies/usms-eks-cluster-policy.json`: USMSEKSClusterPolicy, local stand in for AmazonEKSClusterPolicy
- `../../policies/usms-eks-node-policy.json`: USMSEKSNodePolicy, local stand in for the three AWS managed node policies
- `../../templates/lab-07-create-cluster.json`: create-cluster body with all four subnets and the _lb_ports_ tag
- `../../templates/lab-07-create-nodegroup.json`: create-nodegroup body, private subnets only, min 2 / max 4 / desired 2
- `../../manifests/lab-07/00-namespace.yaml`: namespace usms
- `../../manifests/lab-07/10-configmap-app.yaml`: usms-app-config, shared by all services
- `../../manifests/lab-07/20-enrolment.yaml`: usms-enrolment ConfigMap, Deployment and Service, plus the spread rule and PodDisruptionBudget from Exercise 4
- `../../manifests/lab-07/30-results.yaml`: usms-results ConfigMap, Deployment and Service
- `../../manifests/lab-07/40-gateway.yaml`: usms-gateway ConfigMap, Deployment and Service, with the /timetable/ route from Exercise 2
- `../../manifests/lab-07/60-serviceaccount.yaml`: usms-enrolment-sa for IRSA
- `../../manifests/lab-07/70-timetable.yaml`: usms-timetable (Exercise 1)
- `../../scripts/utilities/eks-support-probe.sh`: decides the support path (Step 2)
- `../../scripts/utilities/verify-lab-07.sh`: checks 30 things about this lab
- `../../scripts/cleanup/lab-07-cleanup.sh`: end of course only, not run

The Secret manifest is not committed. I moved it to outputs/lab-07-secret.yaml, which is git ignored.

## Floci support path

Path A: aws eks create-cluster and create-nodegroup worked, and Floci ran the cluster as a real k3s container, so every kubectl step was real. The limits were on the AWS side. Only one node joined instead of two and it runs Kubernetes 1.34, IAM policies are stored but not enforced, and IRSA stopped after registering the OIDC provider. After a Docker or Floci restart, Floci builds a new k3s container and I had to delete the old node so the pods could move.
