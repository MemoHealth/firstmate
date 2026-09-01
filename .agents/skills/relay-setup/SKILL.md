---
name: relay-setup
description: >-
  One-time setup for the plan/build/review relay, runnable from anywhere including a phone.
  Use when the captain invokes /relay-setup, or asks to set up the relay, the phase profiles, model-per-phase routing, or the issue labels the relay depends on.
  Verifies the relay actually landed in this home, writes this home's local dispatch profile from the canonical snippet, creates any missing issue labels, and reports in plain language exactly what is left that only the captain can do.
user-invocable: true
metadata:
  internal: true
---

# relay-setup

Everything the relay needs that a machine can do, done from one message.
The captain should never have to open an editor, a config file, or a repository settings page to turn this on.

Run the steps in order and report once at the end.
Each step is idempotent, so running this again after a partial setup is safe and is the intended recovery.

## 1. Confirm the relay is actually here

```
ls .agents/skills/phase-relay/SKILL.md
```

Absent means the instruction change has not reached this home yet, and nothing below will hold.
Say exactly that, name the two steps that fix it (land the change, then update this home through `/updatefirstmate`), and stop.
Do not write a dispatch profile for a relay this home cannot run.

## 2. Write this home's per-phase profiles

`config/crew-dispatch.json` is this home's local, gitignored routing file, and `docs/configuration.md` owns its schema.
The profile content is owned by `phase-relay` section 7; read the snippet from there and write it, rather than composing a second copy that can drift.

- File absent: write the snippet, then validate it with `jq . config/crew-dispatch.json`.
- File present: never overwrite it silently. Report what the current file routes, what the relay expects, and ask one question naming the concrete difference. A home may have deliberate local rules, and they outrank the default snippet.

Check every `harness` value against the verified adapters in `harness-adapters` before writing.
An unverified adapter in a routing file turns every later spawn into a refusal, so catch it here rather than at dispatch.

Session start validates this file on its own; do not run a full bootstrap sweep just to check it.

## 3. Create the labels the issue rules depend on

The label taxonomy is owned by the project's own issue rules, not by this skill.
For Munra that is `projects/Munra/.claude/rules/issues.md`; read the label names from there.

List what the repository already has, then create only what is missing.
Never rename, recolor, or delete a label that already exists, because an existing label is already carrying meaning on open issues.
Report created and skipped counts rather than a list of every label.

This step changes repository settings, which is outward facing.
The captain's invocation is the authorization for exactly this step, and it extends no further: it never closes, relabels, or edits an existing issue.

## 4. Report what remains

Close with a short plain-language list of what is now handled automatically and what still needs the captain, without internal vocabulary.
Only these belong on the remaining list:

- landing the instruction change, and the merge authority for any pull request
- answering a question that is genuinely his to answer
- sealing, waiving, or dropping his own dogfood rows
- choosing whether routine gates may be decided without him

If any step was skipped or refused, say which and why in one clause, and give the single next action that unblocks it.

## Rules

Never overwrite an existing dispatch profile without the captain's explicit word.
Never touch anything under `projects/`; reading a project's own rules file is a read, and label creation happens through the forge, not through the clone.
Never invent a profile, a model, or a label name that its owner file does not carry.
