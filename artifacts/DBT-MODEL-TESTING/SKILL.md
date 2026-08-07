---
name: dbt-model-testing
description: Choosing dbt schema tests that catch real defects - what to test per column role, and what to do when a test fails.
---

# Testing dbt models

[dbt-project-conventions](../DBT-PROJECT-CONVENTIONS/SKILL.md) covers where test
YAML lives and how it is wired into the project. This is about which tests are
worth adding and how to respond when one fails.

For testing Python pipeline code rather than warehouse models, see
[pytest-data-pipelines](../PYTEST-DATA-PIPELINES/SKILL.md) — a different layer with
different tools.

## Match the project before adding anything

```bash
find . -name "*.yml" -path "*/models/*" | head
cat packages.yml 2>/dev/null           # is dbt_utils or dbt_expectations available?
ls tests/                              # singular tests already written
```

Read the existing test YAML before writing more. You are looking for which test
packages the project actually depends on, whether tests are applied to every column
or only key ones, and whether `severity: warn` is in use.

The package check matters most: adding a `dbt_utils.expression_is_true` test to a
project that does not depend on `dbt_utils` breaks the build for everyone, and the
error names a missing macro rather than your new test.

## Test by column role

Not every column deserves a test. These do:

| Role | Tests | Why |
|---|---|---|
| Primary key | `unique` **and** `not_null` | Together they assert the grain. Either alone does not |
| Foreign key | `not_null`, `relationships` | Catches orphans — rows pointing at parents that no longer exist |
| Categorical | `accepted_values` | Catches new values appearing upstream without warning |
| Required business field | `not_null` | The columns whose absence makes the row meaningless |

**`unique` and `not_null` on the primary key are the pair that matters.** They are
the executable statement of the model's grain. A model whose key is unique and
non-null cannot have silently fan-out-duplicated during a join, which is the single
most common way a dbt model goes wrong.

`accepted_values` earns its place for a different reason: it is the only one of
these that fails when *upstream* changes rather than when your SQL is wrong. A new
status code appearing in the source is information you want, on the day it appears.
Confirm the permitted values with whoever owns the data rather than reading them off
today's rows — today's rows show you what exists, not what is allowed.

## Run them

```bash
dbt test --select my_model      # this model
dbt test --select +my_model     # and everything it depends on
```

The `+` prefix is worth using when a test fails: it tells you whether the upstream
models are sound, which decides where to look.

## When a test fails, the test is probably right

A failing test is a finding. The reflex to make it pass is the thing to resist —
adding `coalesce` around a failing `not_null`, or extending `accepted_values` to
include whatever appeared, converts a signal into silence and leaves the bad data
in place.

| Failure | Usual cause | Right response |
|---|---|---|
| `unique` | A join fanned out, or the source has duplicates | Fix the join or deduplicate deliberately — do not drop the test |
| `not_null` | Nulls upstream, or an inner join became outer | Find out why the null is there before deciding what it should be |
| `relationships` | Orphan rows; parent deleted or filtered | Usually an upstream filter problem, not a reason to loosen the test |
| `accepted_values` | A genuinely new category | Confirm it is legitimate, then add it deliberately |

Query what failed before deciding:

```bash
dbt show --inline "
  select contact_id, count(*)
  from {{ ref('dim_contacts') }}
  group by 1 having count(*) > 1 limit 10
"
```

Widening a test is sometimes the correct response — categories really are added.
The distinction is whether you confirmed the new value is legitimate, or simply
made the red go away.

## Severity

`severity: warn` reports without failing the build. It is right for conditions that
are real but not release-blocking — a freshness check on a source that is
occasionally late, a category list you expect to grow.

It is wrong as a way to keep a known-failing test in the project. A warning that
fires on every run stops being read within a week, and the test is then worse than
absent: it produces noise while implying coverage.

## Anti-patterns

- Adding `dbt_utils` tests without checking `packages.yml`
- A primary key with `unique` but not `not_null`, or the reverse
- Loosening a test so it passes, without establishing why it failed
- `accepted_values` populated from today's distinct values rather than confirmed rules
- Downgrading a genuine failure to `warn` and leaving it
- Testing only the obvious columns while the business-critical ones go uncovered
- Models with no tests at all
