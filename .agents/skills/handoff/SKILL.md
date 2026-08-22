---
name: handoff
description: Capture a Munra session's state so the context can be cleared to save tokens, then pick it back up afterwards. Use when the captain invokes /handoff or asks "kan jag cleara", "can I clear", "spara laget", "var var vi", "where were we", or "pick up where I left off". Run it BEFORE a clear (verifies nothing is uncommitted or unpushed, reconciles the open-PR table against GitHub, confirms the watches, appends a fresh state section to the handoff file, and either greenlights the clear or names what blocks it) and AFTER a clear (reports where the work stands so the next context resumes in the same place). One command, safe in both directions.
user-invocable: true
metadata:
  internal: true
---

# handoff

One command, two directions.
Run it before a context clear to secure the state, and after one to pick it back up.
The file it owns is `/home/user/HANDOFF-munra.md`.

Report in Swedish and address the captain as "kapten".
The handoff file itself is written in ASCII-folded Swedish, because Munra's encoding gate rejects some accented forms; match what is already there rather than introducing accents.

This skill is Munra-specific.
It assumes the `munrahealth/Munra` repo, worktrees under `Munra/.worktrees/`, and hadhud as sole reviewer.

## Always run these, in order

### 1. Read the state

```
grep -n "^## LAGE" /home/user/HANDOFF-munra.md | head -3
```

Read the TOPMOST `## LAGE` section in full.
Order is position, not timestamp: several older headings carry "NYASTE" incorrectly, and the file says so itself.
The first section is always the freshest.

Do not read the whole file.
It is long and most of it is history kept for its WHY.

### 2. Check that no work is loose

```
cd /home/user/Munra && git worktree list
```

For each worktree belonging to work in progress:

```
git -C <worktree> status --short
git -C <worktree> rev-parse --short HEAD @{u}
```

Uncommitted changes: say what they are, and do not commit them automatically if they look half-finished.
Ask instead.

HEAD differing from `@{u}`: unpushed, so push with `git push -u origin <branch>` or say why not.

No upstream at all: the branch exists only locally, which is the most dangerous variant because a container reclaim loses it.
Name it explicitly.

### 3. Check the pull requests

One call, not one per PR:

```
mcp__github__list_pull_requests(owner: "munrahealth", repo: "Munra", state: "open", minimal_output: true)
```

Compare against the table in the handoff's newest `LAGE` section.
A PR that has dropped out of the list is merged or closed, so unsubscribe it with `mcp__github__unsubscribe_pr_activity` and remove its row from the table.

Go deeper with `get_check_runs` only on PRs that changed since the table was written.

Known false alarm: the `no AI attribution trailer in the PR body` job often shows a FAILURE on the first run and a SUCCESS on a later one.
That is the footer `create_pull_request` appends and `update_pull_request` then removes.
The later run is the one that counts, and a green `CI gate` is the proof.

### 4. Check the watches

Subscriptions are bound to the SESSION, not the context window, so a clear does not tear them down.
But the new context does not know what it is watching until it reads the handoff, so the table has to be right.

Confirm every open PR of ours is subscribed.
`mcp__github__subscribe_pr_activity` is idempotent, so re-run it when in doubt.

Check scheduled check-ins with `mcp__Claude_Code_Remote__list_triggers`.
A check-in must point at the handoff file so it still works after a clear.

### 5. Update the handoff if anything changed

Add a NEW `## LAGE <date> <time> UTC` section at the top, directly above the previous one.
Never rewrite older sections, which stay for their WHY.
Stamp it with `date -u`, not the shell's local time, and update the `Uppdaterad ...` line at the top of the file.

A good section carries:

- What the captain asked for, in his own words where they shaped the build.
- A table of our open PRs: number, issue, branch, state.
- Which worktree belongs to what, and whether each is clean.
- What is NOT proven.
- Decisions that were backed out, and why, so the next context does not redo them.
- Open questions waiting on the captain.

The "what is not proven" line is the most valuable one in the file.
A green suite that looks like proof but is not is what costs the next context most.

New recurring mistakes belong in the `ATERKOMMANDE PROBLEM` section, not in a state section.
That section is mirrored by the `munra-pitfalls` skill, so change both or neither.

### 6. Give the verdict

Short, in plain language:

- Clear is safe: everything committed, pushed, handoff accurate, watches active.
  Say it plainly.
- Clear is not safe yet: name exactly what is loose and what you propose.

Always say what survives the clear (subscriptions, scheduled check-ins, the handoff file) and what does not (everything in context).

## After a clear

Same command.
Step 1 gives the state, steps 2 to 4 confirm reality matches what the handoff claims, and step 5 finds nothing to update.
Report where the work stands and what the handoff names as the next step.
Start nothing new without asking.

If reality does NOT match the handoff, say that first.
The handoff is then wrong and gets corrected before any work begins.

## Rules

Never write the state from memory, and verify against git and GitHub every time.
Never commit or push half-finished work just to be able to clear, and ask instead.
Never delete a `LAGE` section, and add above it.
Never touch another session's PRs, which the handoff names.
