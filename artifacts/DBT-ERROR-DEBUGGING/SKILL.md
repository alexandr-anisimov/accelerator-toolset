---
name: dbt-error-debugging
description: Diagnosing dbt failures - read the compiled SQL, suspect upstream before the current model, and know when to stop patching.
---

# Debugging dbt errors

Most dbt debugging time is lost in two places: fixing the model that reported the
error when the cause is upstream, and making small adjustments to an approach that
was wrong from the start.

## Read the whole error

dbt errors carry the file, the line, and the failing statement. Read to the end
before acting — the first line names the model that failed, which is frequently not
the model at fault.

Sort the failure into one of three kinds, because they are diagnosed differently:

| Kind | Means | Look at |
|---|---|---|
| Compilation Error | Jinja never rendered | The template: unbalanced `{{ }}`/`{% %}`, a `ref` to a model that does not exist, malformed YAML |
| Database Error | SQL rendered and the warehouse rejected it | The compiled SQL: missing column, type mismatch, ambiguous reference |
| Test failure | The model built, the data is wrong | The test's own SQL, then the rows it returned |

## Read the compiled SQL, not the model file

For any Database Error, the model file is not what ran:

```bash
dbt compile --select my_model
cat target/compiled/<project>/models/<path>/my_model.sql
```

This is the actual statement the warehouse received, with every `ref` resolved and
every macro expanded. Errors that are baffling in the template are usually obvious
here — a macro that expanded to nothing, a `ref` pointing at last week's schema, a
`where` clause that a conditional block silently dropped.

## Suspect upstream first

When a column is missing or has the wrong type, the current model is the place the
error surfaced, not usually the place it originated.

```bash
grep -E "ref\(|source\(" models/marts/my_model.sql   # what this model depends on
dbt show --select stg_orders --limit 5               # what that dependency emits
```

Compare the columns the upstream model actually produces against what your model
assumes. A renamed column in staging produces an error in every downstream model at
once, and fixing them one at a time by patching each downstream `select` spreads
the damage instead of repairing it.

## Common causes

| Symptom | Usual cause | Fix |
|---|---|---|
| Column not found | Renamed or dropped upstream | Fix upstream, or update the reference |
| Ambiguous column | Same name from two joined tables | Qualify it: `orders.status` |
| Type mismatch | Implicit cast the warehouse will not make | Explicit `cast(...)` |
| Division by zero | Unguarded denominator | `nullif(denominator, 0)` |
| Jinja error | Unbalanced delimiters, or a macro arity change | Compare against the macro definition |
| Test fails after a green build | The SQL ran; the data is wrong | Query the failing rows, do not weaken the test |

## For wrong output, look at the data first

When the complaint is "the numbers are wrong" rather than an exception, the
temptation is to re-read the SQL until the bug appears. Query the data instead:

```bash
# What does the distribution look like?
dbt show --inline "
  select status, count(*)
  from {{ ref('fct_orders') }}
  group by 1 order by 2 desc
"

# Is one known row right?
dbt show --inline "
  select * from {{ ref('fct_orders') }} where order_id = 1042
"
```

Find a specific wrong row before theorising. "Every row is duplicated" points at a
join; "the total is right but the breakdown is wrong" points at a grouping; "only
recent rows are wrong" points at an incremental filter. Each of those sends you to
a different part of the model, and guessing between them is what makes this slow.

## Rebuild, then check downstream

```bash
dbt build --select my_model
```

Compile does not verify a fix any more than it verifies a new model. Once it
passes, check what depends on this model:

```bash
dbt build --select my_model+
```

The `+` suffix builds the model and everything downstream of it. A fix that changes
a column's type or nullability can break a consumer several models away, and it is
cheaper to find that now than after the change is merged.

## Stop after three attempts

**Three failed fixes on the same error means the diagnosis is wrong, not the fix.**

The pattern to interrupt is the one where each attempt is a small variation of the
last — adding a cast, then a `coalesce`, then a subquery — against an error you
have not actually understood. Each change makes the model harder to read and none
of them address the cause.

When you hit three, stop editing. Re-read the original error from the top. Verify
your assumption about what the upstream model contains, rather than trusting it.
Then ask whether the approach itself needs replacing.

## Verify you fixed the problem, not the symptom

Making the error stop is not the same as making the model correct. A `coalesce`
that silences a `not_null` test failure has hidden a data quality problem rather
than solved it, and the null is now a zero in someone's report.

Before closing: does the output match what was asked for? Did you address the cause
or suppress the signal? If a test failed, is the underlying data now correct — or
did you edit the test?

## Anti-patterns

- Changing SQL before understanding why it failed
- Fixing the reporting model when the cause is upstream
- Reading only the error's first line
- Treating a green `dbt compile` as a verified fix
- Weakening or deleting a test to make it pass
- Patching downstream models one by one for a single upstream rename
