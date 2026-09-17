# GAMEPLAN: getting from tier 0 to tier 4

This is a short read for the people who actually do the work: junior developers and SREs picking up the
task of moving a real platform from tier 0 toward tier 4. If you want the full technical detail, each
tier has its own `README.md`. This page is the pitch and the map, not the manual.

## The problem, in one sentence

At tier 0, "deploy" means "git commit to a repo," one team owns both the app and its infrastructure
shape, and the only way to know who is allowed to deploy what is to ask around.

That works fine with five services and one team. It stops working once you have many app teams, a
platform team that owns shared infrastructure, and an auditor who wants a straight answer to "who
approved this change, and how do you know?"

## The journey, tier by tier

Think of this as five stops, each one removing a manual step or closing a gap the last stop opened.

1. **Tier 0 — the baseline.** Flux is already watching a git repo and deploying whatever's committed. A
   deployer tool automates the commit. Nothing here is broken, but the app's code and its Kubernetes
   shape (`Deployment`, `Service`, resource limits) are one undifferentiated blob, owned by one team.
2. **Tier 1 — split the ownership.** The platform team publishes a reusable Helm chart. The app team
   only owns their values. This is the first time "platform" and "application" become separate jobs
   with separate repos to touch.
3. **Tier 2 — deploy without a commit.** The app team stops committing to the cluster repo at all. They
   publish an image and a values file to a registry, and Flux picks it up automatically. Faster, but it
   quietly removes something: nobody reviews the change before it goes out, because there's no longer a
   pull request to review.
4. **Tier 3 — check who's allowed to deploy.** A policy engine (Kyverno) and an authorization service
   (SpiceDB) get added. Now the cluster checks, at the moment of deploy, whether the person who built
   this image is actually allowed to deploy this service. Unauthorized deploys are rejected automatically.
5. **Tier 4 — trust but verify.** The authorization check now works across every team's namespace, not
   just one hardcoded example. On top of that, the cluster verifies the image itself wasn't tampered
   with, and every policy decision gets logged somewhere you can actually look at later.

Each tier's README ends with a short "Progressing to the next tier" section if you want the exact
mechanics. This document is only the why.

## What you gain by making the trip

* **A platform team that can move independently of every app team**, and vice versa. Nobody's waiting on
  someone else's PR to ship their own change.
* **Deploys that don't require a human to babysit them.** Publishing an artifact is the deploy — no
  waiting for a merge, no manual `kubectl apply`.
* **An automatic answer to "was this person allowed to deploy this?"** instead of "let's check the Slack
  history."
* **A record you can hand to an auditor** that shows what was deployed, by whom, and whether it passed
  the checks in place at the time — instead of hoping someone remembers.
* **Tamper-evidence on what actually runs.** By tier 4, the cluster refuses to run an image whose
  provenance it can't verify, not just an image someone forgot to update.

None of this is free. Every tier trades a manual, human-mediated step for an automated one, and the whole
point of `docs/spikes/` is that one of those trades — the human review that disappears at tier 2 — hasn't
been fully replaced by anything automated yet. That's honest, ongoing work, not a solved problem. Read
[`docs/spikes/README.md`](docs/spikes/README.md) when you get there.

## What you lose by staying at tier 0

Staying put isn't free either. It just hides the cost instead of paying it up front.

* **Every app team is coupled to the same deploy mechanism and the same manifests.** A platform-wide
  change means editing every app's YAML by hand, or building your own bespoke tooling to do it, forever.
* **"Who can deploy what" lives in people's heads, or in a wiki page that goes stale.** There's no
  automatic check, so there's no automatic evidence either.
* **You're one Slack outage away from not knowing who approved a change**, because approval is a
  conversation, not a system.
* **Every new app team means more copy-pasted manifests**, not more reuse. The platform team's expertise
  doesn't scale past however many services they can personally review.
* **When an auditor or a security review asks "prove this," the honest answer is "we don't have that
  recorded."** Not because anyone did anything wrong — because tier 0 was never built to answer that
  question.

None of this means tier 0 is a mistake. It's a legitimate starting point, and it's where most real
platforms actually begin. The point of this progression is that staying there is a choice with a cost,
and that cost grows with every team, every service, and every audit you go through.

## Where to start

Read `tier-0/README.md`, spin up the cluster with `./cluster.sh up`, and look at what's actually running.
Then move to `tier-1/README.md` and do the same. Each tier is a real, working cluster you can poke at —
this isn't slides, it's a thing you can break and rebuild in a few minutes.
