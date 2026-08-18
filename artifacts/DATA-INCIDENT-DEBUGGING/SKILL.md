---
name: data-incident-debugging
description: Investigating wrong data when the pipeline reported success - tracing the value back to the code that produced it, and proving the cause before changing anything.
---

# Debugging a data incident

The pipeline is green and the numbers are wrong. That is a different problem from a
failed run: nothing threw, so there is no stack trace and no failing task to start
from. See [dbt-error-debugging](../DBT-ERROR-DEBUGGING/SKILL.md) for the case where
a build actually broke.

The symptoms this covers: a total that does not match the source, duplicate rows
that were not there yesterday, records missing from an output, a status that never
advanced, freshness that silently stopped.

## Read-only until proven otherwise

Investigation is a read. Nothing here needs `INSERT`, `UPDATE`, `DELETE`, `MERGE`,
`DROP`, `ALTER` or `TRUNCATE`, and a fix is a separate decision the user makes after
seeing the evidence.

Default to a non-production environment. If the incident only reproduces in
production, say which environment you are about to query and get confirmation
first — then use a read-only connection.

**A `SELECT` is not automatically safe.** It can scan a table that costs real money,
and it can pull PII into a document that outlives the incident. Select the columns
you need, filter on a key and a time window, and add a `LIMIT`. Put counts and
aggregates in the log rather than raw rows.

Never print or copy credentials. Use whatever secret mechanism the project already
has.

## Keep a log, starting before the first query

Open `docs/incidents/debug-<timestamp>.md` — or wherever the repo keeps these — and
fill in the scope before investigating:

```markdown
# Incident: <short title>

## Scope
- Environment:
- Expected behavior:
- Actual behavior:
- Time window:
- Affected pipeline/job/entity:
- Evidence provided:        # the alert, ticket, or query result that started this

## Hypotheses
| ID | Hypothesis | Evidence for | Evidence against | Status |
|----|------------|--------------|------------------|--------|

## Checks
### Check 1 - <name>
- Question it answers:
- Query:
- Result:
- What it rules in or out:
```

The log exists because a data incident is a search, and searches loop. Writing the
query down *before* running it is what stops the fourth variation of a query you
already ran; recording what each result ruled out is what stops re-testing a
hypothesis you already killed.

## Find the producer before querying the data

The instinct is to query the bad table immediately. Resist it — you do not yet know
that the table you are looking at is the one the number came from.

```bash
grep -rn "<table_name>" --include=*.py --include=*.sql .
```

Work out, from the code:

1. Which DAG, job, model or notebook writes this object.
2. What the authoritative schema or contract says the grain is.
3. Which upstream inputs feed it, and what the joins, filters and dedup rules do.
4. Where state transitions happen, if the entity has a status.

**Do not infer a column's meaning from its name.** `created_at` is the single most
overloaded name in any warehouse: source creation, ingestion, or row-write time,
and the incident often *is* the difference between them. If the code does not say
which, that ambiguity is a finding — write it in the log and keep going.

## Write hypotheses a query can kill

A hypothesis that no result can disprove is not a hypothesis. These are the
recurring ones, and each has a check that settles it:

| Hypothesis | What proves or kills it |
|---|---|
| Late-arriving partition excluded by the watermark | Compare source event time against the run's watermark |
| A join changed the grain and multiplied rows | Count rows per business key before and after the join |
| A retry wrote the same batch twice | Group by batch/run id, look for two loads in the window |
| The write succeeded, the status update did not | Compare the data row's timestamp against the state row's |
| Timezone conversion moved rows out of the window | Re-run the filter in UTC and compare counts |

Duplicates and wrong totals are the same bug more often than not: a join fanned
out. Check the grain first, because it is cheap and it is usually the answer.

## The smallest query that reduces uncertainty

Prefer metadata to data. Row counts, `count(distinct key)`, min/max timestamps and
per-day aggregates answer most of these questions without reading a single business
value:

```sql
select
    <key_column>,
    count(*) as row_count
from <schema>.<table>
where <event_timestamp> >= <window_start>
  and <event_timestamp> <  <window_end>
group by <key_column>
having count(*) > 1
limit 100;
```

Compare against a known-good entity or an earlier time window whenever one exists.
"This key has four rows" means little on its own; "this key has four rows and every
other key has one" is a finding.

Record a summary of each result, not a dump. A pasted thousand-row result makes the
log unreadable and is how PII ends up in a document nobody remembers writing.

## Close with what you proved

```markdown
## Root cause
<one sentence>

## Evidence
- <code reference or query result, and what it establishes>

## Impact
- Affected scope:
- Correctness / freshness:
- PII exposure:

## Fix
1. Containment:              # needs user approval if it changes state
2. Permanent fix:
3. The check that would have caught this:

## Still unproven
- <anything the evidence does not cover>
```

**The "still unproven" section is the one that matters.** A plausible explanation
that fits the symptom is not a root cause — plenty of wrong explanations fit. If you
did not run the check that separates two candidates, the section is where you say
so, rather than letting the report imply a certainty the evidence does not carry.

Do not apply a state-changing fix as part of the investigation. Backfills and
corrective updates are their own decision, made by someone who has read the report.

## Project adaptation

Fill these in for the repository this is installed in: where pipeline code and data
models live, where run logs and run metadata are read from, the approved read-only
query command, the environment names, and where incident documents belong.
