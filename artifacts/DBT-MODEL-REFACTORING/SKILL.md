---
name: dbt-model-refactoring
description: Restructuring a dbt model without changing its output - establishing the downstream blast radius first, and proving the result is unchanged.
---

# Refactoring dbt models

Refactoring means the output does not change. In a dbt project the output has
consumers you did not write and may not know about, so the work is mostly in
establishing what depends on this model and proving you did not disturb it.

For splitting Python pipeline code rather than SQL models, see
[etl-decomposition](../ETL-DECOMPOSITION/SKILL.md).

## Find the blast radius first

```bash
dbt ls --select my_model+ --output list     # everything downstream
```

Use the dbt graph, not `grep`. A `grep` for `ref('my_model')` misses references
built through macros or Jinja loops, and it will not find exposures. The `+` suffix
gives the full transitive set — the model that breaks is often two hops away, not
one.

Then find out what those consumers actually use:

```bash
dbt ls --select my_model+ --output json | head    # names, then read the ones that matter
```

The distinction that governs everything else: **restructuring internals is safe,
changing the interface is not.** The interface is the set of columns, their names,
their types, and their nullability. Rearranging CTEs behind a stable interface
cannot break a consumer. Renaming one column can break every consumer at once.

If the columns change, tell the person whose work depends on them before doing it,
not after. "This affects seven downstream models and two dashboards" is a
conversation; discovering it in a failed nightly run is an incident.

## Record the output before touching anything

You cannot show the output is unchanged without knowing what it was.

```bash
dbt build --select my_model
dbt show --inline "select count(*) from {{ ref('my_model') }}"
dbt show --inline "
  select count(*)              as rows,
         count(distinct order_id) as keys,
         sum(revenue)          as total_revenue,
         min(ordered_at)       as earliest,
         max(ordered_at)       as latest
  from {{ ref('my_model') }}
"
```

Row count alone is weak — a refactor can preserve the count while corrupting values.
A handful of aggregates over the key columns catches far more, and costs one query.
Save the numbers somewhere you can read them afterwards.

## Change one thing at a time

Each step: make one structural change, rebuild, compare against the recorded
numbers.

```bash
dbt build --select my_model
```

Batching five changes and finding the totals no longer match means bisecting your
own work. The cost of one rebuild per step is far below the cost of that.

## What is worth extracting

| Situation | Move |
|---|---|
| A CTE with its own meaning, reused elsewhere | Intermediate model |
| Identical expression in three or more models | Macro |
| Several joins that each need their own filters | Intermediate models per step |
| A CTE that is merely long | Usually nothing — see below |

**Extract on reuse, not on length.** A 60-line CTE used once is not a design
problem; splitting it into its own model adds a file, a name, a materialisation
decision, and a graph edge to make one file shorter. That trade is worth making
when a second consumer appears, because then the alternative is duplication.

Same rule for macros. Two occurrences of a `case` expression are a coincidence;
three are a pattern. A macro written at the first occurrence usually gets its
signature wrong, because one call site is not enough evidence about what varies.

Extraction to an intermediate model has a real cost worth naming: the intermediate
model materialises, so the warehouse now writes an object that previously existed
only inside one query. On a large table, extracting a CTE for readability can add
minutes to the build.

## Prove the output is unchanged

Run the same aggregates and compare against what you recorded:

```bash
dbt show --inline "
  select count(*) as rows, count(distinct order_id) as keys, sum(revenue) as total_revenue
  from {{ ref('my_model') }}
"
```

Every number must match. A difference is a defect in the refactor until proven
otherwise — the reflex to decide the new number looks more correct is how a
refactor quietly becomes a behaviour change.

Then build the downstream set, which is what you were protecting all along:

```bash
dbt build --select my_model+
```

## When the interface must change

Sometimes a rename is the point. Then it is not a refactor and should not be
presented as one — it is a breaking change with a migration.

Change the model and every consumer in the same commit, so the graph is never in a
broken intermediate state, and update the `schema.yml` descriptions and tests along
with it. Documentation left pointing at the old column name is worse than none: it
is confidently wrong.

## Anti-patterns

- Changing a model before knowing what consumes it
- `grep` for `ref()` instead of the dbt graph
- Several structural changes between rebuilds
- Comparing row counts only, then declaring equivalence
- Accepting a changed total because it looks more plausible
- Extracting a CTE for length when it has one consumer
- Writing a macro at the first occurrence
- Renaming columns without updating tests and descriptions
