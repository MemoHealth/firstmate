---
name: issue-flow
description: >-
  Agent-only procedure for driving one Munra issue to a PR at the lowest defensible cost, invoked explicitly as "/issue-flow <issue-number>" (never auto-triggered).
  Load when the captain says "/issue-flow <N>" or otherwise asks to run a Munra issue through this named flow.
  Owns the free triage gate that decides how many workers an issue gets, the two-worker default shape, the model policy, the one-review-round rule, and the cost rules that keep a worker count from inflating.
  Does not own Munra's architecture protocol (munra-architecture-intake), the general plan/build/review relay (phase-relay), or reviewing someone else's finished diff.
user-invocable: true
metadata:
  internal: true
---

# issue-flow

One Munra issue, from intake to a PR, spending as little as the risk allows.

Everything else is owned elsewhere and referenced, not restated: Munra's architecture protocol (`munra-architecture-intake`), issue conventions (Munra's `.claude/rules/issues.md`), coding conventions (Munra's root `CLAUDE.md`), recurring traps (`munra-pitfalls`), and worktree/brief/merge rules (`AGENTS.md` sections 4, 7, 11).

## 1. What actually costs money

A worker is expensive because it starts cold: it re-reads the instruction files and then re-reads the repo from nothing.
Measured on 2026-09-02, five issues, fifteen workers, 2.55M tokens, three landed PRs.
Two issues produced no PR at all and burned 770k, thirty percent of the night, and BOTH were avoidable before any worker started.

So the cheapest lever is not a faster model or a shorter prompt.
It is spawning fewer workers, and never spawning one for an issue that should not be built yet.

## 2. Triage gate, before any worker

Free, and it is where the savings are.

1. **Is it already taken?** Check the open PR list, then ASSIGN the issue to yourself. Checking protects you; assigning protects the other party. Skipping this cost 352k on #1179 when a parallel session opened its PR seven minutes before our commit.
2. **Does the issue carry an unresolved owner decision?** If the body says "policy call", offers two shapes, or the thread contradicts itself, put the question to the captain NOW with the default that ships if he does not answer. Building first cost 418k on #1180, where the captain's answer arrived after the build and the review and reversed both.
3. **Is the issue body still true?** A stale premise in the body is not a detail: on #276 two load-bearing claims were false at current master. Verify against code before planning against prose.
4. **Does a plan already exist** as an issue comment? Then the plan stage is done. Do not re-plan.

## 3. Shape: how many workers

Default is TWO. Three is the exception, and it must be argued.

**Two workers (size-S, size-M, a clear fix sketch in the issue):**
one worker plans and implements in the same context, then one COLD reviewer.
The plan is not the risk on a small issue; the code is.
Splitting plan from build here buys a document and pays a full cold repo read for it.

**Three workers (size-L, size-XL, cross-cutting, or an unclear target model):**
a separate plan worker first, because a wrong plan wastes a whole build.
Its plan lands as a `## Plan` issue comment, which is the durable handoff.

**Plan only:** when the captain wants the thinking handed to someone else. Post the plan, label `plan-ready`, assign the reviewer, stop.

## 4. Model policy

The reviewer gets the stronger model. The builder gets the cheaper one.

That is the reverse of the intuitive split, and the reason is what the evidence shows: every real defect on 2026-09-02 was caught by the REVIEW, not prevented by the build.
Reviews found a microtask gap in a concurrency token, a test that asserted against the same constant the code iterated, keyboard focus lost to `<body>`, and a deny-list widened past what its own header documented.
No build produced visibly better code for running on a stronger model.

Honest caveat: that is five issues, observational, with no controlled comparison.
It is enough to stop paying a premium for the build stage; it is not enough to claim the build model never matters.
Revisit if a builder starts producing findings a reviewer has to fix twice.

Resolve the pin through the ordinary dispatch-profile path (`AGENTS.md` section 4), never by asking a live worker to switch model mid-conversation.

The review phase's FINAL pass runs on Fable; `phase-relay` section 7 owns that rule and the evidence behind it.


## 5. Review, fix, and when to stop

The reviewer must be COLD and must never see the builder's transcript, only the diff, the issue and the surrounding code.
Independence is the whole product; a reviewer that inherits the builder's reasoning inherits its blind spots.

Give the reviewer the builder's OWN uncertainty list as its sharpest questions.
Builders on this flow have repeatedly flagged their own weak spots, and the reviewer confirming or refuting one is worth more than a generic sweep.

Require falsifiability from both sides: every new test must be proven to fail without its fix, and the reviewer re-runs the mutations itself rather than trusting the claim.
A test that passes either way is a finding, not a test.

**One review round.** Findings go back to the SAME builder, which still has the context.
A second review runs only when the fix changed the shape of the diff.
When the fix is small, the builder's own RED/GREEN evidence for exactly the named findings is the proof, and a second cold read is 150k for a paragraph of reassurance.
A review that surfaces a genuinely new class of problem stops the flow and goes to the captain, never a third round.

## 6. Cost rules

- **Never resume a worker to ask whether its background job finished.** Every resumption replays its whole transcript. One reviewer cost 263k that way on #1167, mostly re-reading itself. Wait on the job, then wake the worker once.
- **Never fetch every open issue.** One such call returned 333k characters. Search for what you need.
- **Ask for narrow fields.** A CI-status call that returns full commit bodies costs 77k for a one-word answer.
- **Do not split a stage to be thorough.** Thoroughness lives in the review's depth, not in the number of handoffs.
- Keep every handoff minimal: the plan comment carries goal, acceptance criteria, decisions and tests; the build-to-review handoff carries what changed, why, and test status. Padding a handoff reintroduces exactly the context a cold worker was meant to avoid.

## 7. Landing

Bring the branch up to date with `origin/master`, rerun the proving lanes against the synced tree, then open the PR referencing the issue (`Closes #N`).
Follow Munra's PR-body and attribution conventions: human-authored commits, `made by:` line, no assistant trailers, and the encoding rule applies to the PR title and body because they become master's commit message.
Report the full PR URL to the captain.
A captain instruction, or the project's `yolo` posture, authorizes the merge; this flow never does.

## 8. What this flow is not

- Not `phase-relay`. That skill's triage still decides whether an issue needs a written plan at all, and its flexible profile rule still applies to anything outside this shape.
- Not a review of someone else's finished diff.
- Not a justification for a fixed stage list. If an issue is genuinely one small fix with an obvious test, one worker plus one review is the whole flow, and inventing stages to look rigorous is the failure this skill exists to stop.
