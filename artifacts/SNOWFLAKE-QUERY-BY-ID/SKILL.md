---
name: snowflake-query-by-id
description: Diagnosing one Snowflake query from its profile - operator stats, pruning and spill, and separating a query problem from a warehouse problem.
---

# Diagnosing a query by id

With a `query_id` you have what a pasted query never gives you: what actually
happened when it ran. Use it, rather than reading the SQL and guessing.

For finding which queries are worth this attention, see
[snowflake-expensive-queries](../SNOWFLAKE-EXPENSIVE-QUERIES/SKILL.md).

## Fetch the run

```sql
select query_text,
       warehouse_size,
       total_elapsed_time / 1000                        as seconds,
       bytes_scanned / power(1024, 3)                   as gb_scanned,
       bytes_spilled_to_local_storage / power(1024, 3)  as gb_spill_local,
       bytes_spilled_to_remote_storage / power(1024, 3) as gb_spill_remote,
       partitions_scanned,
       partitions_total,
       rows_produced,
       queued_overload_time / 1000                      as queued_seconds
from snowflake.account_usage.query_history
where query_id = '<query_id>'
  and start_time >= dateadd('days', -7, current_timestamp());
```

Widen or drop the time bound only if the query is older than the window — the
predicate is what keeps this lookup from scanning a year.

Use `information_schema.query_history()` instead if the query ran in the last few
hours; `ACCOUNT_USAGE` lags by up to 45 minutes.

**Read `queued_seconds` first.** If the query spent most of its wall-clock time
queued, it is not slow — the warehouse is saturated, and rewriting the SQL will
change nothing. That is a concurrency or sizing problem.

## Get the operator profile

```sql
select *
from table(get_query_operator_stats('<query_id>'));
```

This is the part that distinguishes diagnosis from guesswork. It reports, per
operator, how many rows went in and came out, how long each took, and which ones
spilled.

Three things to look for:

- **An operator whose output rows greatly exceed its input rows.** That is a join
  fanning out. Everything downstream then processes the inflated row count, so this
  is usually the whole explanation for both the runtime and the spill.
- **A `TableScan` reading far more than the query returns.** Points at pruning or
  projection — the columns and partitions being read are not the ones needed.
- **Which operator spilled.** A spilling sort and a spilling join have different
  fixes. Without the profile you know only that spill occurred, not where.

## Separate the query problem from the warehouse problem

This is the judgement call, and getting it wrong wastes the most time.

| Evidence | Conclusion |
|---|---|
| High `queued_overload_time` | Warehouse — concurrency, not this query |
| Spill with no fan-out, warehouse at its floor size | Warehouse — the work genuinely needs more memory |
| Spill following an operator that multiplies rows | Query — fix the join; a bigger warehouse only makes the same bug cost more |
| `partitions_scanned` ≈ `partitions_total` with a selective filter | Query — the filter cannot prune |
| Fast, but running thousands of times a day | Neither — a scheduling or caching question |

Resizing the warehouse is the tempting move because it is one setting and it
usually works. It also raises the cost of every query on that warehouse, forever, to
work around one query's defect. Establish that the query is sound before paying
that.

## Common causes and their fixes

**No partition pruning.** Snowflake prunes on micro-partition metadata, so a filter
must be a plain comparison against a stored column. Wrapping the column in a
function — `date(ts) = '2024-01-01'` — defeats it. Rewrite as a range on the raw
column. If the filter is already plain and pruning still does not happen, the table
is not clustered along the way it is queried, which is a table-level decision rather
than a query fix.

**Projection.** `select *` on a wide columnar table reads columns nobody uses. Naming
the needed columns is often the single largest reduction in bytes scanned.

**Filtering after the join.** Filters written in the outer query on a joined result
mean the join processed rows that were then discarded. Push each filter into a CTE
against its own table so the join runs on the smaller inputs. Note this changes
nothing semantically only when the filter applies to one side — pushing a filter
across an outer join changes results.

**Repeated identical subqueries.** The same subquery written twice may be scanned
twice. Extract it to a CTE. This does not apply to correlated subqueries, which are
genuinely different per row.

## Verify before claiming an improvement

```sql
explain using json <optimized_query>;
```

`EXPLAIN` gives the plan without running the query — enough to confirm the partition
count dropped and the join order is what you expect.

That is a prediction, not a result. The claim is only established by running the
rewrite and comparing its actual metrics against the original's. Report the numbers
you measured; if you only have the plan, say that is what you have. An estimate
presented as a measurement is the failure mode here — "12.3 GB → 0.4 GB" reads as
fact and gets repeated as one.

## Anti-patterns

- Reading the SQL and theorising when the profile is available
- Resizing the warehouse before establishing the query is sound
- Missing that the time was spent queued, not executing
- Treating spill as a memory problem when a fan-out caused it
- Reporting `EXPLAIN` estimates as measured improvements
- Optimising a query that is fast but runs constantly
