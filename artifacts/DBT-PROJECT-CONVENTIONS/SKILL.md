---
name: dbt-project-conventions
description: dbt project layering, sources, tests, contracts, and incremental models - what belongs in each layer and why.
---

# dbt project conventions

Layout, layering, and the four features that carry most of the value: sources,
tests, contracts, and incremental models.

## Layers

```text
models/
  staging/
    _sources.yml       # raw table declarations
    _staging.yml       # tests on staging models
    stg_customers.sql
    stg_orders.sql
  marts/
    _marts.yml
    dim_customers.sql
    fct_orders.sql
snapshots/
  customers_snapshot.sql
```

Materialisation per layer, set once in `dbt_project.yml` rather than per model:

```yaml
models:
  analytics:
    staging:
      +materialized: view
      +schema: staging
    marts:
      +materialized: table
      +schema: marts
```

**Staging is views.** It is thin cleanup - renaming, casting, lowercasing - so
materialising it as a table doubles storage to persist a near-copy of the source.

**Marts are tables.** They are read often and joined against; recomputing a view
chain on every dashboard query is where warehouse spend goes.

## The staging rule

**Staging is 1:1 with the source. No joins, no business logic.**

```sql
-- stg_customers.sql
with source as (
    select * from {{ source('raw_source', 'customers') }}
)

select
    customer_id,
    full_name,
    lower(email) as email,
    loyalty_tier,
    city,
    updated_at
from source
```

Renaming, type casting, and normalising like `lower(email)` belong here. A join
does not. Once staging joins, it stops being a predictable projection of one source
table and there is no layer left that answers "what does the source actually
contain". Every downstream model then re-derives that answer differently.

The `with source as (select * from ...)` opener is convention, not decoration - it
keeps the `source()` call in exactly one place per file.

## Sources

Declare raw tables dbt does not manage:

```yaml
sources:
  - name: raw_source
    description: "OLTP source: the application production database."
    schema: raw_source
    tables:
      - name: customers
        columns:
          - name: customer_id
            tests: [not_null, unique]
      - name: orders
        loaded_at_field: ordered_at
        freshness:
          warn_after: {count: 24, period: hour}
          error_after: {count: 72, period: hour}
```

Three things this buys, and the third is the one people miss:

- `source()` in SQL instead of a hardcoded schema name
- `dbt source freshness` - the only check that catches a **stopped upstream feed**.
  Every other test validates rows that arrived; freshness is what fires when none
  did. A pipeline whose source silently stopped yesterday passes every `not_null`
  and `unique` test perfectly.
- Lineage that starts at the source, not at the first dbt model

## Tests

Start with the four built-ins, on the columns that carry meaning:

```yaml
columns:
  - name: order_id
    tests: [not_null, unique]
  - name: customer_id
    tests:
      - relationships:
          to: ref('dim_customers')
          field: customer_id
  - name: status
    tests:
      - accepted_values:
          values: ['new', 'paid', 'shipped', 'cancelled']
```

- `unique` + `not_null` on every grain key. If the grain is composite, test a
  surrogate key or use `dbt_utils.unique_combination_of_columns` - `unique` on each
  column separately tests something different and weaker.
- `relationships` is the referential integrity a warehouse has no foreign keys to
  enforce. It is how orphaned facts get caught.
- `accepted_values` on low-cardinality columns catches an upstream enum gaining a
  value - which usually breaks a `CASE` downstream that silently falls through to
  `ELSE`.

Test the source too, not just the models. A failure on `source.customers.customer_id`
points at the upstream system; the same failure surfacing three models later costs
an hour of tracing.

## Contracts

```yaml
- name: dim_customers
  config:
    contract:
      enforced: true
  columns:
    - name: customer_id
      data_type: integer
      constraints:
        - type: not_null
    - name: revenue
      data_type: numeric
```

With `enforced: true`, dbt compares the model's actual columns and types against
the declaration **before** materialising. A renamed column or a type that drifted
from `numeric` to `text` fails the build instead of quietly reshaping a table that
a BI tool reads.

Enforce contracts on models other teams consume. Skip them on internal
intermediates, where the declaration is pure maintenance cost.

`data_type` must be spelled the way the warehouse reports it - `integer` not `int`
on Postgres - or the build fails on a difference that is only notation.

## Incremental models

```sql
{{ config(
    materialized='incremental',
    unique_key='order_id',
    incremental_strategy='delete+insert',
) }}

select order_id, customer_id, amount, status, ordered_at
from {{ ref('stg_orders') }}

{% if is_incremental() %}
    where ordered_at > (select coalesce(max(ordered_at), '1900-01-01') from {{ this }})
{% endif %}
```

`{{ this }}` is the existing physical table. The `is_incremental()` block is skipped
on a full refresh and on the first run, so the same file handles both paths.

Three traps:

- **`coalesce` on the watermark is required.** Against an empty table `max()` returns
  `NULL`, `ordered_at > NULL` is `NULL`, and the model loads zero rows - a green run
  that produced nothing.
- **`>` versus `>=`.** With `>` a row landing on the exact boundary timestamp is
  never loaded. With `>=` it loads twice - which is safe *only* because
  `delete+insert` with a `unique_key` removes the duplicate first. On `append` it is
  a duplicate row.
- **Late-arriving rows are missed.** A row inserted upstream today with yesterday's
  `ordered_at` falls below the watermark forever. Either use an ingestion timestamp
  as the watermark, or subtract a lookback window (`> max(ordered_at) - interval '3 days'`).

Reach for incremental when a full rebuild is genuinely too slow. Below a few million
rows, `table` is simpler, always correct, and immune to every trap above.

## Snapshots

SCD2 in one command - see [scd2-implementation](../SCD2-IMPLEMENTATION/SKILL.md) for
what it is doing underneath and when to hand-write it instead.

```sql
{% snapshot customers_snapshot %}
{{ config(target_schema='snapshots', unique_key='customer_id',
          strategy='timestamp', updated_at='updated_at') }}
select customer_id, full_name, email, loyalty_tier, city, updated_at
from {{ source('raw_source', 'customers') }}
{% endsnapshot %}
```

Snapshot **the source, not a model.** A snapshot records what arrived; pointing it
at a model means a change to that model's logic rewrites history that already
happened.

`strategy='timestamp'` needs a trustworthy `updated_at`. Without one use
`strategy='check'` with explicit `check_cols`.

## Checklist

- [ ] Staging is 1:1 with source, no joins
- [ ] Every raw table declared as a `source`
- [ ] `freshness` on tables that should keep arriving
- [ ] `not_null` + `unique` on every grain key
- [ ] `relationships` from facts to dimensions
- [ ] Contracts on externally consumed marts
- [ ] `coalesce` in every incremental watermark
- [ ] `target/` and `logs/` are gitignored
