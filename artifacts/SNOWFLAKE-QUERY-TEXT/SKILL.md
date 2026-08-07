---
name: snowflake-query-text
description: Rewriting a Snowflake query for performance without changing its results - which transformations are safe, which only look safe, and why.
---

# Optimising query text

Rewriting a query you cannot run is a different job from tuning one you can profile.
Without execution metrics there is no feedback, so the discipline is entirely in
knowing which transformations preserve results and which only appear to.

If a `query_id` exists, use
[snowflake-query-by-id](../SNOWFLAKE-QUERY-BY-ID/SKILL.md) instead — a profile beats
pattern-matching.

## The rule that governs everything else

**A faster query returning different rows is not an optimisation, it is a bug you
introduced.** Nothing below is worth breaking this for.

Preserve exactly: the columns, their order, their aliases, the rows, the ordering,
and the `LIMIT`. Do not add a `LIMIT` that was not there. Copy identifiers
character-for-character rather than tidying them — renaming an alias breaks whatever
consumes the result downstream.

**When you cannot establish that a rewrite is equivalent, leave it alone** and say
why. An unoptimised query that is correct beats a fast one that is subtly wrong, and
the wrongness here is the kind nobody notices for months.

Always report what you changed and why. A rewritten query handed over with no
account of the changes cannot be reviewed, and the person running it has no idea
which assumptions it now depends on.

## Functions on filtered columns

The highest-value fix. Snowflake prunes micro-partitions using metadata about stored
column values, so a predicate on the raw column can skip partitions — and one
wrapping the column in a function cannot, forcing a full scan.

Safe, because each is an equivalent range:

| Original | Rewrite |
|---|---|
| `where date(ts) = '2024-01-01'` | `where ts >= '2024-01-01' and ts < '2024-01-02'` |
| `where year(dt) = 2024` | `where dt >= '2024-01-01' and dt < '2025-01-01'` |
| `where year(dt) = 2024 and month(dt) = 3` | `where dt >= '2024-03-01' and dt < '2024-04-01'` |
| `where date(ts) >= '2024-01-01' and date(ts) < '2024-02-01'` | `where ts >= '2024-01-01' and ts < '2024-02-01'` |

Use a half-open interval — `>= start and < end`. `between` on a timestamp includes
the upper bound, so it silently catches rows at exactly midnight.

Not safe:

| Pattern | Why |
|---|---|
| `where year(dt) in (select yr from ...)` | Values unknown until run time; no range to precompute |
| `where date(ts) = date(other_col)` | Two columns, not a constant |
| `where extract(dow from dt) = 1` | Day-of-week is not a contiguous range |
| `where date_trunc('month', dt) = '2024-01-01'` used for grouping | Removing it changes the grouping |

Functions in `select` or `group by` are irrelevant to pruning. Only predicates
matter.

## Functions on join keys

A function on a join key prevents a hash join, forcing a far slower strategy. Whether
it can be removed depends on the data, not the SQL:

| Original | Rewrite | Only if |
|---|---|---|
| `on cast(a.id as varchar) = cast(b.id as varchar)` | `on a.id = b.id` | Both columns are already the same type |
| `on upper(a.code) = upper(b.code)` | `on a.code = b.code` | Both sides are genuinely consistently cased |
| `on trim(a.name) = trim(b.name)` | `on a.name = b.name` | Neither side has padding |

Each condition is a claim about the data that the query text cannot prove. `upper()`
on both sides is often there because someone hit a casing mismatch. Verify against
the columns before removing it; if you cannot, leave it.

Never removable: a genuine type difference, a granularity difference such as
`on date(a.ts) = b.day`, or arithmetic like `on a.id = b.id + 1`.

## NOT IN to NOT EXISTS

`not in` against a subquery returning even one NULL yields **no rows at all** — a
comparison against NULL is unknown, never true. `not exists` does not behave this
way, so the two are equivalent only when the subquery column cannot be NULL.

```sql
-- safe only when t.id is NOT NULL
where id not in (select id from t)
-- becomes
where not exists (select 1 from t where t.id = main.id)
```

Check the column's nullability first. If it is nullable, this rewrite changes
results — and in the direction that returns *more* rows, which looks like a fix
rather than a regression.

Multi-column `not in` has more intricate NULL semantics again; leave it.

## Repeated subqueries and implicit joins

An identical subquery written two or more times may be scanned each time. Extracting
it to a CTE and referencing it is safe. This does not apply to correlated
subqueries — they reference the outer row and are genuinely different per row.

Comma joins — `from a, b where a.id = b.id` — convert to explicit `join ... on`
syntax. Pure restructuring, always safe, and it makes an accidental cross join
visible.

## Never do these

- **`union` → `union all`.** `union` deduplicates. Different results, and this is the
  most commonly proposed unsafe "optimisation".
- **Restructuring window functions.** Nested aggregates like `sum(sum(x)) over (...)`
  are usually deliberate.
- **Duplicating a `where` filter into a `join ... on` clause.** On an outer join this
  changes which rows survive.
- **Adding a `LIMIT` that was not in the original.**
- **Renaming columns or aliases.**

## Order of work

1. Functions on filtered columns — largest effect, and safe when the range is exact
2. Comma joins to explicit joins — always safe
3. Repeated subqueries to CTEs — safe when uncorrelated
4. `not in` to `not exists` — only after confirming nullability
5. Functions on join keys — only after confirming the data

Make the fewest changes that address the cause. A minimal rewrite is reviewable; a
wholesale restructuring is not, and it hides which change mattered.

## Anti-patterns

- Returning a rewrite with no account of what changed
- Rewriting on a guess about the data instead of verifying it
- `not in` → `not exists` without checking nullability
- `union` → `union all`
- Restructuring the whole query when one predicate was the problem
- Claiming an improvement that was never measured
