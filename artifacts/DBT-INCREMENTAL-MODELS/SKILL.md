---
name: dbt-incremental-models
description: Choosing an incremental strategy and a unique key, and handling late-arriving data, schema drift, and the divergence that follows.
---

# Incremental models

[dbt-project-conventions](../DBT-PROJECT-CONVENTIONS/SKILL.md) covers the shape of
an incremental model and the three watermark traps — the `coalesce` on an empty
table, `>` versus `>=`, and late-arriving rows. Read that first; this does not
repeat it.

This is about the decisions around that shape: whether to be incremental at all,
which strategy, what the key is, and what goes wrong over months rather than on the
first run.

## First, do not

Incremental is a performance optimisation that costs correctness guarantees. A
`table` model rebuilds from scratch every run, so it cannot drift, cannot
double-count, and has no state to reason about. An incremental model can do all
three, and the failures are quiet.

Stay with `table` until a full refresh is actually too slow or too expensive.
Source row count is the usual proxy, and below roughly ten million rows a full
rebuild on a modern warehouse is rarely the bottleneck — but the real question is
what the rebuild costs in time and credits against how often it runs. A ten-minute
rebuild nightly is fine. The same rebuild every fifteen minutes is not.

```bash
dbt show --inline "select count(*) from {{ source('crm', 'contacts') }}"
```

## Then characterise the source

The strategy follows from the source's behaviour, so establish it before choosing:

- **Are rows ever updated after they are written**, or only appended?
- **Is there a timestamp that reliably moves when a row changes** — and does it
  reflect when the row was *ingested* or when the event *happened*?
- **What identifies a row uniquely**, and is it unique in practice rather than in
  the schema documentation?

That second question decides whether late-arriving data is a problem you have. A
watermark on an ingestion timestamp is monotonic and safe. A watermark on an event
timestamp is not: a row can arrive today carrying yesterday's date, land below the
watermark, and never be loaded.

## Choose the strategy

| Strategy | Use when | Cost |
|---|---|---|
| `append` | Rows are never updated — logs, events, immutable facts | No deduplication whatsoever; a re-run duplicates rows |
| `merge` | Rows can be updated and you have a genuine unique key | Requires `unique_key`; fails on duplicates |
| `delete+insert` | Rows are updated in batches, or `merge` hits duplicate keys | Deletes the matching set before inserting |
| `insert_overwrite` | Partitioned tables, whole partitions reprocessed | Replaces partitions wholesale; no `unique_key` |

`merge` is the reasonable default when rows can change. `append` is the fastest and
the most dangerous — it is correct only if the source is genuinely append-only, and
"mostly append-only" is not append-only.

Availability varies by adapter. Check the
[dbt incremental strategy docs](https://docs.getdbt.com/docs/build/incremental-strategy)
for your warehouse before committing to one.

## Verify the unique key against the data

`merge` on a non-unique key either fails outright or, worse, silently keeps one
arbitrary row of each duplicate set. Check before building, not after:

```bash
dbt show --inline "
  select contact_id, count(*)
  from {{ source('crm', 'contacts') }}
  group by 1 having count(*) > 1 limit 10
"
```

Duplicates mean one of three things: the key is really a composite and needs the
other columns, the source contains genuine duplicates that the model should
deduplicate, or `merge` is the wrong strategy and `delete+insert` fits better.

To deduplicate in the model:

```sql
with ranked as (
    select *,
           row_number() over (partition by contact_id order by updated_at desc) as rn
    from {{ source('crm', 'contacts') }}
    {% if is_incremental() %}
    where updated_at > (select coalesce(max(updated_at), '1900-01-01') from {{ this }})
    {% endif %}
)
select * from ranked where rn = 1
```

Note the filter sits **inside** the CTE. Deduplicating after the incremental filter
ranks only the new rows, which is what you want; deduplicating across the whole
source on every run throws away the performance you went incremental for.

## Full refresh first, always

```bash
dbt build --select fct_orders --full-refresh   # establish the baseline
dbt build --select fct_orders                  # then exercise the incremental path
```

The first run of an incremental model does not execute the `is_incremental()`
block — it builds like a table. So a model whose incremental logic is completely
broken will build, pass tests, and look correct on day one. The bug appears on the
second run, in production, when the filter runs for the first time.

Run both paths before you trust it, and compare the row counts between them.

## Declare what happens when the schema changes

`on_schema_change` defaults to `ignore`, which means a new column added upstream is
silently dropped from your model. Nothing errors; the column is simply not there,
and someone notices weeks later.

| Setting | Behaviour |
|---|---|
| `ignore` (default) | New upstream columns are not added |
| `append_new_columns` | New columns are added to the target |
| `sync_all_columns` | Target matches source, including drops and type changes |
| `fail` | The run errors on any schema difference |

`append_new_columns` is the usual choice. Set it explicitly even when you want the
default, so the next reader knows it was decided rather than inherited.

## Schedule a periodic full refresh

Incremental models drift. Rows corrected upstream below the watermark, a backfill
that landed while the model was paused, a bug fixed after a week of bad data — none
of these are repaired by an incremental run, because the incremental run never looks
at old rows.

Schedule a full refresh at a cadence that matches the tolerance for staleness —
weekly is common — and treat a divergence between the incremental result and the
full refresh as a defect to diagnose, not a number to accept.

## Anti-patterns

- Reaching for incremental before a full refresh is measurably too slow
- Trusting `merge` against a key never verified as unique
- `append` on a source where rows can be updated
- Testing only the first run, which never exercises the incremental path
- Leaving `on_schema_change` at its default by omission
- Never running a full refresh, then trusting the drift
- Deduplicating across the whole source on every incremental run
