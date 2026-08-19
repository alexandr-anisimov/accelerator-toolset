---
name: refactoring-safety
description: Restructuring code without changing behaviour - establishing a baseline first, separating internals from interfaces, sequencing reversible steps, and knowing when to stop.
---

# Refactoring safely

Refactoring means the behaviour does not change. The moment behaviour changes it is
no longer a refactor — it is a change wearing a refactor's clothes, and it will be
reviewed as if nothing could break.

That confusion causes the damage. A pure refactor can be reviewed quickly and merged
with confidence; a behaviour change disguised as one gets the same light review and
none of the scrutiny it needed.

For dbt models specifically, see
[dbt-model-refactoring](../DBT-MODEL-REFACTORING/SKILL.md). For splitting Python ETL
functions, see [etl-decomposition](../ETL-DECOMPOSITION/SKILL.md).

## Before anything: is this the right work?

A refactor is justified when it removes a real obstacle — code that must be changed
and cannot be safely, duplication that has already caused a divergent bug, a
structure that resists testing. "It is untidy" is not sufficient on its own, because
every refactor carries risk, review cost, and merge conflicts for everyone else.

If you cannot name what becomes possible afterwards, do not start.

## Establish the baseline first

**You cannot prove behaviour is unchanged without a record of what it was.** This
step is skipped more than any other, and skipping it means the refactor concludes
with "it looks right", which is not evidence.

In order of preference:

1. **A passing test suite that covers the behaviour.** Run it, and record that it
   passed *before* the first edit. A suite you never saw green is not a baseline.
2. **Characterisation tests**, when coverage is thin. Write tests that assert what
   the code currently does — including behaviour that looks wrong. The goal is to
   pin current behaviour, not correct it. Bugs get fixed separately, afterwards,
   where they are visible as fixes.
3. **Captured output**, when the code is not testable as written. Run it on
   representative input and save the result. Compare after.

If none is possible, say so explicitly before starting. A refactor with no baseline
is not verifiable, and the honest description of the result is "restructured,
behaviour not verified" — not "refactored safely".

```bash
<test command>              # must pass before any edit; record the output
git status                  # start from a clean tree, so the diff is only yours
```

Start on a clean tree. A refactor mixed with unrelated edits cannot be reverted
independently, which removes the main safety property.

## Internals versus interface

The distinction that governs how risky each step is.

| | Safe to change freely | Requires coordination |
|---|---|---|
| **Internals** — private functions, local structure, names not referenced elsewhere | ✅ | |
| **Interface** — exported names, signatures, return shapes, events, persisted formats, config keys | | ✅ |

Restructuring internals cannot break a caller, by definition. Changing an interface
can break every caller at once, and the diff will not show them.

Before touching anything exported:

```bash
git grep -n "<name>"        # direct references in this repository
```

`grep` misses dynamic dispatch, reflection, configuration-driven wiring, and
consumers in other repositories. When a name is public, treat the caller set as **not
fully known**, and say so rather than implying you checked. If the interface must
change, that is a coordinated change with a migration path — not part of the
refactor.

## Sequence the work into reversible steps

One behaviour-preserving transformation at a time, each verified before the next.

```text
extract function → run tests → commit
rename → run tests → commit
move to new module → run tests → commit
```

The reason is diagnostic, not ceremonial. When step 7 breaks the suite, you know
step 7 caused it. When all seven land together, you have a large diff, a failing
test, and no idea which part is responsible — and the usual response is to debug
forward rather than revert, which is how a two-hour refactor becomes two days.

Order the steps so the riskiest is early, while the change is still small enough to
abandon cheaply.

Keep each commit green. A commit that does not build is not a revert point, and
revert points are the entire benefit of small steps.

## Transformations that preserve behaviour

These are safe when applied exactly. Each has a way to get it wrong.

| Transformation | Watch for |
|---|---|
| Extract function | Captured variables, early returns, mutation of outer state |
| Inline function | Multiple call sites where evaluation order or side effects differ |
| Rename | String references, serialised names, reflection, config, documentation |
| Move to another module | Import cycles, initialisation order, changed visibility |
| Replace conditional with lookup | Fall-through and default behaviour that the conditional had |
| Introduce a parameter | Existing callers must get the previous value as the default |
| Deduplicate similar blocks | Whether the blocks are genuinely identical, including edge cases |

That last one is the most common source of a "refactor" that changes behaviour. Two
blocks that look the same frequently differ in one condition, and merging them
silently picks one of the two behaviours. Diff them properly before merging them.

## Prove it afterwards

Run the same baseline check and compare against the recorded result — not against
your memory of it.

- Test suite: same tests passing, same count. A test that disappeared is not a pass.
- Captured output: byte-identical, or differences explained individually.
- Performance, when it was a reason for the refactor: measured, not assumed.

**A suite that was green before and is green after is only meaningful if it covered
the behaviour.** With thin coverage, green after a refactor means very little, and
the report should say that rather than presenting it as proof.

## When to stop

Refactors expand. Each improvement reveals another, and the change that was going to
be an hour becomes unreviewable.

Stop when:

- The original obstacle is gone — even if you can see three more
- The diff is large enough that a reviewer will skim rather than read
- You are changing code unrelated to the reason you started
- You are fixing bugs you found along the way. Note them, finish the refactor,
  fix them separately where they are visible as fixes
- The baseline no longer covers what you are now changing

Write the remaining improvements down and stop. A merged small refactor is worth
more than an abandoned large one, and large refactors are abandoned regularly.

## The report

```markdown
## Refactor: <what and why>

### Baseline
- Method: test suite / characterisation tests / captured output / none
- Recorded before first edit: <command and result>

### Interface
- Changed: <exported names that moved, or "none - internals only">
- Callers found in this repository: <n>
- Callers outside this repository: <checked / not knowable from here>

### Steps
1. <transformation> - tests PASS
2. ...

### Verification
- <same command, same result, compared against the recorded baseline>
- Coverage of the affected behaviour: <good / thin - green means little>

### Not done
- <improvements deliberately left, bugs found and deferred>
```

## Guardrails

- Never mix a behaviour change into a refactor commit. If both are needed, two
  commits, clearly labelled.
- Never refactor without a baseline and then report the behaviour as unchanged.
  "Restructured, unverified" is the honest phrasing.
- Never fix a bug silently during a refactor. The fix becomes invisible to review
  and to anyone reading history.
- Never change an interface as part of "just tidying up".
- Do not let a green suite substitute for a suite that actually covers the code.
- If the tests fail mid-refactor and the cause is not immediately clear, revert to
  the last green commit rather than debugging forward.
