# Spike 5: Evidence that the gate ran

* **Target tier:** tier 4
* **Enforcement point:** Policy Reporter, backed by Kyverno `PolicyReport` data
* **Size:** S
* **Controls:**
  * A.8.15 — logging
  * A.5.33 — protection of records
  * A.8.16 — monitoring activities
  * A.8.32 — change management

## Question

What record demonstrates that the automated approval control operated on every deploy, rather than only
that the control exists?

## Why the gap exists

Four-eyes review produces evidence as a side effect. The pull request holds the reviewer identity, the
approval timestamp, the diff that was approved, and the fact that nothing merged without it. An auditor
reads the history, and the control evidences itself.

An automated gate does not. Tier 4 adds Policy Reporter with SQLite persistence and describes it as giving
governance decisions a queryable audit trail. That holds for one class of decision, but likely not for the
class that matters most here. Kyverno `PolicyReport` resources describe results for resources that exist. A
`Deployment` rejected at admission never exists, so the rejection surfaces as an admission error returned
to the client and as a Kubernetes event, not necessarily as a durable report row.

If that is correct, the evidence store holds the allowed deploys and omits the blocked ones, which is the
reverse of what an auditor asks for first. Confirming or refuting it is this spike's primary job, and it is
cheap to test.

## Investigation approach

### Test the denial-recording behavior directly

Trigger a rejection against a tier-4 cluster. Check whether it appears in `PolicyReport` data and in the
Policy Reporter UI, or only as an event. Determine whether Kyverno's admission reporting configuration
changes the result, and whether Policy Reporter's targets can capture denials by consuming the event stream
instead.

### Define the evidence a deploy needs

Start from the claim that needs evidencing rather than from what the tooling emits: every deploy that
reached this cluster carried a valid, independently issued approval attestation, and admission rejected
deploys without one. Work out the minimum record that supports that claim. It plausibly needs the workload
identity, the image digest, the accepted approval predicate including its approvers and signing identity,
the gate verdict, and the timestamp. Then determine which of those fields the current tooling can produce,
and where the gaps are.

### Establish completeness, not only presence

An evidence store that records some deploys does not support this claim at all, because it cannot
distinguish "no violations occurred" from "violations occurred and went unrecorded". Determine what
demonstrates that the gate ran on every admission during a period. Reconciling the deploy count against the
record count is one option, which requires both to be countable.

### Note the absent notification path

The `FluxInstance` enables `notification-controller`, but the repository contains no `Provider` or `Alert`,
so a failing reconciliation or a rejected release notifies no one. A control whose failures go unannounced
is not monitored, whatever the evidence store holds. Decide whether alerting on gate failures belongs to
this control or to a separate operational concern.

## Done when

You can state whether denials reach durable storage, you have defined the minimum evidence record for an
approved deploy, and you have identified which parts of that record tier 4's current tooling cannot
produce.

## Notes

Policy Reporter's storage here is a showcase artifact rather than this spike's subject: SQLite on a single
`ReadWriteOnce` volume served by kind's `local-path` provisioner, one replica, no retention policy, and no
backup or export path, so the evidence disappears with the cluster. A real adoption would use a durable
database. The design question that survives that substitution is what this spike investigates: what the
gate must emit to be auditable, and how long that record must be kept.
