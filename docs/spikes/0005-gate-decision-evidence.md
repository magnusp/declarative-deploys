# Spike 5: Evidence that the gate ran

* **Target tier:** tier 4
* **Enforcement point:** Policy Reporter, backed by Kyverno `PolicyReport` data
* **Size:** S
* **Controls:** A.8.15 (logging), A.8.16 (monitoring activities), A.5.28 (collection of evidence), A.8.32 (change management)

## Question

What record demonstrates that the automated approval control operated on every deploy — rather than merely
that it exists?

## Why the gap exists

Four-eyes review leaves evidence for free. The pull request holds the reviewer identity, the approval
timestamp, the diff that was approved, and the fact that nothing merged without it. An auditor reads the
history and the control is self-evidencing.

An automated gate is not. Tier 4 adds Policy Reporter with SQLite persistence and describes it as giving
governance decisions "a queryable audit trail", which is true for a class of decisions but likely not the
class that matters most here. Kyverno `PolicyReport` resources describe results for resources that **exist**.
A `Deployment` rejected at admission never exists, so the rejection surfaces as an admission error returned
to the client and a Kubernetes event — not necessarily a durable report row.

If that holds, the evidence store contains the allowed deploys and omits the blocked ones, which inverts what
an auditor asks for first. Confirming or refuting this is the spike's primary job, and it is cheap to test.

## Investigation approach

**Test the denial-recording behaviour directly.** Trigger a rejection against a tier-4 cluster and check
whether it appears in `PolicyReport` data and in the Policy Reporter UI, or only as an event. Determine
whether Kyverno's admission reporting configuration changes the answer, and whether Policy Reporter's
targets can capture denials by consuming the event stream instead.

**Define the evidence a deploy needs.** Rather than starting from what the tooling happens to emit, start
from the claim being evidenced: *every deploy that reached this cluster had a valid, independently-issued
approval attestation, and deploys without one were rejected*. Work out the minimum record that supports that
claim — the workload identity, the image digest, the approval predicate that was accepted including its
approvers and signing identity, the gate verdict, and the timestamp. Then check which fields the current
tooling can actually produce, and where the gaps are.

**Establish completeness, not just presence.** An evidence store that records some deploys is worse than
useless for this claim, because it cannot distinguish "no violations occurred" from "violations occurred and
went unrecorded". Determine what demonstrates that the gate ran on every admission during a period —
plausibly by reconciling the deploy count against the record count, which needs both to be countable.

**Note the absent notification path.** The `FluxInstance` enables `notification-controller`, but there is no
`Provider` or `Alert` anywhere in the repository, so a failing reconciliation or a rejected release notifies
nobody. A control whose failures are never announced is not monitored, whatever the evidence store contains.
Decide whether alerting on gate failures is in scope for the control or a separate operational concern.

## Done when

You can state whether denials are durably recorded, define the minimum evidence record for an approved
deploy, and identify which parts of that record tier 4's current tooling cannot produce.

## Notes

Policy Reporter's storage here is a showcase artifact and not the subject of this spike: SQLite on a single
`ReadWriteOnce` volume served by kind's `local-path` provisioner, one replica, no retention policy, and no
backup or export path, so the evidence dies with the cluster. A real adoption would obviously back this with
a durable database. The design question that survives that substitution — what the gate must emit to be
auditable at all, and for how long it must be kept — is what this spike investigates.
