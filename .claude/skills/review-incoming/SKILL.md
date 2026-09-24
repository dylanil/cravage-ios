---
name: review-incoming
description: Check commits another session (Codex, or another Claude) pushed to main. Use when the owner says another agent made changes, or when a fetch shows commits this session did not write. Verifies locally rather than trusting CI, and reports in plain words.
---

# Reviewing another session's commits

More than one session pushes to `main`. Twice now (2026-09-15, 2026-09-23) the owner has asked
"can you check them?" and the answer has to be evidence, not a reading of the diff. A green CI
badge is necessary and not sufficient: it proves the checks that exist passed, not that the change
is what its message says.

## 1. Establish the scope

- `git fetch`, then `git log --oneline <last-known>..origin/main` and `--format="%h %an %ar %s"`.
  The owner's git identity is on every commit whoever wrote it, so authorship does not identify
  the agent; the commit messages and any `docs/review/` record do.
- `git diff --stat` for shape. Read any review record the other session left before reading code:
  it says what they were trying to do, which is what you are judging the code against.

## 2. Check what a diff cannot tell you

In this order, because the cheap checks rule out the most:

1. **Nothing was weakened.** `git diff <base>..HEAD -- CravageTests/ Tools/` and
   `git diff <base>..HEAD | grep "^-.*func test"`. A slice that only adds tests and mutation
   entries is a different risk from one that edits them. Check `Tools/mutations.json` entry counts
   went up, not down.
2. **It runs here.** `swift test --package-path CravageCore`, the simulator suite, and every lint.
   Do not report on CI's word alone; CI can be green on a checkout that differs from this one.
3. **The project file is still generated.** `xcodegen generate` then `git status --short
   Cravage.xcodeproj` - empty means nobody hand-edited it in Xcode.
4. **Documents match behaviour.** Where the change touches SPEC, PLAN, README or the mockups, read
   those diffs as carefully as the code. A doc that now claims a capability, an approval or a date
   is a claim to verify, not prose to skim. Approval claims especially: check the owner actually
   gave it, in this repository's record or in the conversation, and say so if you cannot find it.
5. **Load-bearing invariants.** Anything touching the confirmation barrier, entitlement, the
   restart warning, masks, or what a screen claims to know. Read the new code, not the summary.

## 3. Report

Give the owner a verdict first, then what the change actually does in their terms, then anything
they must decide. Name what you verified and how, so "it is sound" is a finding rather than a
vibe. Where the other session left an open question or an unapproved claim, surface it as an item
for the owner rather than adopting it.
