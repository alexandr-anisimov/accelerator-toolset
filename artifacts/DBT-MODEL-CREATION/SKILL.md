---
name: dbt-model-creation
description: The build-and-verify loop for writing a dbt model - read the project first, build rather than compile, and check the output before declaring done.
---

# Creating a dbt model

Where [dbt-project-conventions](../DBT-PROJECT-CONVENTIONS/SKILL.md) says what a
correct model looks like, this is the loop that gets you to one: read the project
before writing, build rather than compile, and verify the data rather than the exit
code.

## Read the project before writing

A model that is correct in isolation and wrong for the project still has to be
rewritten. Before writing anything, spend the two minutes:

```bash
cat dbt_project.yml                    # materialisation per layer, model paths
ls models/staging models/marts         # which layers actually exist
```

Then open two or three existing models in the layer you are adding to. You are
reading for the things no style guide records: how CTEs are named, whether the
final `select` is explicit or `select *`, how joins are laid out, whether `coalesce`
or `nullif` is the local habit for NULL handling.

Match what you find. If the project is wrong about something, that is a separate
conversation with the team, not something to fix silently in one new file.

## Pin the grain before writing SQL

State, in one sentence, what one row of this model represents: *one row per
customer per order date*. Everything else follows from that.

The grain determines the join type, whether an aggregation is needed, and what the
primary key is. Getting it wrong produces a model that builds cleanly, passes
tests, and silently double-counts revenue after a fan-out join. Writing it down
first turns that into a question you can answer while reading the source, rather
than a bug someone finds in a dashboard.

If the model has upstream models you have not read, look at the data before
assuming its shape:

```bash
dbt show --select stg_orders --limit 10
```

## Build, do not compile

```bash
dbt build --select my_model
```

`dbt compile` renders Jinja into SQL and stops. It proves the template is
syntactically valid. It does **not** run the query, so it cannot tell you that a
column does not exist, that a join explodes the row count, or that a cast fails on
one bad value. A green compile followed by "done" is the most common way a broken
model reaches review.

`dbt build` runs the model and its tests. That is the gate.

## Verify the output, not the exit code

A successful build means the SQL ran. It does not mean the answer is right.

```bash
dbt show --select my_model --limit 10
```

Check the column names against what was asked for, spelling included. Check that
the row count is plausible for the grain you pinned — a model at one row per
customer that returns more rows than there are customers has a fan-out. Check
whether the NULLs are the ones you expect.

For anything computed, verify one row by hand:

```bash
dbt show --inline "
  select order_id, quantity, unit_price, total_revenue
  from {{ ref('fct_orders') }}
  where order_id = 1042
"
```

Take that single row and do the arithmetic yourself. `quantity * unit_price`
should equal `total_revenue`. This catches the class of error that no test and no
build will: logic that is valid SQL, runs without complaint, and computes the wrong
number. One row is enough — you are testing the formula, not the data.

## Re-read the request before declaring done

Before you say it is finished, read the original request again, next to the model.

The failure this catches is not carelessness. It is drift: you learn something
about the data halfway through, adapt the model to what is convenient, and end up
delivering something adjacent to what was asked. Specifically check that the column
names are as specified rather than as you would have named them, that the grain
matches, and that you implemented the requirement rather than your reconstruction
of it.

## When the build keeps failing

**After three failed attempts on the same model, stop.**

Three failures means the mental model is wrong, not the syntax. Continuing to
adjust the SQL from inside that wrong model produces increasingly elaborate
attempts at a problem you have misdiagnosed. Step back and re-read the error from
the top, check whether the upstream model actually contains what you assume, and
consider that the approach may need replacing rather than patching. See
[dbt-error-debugging](../DBT-ERROR-DEBUGGING/SKILL.md) for working through the
error itself.

## Anti-patterns

- Declaring done after `dbt compile`, without ever running the model
- Reading the build's exit code and not the data it produced
- Writing SQL before reading how the project's existing models are written
- Assuming the table exists because the `.sql` file exists
- Adjusting SQL repeatedly against the same error instead of reassessing the approach
