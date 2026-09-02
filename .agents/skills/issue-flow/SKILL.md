---
name: issue-flow
description: >-
  Agent-only procedure for driving one Munra issue through a fixed plan/implement/review/fix state machine with a hard model pin per stage, invoked explicitly as "/issue-flow <issue-number>" (never auto-triggered).
  Load when the captain says "/issue-flow <N>" or otherwise asks to run a Munra issue through this named flow.
  Owns the PLAN -> IMPLEMENT -> REVIEW_1 -> FIX -> REVIEW_2 -> READY_FOR_PR state machine, the Fable-plans/Opus-builds model rule, the two-round review cap, and session-hygiene (checkpoint over compact) across the flow. Does not own Munra's architecture protocol (munra-architecture-intake), the general plan/build/review relay (phase-relay), or reviewing someone else's finished diff (a separate, not-yet-built /review-pr skill).
user-invocable: true
metadata:
  internal: true
---

# issue-flow

A named, stricter instance of `phase-relay` for one Munra issue: same relay mechanics (checkpoint, tear down, respawn on the right profile - never a live in-session model swap, which no verified harness here supports per `harness-adapters`), but with a fixed named state and a hard model pin instead of a flexible dispatch-profile suggestion.
Use `phase-relay` itself for any other project, or for a Munra change too large or unusual to fit this fixed shape.
Only run this flow when the captain names it explicitly (`/issue-flow <N>`); do not self-trigger it just because a task looks like a Munra issue.

This skill owns the state machine, the model pin, the round cap, and session hygiene only.
Everything else is owned elsewhere and referenced, not restated:

- Munra's architecture protocol, current-master refresh, and issue selection: `munra-architecture-intake`.
- Issue body/comment shape, labels, and closing convention: Munra's `.claude/rules/issues.md`.
- Munra's coding conventions (audit seam, migrations, gofmt, PR body/attribution rules): Munra's root `CLAUDE.md`.
- Known recurring traps: Munra's `munra-pitfalls`.
- Worktree isolation, dispatch profiles, brief scaffold, delivery mode, merge authority: `AGENTS.md` sections 4, 7, 11.

## 1. State machine

Exactly one task record carries the issue through six named states, in order, with no skipping and no silent backward move:

```
PLAN -> IMPLEMENT -> REVIEW_1 -> FIX -> REVIEW_2 -> READY_FOR_PR
```

Record the current state in the task's status trail (a `state: <NAME>` status line) every time it changes, so a session restart or supervision wake reads the state back rather than inferring it from conversation memory.
A worker that reports something inconsistent with the recorded state (implementing during `REVIEW_1`, re-planning during `FIX`) is a signal to stop and reconcile, exactly like `phase-relay`'s contradiction rule: never let a worker quietly re-plan or re-scope mid-flow.
`REVIEW_2` is the hard ceiling: a second round exists only to verify the `FIX`, never to open new findings. A `REVIEW_2` that finds a genuinely new class of problem ends the flow with an escalation to the captain rather than a manufactured `REVIEW_3`.

## 2. Model pin per stage

Unlike `phase-relay`'s flexible dispatch-profile rule, this flow pins the model per stage as a hard requirement, not a default:

| Stage | Model | Why |
|---|---|---|
| PLAN | Fable | Planning is where expensive reasoning has the highest leverage and the deliverable is compact. |
| IMPLEMENT | Opus | Implementation is long and tool-heavy; it runs on the strong general coding profile. |
| REVIEW_1, REVIEW_2 | Fable | An independent reviewer reading only the diff is cheap in tokens and expensive to get wrong. |
| FIX | Opus | Same worker class as IMPLEMENT; it is fixing its own code. |

Resolve this pin through the ordinary dispatch-profile path (`AGENTS.md` section 4, `docs/configuration.md`), by adding or matching a `crew-dispatch.json` rule per stage - never by asking a live worker to switch its own model mid-conversation.
No harness verified in `harness-adapters` documents an in-session model swap; treat each state transition below as a checkpoint-and-respawn, not a continued conversation, so the model pin is honored exactly rather than aspirationally.
Checkpoint-and-respawn across a model change is also the right call where a harness does expose a native mid-session model swap, for a second and separate reason: a model change does not carry over the prompt cache the outgoing model built, so the incoming model reads the accumulated conversation cold regardless, and a long `IMPLEMENT` stage is often enough on its own for the original cache window to have lapsed by the time the flow would return to it.
Conversation continuity and cache economy are two different things; do not keep a session alive across a model boundary on the assumption that it saves cost.

## 3. Flow

1. **Intake.** Load `munra-architecture-intake` first: refresh the Munra clone to current `origin/master`, pick the issue from current reality, and read its acceptance criteria. Check for an existing branch or open PR for this issue before dispatching anything.
2. **PLAN.** Dispatch on the Fable profile. The brief requires the plan shape `phase-relay` section 2 defines (goal, acceptance criteria, affected components, decisions with rejected alternatives, implementation order, tests, risks and non-goals) and requires consulting Munra's architecture index per `munra-architecture-intake`.
3. **Checkpoint the plan.** The worker posts it as an issue comment headed `## Plan`, per `.claude/rules/issues.md`. This comment is the durable handoff; nothing later depends on the planning worker still being alive. Tear the planning worker down once it lands.
4. **IMPLEMENT.** Dispatch on the Opus profile, briefed on the issue and the `## Plan` comment, on a fresh branch off current `origin/master` in an isolated worktree per `AGENTS.md` section 11. It follows the plan; a worker that finds the plan contradicted by the current tree stops and says so rather than silently re-planning (`phase-relay` section 4). Run the project's relevant test lanes before calling this stage done.
5. **REVIEW_1.** Dispatch a fresh worker on the Fable profile, never the implementing worker. It reads only `git diff`, `git status`, `git log` against the base, the issue and its acceptance criteria, and the surrounding code the diff touches - never the implementation worker's transcript or intermediate failures (`phase-relay` section 5). It reviews the actual diff against the acceptance criteria, not the plan.
6. **FIX.** Findings return to the SAME implementing worker while it is still alive, on the Opus profile, exactly as `phase-relay` section 6 requires - re-explaining the change to a fresh worker wastes the continuity that matters here. A disputed finding is evidence to weigh on the code, not an order; escalate a genuine disagreement to the captain with both positions.
7. **REVIEW_2.** The same reviewer verifies the fix when the round-one findings were small; spawn a fresh Fable reviewer when the fix changed the shape of the diff. This is the last review round - see section 1.
8. **Sync and re-verify.** Bring the branch up to date with `origin/master` (merge, never rebase someone else's history if this branch is already shared) and rerun the relevant test lanes once more against the synced tree.
9. **READY_FOR_PR.** Open the PR referencing the issue (`Closes #N`), following Munra's root `CLAUDE.md` PR-body and attribution conventions (human-authored commits, `made by:` line, no assistant trailers, template compliance). Report the full PR URL to the captain per `AGENTS.md` section 9; a captain instruction to merge, or the project's `yolo` posture, is what authorizes the merge itself, never this flow.

## 4. Session hygiene across the flow

The whole issue lives in one durable task record and one branch, checkpointed at every stage boundary above, even though the underlying worker is respawned per stage per section 2:

- Do not compact routinely mid-stage. When a worker shows real context pressure, have it checkpoint first (commit, push, post a `## Checkpoint` comment per `phase-relay` section 4's shape) rather than compacting through the pressure.
- The session boundary follows the model/role boundary, not the stage list by default.
  Preserve a warm worker session across an in-place continuation of the SAME model doing the SAME work: resuming the implementing worker for `FIX` (section 3 step 6), and resuming the round-one reviewer for `REVIEW_2` when the fix stayed small enough not to need a fresh reviewer (section 3 step 7).
  Across every model or role change - `PLAN` to `IMPLEMENT`, `IMPLEMENT` to `REVIEW_1`, and a `REVIEW_2` that does need a fresh reviewer - checkpoint and respawn instead of carrying the conversation forward, per section 2's cache rationale: a fresh worker there costs nothing extra in cache economy and gets a genuinely independent read.
- Keep every checkpoint minimal by construction; it is a handoff, not a transcript.
  The `## Plan` comment carries goal, acceptance criteria, affected components, decisions, implementation order, tests, risks and non-goals - nothing about how the planning session got there.
  The handoff from `IMPLEMENT` to `REVIEW_1` carries only what changed, why, and current test status ("implementation complete, tests X") - the reviewer reads the diff, the issue, and the code itself for everything else (section 3 step 5), never the implementing worker's transcript or intermediate failures.
  Padding a handoff "to be safe" defeats the reason the boundary exists: it reintroduces the cross-model context a fresh dispatch was meant to avoid.
- Do not `/clear` the whole task before `READY_FOR_PR` or a genuinely new issue - the task record carries state across every respawn above, and clearing early just discards useful supervision context for no reason.
- A worker that is actually confused (looping, contradicting its own prior output, answering questions already settled in the plan or checkpoint) gets the `stuck-crewmate-recovery` treatment: checkpoint what is committed, then reset that worker - never push it forward confused hoping the next turn clears up.

## 5. What this flow is not

- Not `phase-relay` itself: `phase-relay`'s triage in section 1 still decides whether an issue needs a written plan at all, and its flexible dispatch-profile rule still applies to any Munra issue big or unusual enough to fall outside this fixed shape. Use `phase-relay` directly there instead of forcing this flow's rigid stage list onto it.
- Not a review of someone else's already-finished diff. That is a smaller, separate `/review-pr`-style skill, not yet built - do not fold ad hoc diff review into this flow just because a review stage already exists here.
