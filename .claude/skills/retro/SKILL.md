---
name: retro
description: Close-of-session retrospective that acts, then syncs. Run when the user signals stopping (calling it a night, wrapping up, asking if this is a stopping point, typing /retro), or when a milestone lands (plan approved, release shipped, long task finished) and no further work is queued. Gathers evidence, writes the retro (went well, went badly, missing gates, skills, handoff), applies the skill and memory changes it finds, stores a public-safe record where the project names one, and commits and pushes every repo it touched.
---

<!-- Canonical copy: this file in the cravage-ios repo, so every machine that clones the repo has it. The copy under ~/.claude/skills/ on the owner's Windows machine mirrors it for other projects; when this file changes, update that mirror in the same session. -->

# Retro - evidence-bound close of session that acts

The owner's standing rule: **a correction made more than once is a missing gate**, and a gate is a
rule plus an automated check, never a memory note. The retro finds gates while the evidence is in
context, applies what it finds, and leaves the next session a handoff it can act on without
re-deriving anything. It is authorised to push (owner, 2026-09-13): a retro that edits a repo and
leaves it unpushed has failed, because local and remote must never drift.

## 1. Gather evidence

Facts come from tools, not recall. Scope is everything since the previous retro (this session's
first commit if there was none). A skill written this session is callable only from the next
session; run its steps by hand rather than invoking it.

- `git log --oneline` since the session's first commit in every repo touched; `git status -sb` for
  uncommitted or unpushed work; CI status of the last push where CI exists.
- Every correction the user made this session, quoted, with its trigger. A correction is any
  message that redirects, reformats or contradicts something you did or claimed.
- Every claim you stated as fact that was later shown wrong, and who caught it.
- Every tool failure and its workaround.
- Skills invoked, memory files touched, plan files produced. Read the current skills and memory
  index: they are what step 3 prunes.

Done when every retro item can cite a hash, a path, a quoted message or a tool result. Anything
uncitable is dropped, not softened.

## 2. Write the retro

Five short lists, one or two sentences per bullet, evidence inline. Forty lines is the ceiling; a
retro that needs more is carrying material that belongs in a plan or a spec.

- **Went well.** Decisions that held, checks that caught something, work verified end to end.
- **Went badly.** Each item names its root cause in one clause. Errors caught by the user or a
  reviewer outrank errors you caught yourself.
- **Missing gates.** For every repeated correction and every wrong fact with a plausible repeat:
  the rule and the automated check that enforces it (CI step, script, hook, lint). Where no check
  is possible, say so and name the memory note that is the fallback.
- **Skills.** Four verbs with concrete targets or "none": write (a process done by hand this
  session that will recur), edit (a skill that fired and steered wrong or fell short), audit (a
  skill that should have fired and did not, or whose triggers read stale), prune (a skill, skill
  passage or memory that is sediment: stale, duplicated, contradicted by the repo, or a no-op the
  agent obeys by default).
- **Handoff.** Open items with owners (user or agent) and the exact next action; where the plan
  and decisions live; anything approved but not yet implemented, in those words; every placeholder
  awaiting a value.

## 3. Act

Apply the skills section rather than proposing it:

- Write, edit and prune skills directly. Global skills live in `~/.claude/skills/`; project skills
  under the project's `.claude/skills/`. Every edit tightens: shorter, one source of truth, positive
  phrasing, leading words over restatement.
- Prune memory you can verify against the repo now; update the project memory file and its
  `MEMORY.md` line so the index carries the next action in one line.
- Store the retro where the project's `CLAUDE.md` names a retros location. In a public repo the
  stored copy is **public-safe**: findings, gates and handoff only; nothing about the owner as a
  person (experience level, setup walkthroughs, devices, accounts, finances), no third-party names,
  secrets, unpublished decisions or private-tree contents. Anything that fails that test lives in
  the project's untracked private tree (`.git/agents/private/`) or in memory. Apply the same sort
  to every tracked document the session produced; when unsure which side one falls on, ask. Where no location is named, the retro lives in the chat and the handoff in
  memory.
- Commit and push every repo touched, one concern per commit, following the project's workflow;
  confirm `git status -sb` shows each branch level with its remote. Report CI status where it
  exists.

Done when the handoff is in memory, every proposed gate has a named check or a named fallback, every
skill and memory change is applied, every touched repo is pushed and level, and the user has the
retro in chat with nothing unverified.
