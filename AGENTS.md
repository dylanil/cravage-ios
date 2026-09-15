# Codex repository entry point

Read `.git/agents/private/AGENTS.md` first if it exists. Keep private working notes there.

Read `CLAUDE.md` in full before substantive work. It is the shared source of truth for both
Codex and Claude: architecture, invariants, acceptance gates, privacy rules and git workflow.
Its instructions apply to Codex as well. Follow its pointers to `docs/PLAN.md`, `docs/SPEC.md`
and the latest `docs/retros/` handoff. Keep shared rules in `CLAUDE.md` rather than duplicating
those rules here. Codex-specific private notes use the path above.

## Working alongside Claude

- Inspect the working tree before editing. Preserve changes owned by another session and the
  intentionally uncommitted signing settings. Coordinate overlapping edits before changing them.
- Fetch and fast-forward before each commit, as required by `CLAUDE.md`. Stage only named files
  belonging to the current task; push without force and verify CI for that exact commit.
- The Codex entries under `.agents/skills/` point to the canonical project skills under
  `.claude/skills/`. Read those canonical files when invoking a project skill; edit shared skill
  behavior there so both agents receive the same instructions.

## Review baseline

The read-only review of `356bdb9` is in `docs/review/2026-09-15-codebase-review.md`.
It records open findings and regression scenarios, not implemented fixes. Check their status
against the current tree before beginning follow-up work.
