# Lab 05 Working Notes

## Support path (Step 3)

Final: path A for the control plane and health checks, path B for the client data path. All ten probes in Step 3 answered SUPPORTED, Step 5 returned an ARN, and in Step 11 Floci really health checked the containers and marked both targets healthy. But in Step 12 the DNS name did not resolve and curl could not connect, so I never saw a 200 from my shell. Details under Step 12.

## Pre lab checks (Steps 1 and 2)

floci-storage-check.sh: my version prints [ok] lines instead of a PASS=16 total. Every line was [ok], so I counted it as passing.
verify-lab-02.sh: PASS=32 FAIL=1, the same Floci limitation recorded in Lab 2.
verify-lab-03.sh: PASS=34 FAIL=2, the same two Floci limitations recorded in Lab 3.
verify-lab-04.sh: PASS=38 FAIL=0. The doc example shows 49 because its script has more checks than mine. FAIL=0 is what the doc requires.

## Step 4 Your turn: why port 443 alone does not give HTTPS

Opening 443 on usms-alb-sg only opens the firewall, so the two missing things are an HTTPS listener on port 443 and a TLS certificate attached to that listener, because a listener is what actually accepts connections and HTTPS needs a certificate to do the TLS handshake. AWS Certificate Manager gives the public certificate for free, but it can only issue it for a domain name I own, and that domain is the part I have to obtain from a registrar.

## Step 5: the load balancer

ARN: arn:aws:elasticloadbalancing:us-east-1:000000000000:loadbalancer/app/usms-enrolment-alb/7ebbd0c317ac42a4
DNS name: usms-enrolment-alb-7ebbd0c317ac42a4.elb.floci (Floci format, not the real AWS elb.amazonaws.com form)
State went active on the first poll and the waiter returned straight away. Two AZs, us-east-1a and us-east-1b. Both attributes were accepted.

## Step 6 Your turn: the health check matcher

I widened the matcher to 200-399 with modify-target-group, read it back, then set it back to 200. Both changes worked straight away without recreating the target group.

(a) A web app that redirects / to /login with a 302 when you are not signed in would work perfectly but fail a strict 200 health check forever.

(b) It would be a bug in my work, not the script, because a verification script exists to check the build against the agreed baseline in Section 5.1, which says matcher 200, so a failure there is the script correctly catching that my config drifted from the spec.

## Step 7: target group attributes

deregistration_delay.timeout_seconds 30 and load_balancing.algorithm.type least_outstanding_requests were both accepted.
Floci limitation: describe-target-group-attributes only listed the two attributes I set. Real AWS returns the full list including defaults like stickiness.enabled false and slow_start.duration_seconds 0.

## Step 8: the listener

HTTP:80 listener created, default action forward to usms-enrolment-tg, and AttachedToLoadBalancers went from 0 to 1.
Floci difference: SslPolicy came back as an empty string "" instead of null. Both mean no TLS policy because it is an HTTP listener.

## Step 9: enrolment sg now admits usms-alb-sg

Both sources are on port 80: usms-app-sg (Lab 04, still there on purpose) and usms-alb-sg (this step). CIDRs empty.
Floci difference: real AWS merges the two rules into one IpPermission entry with two UserIdGroupPairs because they share protocol and port. Floci kept them as two separate IpPermission entries. Unlike Lab 2, the group referenced rule was not dropped.

## Step 10: attaching the service (fallback path taken)

update-service --load-balancers --health-check-grace-period-seconds 60 returned no error, but the response and describe-services both showed loadBalancers null and grace null. My Floci build accepts the flag on update-service and silently ignores it.
I took the doc's fallback path: scaled the service to 0, deleted it, and recreated it with create-service and --load-balancers attached.
Two changes from the doc's fallback command: I used usms-enrolment:4 instead of :2 because :4 is my Lab 04 revision (the doc's rule is the same task definition as Lab 04), and I left out --deployment-configuration file://templates/lab-04-deployment-config.json because Lab 04 never created that file and Lab 04's own create-service did not use it.
Same name, cluster, desired count 2, private subnets a and b, usms-enrolment-sg, assignPublicIp DISABLED and the Lab=04 tag were all kept.
Result: loadBalancers now has one entry (enrolment-api on port 80, usms-enrolment-tg) and the task definition is still usms-enrolment:4, no new revision.
Floci limitation: healthCheckGracePeriodSeconds stays null after both create-service and a second update-service. Real AWS would store 60 and ignore target health for the first 60 seconds of each task.

## Step 11: targets registered by the service

Two targets appeared on the first poll, both healthy, and I never ran register-targets. The ECS service registered them.
Floci difference: the target addresses were 172.18.0.3 and 172.18.0.4, which are the Docker network addresses of the real nginx containers on my laptop, not addresses from my private subnets, and AvailabilityZone came back None. Real AWS would register one 10.x address in each private subnet, one per AZ.
Because the targets went healthy, Floci's load balancer really probed GET / on the containers and got 200.
Service: desired 2, running 2, pending 0, one deployment, rolloutState COMPLETED, loadBalancers pointing at usms-enrolment-tg. Events list was None, the same as Lab 04.
Part 3: list-tasks returned four tasks, two RUNNING (new service) and two STOPPED (the old service before the fallback). For every task healthStatus and the private IP were None, so I could only observe the load balancer half of the side by side comparison. Real AWS would give HEALTHY or UNKNOWN and the task's 10.x address so I could line them up by address.

### Reading ECS health and target health together

| ECS healthStatus | Target health | Diagnosis |
| --- | --- | --- |
| HEALTHY | healthy | Working |
| HEALTHY | unhealthy | The network path is broken: security group, subnet, or the health check path returning the wrong code |
| UNHEALTHY | unhealthy | The application is broken, read the container logs |
| UNKNOWN | healthy | Not a fault, the task definition has no container health check |
| anything | unused | Nothing forwards to this target group |

## Step 11 Your turn: scaling 2 to 3 to 2

At desired 3 a third target (172.18.0.5) appeared as initial on the second poll. Back at desired 2 it was gone on the first poll and the two original targets stayed healthy. I never ran register-targets or deregister-targets.
Floci difference: the removed target disappeared straight away instead of showing draining for the 30 second deregistration delay.

Without the service registering its own targets, after every scaling event I would have had to update the target group by hand, running register-targets with each new task's IP address and deregister-targets for each task that stopped.

## Step 12: proving the path

Part 1, data path: usms-enrolment-alb-7ebbd0c317ac42a4.elb.floci did not resolve on my Windows host (getaddrinfo failed) and curl returned http_code=000. I did NOT get a 200. Floci does not publish the load balancer on any host port and the doc says not to publish extra ports to force it.
Real AWS would resolve the name to the public addresses of the nodes in us-east-1a and us-east-1b and forward to a healthy target.
Part 2, control plane proof, saved in outputs/lab-05-path-proof.txt:
1. Listener HTTP 80 forwards to usms-enrolment-tg.
2. usms-enrolment-tg is type ip, HTTP 80, health check /, in vpc-7b4598ab.
3. Two targets, 172.18.0.3 and 172.18.0.4. The script says NOT in a Lab 02 private subnet because Floci registers the Docker network address of each container, the same difference I recorded in Step 11.
4. usms-enrolment-svc registered them, container enrolment-api on port 80. Grace period None, as recorded in Step 10.
5. usms-enrolment-sg admits usms-alb-sg (sg-43a4d32b229ced732), so the link that matters on real AWS is in place. usms-app-sg is still there until Step 13.

## Step 13: the cutover

describe-security-group-rules found the Lab 04 rule as sgr-bf15d58c0dae9e42c (inbound tcp/80 from usms-app-sg).
Floci limitation: revoke-security-group-ingress --security-group-rule-ids returned True but removed nothing. Both describe views still showed usms-app-sg.
Workaround: I revoked the same rule using --ip-permissions file://policies/usms-enrolment-sg-ingress.json, the Lab 04 document for exactly this rule, which the doc's danger box names as the way to restore it. That also returned True.
After that, describe-security-groups (the view the doc's Verify uses) shows one source on port 80, usms-alb-sg (sg-43a4d32b229ced732), and usms-app-sg is gone. The load balancer is now the only thing that can open a connection to an enrolment task.
Floci limitation: describe-security-group-rules still lists the old sgr-bf15d58c0dae9e42c, so Floci keeps a separate rule list that went stale. On real AWS both views always agree.

## Step 13 part 3: verify-lab-04.sh after the cutover

verify-lab-04.sh went from PASS=38 FAIL=0 (outputs/lab-05-pre-verify-04.txt) to PASS=37 FAIL=1 (outputs/lab-05-post-verify-04.txt). The diff shows exactly one check changing: "usms-enrolment-sg is sourced from usms-app-sg (not a CIDR)" went from ok to FAIL. This is expected, because that check describes the architecture before the load balancer. The script did its job by failing.
Three possible responses: leave it and document the expected failure (what I am doing now, because Lab 04's script is a record of what Lab 04 built), update the check to assert usms-alb-sg as the source (Exercise 2), or delete the check (almost never right, because the property still matters and only the expected value changed).
From here verify-lab-05.sh is the script of record.

## Step 14: forced deployment behind the load balancer

update-service --force-new-deployment returned Deployments 1 straight away. Over 15 polls the deployment stayed COMPLETED with 2 running and both targets stayed 172.18.0.3 and 172.18.0.4 healthy.
Pre and post deploy (outputs/lab-05-pre-deploy.txt and lab-05-post-deploy.txt): same task definition usms-enrolment:4, same counts 2 and 2, and the SAME addresses.
As the doc says, I then checked task ARNs: the running tasks were still c2150cc4... and 528b59cd..., the same ones as Step 11.
Floci limitation: --force-new-deployment returns success but does not replace any tasks, so I could not observe initial, healthy and draining during a deployment. Real AWS would start new tasks, register them as initial, wait for healthy, then mark the old ones draining for up to the 30 second deregistration delay before stopping them.
Doc bug: the poll loop's stop check uses --query 'length(deployments)', which errors with "invalid type for value: None" because the path is missing services[0]. It should be 'length(services[0].deployments)'. This made the loop always run all 15 polls but did not affect the polls themselves.

## Step 15: listener rule

Rule at priority 10 created: path-pattern /alb-health and /alb-health/* returns a fixed-response 200 text/plain "usms-enrolment-alb ok" without contacting any target.
describe-rules shows two entries: my rule (Priority "10", IsDefault false, fixed-response, status "200", no target group) and the default action (Priority "default", IsDefault true, forward to usms-enrolment-tg).
Floci difference: Conditions[0].Values came back empty. The two paths are stored only in Conditions[0].PathPatternConfig.Values, which I checked separately. Real AWS fills both.
Part 3: curl to / and /alb-health both returned 000, the same missing data path as Step 12, so describe-rules is my evidence that the rule is in place and is evaluated before the default action.

## Step 16: persistence

After floci-down.sh and floci-up.sh I re-derived the load balancer ARN, target group ARN, listener ARN and usms-alb-sg from the API, and all four matched the values from before the restart. The diff of outputs/lab-05-pre-restart.txt and lab-05-post-restart.txt was empty, so the script printed PERSISTENCE PROVEN.
Honest note: the grace period was None both before and after (the Step 10 limitation), so the check proves the None survived, not a stored value of 60.
The tag:Name filter on describe-security-groups returned the right group, sg-43a4d32b229ced732.

## Step 17: closing the loop

usms-alb-sg admits tcp/80 and tcp/443 from 0.0.0.0/0 (443 is from my Step 4 Your turn, so it is one more rule than the doc's example).
CUTOVER CONFIRMED: the only source group on usms-enrolment-sg is usms-alb-sg (sg-43a4d32b229ced732).
LOOP CLOSED: usms-web-01 (i-00d916c5e2de6fcf8) still carries usms-app-sg, but that group no longer grants it anything on the tasks. It now has to call usms-enrolment-alb-7ebbd0c317ac42a4.elb.floci instead of a task address. The instance.group-id filter worked this time and returned only usms-web-01.
Audit: usms-alb-sg, the load balancer and the target group are all tagged Lab=05, and elbv2 describe-tags worked on my build.

## Step 18: configs/lab-05.env

Written by lookup, 15 exports, all populated except USMS_SVC_GRACE_PERIOD=None, which is the Step 10 Floci limitation (real AWS would record 60).
Doc bug: the listener line's filter Listeners[?Port==\`80\`] failed on my shell with "Bad jmespath expression: Unknown token \" because inside $(...) the backslash reached the AWS CLI along with the backtick, which left USMS_ALB_LISTENER_ARN empty. I changed only that filter to Listeners[?to_string(Port)=='80'], which means the same thing and needs no backticks. After that the listener ARN was filled in.

## Section 9: verify-lab-05.sh

First run: PASS=46 FAIL=3 out of 49 checks.
Doc bug fixed: "no secret is tracked by git" used ! git ls-files | grep -q '^outputs/', which always fails because outputs/.gitkeep is meant to be tracked (Step 19 confirmed it is the only tracked file there). I changed it to ! git ls-files outputs/ | grep -vx 'outputs/.gitkeep' | grep -q . which is the same fix I made to verify-lab-04.sh in Lab 04.
Final run: PASS=47 FAIL=2. Both remaining failures are benign and have one cause:
1. "healthCheckGracePeriodSeconds is set (not None, not 0)": my Floci build accepts --health-check-grace-period-seconds on create-service and update-service but does not store it (Step 10). This is in the doc's own benign table. Real AWS would store 60.
2. "configs/lab-05.env has no empty values": the file records USMS_SVC_GRACE_PERIOD=None for the same reason. Every other value in the file is populated.
Cleanup script: scripts/cleanup/lab-05-cleanup.sh built and checked with bash -n (syntax OK). It has NOT been run.
Doc typo: its comments say "Run AFTER lab-04-cleanup.sh and BEFORE lab-04-cleanup.sh". From the doc's own order list the first one should be the Lab 06 cleanup (scaling configuration). I copied it as written because it is only a comment.

## Section 12.1: what I actually observed on my build

OBSERVED (I saw it in command output):
- usms-alb-sg admitting 0.0.0.0/0, and usms-enrolment-sg admitting only usms-alb-sg after the cutover (Steps 4, 13, 17)
- a load balancer across two subnets in us-east-1a and us-east-1b (Step 5)
- a target group with target-type ip (Step 6)
- the target group's LoadBalancerArns count going from 0 to 1 when the listener was created (Steps 6 and 8)
- the ECS service filling the target group itself, two targets, without me registering anything, and scaling to 3 and back to 2 (Step 11)
- targets reported healthy, and a new target reported initial (Step 11)
- a listener rule at priority 10 ordered ahead of the default action (Step 15, and the report tool in Exercise 3)
- the security cutover, and verify-lab-04.sh changing exactly one check from ok to FAIL (Step 13)
- all of it surviving a Floci restart with every ARN re-derived from the API (Step 16)

NOT OBSERVED, even though the doc lists it as observable:
- "a load balancer with no listener, answering nothing": I never ran describe-listeners or curl before Step 8, so I reasoned this rather than saw it
- "refusing to be anything else afterwards": I did not try to change the target type, I only read that there is no command for it
- "target addresses inside Lab 02's private subnet CIDRs": my targets were 172.18.0.3 and 172.18.0.4, Docker network addresses (Step 11)
- "a forced deployment producing new addresses": Floci kept the same two tasks and addresses (Step 14)

CONCEPTUAL (reasoned, not seen):
- a request going from a client to a task and back: no 200, DNS did not resolve and curl got 000 (Step 12)
- a health check probe being sent: the healthy state suggests Floci probed the containers, but I never saw a probe itself
- a target going from initial to healthy: I saw a target at initial and others at healthy, but never watched one change
- a target draining: the removed target disappeared straight away (Steps 11 and 14)
- least_outstanding_requests choosing a target: stored, no traffic to choose for
- a rule's path condition evaluated against a real URL: no data path (Step 15 curl got 000)
- the 2 to 4 minute provisioning time: mine went active on the first poll
- HTTPS, certificates and the TLS listener: planned in Exercise 4 only
- the cost: calculated from the AWS pricing pages in Exercise 4, never billed

## Review questions

**1. The group rule in Lab 04 and the load balancer in Lab 05**

Both exist because the tasks have no stable address. A task that stops takes its IP with it and a new task gets a new one, so anything written against an address is wrong as soon as the next deployment happens. The security group rule solved this for the firewall by naming a group instead of an address, and the load balancer solves it for clients by giving them one stable DNS name instead of a list of task IPs. The general problem is indirection: put something stable in front of something that changes, and give the job of keeping it up to date to whatever already knows about the changes (here the ECS service registers and deregisters its own targets). A third example from elsewhere in computing is DNS itself, where people use a hostname and the record is updated when the server's IP changes. Virtual memory is another, where programs use virtual addresses and the operating system maps them to physical memory that can move.

**2. "The health check says unhealthy, so the app is broken"**

That is not a safe conclusion, because the target group health check is sent from outside the task across the network, so it fails the same way whether the application is broken or the network path to it is broken. It cannot tell "the process is dead" apart from "the process is fine but the security group, subnet or health check path stops the probe reaching it". The field that separates them is the ECS task's healthStatus from the container health check, which runs inside the task. My diagnostic order would be: first look at healthStatus for the same task; if it is UNHEALTHY, read the container logs because the app is broken; if it is HEALTHY, check that usms-enrolment-sg admits usms-alb-sg on the target port, then the health check path and matcher, then the subnets and NACLs.

**3. Configuration versus identity**

There is no update-target-group-target-type because AWS treats the target type as part of what the target group is, not a setting on it. Changing it would make it a different object, so the only way is to create a new one. It is the same idea as Lab 04's task definition revisions: a revision is never edited, you register a new one. Two other fields in this lab that behave the same way are the load balancer's scheme and its type (application or internet facing cannot be changed after creation), and the target group's VPC. One that looks like it should be fixed but is not is the load balancer's security groups, which can be changed later with set-security-groups. The health check path and matcher can also be changed in place, as I did in the Step 6 Your turn.

**4. A request in flight when its task is stopped**

When ECS decides to stop the task, it first deregisters it from usms-enrolment-tg, and the load balancer marks it draining: it sends no new requests to it but lets requests already in flight finish. That lasts up to deregistration_delay.timeout_seconds, which I set on the target group to 30 seconds. After draining, ECS sends SIGTERM to the container and waits the stopTimeout from the task definition before sending SIGKILL. During a deployment, minimumHealthyPercent on the service decides whether a new task has to be healthy before the old one is taken out. A normal request that takes milliseconds therefore succeeds, because it finishes well inside the 30 second drain. If the delay were left at the default of 300 seconds the request would still succeed, but every task would wait up to five minutes before stopping, so a deployment of two tasks could take around ten minutes for no benefit.

**5. Fix the Lab 04 script or leave it failing**

The case for updating it straight away is that a script that fails for a known reason trains people to ignore it, and then a real failure is missed among the expected ones. The case for leaving it failing and documenting it is that Lab 04's script is a record of what Lab 04 built, and changing it quietly can hide a regression. On a system with four other engineers I would update the check in the same commit as the architecture change and say why in the commit message, because the others cannot know the failure is expected unless they read my notes. With only me on the system, leaving it failing for a short time with a note is more acceptable, because the person reading the failure is the person who knows why, which is what I did until Exercise 2.

**6. Internet facing load balancer, private tasks**

Both are true because the load balancer and the tasks are in different subnets. The load balancer's nodes are in usms-public-subnet-a and usms-public-subnet-b, whose route table usms-public-rt sends 0.0.0.0/0 to usms-igw, so the nodes get public addresses and can be reached from the internet. The tasks are in usms-private-subnet-a and usms-private-subnet-b, whose route table usms-private-rt only goes out through usms-nat (outbound only), and the tasks have no public IP, so nothing outside the VPC can start a connection to them. The load balancer reaches them because it is inside the same usms-vpc and usms-enrolment-sg admits usms-alb-sg. An attacker who controlled the load balancer's configuration could change listeners and rules, send traffic to other target groups in the VPC, or read and redirect the requests passing through it, but could still only reach the tasks on tcp/80, because usms-enrolment-sg admits nothing else, and could not reach usms-db-01. If the tasks had public addresses, anyone could try to connect to them directly and skip the load balancer, its listener and its rules, and the only thing protecting them would be their own security group.

**7. Requests per target versus CPU**

Requests per target is a better signal for a web API because the load on the service is the number of requests coming in, so it scales on the demand itself and can add tasks before CPU has climbed. CPU is the better choice when the work is CPU heavy and the cost of each request varies a lot, for example generating large reports, or when most of the work does not come through the load balancer at all. ALBRequestCountPerTarget would scale the enrolment service badly if a small number of requests were very expensive while most were cheap, so the request count would stay low while the tasks were overloaded, or if clients kept long lived connections that send few requests but use a lot of resources.
