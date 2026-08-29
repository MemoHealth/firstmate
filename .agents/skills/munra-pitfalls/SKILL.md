---
name: munra-pitfalls
description: Munra's recurring engineering traps, written as rules rather than as history. Load before starting any Munra code task, before opening a Munra pull request, and whenever a verification step behaves oddly - a gate returning 1 from the wrong directory, an integration suite that will not start, a mutation that stays green, or a fixture that fails after a change that was correct. Covers the three-part AI-trailer mechanism in PR bodies, the encoding gate on the PR title and body, fixing the surface a review actually names, reviewing an artefact's format and not only its logic, inventory and pin tests, checking open PRs and fresh master first, verifying against the merged tree, stale-base false reds in the contract check, running node gates from the repo root, files the encoding gate never scans because they are unstaged, running the integration lane as pgtest, killing leftover embedded postgres, abandoned runs that look like failures, sign-off receipts that cannot be faked, what a green mutation means, hand-computed fixtures, and locked checksums. Also use when the captain invokes /munra-pitfalls or asks about "aterkommande problem" or "fallgropar".
user-invocable: true
metadata:
  internal: true
---

# munra-pitfalls

Mistakes that have cost time more than once, in the `munrahealth/Munra` repo.
These are rules, not status.

The canonical longer version with incident history is `/home/user/HANDOFF-munra.md`, section `ATERKOMMANDE PROBLEM`.
This skill mirrors it, so a change to one belongs in the other.

## A PR body must never carry an AI signature

Three things hang together and are easily confused.

First, `create_pull_request` appends an attribution footer by itself, on the SERVER side.
What you submitted is not what stands on the page.
Read the body back from GitHub with `pull_request_read` after submitting, then strip the line with `update_pull_request`.
Running `check-encoding.mjs --pr-text` locally over the text you wrote is false comfort, because it inspects the wrong copy.
The PR body is master's commit message, because the repo is set to `PR_TITLE` plus `PR_BODY`.

Second, the `no AI attribution trailer in the PR body` job in `.github/workflows/pr-body.yml` is required on master and fails on a trailer in the TITLE or the BODY.
A trailer inside a fenced code block is documentation and passes.

Third, the trailer that actually lands does not come from either of those.
On squash, GitHub derives `Co-authored-by:` from the AUTHORSHIP of the squashed commits, whatever the message setting says.
The gate reads only the title and the body, so it cannot see this one at all.
Branch commits therefore need human authorship, which the repo-local git identity already provides.
Verify it anyway with `git log --format='%an <%ae>' origin/master..HEAD`.
That is how 190 banned trailers reached master in #881 and #882.

`git merge` inherits the surrounding identity, and `git merge -c user.name=...` is not a valid flag on merge.
Use `git -c user.name=... merge`, which is the git-level config override, or rely on the repo-local identity.

There is a standing conflict to know about.
The stop hook in the Claude Code Remote environment wants `noreply@anthropic.com` as the commit author, which is the opposite of the third point.
Following the hook plants the trailer in master.
The captain has been told; until he rules otherwise, keep authorship human and name the hook in the report.

One exception: GitHub COMMENTS (issue, PR, and review comments) are supposed to carry the Claude Code footer.
It is the PR title and body that must stay clean.

Normal reading of CI: that job often shows a FAILURE on the first run and a SUCCESS on a later one, which is the footer being written away.
The later run is the one that counts, and a green `CI gate` is the proof.
Do not chase the red row.

## The encoding gate also covers the PR title and body

ASCII plus the six Swedish accented letters ONLY.
Write `--` rather than an em dash and `->` rather than an arrow, and use no middle dot and no other accents.
The description becomes master's commit message, which is why it is inspected at all.
This has caught us twice: once a middle dot, once a misspelled `lasens` carrying the wrong accent.

## When a review names a surface, fix THAT surface

In #889 the review said `ps-print` was gated only on `isEmpty`.
The adjacent claim was fixed - the footer wording - and the button was left alone, so an unsigned unapproved draft could still be printed to A4 and handed to a patient.
hadhud had to fix it.
A finding is closed only when the surface it points at is fixed or explicitly dismissed with a reason, never because something nearby became correct.

## Review the artefact's format, not only its logic

hadhud found seven defects in `voiceeval` and none in the arithmetic.
The patterns worth checking every time:

- What does the reader let through? A repeated tag counted the attempt TWICE in its group, and a second JSON value on the same line vanished without trace.
- What identity does the file carry? A frozen threshold with no model name could be applied to another model's numbers, silently.
- Is the fingerprint unambiguous? `["a,b"]` and `["a","b"]` shared a digest.
- What does the artefact CLAIM? Two entirely different states - no counter-evidence at all, versus counter-evidence that missed the budget - rendered identically.

Always ask what happens to malformed input, and whether two different realities can produce the same artefact.

## A failing test fixture is an ANSWER, not an obstacle

The question is always which of the two is wrong, the code or the fixture.
It is never how to get the test green.

In #880, eighteen e2e tests failed because the fixtures lacked `totpEnrolledAt` and so modelled a clinician who holds a session but never enrolled in 2FA.
The behaviour was right and the fixture was unrealistic.

In #890, six verifier fixtures failed because a word band's FLOOR had been raised to make the bands disjoint.
A floor is enforced by REJECTION, so a floor set to make a label meaningful fails a genuinely thin visit that simply had less to say.
The fixtures that failed were the evidence, and only the ceilings moved in the end.

## Changing a SHARED fixture means reading every user of it

Adding timestamps to `mockAuthService` broke a test whose own comment said it relied on the empty account.
The right shape is to leave the shared default alone and let the tests that need something else opt in explicitly, through a helper registered after `beforeEach`.

## Expect inventory and pin tests

In #891 two new sentinels were added and `TestRemissFailureRuleCoversEverySentinel` was missed, which exists precisely to catch that.
The mutations tested the RULE, not whether the REGISTRY was complete.
When touching a sentinel, registry, `ActionKind`, or allow-list block, grep for a test that COUNTS or LISTS the entries before calling the work done.

## Check open PRs and fresh master BEFORE starting

hadhud works the same issue list in parallel.
Issue #888 became wasted work because he landed #925 while our PR was open.
The check is cheap and belongs first, not afterwards.

The other half of that protection is the title marker.
Mark the issue `[in progress]` in its TITLE when taking it, restore the title when stopping, and leave `[almost done]` when it is nearly finished.
Checking only protects you; marking protects the other party.

## Verify against the MERGED tree

Run `git fetch origin master` first, always.
If master moved, merge it in and re-run the gates against the result.
`git merge-tree` reports "clean" even when 282 files vanished under the branch.
If the merge is documentation-only a Go verification can stand, but confirm that it is with `git diff --name-only HEAD@{1} HEAD | grep '\.go$'`.

A stale base also surfaces as a false red in the contract check.
If `proto (contract + generation)` reports "previously present field ... was deleted" for a field your branch never touched, master ADDED that field and your branch is behind.
Merge master in, re-validate, push.
Nothing is wrong with the work.

## Run the node gates from the REPO ROOT

`check-encoding.mjs`, `check-gofmt.mjs`, `validate-architecture-docs.mjs`, and `check-mdsw-boundary.mjs` exit 1 with MODULE_NOT_FOUND when run from `services/api` or `apps/verification-ui-dd`.
It looks like red and is not.

The encoding gate walks `git ls-files`, so NEW files that are not staged are never scanned at all.
It then reports the same file count as before and looks green without having read your work.
Stage first, run second, and check that the file count went up.

## The integration lane runs as `pgtest`

Embedded postgres refuses to run as root.
After `chmod -R a+rX <worktree>`:

```
su pgtest -c "cd <worktree>/services/api && HOME=/var/tmp/pgtest TMPDIR=/var/tmp/pgtest GOPATH=/var/tmp/pgtest/go GOCACHE=/var/tmp/pgtest/gocache GOMODCACHE=/root/go/pkg/mod MUNRA_EMBED_POSTGRES=1 /usr/local/go/bin/go test ./test/integration/... -tags=integration -timeout 30m"
```

It takes about 21 minutes, so run it in the background.

## Aborting the integration suite means killing postgres too

`pkill` on the go test leaves the embedded postgres running, and the next run dies on `process already listening on port 54329`.
That looks like a defect in the code and is not.
After an aborted run: `pgrep -af "bin/postgres"`, then `kill -TERM <pid>`, then confirm with `ss -lnt | grep 54329`.

## Several e2e lanes exist, and one spec sits outside the default run

`dictation-stream.spec.ts` is `testIgnore`d in `playwright.config.ts` and runs only through `playwright.dictation.config.ts`, which needs real Chrome rather than Chromium and therefore cannot run in the Claude Code Remote container.
It does not appear in an ordinary `--project=chromium` run.
After a change touching auth or boot, search ALL spec files for inline fixtures, not only the ones that failed.

## Local gates lie about fonts and layout

The overlap assertions in `dashboard-sync-status-header.spec.ts` fail inside a worktree because fonts do not load - "outside of Vite serving allow list" - which changes text geometry.
They are green in CI.
Check against CI on another PR before chasing them, and remember the converse: a locally green suite does not prove CI.

A fresh worktree has no `node_modules`, and vitest and playwright fail at startup without them.
Link them with `ln -s /home/user/Munra/apps/verification-ui-dd/node_modules <worktree>/apps/verification-ui-dd/node_modules`.

## An abandoned run looks like a failure

A run where EVERY track says `cancelled` is a run that was aborted when someone pushed a new commit on top.
The aggregate gate counts cancelled as not-passed, which is the correct behaviour.
Do not comment on it; check the current head instead.

## Sign-off receipts cannot be faked in a test

A trigger validates line membership, hashes, owner, and the audit row TOGETHER at commit time.
`line_count` must be positive.
`visit_signoff_line` is append-only, using TRUNCATE in cleanup and never DELETE.
Use `seedSoapLine` plus `signOffVisit`, never a hand-written INSERT.
Check also that the test does not already sign off, because `visit_signoff` is unique per visit and a second one fails hard.

## A green mutation is a failed test

Every mutation must be a REVERT to the code's state before the change, so that red-before and green-after is literal.
When a mutation stays green, ask what in the test DATA makes the assertion non-discriminating.
Recurring causes: only one vocabulary value pushed end to end; no case outside the permitted set; two different texts where the real case is the same text twice; and negative assertions that pass because the effect has not run yet.
For that last one, wait on something that PROVES the effect ran.
Report a mutation that stays green rather than papering over it.

Verify a proposed test value empirically instead of trusting a plan.
In #232 the plan proposed `0.070731` to expose floating-point rounding, the value did not work, and the mutation would have stayed green.
The right value was `0.500002`, and the executor found it by trying rather than by trusting.

## A test that recomputes the measure the code's way proves nothing

Use hand-computed cases with the expected answer written in as literals, not property tests that mirror the implementation.
Make the fixture ASYMMETRIC, for example 4 against 3, so that a swapped numerator and denominator is caught.

## Locked checksums pin what the code DID, not what it SHOULD do

A hash cannot possibly be known before the code that produces it.
Compute every number in the fixture BY HAND, outside the implementation, and compare those against the artefacts.
A deterministic wrong answer is still wrong.

## A silent fallback is a silent untruth

Dictation falls back to the process vendor when the configured one cannot be constructed, for example on a missing `SONIOX_API_KEY`.
Without a log line the deployment runs OpenAI while believing it runs Soniox.
Warn at startup, once, rather than per session.

## A review finding about a false statement in a comment is a real finding

The `DictationSTTVendor` doc comment said "Empty keeps the process-wide STTVendor" while `envOr` defaulted it to `soniox`.
No behaviour bug, but the next reader would have believed it.
Fix the text; do not write the finding off as a style note.

## Contradictory prompt instructions burn both attempts

The `kort` length was told to "Skriv STATUS" and then given an allowed-headings list without STATUS.
At temperature 0 the retry replays identical input, so a contradiction is not flaky - it is two certain failures.
When a verifier gains a new rule, search ALL text that reaches the model for sentences that now contradict it.
