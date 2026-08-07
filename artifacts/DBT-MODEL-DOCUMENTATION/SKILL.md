---
name: dbt-model-documentation
description: Writing dbt model and column descriptions that answer what SQL cannot - grain, business rules, and the caveats a reader would otherwise learn the hard way.
---

# Documenting dbt models

A reader can already see the SQL. Documentation earns its place only where it says
something the SQL cannot: why a filter exists, what a null means, which of two
plausible readings of a column is the right one.

Descriptions live in the `schema.yml` alongside the model — see
[dbt-project-conventions](../DBT-PROJECT-CONVENTIONS/SKILL.md) for where that sits.

## Write only what the SQL does not say

The failure mode is restating the column name in a sentence:

```yaml
- name: order_id
  description: "The ID of the order."      # says nothing
```

That is worse than an empty description. It occupies the space where the useful
sentence would go, and it makes a documentation coverage report show green.

The test before writing any description: **would a competent reader with the SQL
open in front of them already know this?** If yes, do not write it. If the answer
is genuinely nothing, leave the column undocumented and spend the effort on the
ones that need it.

Not every column needs a description. The ones that do are those where a reader
could be confidently wrong.

## Start with the grain

The single most valuable line in any model's documentation:

```yaml
description: |
  Order line items, one row per order_id + product_id.
```

The grain determines whether it is safe to sum a column, join to this model, or
count its rows. It is the first thing a consumer needs and the thing SQL states
least clearly — recovering it means reading every join and group-by in the model.

## Then the business rules

These are the decisions encoded as filters and expressions, which a reader can see
but cannot interpret:

```yaml
description: |
  Order line items, one row per order_id + product_id.

  Revenue is recognised on ship_date, not order_date — finance reports on
  shipment. Cancelled orders are excluded entirely; returns appear as negative
  line items rather than deletions, so sums net out correctly but counts do not.
```

Every sentence there corresponds to something visible in the SQL and explains why
it is that way. `where status <> 'cancelled'` is legible; that returns are handled
as negative rows, and what that implies for counting, is not.

## Columns worth describing

| Column | Say |
|---|---|
| Primary key | Which system it comes from, whether it is stable across reloads |
| Foreign key | What it joins to, and what a null means |
| Metric | The formula, the units, and what is excluded |
| Date/timestamp | Which event it marks, and the timezone |
| Status or category | The permitted values and what they mean in business terms |
| Boolean | What `true` asserts — flag names are frequently ambiguous |

```yaml
- name: customer_id
  description: |
    Joins to dim_customers. Null for guest checkouts, which exist only
    before 2023 — after that a customer record is always created.

- name: revenue
  description: |
    Net revenue in USD: unit_price * quantity - discount_amount.
    Excludes tax and shipping. Negative for returns.

- name: is_active
  description: |
    True when the subscription is billable now. A paused subscription is
    false but not cancelled — use cancelled_at to distinguish them.
```

Each of those prevents a specific, likely mistake: summing revenue and expecting it
to reconcile with an invoice, treating a null customer as a data error, reading
`is_active = false` as churn.

## Timezones and units, always

Two facts that are invisible in the data and expensive to get wrong: what timezone
a timestamp is in, and what unit a number is measured in. `amount` could be dollars
or cents; `duration` could be seconds or milliseconds. Both have plausible-looking
wrong answers, which is what makes them dangerous.

## Match the project's existing style

```bash
find . -name "*.yml" -path "*/models/*" | head
```

Read a well-documented model before writing. Projects differ on whether
descriptions are one line or several paragraphs, whether markdown headings are
used, and whether every column is covered or only the ambiguous ones. Consistency
matters more than your preference — a file in a different style reads as an
oversight.

For text reused across models, `{% docs %}` blocks in a `.md` file under `models/`
let one definition serve many `description:` fields, so a shared concept has one
definition rather than five that drift.

## Keep it true

`dbt docs generate` will publish whatever is written, correct or not. Nothing
validates a description against the model, so documentation decays silently: a
filter changes, the description that explained it does not, and the file now states
something false with full authority.

Treat a description as part of the model's interface. When a model's logic changes,
the description changes in the same commit — see
[dbt-model-refactoring](../DBT-MODEL-REFACTORING/SKILL.md). Stale documentation is
worse than absent documentation, because it is trusted.

## Anti-patterns

- Restating the column name as a sentence
- No grain on the model description
- Timestamps with no timezone, amounts with no unit
- Documenting the transformation instead of the reason for it
- Enumerating status values from today's data rather than the defined set
- Writing filler for every column to make coverage look complete
- Leaving descriptions unchanged when the logic changes
