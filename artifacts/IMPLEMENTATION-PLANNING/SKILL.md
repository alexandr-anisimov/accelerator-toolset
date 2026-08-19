---
name: implementation-planning
description: Turning agreed requirements into an ordered plan - steps that can be verified independently, risky assumptions tested early, done criteria per step, and an explicit statement of what the plan excludes.
---

# Planning an implementation

A plan is useful when it can be checked. Each step has to produce something
observable, so that "step 3 is done" is a fact rather than an opinion. A list of
intentions — "implement the backend", "wire up the frontend" — cannot be checked,
which means nobody knows where the work actually is until it is finished or late.

This assumes the requirements are settled. If the goal, scope or constraints are
still open, plan after that, not before — see
[requirements-brainstorming](../REQUIREMENTS-BRAINSTORMING/SKILL.md).

## Understand the ground first

Plan against the code that exists, not the code you imagine.

- Find where similar work already lives, and follow that structure
- Identify the files and modules the change touches
- Find what depends on them, and whether any interface is public
- Check what tests exist for the affected area
- Note the conventions in the neighbouring code

A plan written without reading the repository produces steps that do not fit and get
rewritten on contact. The half hour spent here is recovered several times over.

## Front-load the risky part

The default order should be by risk, not by convenience or by architectural layer.

Ask: **which assumption, if wrong, invalidates the rest of the plan?** That gets
tested first, in the smallest form that gives an answer — a spike, a query against
real data, one call to the external API, a proof that the library does what its
documentation claims.

Building the easy, well-understood parts first feels productive and defers the moment
of truth. When the risky assumption then fails, everything built on it is wasted. The
worst version of this is leaving the integration with an external system until last.

Where a step exists only to answer a question, say so and give it a decision point:

```markdown
1. Spike: confirm the reporting API returns line-level detail (2h cap).
   - If yes: continue with steps 2-6.
   - If no: the aggregate-only design applies instead; re-plan from step 2.
```

A timebox on an investigation step is what stops it becoming the project.

## Make each step verifiable

Every step needs an observable outcome — something you can run, see, or point at.

```text
Weak:   "Implement the sync logic."
Better: "Add syncBatch(records) writing to the staging table.
         Done when: unit tests cover empty input, partial failure and the
         happy path, and `pytest tests/test_sync.py` passes."
```

The "done when" line does the work. Without it, a step is finished whenever whoever
wrote it decides it is.

Size steps so each is small enough to complete and verify in one sitting, and large
enough to be worth listing. A step you cannot verify within a few hours is really
several steps that have not been separated yet.

Prefer an order where the system is working at the end of every step. Steps that
leave the repository broken until a later step lands remove the ability to stop, to
review incrementally, or to hand the work over.

## Sequence by real dependencies

Order by what genuinely blocks what — not by layer, and not by what feels natural.

```markdown
1. Schema migration            (blocks 2, 3)
2. Repository read/write       (blocks 4)
3. Validation rules            (independent of 2)
4. API endpoint                (needs 2)
5. Error handling and retries  (needs 4)
```

Marking dependencies explicitly shows which steps could proceed in parallel, and
makes it obvious what is actually blocked when one step stalls. Most plans have fewer
real dependencies than their order implies.

## State what the plan does not cover

The exclusions are as load-bearing as the steps.

```markdown
## Not in this plan
- Backfilling existing rows - separate task, needs a migration window.
- Rate limiting - the current volume does not require it.
- Removing the old endpoint - after consumers migrate, next quarter.
```

Without this section, everything the plan omits looks like something the plan forgot,
and reviewers spend their time asking about deliberate decisions instead of examining
the ones that were made.

## Include the work that is not code

Plans routinely omit these and then run over by exactly the omitted amount:

- Tests — as part of each step, not a step at the end
- Migrations, and how to run them safely against real data
- Documentation the change invalidates (see
  [project-documentation](../PROJECT-DOCUMENTATION/SKILL.md))
- Configuration and secrets in each environment
- Rollout: feature flag, staged deploy, or straight release
- Rollback: what to do if it goes wrong after deploy
- Coordination with anyone whose work this breaks

A step called "write tests" at the end is a step that gets cut when time runs short.

## Keep the plan proportionate

A plan is overhead. It has to cost less than the confusion it prevents.

| Change | Planning |
|---|---|
| One-file fix with an obvious approach | None. Do it |
| A few files, one approach, known ground | A short ordered list |
| Multiple components, or an unfamiliar area | Full plan with dependencies and risks |
| Migration, or anything hard to reverse | Full plan, plus rollback and verification per step |

Writing a formal plan for a small change is not diligence — it delays work that
could already be done and reviewed.

## The output

```markdown
## Plan: <what>

### Goal
<one sentence, from the agreed requirements>

### Approach
<2-4 sentences: the shape of the solution and why this one>

### Risks tested first
| Assumption | How it gets tested | If it fails |
|------------|--------------------|-------------|

### Steps
| # | Step | Blocked by | Done when |
|---|------|-----------|-----------|
| 1 | | - | |

### Not in this plan
- <explicit exclusions>

### Rollout and rollback
- <how it ships, how it is undone>

### Open questions
- <blocking vs. proceeding-on-assumption>
```

## Guardrails

- Do not plan work whose requirements are still unsettled.
- Do not write a step you cannot state a done condition for.
- Do not defer the risky unknown to the end of the plan.
- Do not invent an estimate you have no basis for. A step with an unknown size is
  labelled unknown, or gets a spike first.
- Do not plan past the point of useful precision. Steps beyond the first few
  frequently change; sketch them and refine as the earlier work lands.
- A plan is a hypothesis about the work, not a contract. When execution shows it is
  wrong, the plan changes — see [plan-execution](../PLAN-EXECUTION/SKILL.md).
