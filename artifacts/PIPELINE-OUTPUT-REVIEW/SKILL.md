---
name: pipeline-output-review
description: Reviewing what a pipeline run actually produced - row accounting, contracts, drift against a baseline, and why a green test suite does not settle the question.
---

# Reviewing pipeline output

Tests passing means the code did what it was written to do. It does not mean the
output is right. A transformation can be correct on every fixture and still drop
half a partition in production, because the fixture never contained the row shape
that triggers it.

This is the review of the data itself, after a change or a run.
[dbt-model-testing](../DBT-MODEL-TESTING/SKILL.md) covers assertions declared ahead
of time in the project; this covers looking at what came out.

## Collect the inputs first, and name the gaps

- the change or diff being reviewed
- the current output
- the input, or the output before the filtering stage
- the previous approved baseline
- the schema or data contract
- business keys and relationships
- the project's test and validation commands
- agreed thresholds for acceptable drift

**Never invent one of these.** If there is no baseline, the review does not get a
verdict on drift — it gets "no baseline, drift unassessed". A guessed expected row
count is worse than an absent one, because it produces a confident PASS that means
nothing. Missing evidence is a finding in its own right.

## Row accounting is the first check

Every row that went in ended up somewhere. That is the whole idea, and it catches
more real defects than any other single check:

```text
input_count = accepted_count + rejected_count + quarantined_count
```

When that equation does not balance, rows vanished silently — a join dropped
non-matching keys, a filter caught more than intended, a write partially failed.
None of those raise an error.

If the pipeline legitimately changes grain — aggregation, an explode, a fan-out
join — the equation does not apply as written, and the review needs the documented
grain transition instead, reconciled at the new grain.

**Comparing totals alone is not row accounting.** Two errors that cancel produce a
matching total, and a grain change that doubles one segment while dropping another
looks perfect at the top line. Reconcile per stage and per meaningful slice.

## Deterministic contracts

These have right answers, so check them before anything statistical:

| Check | Fails when |
|---|---|
| Required columns and types | Schema drifted upstream, or a cast changed silently |
| Business key uniqueness | A join fanned out — the most common data defect there is |
| Allowed nullability | A left join produced nulls the contract forbids |
| Referential integrity | Child rows outlived their parent |
| Enumerations and ranges | A new source value appeared |
| Timestamp ordering, partition coverage | A window was missed, or a backfill overlapped |

Key uniqueness is the one to run first. It is cheap, and duplicates are the defect
most likely to be mistaken for real growth.

## Rejection funnels

For each filter or validation stage, get the rejection count and rate, the
distribution of reasons, and how that distribution breaks down by source, partition
and time.

What you are looking for is concentration. A rejection rate that stays flat overall
while one source moves from 2% to 40% is a broken source, and the aggregate hides
it completely.

Distinguish business rejection from technical failure. A row rejected because it
failed a validation rule is the pipeline working; a row rejected because a parser
threw is the pipeline broken. Counting them together makes both invisible.

## Drift against the baseline

Compare current output to the approved baseline on row and distinct-key counts,
null rates, cardinality, numeric quantiles, categorical distributions, date
coverage and duplicate rate.

Two rules keep this honest:

**Record the baseline's version and date in the report.** A baseline is only a
reference point if you know what it is a baseline of. "Compared against last
month's numbers, which someone remembers" is not a comparison.

**Large drift is not automatically bad.** A change that adds a source is *supposed*
to move the counts. Compare against an approved threshold or an expected delta
stated in the change description. Where neither exists, report the observed delta
and say explicitly that no threshold was available — do not invent a pass or fail.

The same applies to near-duplicate detection: thresholds are domain-specific. If
you use one, record the method, the value, and why it suits this data.

## Cross-output consistency

Where several outputs describe the same entity, stable facts should agree across
them — identifiers, effective dates, amounts, status transitions.

Flag conflicting facts for one entity, child rows without a parent, status changes
with no corresponding event, aggregates that do not reconcile with their detail
rows, and time windows that differ between stages.

## Sample deliberately

Systematic checks cannot see semantic wrongness — a correctly-typed, unique,
non-null value that means the wrong thing. Sampling can, but only if the sample is
chosen rather than taken from the top: common successful rows, boundary values, one
row per major rejection reason, new categories, the largest drift segments, and
rows the change actually touched.

Sampling supplements the systematic checks. It does not replace them, and it never
establishes an absence of defects.

## Run the project's own checks

Run the repository's tests, lint, type checks and validation scripts. Record the
exact commands and their outcomes.

**Do not report a check as passed when it was skipped or unavailable.** `SKIPPED`
is a real result and belongs in the table; a review whose reader cannot tell the
difference between "passed" and "never ran" is worse than no review.

## The report

```markdown
## Output review: <run or change>

### Verdict
<PASS | PASS WITH WARNINGS | FAIL | INSUFFICIENT EVIDENCE>

### Inventory
| Stage | Rows | Distinct keys | Time coverage | Notes |
|-------|------|---------------|---------------|-------|

### Checks
| Check | Result | Evidence |
|-------|--------|----------|
| Schema / contract | PASS/FAIL/SKIPPED | |
| Row accounting | PASS/FAIL/SKIPPED | |
| Key uniqueness | PASS/FAIL/SKIPPED | |
| Baseline drift | PASS/FAIL/SKIPPED | |
| Repository tests | PASS/FAIL/SKIPPED | |

### Findings
| Severity | Finding | Evidence | Action |
|----------|---------|----------|--------|

### Baseline
- Version / date:
- Material deltas:

### Missing evidence
- <contract, threshold, baseline or test that was not available>

### Actions
1.
```

`INSUFFICIENT EVIDENCE` is a real verdict and the honest one when the baseline or
contract is missing. Reaching for `PASS` because nothing visibly broke is how a
review becomes a rubber stamp.

Treat unexplained row loss, key duplication, broken accounting and cross-output
inconsistency as blockers. Keep code correctness, contract correctness and business
semantics separate in the findings — they have different owners and different fixes.
