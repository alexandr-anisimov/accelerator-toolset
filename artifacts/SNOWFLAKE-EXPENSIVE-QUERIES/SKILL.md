---
name: snowflake-expensive-queries
description: Finding Snowflake's costly queries - which history view to use, why credits and elapsed time rank differently, and reading the metrics that point at a fix.
---

# Finding expensive queries

Snowflake bills for warehouse time, not for queries. So "expensive" and "slow" are
different questions with different answers, and the first decision is which one you
are actually asking.

## Decide what expensive means here

| Ranking by | Finds | Use when |
|---|---|---|
| `credits_attributed_compute` | What the money went to | Reducing the bill |
| `total_elapsed_time` | What users wait on | A dashboard or job is too slow |
| `bytes_scanned` | Queries reading too much | Hunting for missing pruning |
| Spill bytes | Queries exceeding memory | Warehouse is undersized for the work |
| Repeated `query_hash` | Cheap queries run constantly | Aggregate cost hides in frequency |

These disagree, and the disagreement is the useful part. A ten-second query running
every minute costs far more than a four-minute report that runs at 06:00 daily,
while ranking by elapsed time puts the report on top and never shows the other one.
When the goal is cost, rank by credits and look at frequency; when the goal is a
complaint about waiting, rank by elapsed time.

Also settle the window and the scope before querying — last 7 days, a specific
warehouse, a specific service account. Without a time bound the query scans a year.

## Pick the right history source

Two places report query history, and they are not interchangeable:

| | `ACCOUNT_USAGE` | `INFORMATION_SCHEMA` |
|---|---|---|
| Retention | 365 days | 7 days |
| Latency | **Up to 45 minutes** | Effectively current |
| Shape | View | Table function |

**The 45-minute latency is the trap.** A query that ran ten minutes ago is usually
not in `ACCOUNT_USAGE` yet. Investigating something that just happened and finding
nothing is the expected result, not evidence that it did not run — use
`INFORMATION_SCHEMA` for the last few hours, and `ACCOUNT_USAGE` for anything
older than an hour or spanning more than a week.

Cost attribution lives only in `ACCOUNT_USAGE`.

## Rank by cost

```sql
select query_id,
       warehouse_name,
       user_name,
       credits_attributed_compute,
       start_time,
       query_tag
from snowflake.account_usage.query_attribution_history
where start_time >= dateadd('days', -7, current_timestamp())
order by credits_attributed_compute desc
limit 20;
```

`QUERY_ATTRIBUTION_HISTORY` divides each warehouse's credits among the queries that
ran on it. This is what makes per-query cost meaningful: a warehouse's bill is its
uptime, so a query's share depends on what else was running alongside it. Idle
warehouse time is not attributed to any query and will not appear here — if the
credits in this view fall well short of the warehouse bill, the gap is idle time,
and the fix is the auto-suspend setting rather than any query.

`query_tag` is worth selecting even when empty. If jobs set it, cost rolls up per
pipeline immediately; if the column is always null, that is a reason to start
setting it.

## Then pull the performance metrics

Attribution tells you which queries cost money, not why. Fetch the diagnostics
separately, by id:

```sql
select query_id,
       total_elapsed_time / 1000                    as seconds,
       bytes_scanned / power(1024, 3)               as gb_scanned,
       bytes_spilled_to_local_storage / power(1024, 3)  as gb_spill_local,
       bytes_spilled_to_remote_storage / power(1024, 3) as gb_spill_remote,
       partitions_scanned,
       partitions_total,
       rows_produced
from snowflake.account_usage.query_history
where query_id in ('<id>', '<id>')
  and start_time >= dateadd('days', -7, current_timestamp());
```

Keep the `start_time` predicate even when filtering by `query_id`. The view is
partitioned on time, so without it Snowflake scans the full year to find a handful
of rows — the diagnostic query becomes one of the expensive ones.

## Read the metrics

| Signal | Means | Points at |
|---|---|---|
| `partitions_scanned` ≈ `partitions_total` | No pruning — the whole table was read | A filter that cannot prune, or clustering that does not match the access pattern |
| `gb_spill_remote > 0` | Spilled past local disk to object storage | Serious: usually orders of magnitude slower. Undersized warehouse or an exploding join |
| `gb_spill_local > 0` | Exceeded memory, still on local disk | Tolerable; worth watching if it grows |
| High `bytes_scanned`, low `rows_produced` | Read a lot, returned little | `select *`, or filtering after a join instead of before |
| Same `query_hash`, many executions | Aggregate cost hidden in frequency | Caching, materialisation, or scheduling |

Remote spill and absent pruning are the two worth acting on first. Both usually have
a specific, cheap fix, whereas "this query is slow" without either signal often
means the work is genuinely large.

## Report the finding, not just the ranking

A list of the twenty most expensive queries is a starting point, not an answer. What
makes it actionable: which of them share a cause, what the specific signal was for
each, and which single change would recover the most credits. Three queries scanning
the same unclustered table are one finding, not three.

Once a candidate is chosen, see
[snowflake-query-by-id](../SNOWFLAKE-QUERY-BY-ID/SKILL.md) for diagnosing it from
its profile.

## Anti-patterns

- Ranking by elapsed time when the question was cost
- Expecting a query from ten minutes ago to appear in `ACCOUNT_USAGE`
- Omitting `start_time` and scanning a year of history
- Judging cost per query without checking frequency
- Reading idle-warehouse cost as a query problem
- Reporting a ranked list with no cause attached
