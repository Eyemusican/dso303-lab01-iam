# Lab 08: Scaling and Exposing USMS on EKS

Tenzin Namgay (02230307), DSO303

## Where to find everything

- Report: [report.md](report.md)
- Exercises 1 to 5: [exercises.md](exercises.md)
- Notes and review questions: [../../notes/lab-08-notes.md](../../notes/lab-08-notes.md)
- Screenshots: [../../screenshots/](../../screenshots/) (all files start with lab08-)
- Architecture diagram: [../../diagrams/lab08-architecture.png](../../diagrams/lab08-architecture.png)

## Result

I scaled USMS on the Lab 07 EKS cluster by hand and with Horizontal Pod Autoscalers, set requests and limits and checked their QoS classes, protected the gateway and enrolment with PodDisruptionBudgets, pinned enrolment to its node with a nodeSelector and exposed the services as ClusterIP, NodePort, LoadBalancer and Ingress.

- usms-enrolment-hpa scaled enrolment from 2 to 3 under load from the loadgen pods and back to 2 after the 300 second scale down window.
- usms-results-hpa (Exercise 1) runs at 60% CPU with min 2 and max 6.
- The gateway now runs 2 replicas, so its PDB allows 1 disruption (Exercise 2).
- I found the two faults in the usms-reports HPA and fixed each with one field (Exercise 3).
- usms-results-ingress gives results its own path on the shared ALB group with a source IP condition (Exercise 4).
- Evidence and IRSA readiness files for Lab 10 are in outputs/ and are not committed (Exercise 5).
- verify-lab-08.sh gave PASS=33 FAIL=1. The one fail is the node group maxSize, because update-nodegroup-config fails on Floci.
- After stopping and starting Floci (floci-down.sh and floci-up.sh) the state was still there (PERSISTENCE PROVEN in Step 18).
- I wrote the cleanup script but did not run it, because Lab 09 builds on this cluster.

## Files in this lab

- [../../manifests/lab-08/10-hpa-enrolment.yaml](../../manifests/lab-08/10-hpa-enrolment.yaml)
- [../../manifests/lab-08/11-hpa-results.yaml](../../manifests/lab-08/11-hpa-results.yaml)
- [../../manifests/lab-08/20-loadgen.yaml](../../manifests/lab-08/20-loadgen.yaml)
- [../../manifests/lab-08/30-pdb-gateway.yaml](../../manifests/lab-08/30-pdb-gateway.yaml)
- [../../manifests/lab-08/40-service-nodeport.yaml](../../manifests/lab-08/40-service-nodeport.yaml)
- [../../manifests/lab-08/50-service-loadbalancer.yaml](../../manifests/lab-08/50-service-loadbalancer.yaml)
- [../../manifests/lab-08/60-ingress.yaml](../../manifests/lab-08/60-ingress.yaml)
- [../../manifests/lab-08/70-ingress-results.yaml](../../manifests/lab-08/70-ingress-results.yaml)
- [../../manifests/lab-07/20-enrolment.yaml](../../manifests/lab-07/20-enrolment.yaml) (nodeSelector added, PDB set to maxUnavailable 1)
- [../../manifests/lab-07/40-gateway.yaml](../../manifests/lab-07/40-gateway.yaml) (2 replicas, Service changed to LoadBalancer)
- [../../configs/lab-08.env](../../configs/lab-08.env)
- [../../scripts/utilities/hpa-watch.sh](../../scripts/utilities/hpa-watch.sh)
- [../../scripts/utilities/verify-lab-08.sh](../../scripts/utilities/verify-lab-08.sh)
- [../../scripts/cleanup/lab-08-cleanup.sh](../../scripts/cleanup/lab-08-cleanup.sh) (written, not run)

## Floci support path

I used Path A, the Floci EKS cluster, which runs as a k3s container (Kubernetes v1.34.1+k3s1) behind https://localhost:6500.

What worked: metrics-server, usms-enrolment-hpa scaling out and in, usms-results-hpa reading 2%/60%, QoS classes, PDBs with the eviction API, the nodeSelector, ClusterIP, NodePort and the LoadBalancer Service (it got 172.17.0.3 from the k3s service load balancer), and Ingress objects being stored.

What did not work and what I did instead:

- aws eks update-nodegroup-config failed with 400 InvalidArgument, which is the course known issue for this lab, so I used the HPA drill to show scaling.
- The node group labels never reached the k3s node, so I labelled the node with workload=usms and tier=app by hand.
- The load balancer ports 8081 and 8082 were not published on the rebuilt k3s container, so I reached the services with kubectl port-forward.
- There is no ingress controller on this build, so the Ingresses have no class and no address. I explained what the AWS Load Balancer Controller would build on real EKS.
- After Docker or laptop restarts the cluster sometimes stayed at CREATING. I recovered it by removing the k3s container, restarting Floci, deleting the dead node and labelling the new one again.
