---
name: review-council
description: Convene a gated, proportionate expert council to pressure-test a proposed change BEFORE implementing it. Use when the user proposes a non-trivial change (a feature, refactor, protocol/security/crypto edit, claims or copy change, visual pass) and wants it reviewed first, or when a plan names a council as a gate. The driving session convenes only the domains the proposal touches plus a challenger, debates only where they collide, and returns one go / revise / no-go recommendation; no code is written until the owner approves.
---

<!-- Canonical copy: this file in the cravage-ios repo, so every machine that clones the repo has it. The copy under ~/.claude/skills/ on the owner's Windows machine mirrors it for other projects; when this file changes, update that mirror in the same session. -->

# Review Council - a gated, proportionate review of a single proposal

A standing council that reviews a *proposed* change before any code is written. The driving
session is the **manager**: it reads the proposal, convenes only the domain experts whose remit the
proposal touches plus a dedicated **challenger**, takes one independent opinion from each, debates
only where they collide, and adjudicates into a single **go / revise / no-go**. The owner approves;
only then is code written. Scale the council to the blast radius: a copy tweak resolves in one pass,
a protocol change debates properly. A gate you skip is worse than no gate, so keep it usable.

## The proposal

The change under review is in `$ARGUMENTS`. Below the 95% bar on scope or intent, ask the owner to
sharpen it before convening anyone.

## Project context (read before convening)

The project's `CLAUDE.md` is the binding constraint set: owner decisions, invariants, honesty rules,
conduct. Members respect these without re-litigating them; a proposal that touches one is flagged,
not silently overridden. If `CLAUDE.md` names a decision record, plan, gaps register or council
archive, members read the sections matching their remit first, both to avoid re-finding known items
and to flag a proposal that would worsen an open one.

## How to run it

The driving session is the manager because only it can pause for the owner's question or approval;
a subagent runs to completion. Spawn experts as subagents.

**1 - Convene the roster.** Pick the domains the proposal actually touches:

| Domain | Convene when the proposal touches |
|---|---|
| security | trust boundaries, identity, auth, validation, limits, logging, secrets |
| crypto | keys, masks, signatures, canonical encodings, arithmetic domains, verifiers |
| protocol | state machines, message ordering, idempotency, timeouts, restart, consensus claims |
| qa | test strategy, coverage of modes not just paths, races, edge cases, device or environment matrix |
| legal | claims in docs and UI, licensing, privacy copy, store or regulatory paperwork, over-claims |
| ux | flows, waiting and failure states, accessibility, copy, comprehension by an uncoached user |
| product | framing, value, scope, priority, what to cut |
| design | visual craft: type, spacing, colour, motion, platform conventions |
| platform | the target platform's APIs, deprecations, permissions, review guidelines, build and release |

Convene the minimal sufficient subset and **always add the challenger**. Escalate to the full panel
when the change is cross-cutting or you are unsure which domains it hits, and say so. In doubt,
one domain more, not one fewer.

**2 - Spawn the experts in isolation, one message, parallel.** Each gets the proposal, its remit, the
project context above, and the blind-spot checklist below. Each returns one concise opinion: verdict
(support / support-with-changes / oppose), one to three risks or improvements from its lens, and any
binding constraint the proposal touches. Members do not see each other's opinions yet.

- **The challenger** (one per run) argues the strongest honest case against the proposal and for the
  best alternative: a different approach, a simpler version, doing nothing, a sharper framing. It
  challenges to illuminate, never to be contrarian.

**3 - Debate only where they collide.** If opinions agree, say so and skip the debate. Where two
members genuinely conflict, shuttle each position to the other for rebuttal (subagents are
stateless), iterate until resolved or stuck, then adjudicate. Record the why.

**4 - Adjudicate.** Weigh every opinion and produce ONE recommendation: **GO** (with conditions),
**REVISE** (with the specific changes the council converged on), or **NO-GO** (with the reason and
the better alternative). Add a short, separate note of any framing challenge worth the owner's eye.

**5 - Owner approves, then implement.** Present the recommendation and wait for the owner. After
approval, implement per the project's `CLAUDE.md`, one commit at a time.

## Blind-spot checklist (given to every member)

Review campaigns miss the same classes systematically. Each opinion confirms it checked the classes
relevant to its remit:

1. **Propagate the lens.** When a change establishes a principle, name every sibling surface the
   principle also applies to, and check the proposal covers them.
2. **Enumerate modes, not just paths.** Configuration, permission, entitlement and environment modes
   multiply the surface; coverage claims must span the matrix.
3. **Compute aggregate bounds.** Any limit or resource control gets a back-of-envelope total
   (count x rate x lifetime x size) against the real ceiling, not a per-item check.
4. **List what a shared control covers.** A guard at a choke point protects everything behind it;
   name everything, including what it now wrongly covers.
5. **Dead-surface sweep.** Name any export, flag or path with no caller.
6. **Primary sources for platform facts.** Any claim about a platform's behaviour, limits or rules
   cites the vendor's own page or is marked unverified.

## Output

The durable artefact is the recommendation presented to the owner. For a heavyweight or contested
run, record it where the project's `CLAUDE.md` names a council archive (default
`docs/review/council/<YYYY-MM-DD>-<slug>.md`): roster, each opinion in a line, debate resolutions,
the call, and the owner's decision once made. A lightweight run gets an inline recommendation only.
