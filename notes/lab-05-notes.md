# Lab 05 Working Notes

## Support path (Step 3)

Provisional path A. All ten probes in Step 3 answered SUPPORTED, including both skeletons and describe-load-balancers. I will confirm A when Step 5 returns an ARN, and Step 12 decides whether the data path works or whether I am really on path B.

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
