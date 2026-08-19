---
name: plan-execution
description: Working through an agreed plan - one verified step at a time, deciding when to adapt versus stop and ask, resisting unrequested scope, and keeping the plan honest about actual state.
---

# Executing a plan

A plan survives contact with the code or it does not. Both outcomes are normal. What
determines whether execution goes well is how divergence is handled: adapting
silently, stopping to ask, and pushing on regardless are three different responses,
and picking the wrong one is where planned work goes off the rails.

This assumes a plan exists and is agreed — see
[implementation-planning](../IMPLEMENTATION-PLANNING/SKILL.md).

## One step at a time, verified

Complete a step. Verify it. Then start the next.

The verification is the part that gets skipped under time pressure, and skipping it
is what makes the eventual failure expensive. When three steps land together and
something breaks, the search space is everything you did; when one step lands and
something breaks, the search space is that step.

```text
implement step  →  run its done-condition  →  commit  →  next step
```

Keep the repository working at each boundary. A commit that does not build is not a
revert point, and revert points are the reason for working in steps at all.

If a step turns out to be larger than planned, split it rather than letting it grow.
A step that has been in progress far longer than the ones around it is a signal that
it was really several steps.

## When the plan is wrong

It will be. The plan was written with less information than you now have. What
matters is which kind of divergence you have hit.

**Adapt and continue, noting it.** The plan's intent still holds; the detail was
wrong.

- A step is unnecessary because the behaviour already exists
- A file, function or module is somewhere else than expected
- The order of two independent steps is more convenient reversed
- An extra small step is needed to make the planned one work

Do these, record them, and keep going. Stopping to ask about each one makes the plan
a bottleneck and wastes the requester's attention.

**Stop and ask.** The plan's assumptions no longer hold, and continuing means
guessing at a decision that is not yours.

- The approach cannot work — a technical assumption turned out false
- The change requires modifying something the plan declared out of scope
- Two reasonable interpretations of the requirement now lead to different code
- The work is substantially larger than planned — not by a step, but by a multiple
- A required interface change would break consumers the plan did not account for
- You discovered an existing defect that the planned change would depend on

The test: **if I choose wrong here, is the work wasted or merely adjusted?** Wasted
means stop. Adjusted means proceed and note it.

When you do stop, do not stop empty-handed. Finish everything that does not depend on
the answer, then state the question with the options and a recommendation. "I hit a
decision, here is what I did in the meantime, here is what I need" is worth far more
than an idle question.

## Do not add unrequested scope

Executing a plan surfaces adjacent problems: dead code, a missing test, an
inconsistent name, a function that would be better structured differently. The pull to
fix them while you are there is strong and should mostly be resisted.

Each unplanned improvement:

- Enlarges a diff that was scoped for review
- Mixes changes that need different scrutiny
- Makes a revert take out the good with the incidental
- Was not agreed

Write them down and continue. If you find something that must be fixed for the
planned work to be correct, fix it — and say so explicitly, because it is now part of
a change nobody planned for.

The exception that is not really an exception: a defect that makes the current step
wrong is not adjacent, it is in the way. Fix it as its own commit, clearly labelled.

## Keep the plan honest

The plan should describe the actual state of the work, not the state it was expected
to reach.

Mark steps done only when their done-condition has been observed — not when the code
was written. Record deviations as they happen; a deviation reconstructed from memory
at the end is usually incomplete, and the interesting ones are the ones that get
forgotten.

```markdown
### Progress
- [x] 1. Schema migration - applied locally, `pytest tests/migrations` passes
- [x] 2. Repository read/write - done
      DEVIATION: existing `BaseRepository` already handled batching, so the
      planned batching helper was not needed. Step smaller than planned.
- [ ] 3. Validation rules - in progress
- [ ] 4. API endpoint - blocked: needs the decision on error format (asked)
```

A plan that says everything is on track while the work is stuck is worse than no
plan, because it delays the moment anyone can help.

## Verify before reporting done

A step is done when its stated condition has been observed to hold. A task is done
when every step is done and the original request is met — those are different
claims, and the second is the one that matters to the requester.

Never report completion from expectation. Run the command, read the output, then
report. See [work-verification](../WORK-VERIFICATION/SKILL.md) for what an honest
completion claim requires.

If part of the work could not be finished, say which part and why, plainly, rather
than reporting overall success with the gap buried. Scaling the work down is the
requester's decision to make, and they can only make it if they know.

## Handing over mid-execution

When work stops before completion — out of time, blocked, or being passed on — what
the next person needs is:

- Which steps are genuinely done, with the evidence
- What is in progress and what state it is in
- Every deviation from the plan so far
- The open question, if that is the blocker, with the options
- Anything discovered that changes the remaining plan

Leave the repository in a state someone else can pick up: committed work green,
in-progress work clearly marked, no half-applied edits with no explanation.

## Guardrails

- Do not skip a step's verification because the code "obviously works".
- Do not batch several steps into one commit to save time. The time is saved from
  the diagnosis you will need later.
- Do not silently change the approach. Adapting details is fine; changing the shape
  of the solution is a decision to raise.
- Do not expand scope because you are already in the file.
- Do not report a step as done when its check was not run.
- Do not keep going to avoid the awkwardness of asking. An hour of guessing is more
  expensive than a question.
- When the requester has heard your concern and reaffirmed the original plan, that
  is their call — proceed with it and note the concern.
