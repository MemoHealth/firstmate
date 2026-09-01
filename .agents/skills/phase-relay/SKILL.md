---
name: phase-relay
description: >-
  Agent-only procedure for running one issue through separate plan, build, and review workers so no phase inherits another phase's context.
  Load before dispatching an issue large enough to need a written plan, at every phase boundary (a plan report landing, a build reporting done, a review returning findings), and before promoting any scout, because this flow replaces promotion with a fresh build worker.
  Owns phase triage, the durable handoff artifact, the per-phase dispatch profile, the checkpoint-and-respawn rule for an exhausted build worker, and the fix loop.
user-invocable: false
metadata:
  internal: true
---

# phase-relay

One issue, three workers, no shared context.

A single worker that plans, builds, and then reviews its own change pays for the entire history on every turn, and it reviews its own reasoning rather than the code it actually produced.
Firstmate already gives each crewmate its own session and its own context, so the relay is mostly a discipline of not throwing that away: never carry one phase's context into the next, and put the handoff in a durable artifact instead of in an agent's head.

This skill owns the relay procedure only.
Task lifecycle, delivery modes, and approval authority stay owned by `AGENTS.md` section 7; dispatch profile mechanics stay owned by `docs/configuration.md`; Munra-specific intake stays owned by `munra-architecture-intake`.

## 1. Triage, before anything is spawned

Run the full relay when any of these holds:

- the change touches more than one surface, or the project's architecture model names a shared core for it
- it introduces or alters a data model, schema, migration, or persistence shape
- the issue says what is wrong but not what to build
- an invariant named in the project's architecture docs is in scope
- the captain asks for the relay by name

Run a single-phase ship when all of these hold: one surface, an established pattern to copy, acceptance criteria already concrete, and no invariant in scope.
Skip the review phase only for a trivial mechanical edit such as a rote rename, a formatting sweep, or a targeted typo fix.

State the triage verdict in one clause when reporting the dispatch, so the captain can correct a misjudged call cheaply.

## 2. Phase 1, plan

Dispatch a scout on the planning profile.
The brief names the issue, requires the project's own architecture protocol where one exists, and requires the plan shape below.

The plan is the entire handoff, so it carries conclusions and not the reasoning that produced them:

- goal and acceptance criteria
- affected components and files
- architecture decisions taken, each with the alternative that was rejected and why
- implementation order
- tests and verification that will prove it
- known risks and explicit non-goals

The scout writes it to `data/<id>/report.md` and posts the same content as an issue comment headed `## Plan`.
The issue comment is the durable copy: it survives teardown, a context clear, and this home entirely, and the build worker reads it without any access to the scout.

At the boundary, read the report, relay its findings to the captain as findings, then tear the scout down.
Its worktree is scratch and the report survives, per `AGENTS.md` section 7.

## 3. The boundary rule: do not promote

`bin/fm-promote.sh` deliberately keeps the worker's window, worktree, and loaded context; its own header says so.
That is exactly right when a scout must carry reproduction state or scratch fixes into the implementation, and exactly wrong here, because inheriting the planner's context is the cost this flow exists to avoid.

While the relay is running, the build is a NEW ship task with a NEW worktree, briefed on the issue and the plan comment.
`AGENTS.md` section 7's promotion instruction remains the default for ordinary scout-to-ship work; this section is its only named exception.

## 4. Phase 2, build

Dispatch a ship task on the implementation profile.
The brief requires the worker to read the issue and its `## Plan` comment, implement the plan completely, and follow the project's selected delivery path.

Two lines matter more than the rest, and belong in every build brief:

- Do not redo architecture exploration; the plan already made those decisions.
- If the code contradicts the plan, stop and say so rather than quietly re-planning.

A contradiction reported here is a real signal: the plan was written against a tree that has since moved, or the planner was wrong.
Weigh it, and either steer the build with one corrected decision or return the issue to a short second plan pass.
Never let the build worker silently redesign, because nothing downstream would know the plan no longer describes the change.

### Checkpoint and respawn

When a build worker is clearly exhausted - a stale wake, repeated confusion, or re-reading files it has already changed - do not compact it and do not push through.
Have it, in this order: commit the work in progress on its branch, push the branch, then post a checkpoint comment on the issue headed `## Checkpoint` carrying goal, completed, remaining, decisions that must not be revisited, files changed, tests passing and failing, known problem, and next action.
Then tear it down and dispatch a fresh build worker on the same branch, briefed on the issue, the plan, and the checkpoint.

Committing and pushing first is not optional: teardown refuses unlanded work, and that refusal is a stop-and-investigate result rather than an obstacle to bypass.
The branch is what carries the work across the respawn; the context is deliberately discarded.

## 5. Phase 3, review

Dispatch a fresh scout on the review profile, never the build worker and never a worker that watched the build.
This is a knowledge-only review, which `AGENTS.md` section 7 already permits, so it is not a second manual gate stacked on a selected delivery path.

The reading list is exactly this, and the brief says so:

- `git diff <base>...HEAD`, `git status`, and `git log <base>..HEAD`
- the issue and its acceptance criteria
- surrounding code, opened selectively from what the diff touches

The build worker's transcript, its intermediate failures, and its test logs are deliberately out of scope.
An independent reviewer that never saw the reasoning reviews what the code does.

Ask for correctness bugs, regressions, security and privacy problems, missing tests, unnecessary complexity, and acceptance criteria the diff does not meet.
Ask it to leave cosmetic findings alone unless they are material, which is what keeps a reviewer from redesigning the system.
Each finding carries a file and line plus a concrete failure scenario, so the fix round has something to disprove.

## 6. Phase 4, fix and verify

Findings go back to the SAME build worker while it is alive.
It holds the code in context, and re-explaining the change to a fresh worker is the waste this flow exists to avoid; the independence that mattered was the reviewer's, and it has already been spent.

Do not clear the reviewer between round one and round two when the second pass only verifies its own findings, because that context is small and valuable.
Spawn a fresh reviewer instead when round one was large or the fix changed the shape of the diff.

A finding the build worker disputes is evidence to weigh, not an order to obey.
Resolve it on the code, and escalate an unresolved disagreement to the captain with both positions rather than letting either side win by persistence.

## 7. Per-phase profiles

The relay chooses models through the ordinary dispatch-profile path; it does not add a second routing mechanism.
`docs/configuration.md` owns the schema, and this is a starting point for a home's local `config/crew-dispatch.json`:

```json
{
  "rules": [
    {
      "when": "The task is a phase-relay plan phase, or any investigation, diagnosis, architecture, or audit scout.",
      "use": { "harness": "claude", "model": "claude-fable-5", "effort": "xhigh" },
      "why": "Planning and diagnosis are where expensive reasoning has the highest leverage, and the deliverable is compact."
    },
    {
      "when": "The task is a phase-relay review phase, or any knowledge-only review of a diff.",
      "use": { "harness": "claude", "model": "claude-fable-5", "effort": "high" },
      "why": "An independent reviewer reading only the diff is cheap in tokens and expensive to get wrong."
    },
    {
      "when": "The task implements an already written plan, or is any ordinary ship task.",
      "use": { "harness": "claude", "model": "claude-opus-5", "effort": "high" },
      "why": "Implementation is long and tool-heavy, so it runs on the strong general coding profile rather than the premium one."
    },
    {
      "when": "The task is a trivial mechanical edit such as a rote rename, formatting sweep, or targeted typo fix.",
      "use": { "harness": "claude", "model": "haiku", "effort": "low" }
    }
  ],
  "default": { "harness": "claude", "model": "claude-opus-5", "effort": "medium" }
}
```

A home without that file falls back to its static crewmate harness, and the relay still works; only the per-phase model choice is lost.

## Keeping this skill honest

If `bin/fm-promote.sh` ever stops preserving the worker's loaded context, section 3's reasoning changes and this file is the thing to correct.
If a project's issue tracker is not where its plan comments can live, say so at triage rather than letting the plan exist only inside an agent.
