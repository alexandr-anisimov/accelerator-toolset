---
name: dbt-sql-migration
description: Porting legacy SQL into dbt layer by layer - what to reuse, what the staging layer is for, and reconciling the result against the original.
---

# Migrating SQL to dbt

A stored procedure or a 400-line view can be pasted into a `.sql` file, given a
`{{ config() }}`, and it will run. That is not a migration — it is the same
monolith with a new file extension, and none of what dbt offers applies to it.

The work is decomposing it into layers, and proving the result matches what the
original produced.

[dbt-project-conventions](../DBT-PROJECT-CONVENTIONS/SKILL.md) defines the layers
this targets.

## Read the original for its inputs and its grain

Before writing anything, extract from the legacy SQL:

- Every table it reads, including ones buried in subqueries and `insert ... select`
- What one row of the result represents
- Filters that encode business rules — `where status <> 'cancelled'`, a hardcoded
  date, a magic account id
- Anything the SQL does that dbt models cannot: `update` in place, temp tables,
  cursors, procedural branching

That last category decides whether this is a migration at all. A model is a
`select` that dbt materialises. A procedure that updates rows conditionally may
need to become a snapshot, an incremental model, or to stay where it is.

The hardcoded filters are the part worth slowing down for. They are usually
undocumented, frequently the only record of a business rule, and the easiest thing
to drop silently — after which the numbers change and nobody can say why.

## Reuse what the project already has

```bash
grep -rn "raw_orders" models/ --include=*.yml --include=*.sql
```

For each source table the legacy SQL reads, check whether a source is already
declared and whether a staging model already exists. Most legacy queries read
tables the project already models.

Declaring a second source for a table that already has one, or writing
`stg_orders_v2` next to `stg_orders`, is how a project ends up with two lineages
for the same data that gradually disagree. If an existing staging model is close
but not identical, extend it rather than forking it — and if you cannot tell
whether a table is already covered, ask rather than guess.

## Build one layer at a time

Sources first, then staging, then intermediate, then the mart. Build each layer
before writing the next:

```bash
dbt build --select stg_orders
```

The reason to go in this order is that an error in staging surfaces as an error in
staging. Write all four layers first and the failure appears in the mart, where the
cause could be anywhere in the chain you just wrote.

**Staging is one model per source table** — rename columns, cast types, nothing
else. No joins, no filters, no aggregation. It is a boring layer by design, and the
temptation to fold "just one join" into it is what eventually makes the lineage
unreadable.

Business logic goes in intermediate models; aggregation in the mart.

## Convert the constructs

| Legacy | dbt |
|---|---|
| Nested subquery | Its own model, or a named CTE |
| Temp table | `materialized='ephemeral'`, or an intermediate model if reused |
| Hardcoded date or environment value | `{{ var('start_date') }}` |
| `insert ... on conflict` / `merge` | Incremental model — see [dbt-incremental-models](../DBT-INCREMENTAL-MODELS/SKILL.md) |
| History table maintained by triggers | Snapshot — see [scd2-implementation](../SCD2-IMPLEMENTATION/SKILL.md) |
| Cross-database reference | Source declaration |

Ephemeral is the right default for a temp table used once: it inlines as a CTE and
materialises nothing. If the same temp table is used by several downstream queries,
make it a real intermediate model instead — ephemeral would re-execute it in each
consumer.

## Reconcile against the original

**This is the step that makes it a migration rather than a rewrite.** The original
is still there and still runs, which is a luxury you will not have again once it is
decommissioned. Use it.

```sql
-- run against the legacy query and the new mart, compare
select count(*)                as rows,
       count(distinct order_id) as keys,
       sum(revenue)            as total_revenue,
       min(ordered_at)         as earliest,
       max(ordered_at)         as latest
from <legacy_result_or_new_model>;
```

Then find rows that differ, rather than trusting the totals:

```sql
select * from legacy_result
except
select * from new_model;
```

Run it in both directions — `except` is not symmetric, and rows the new model
invents will not appear in one direction alone.

Expect small differences and investigate every one. Common causes: a `where` clause
dropped during decomposition, an inner join that became a left join, a `distinct`
lost in the split, timezone handling that differed between the original and the
staging cast. Each is a real defect. A difference you cannot explain is not a
rounding artefact — it is a bug you have not found yet.

If the legacy query is non-deterministic — `limit` without `order by`, a
`current_date` filter — pin the inputs before comparing, or the comparison proves
nothing.

## Add tests as you go

The migration is when you know the most about this data. `unique` and `not_null` on
each layer's key, `relationships` where the legacy SQL relied on a join finding a
match — see [dbt-model-testing](../DBT-MODEL-TESTING/SKILL.md). Written now, they
also serve as the regression suite for the rest of the migration.

## Anti-patterns

- One dbt model containing the whole legacy query
- Skipping staging because the source is "already clean"
- Business logic in staging models
- A parallel source or staging model for a table already covered
- Declaring the migration done on a matching row count alone
- Dismissing an unexplained difference as rounding
- Dropping a hardcoded filter without establishing what rule it encoded
- Leaving the legacy query in place with no decision about decommissioning it
