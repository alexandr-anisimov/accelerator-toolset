---
name: requirements-brainstorming
description: Working out what is actually needed before any code is written - finding the goal behind the request, separating requirements from assumptions, and knowing when enough is known to start.
---

# Working out what is needed

The most expensive defect is not a bug. It is a correct, well-tested implementation
of the wrong thing, because no test catches it and it is usually discovered after
everything is built.

This runs before design and before code. It is finished when the goal, the
constraints and the non-goals are written down and agreed — not when everything is
known, which never happens.

## Separate the request from the goal

A request usually arrives as a proposed solution. The solution encodes assumptions
that may not survive contact with the actual problem.

```text
Request: "Add a button to export the report as CSV."
Goal:    Finance needs this data in their spreadsheet every Monday.
```

Once the goal is visible, other solutions appear — a scheduled email, a direct
connection, a different format — and some are much cheaper than the request. Some are
worse. The point is not to override the request; it is to know what it is *for*, so
the trade-offs can be judged.

Ask about the goal once, plainly: *what will this let someone do that they cannot do
now?* If the answer is already clear from the request, do not interrogate further.
Repeatedly asking "but why" is not thoroughness, it is friction.

Sometimes the request really is the requirement — a specified API, a compliance rule,
a decision already taken elsewhere. Accept it and move on.

## Ask the questions that change the work

Not every unknown matters. A question is worth asking when different answers lead to
**materially different implementations**. Everything else is a routine judgement
call you should make yourself and state.

The ones that usually change the work:

| Question | What it changes |
|---|---|
| Who uses this, and how often? | Interface, performance, whether it needs to be self-service |
| What is the input, realistically? | Validation, error handling, scale |
| What should happen when it fails? | Retries, partial results, visibility, whether failure is even acceptable |
| How much data, at what rate? | Architecture — the difference between a loop and a pipeline |
| Who else depends on the current behaviour? | Whether this can change at all |
| What is out of scope? | Where to stop |
| When is it needed, and how long does it live? | Whether a temporary solution is legitimate |

Ask these in one round, not one at a time. A list of five questions gets answered in
one reply; five separate questions across a day stalls the work and reads as
indecision.

## Write assumptions down, then check them

Everything you believe but were not told is an assumption. Unrecorded, it becomes a
requirement nobody agreed to and nobody can find later.

```markdown
## Assumptions
- Under 10k records per run. Not confirmed - changes the design if wrong.
- Manually triggered, not scheduled. Confirmed by <name>.
- Existing CSV export stays. Assumed - nobody mentioned removing it.
```

Mark each as confirmed or unconfirmed, and flag the ones where being wrong is
expensive. An unconfirmed assumption whose failure costs a rewrite must be checked
before starting. One whose failure costs an hour can ride.

**Never present an assumption as a stated requirement.** When writing back what you
understood, keep the two visibly separate. It is the difference between the person
correcting you now and discovering the mistake at review.

## Make non-goals explicit

The scope boundary is the part most often left implicit and most often disputed
later.

```markdown
## Not doing
- Scheduling. Manual trigger only for now.
- Formats other than CSV.
- Historical backfill - current data only.
```

Each line is a decision someone can object to today, cheaply. Without them, every
omission looks like an oversight rather than a choice, and the work is judged
against a scope that was never agreed.

## Explore alternatives before committing

Once the goal is clear, spend a short time on how else it could be met. Two or three
options, with what each costs and what it gives up. The first idea is not reliably
the best one, and comparing is cheap before any code exists.

Include "do nothing" and "do the smallest possible version" as real options. They win
more often than they get considered.

Keep this proportionate. A small, reversible change does not need an options
analysis; a decision that shapes the next year of work does. Judge by how expensive
the choice is to undo.

Where the decision is significant, record it — see
[project-documentation](../PROJECT-DOCUMENTATION/SKILL.md) for the decision record
format. The alternatives you rejected are the part future readers need most.

## Know when to stop

Discovery has to end, and it does not end by itself. Enough is known when:

- The goal is stated in one sentence that the requester would agree with
- The scope has an explicit boundary
- Every assumption that would change the design is confirmed
- Success is described in observable terms — what will be true afterwards
- The first step is unambiguous

That is enough to start. It is not enough to know everything, and waiting for that
guarantees nothing ships.

Conversely, do not start while a load-bearing unknown is open. If the answer changes
the architecture, building first means building twice. Where one part is blocked and
the rest is not, do the unblocked part and name what is waiting.

## The output

```markdown
## <what is being built>

### Goal
<one sentence: what becomes possible>

### Requirements
- <stated by the requester>

### Assumptions
| Assumption | Status | If wrong |
|------------|--------|----------|
| | confirmed / unconfirmed | cost of being wrong |

### Not doing
- <explicit non-goals>

### Constraints
- <deadlines, dependencies, compatibility, compliance>

### Success looks like
- <observable outcome, not "it works">

### Open questions
- <blocking: must be answered before starting>
- <non-blocking: proceeding on the stated assumption>
```

Separating blocking from non-blocking questions is what makes this usable. It tells
the reader precisely what is needed from them and lets everything else proceed.

## Guardrails

- Do not invent requirements. If nobody said it, it is an assumption and is labelled
  as one.
- Do not answer your own questions on the requester's behalf and record the answer as
  agreed.
- Do not expand scope during discovery. Additional ideas are noted, not adopted.
- Do not treat silence as agreement on anything expensive to reverse.
- Do not turn a small request into a project. Match the depth of this work to the
  size and reversibility of the change.
- When the requester reaffirms their original request after you have raised a
  concern, that is their decision. Record the concern and proceed with what they
  asked for.
