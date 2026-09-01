#!/usr/bin/env bash
# tests/fm-phase-relay.test.sh - the phase-relay skill must exist, stay
# agent-only, own every step of the plan/build/review relay, and be loaded by
# real AGENTS.md triggers (a skill nothing loads is dead weight). The promotion
# exception is the safety-critical part: without it the default lifecycle would
# carry the planner's context into the build.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SKILL="$ROOT/.agents/skills/phase-relay/SKILL.md"
AGENTS="$ROOT/AGENTS.md"

test_skill_exists_agent_only() {
  assert_present "$SKILL" "the skill file exists"
  assert_grep "name: phase-relay" "$SKILL" "skill declares its name"
  assert_grep "user-invocable: false" "$SKILL" "skill is agent-only, not captain-invocable"
  assert_grep "  internal: true" "$SKILL" "skill is internal"
  pass "skill exists and is agent-only"
}

test_skill_owns_the_relay() {
  # Triage decides whether an issue is worth three workers at all.
  assert_grep "Run a single-phase ship when all of these hold" "$SKILL" \
    "skill must triage relay against single-phase ship"
  # The durable handoff is the issue comment, not an agent's context.
  assert_grep '`## Plan`' "$SKILL" "skill must name the durable plan artifact"
  assert_grep '`## Checkpoint`' "$SKILL" "skill must name the checkpoint artifact"
  # Teardown refuses unlanded work, so the respawn commits and pushes first.
  assert_grep "teardown refuses unlanded work" "$SKILL" \
    "checkpoint respawn must respect the unlanded-work refusal"
  # The reviewer's independence is the point of the third phase.
  assert_grep "never the build worker and never a worker that watched the build" "$SKILL" \
    "review phase must be independent of the build"
  assert_grep "knowledge-only review" "$SKILL" \
    "review phase must stay inside the permitted knowledge-only review"
  # The fix loop deliberately reuses the build worker's context.
  assert_grep "Findings go back to the SAME build worker while it is alive." "$SKILL" \
    "fix loop must reuse the build worker rather than re-explaining the change"
  # Model choice rides the existing dispatch path, not a second mechanism.
  assert_grep "crew-dispatch.json" "$SKILL" "per-phase profiles must reuse crew dispatch"
  pass "skill owns triage, handoff artifacts, independence, and the fix loop"
}

test_promotion_exception_is_explicit() {
  assert_grep "fm-promote.sh" "$SKILL" "skill must address the promotion path it overrides"
  assert_grep "do not promote" "$SKILL" "skill must state the promotion exception"
  pass "skill states its promotion exception"
}

test_agents_triggers_present() {
  local count
  count=$(grep -Fc -- '- `phase-relay` -' "$AGENTS")
  [ "$count" -eq 1 ] || fail "phase-relay must have exactly one section 13 trigger entry, found $count"
  assert_grep 'Load `phase-relay` before dispatching an issue large enough to need a written plan' "$AGENTS" \
    "intake must trigger the relay before dispatch"
  assert_grep 'Load `phase-relay` before promoting' "$AGENTS" \
    "the promotion step must trigger the relay"
  pass "AGENTS.md loads the skill at intake, at promotion, and in section 13"
}

test_skill_exists_agent_only
test_skill_owns_the_relay
test_promotion_exception_is_explicit
test_agents_triggers_present

SETUP="$ROOT/.agents/skills/relay-setup/SKILL.md"

test_setup_skill_is_captain_invocable() {
  assert_present "$SETUP" "the relay-setup skill exists"
  assert_grep "name: relay-setup" "$SETUP" "setup skill declares its name"
  assert_grep "user-invocable: true" "$SETUP" "setup skill must be captain-invocable"
  pass "relay-setup exists and the captain can run it"
}

test_setup_skill_defers_to_its_owners() {
  # One owner per contract: the profile snippet and the label list live elsewhere.
  assert_grep "owned by \`phase-relay\` section 7" "$SETUP" \
    "setup must take the profile from phase-relay, not restate it"
  assert_grep "issue rules, not by this skill" "$SETUP" \
    "setup must take label names from the project's own rules"
  # Safety: a home may carry deliberate local routing.
  assert_grep "never overwrite it silently" "$SETUP" \
    "setup must not clobber an existing dispatch profile"
  # The project-write boundary still holds.
  assert_grep 'Never touch anything under `projects/`' "$SETUP" \
    "setup must respect the project-write boundary"
  pass "relay-setup defers to its owners and keeps the write boundaries"
}

test_setup_skill_is_captain_invocable
test_setup_skill_defers_to_its_owners
