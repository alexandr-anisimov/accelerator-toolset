---
name: scd2-implementation
description: Implement Slowly Changing Dimension Type 2 in SQL - validity intervals, change detection, and the idempotency traps.
---

# SCD2 implementation

Type 2 keeps history: instead of overwriting a changed attribute, close the current
row and open a new one. Every row is a version with a validity interval.

## Table shape

```sql
CREATE TABLE dds.dim_customers (
    customer_id   integer      NOT NULL,
    full_name     text,
    email         text,
    city          text,
    actual_from   timestamptz  NOT NULL,
    actual_to     timestamptz,           -- NULL = current version
    ts_db         timestamptz  NOT NULL  -- when this row was written
);

CREATE INDEX idx_dim_customers_current
    ON dds.dim_customers (customer_id) WHERE actual_to IS NULL;
```

The partial index matters: nearly every query and every step of the merge below
filters on `actual_to IS NULL`, and that predicate hits a small fraction of a table
that grows without bound.

## Open interval: `NULL` or a sentinel

Two conventions, and mixing them is a real source of bugs.

| | `actual_to IS NULL` | `actual_to = '9999-12-31'` |
|---|---|---|
| Current-row filter | `WHERE actual_to IS NULL` | `WHERE actual_to = '9999-12-31'` |
| Range query | needs `COALESCE` or `OR IS NULL` | plain `BETWEEN` works |
| Wrong-result risk | `NULL` comparisons silently drop rows | sentinel leaks into date arithmetic |

Pick one per warehouse and enforce it. The failure when both exist is that a
`BETWEEN` range query silently omits every current row - no error, just quietly
missing data.

## Half-open intervals

Use `[actual_from, actual_to)` - inclusive start, exclusive end. The new version's
`actual_from` equals the closed version's `actual_to`.

Closing with `actual_to = new_ts` and opening with `actual_from = new_ts` means a
point-in-time lookup uses `WHERE ts >= actual_from AND (actual_to IS NULL OR ts < actual_to)`
and matches exactly one row. Closing with `new_ts - interval '1 second'` instead
creates a one-second gap where the customer does not exist, and hides a genuine
double-write behind what looks like rounding.

## Change detection

Compare with `IS DISTINCT FROM`, never `<>` or `!=`:

```sql
WHERE d.first_name IS DISTINCT FROM n.first_name
   OR d.email      IS DISTINCT FROM n.email
   OR d.city       IS DISTINCT FROM n.city
```

`NULL <> 'x'` evaluates to `NULL`, not `TRUE`, so a plain comparison misses every
change into or out of `NULL`. A customer whose email goes from `NULL` to a real
address produces no new version at all - silent history loss, and the kind that is
only discovered months later.

For wide tables, hashing is the readable alternative. It must handle `NULL` and
separator collisions:

```sql
-- Wrong: NULL nulls the whole hash; 'ab'||'c' collides with 'a'||'bc'
md5(first_name || last_name || email)

-- Correct
md5(concat_ws('|', coalesce(first_name, '<NULL>'),
                   coalesce(last_name,  '<NULL>'),
                   coalesce(email,      '<NULL>')))
```

## The merge

Three steps, one transaction.

```sql
BEGIN;

-- 1. Close versions whose attributes changed
WITH current_rows AS (
    SELECT customer_id, full_name, email, city
    FROM dds.dim_customers
    WHERE actual_to IS NULL
),
incoming AS (
    SELECT customer_id, full_name, email, city, ts_db
    FROM raw.customers
    WHERE ts_db >= :start_ts AND ts_db < :end_ts
),
changed AS (
    SELECT i.customer_id, i.ts_db
    FROM current_rows c
    JOIN incoming i USING (customer_id)
    WHERE c.full_name IS DISTINCT FROM i.full_name
       OR c.email     IS DISTINCT FROM i.email
       OR c.city      IS DISTINCT FROM i.city
)
UPDATE dds.dim_customers dst
SET actual_to = chg.ts_db
FROM changed chg
WHERE dst.customer_id = chg.customer_id
  AND dst.actual_to IS NULL;

-- 2. Open new versions for those changed keys
INSERT INTO dds.dim_customers (customer_id, full_name, email, city,
                               actual_from, actual_to, ts_db)
SELECT i.customer_id, i.full_name, i.email, i.city, i.ts_db, NULL, i.ts_db
FROM raw.customers i
WHERE i.ts_db >= :start_ts AND i.ts_db < :end_ts
  AND EXISTS (SELECT 1 FROM dds.dim_customers d
              WHERE d.customer_id = i.customer_id AND d.actual_to = i.ts_db);

-- 3. Insert first versions for keys never seen before
INSERT INTO dds.dim_customers (customer_id, full_name, email, city,
                               actual_from, actual_to, ts_db)
SELECT i.customer_id, i.full_name, i.email, i.city, i.ts_db, NULL, i.ts_db
FROM raw.customers i
WHERE i.ts_db >= :start_ts AND i.ts_db < :end_ts
  AND NOT EXISTS (SELECT 1 FROM dds.dim_customers d
                  WHERE d.customer_id = i.customer_id);

COMMIT;
```

**One transaction, not three.** Between step 1 and step 2 the changed keys have no
open version. A reader querying `actual_to IS NULL` at that moment sees the customer
as deleted, and a crash there leaves the dimension permanently missing rows.

**Bind parameters, do not interpolate.** Building the window with an f-string
(`f"WHERE ts_db BETWEEN '{start_date}'..."`) is how a timezone-formatted timestamp
silently shifts the window, and it is an injection vector when any part of the
predicate comes from a config table.

**Half-open window `>= start AND < end`.** `BETWEEN` includes both endpoints, so a
row landing exactly on the boundary is processed by two consecutive runs and gets a
duplicate version.

## Idempotency

Re-running the same window must not create new versions. Test it directly - run the
merge twice on identical input and assert the row count is unchanged. The step-2
`EXISTS` guard is what provides this: on the second run nothing was closed at
`i.ts_db`, so nothing re-opens.

Three related traps:

- **Multiple changes per key in one window.** The merge as written closes one
  version and opens one, so intermediate states are lost. If the source can change
  a key twice within a window, either shrink the window or rank the incoming rows
  and process them in order.
- **Late-arriving data.** A row whose `ts_db` precedes the current version's
  `actual_from` needs an interval split, not an append. Decide explicitly whether to
  support this; if not, assert the input and fail loudly.
- **Full-reload initialisation.** The initial load uses
  `LEAD(ts_db) OVER (PARTITION BY id ORDER BY ts_db)` to derive `actual_to` from the
  next row's timestamp. That is a different code path from the incremental merge,
  and it needs its own test.

## Invariants worth asserting

Cheap to check, and each catches a real class of corruption:

```sql
-- At most one open version per key
SELECT customer_id FROM dds.dim_customers
WHERE actual_to IS NULL GROUP BY customer_id HAVING count(*) > 1;

-- No overlapping intervals
SELECT a.customer_id FROM dds.dim_customers a
JOIN dds.dim_customers b
  ON a.customer_id = b.customer_id AND a.ctid <> b.ctid
WHERE a.actual_from < coalesce(b.actual_to, 'infinity')
  AND b.actual_from < coalesce(a.actual_to, 'infinity');

-- No inverted intervals
SELECT * FROM dds.dim_customers WHERE actual_to <= actual_from;
```

Run them as pipeline assertions, not one-off queries. The first one in particular
catches the double-write that step 1 and 2 in separate transactions produces.

## Prefer the built-in

If the warehouse already runs dbt, `snapshot` implements all of this:

```sql
{% snapshot customers_snapshot %}
{{ config(target_schema='snapshots', unique_key='customer_id',
          strategy='timestamp', updated_at='updated_at') }}
select customer_id, full_name, email, city, updated_at
from {{ source('raw_source', 'customers') }}
{% endsnapshot %}
```

dbt maintains `dbt_valid_from` / `dbt_valid_to` (`NULL` = current) and a
`dbt_scd_id` surrogate key. `strategy='timestamp'` needs a trustworthy `updated_at`;
where there is none, `strategy='check'` with `check_cols` compares the columns
directly and is the equivalent of the `IS DISTINCT FROM` block above.

Hand-write the merge when there is no dbt, when the source has no reliable change
timestamp and the table is too wide for `check_cols`, or when late-arriving data
needs interval splitting. Otherwise use the snapshot - the traps above are already
handled in it.
