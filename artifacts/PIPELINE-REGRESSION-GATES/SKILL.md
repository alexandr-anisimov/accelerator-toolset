---
name: pipeline-regression-gates
description: Choosing the cheapest checks that would actually catch the regression - five layers from unit tests to canary, and which ones a given change requires.
---

# Regression gates for pipeline changes

Two failure modes, opposite in shape and equally common. Running the full
end-to-end pipeline to validate a change a unit test would have caught, and
shipping on one green canary run that proves only that the path executes.

Both come from not asking which check would actually catch *this* regression.

## The five layers

| Layer | Cost | Catches |
|---|---|---|
| 1. Deterministic unit and contract tests | lowest | Pure transformations, SQL generation, schema rules, edge cases |
| 2. Local simulation | low | DAG and state transitions, branching, retries, stage contracts |
| 3. Pinned smoke corpus | medium | Real integrations on a small fixed dataset |
| 4. Production observability | continuous | Drift, yield trends, freshness, cost, what escapes pre-release |
| 5. Production-shaped canary | highest per case | IAM, runtime image, network, deployment paths, engine compatibility |

The numbers are increasing integration and cost, not increasing importance. Layer 1
catches more real defects than layer 5 ever will; layer 5 catches the ones that are
invisible everywhere else.

## Pick by what changed

| Change | Required | Add when |
|---|---|---|
| Pure Python or PySpark transformation | 1 | 3, for engine-specific behavior |
| SQL generation or dialect rules | 1 | 3, against the real engine |
| Schema mapping or data contract | 1, 2 | 3, for representative source variants |
| DAG branching, retries, state machine | 1, 2 | 5, for deployment and IAM paths |
| Incremental load, watermark, dedup | 1, 2, 3 | 4, for late-arriving data |
| Data-quality rule or threshold | 1, 3 | 4, to see rejection-rate shifts |
| Connector, credentials, image, IAM, network | 5 | 2, where behavior can be simulated |
| Observability calculation | 1 | 4, to verify the emitted metric |

A change spanning several rows takes the union.

The incremental-load row is the one people under-test. Watermarks and dedup logic
fail on data shapes that only occur in production — the late partition, the
duplicate delivery, the backfill overlapping a scheduled run — so they need a
pinned corpus containing those cases, not just a unit test on the happy path. See
[dbt-incremental-models](../DBT-INCREMENTAL-MODELS/SKILL.md) for what goes wrong.

## What each layer requires

**Layer 1** — no network, no production credentials, no shared state. Small explicit
fixtures. Cover empty input, nulls, duplicates, late data, invalid schema, boundary
dates and reruns. Assert grain and row accounting, not merely that the code
returned. Include negative tests for the states that must not happen.
[pytest-data-pipelines](../PYTEST-DATA-PIPELINES/SKILL.md) covers the mechanics.

**Layer 2** — run stage transitions with no external side effects. Simulate partial
failure, retry, resume and duplicate delivery. Verify every input reaches exactly
one accounted-for terminal state. Isolate queues, checkpoints and output paths from
production.

**Layer 3** — a small versioned corpus with known expected outcomes, covering each
important source variant and at least one failure case. The same corpus before and
after the change. Cap parallelism, scanned data and runtime; write to a dedicated
test location.

**A random sample is not a regression corpus.** If the input changes between runs,
a difference in output proves nothing, because you cannot tell the change from the
sample. Pinned and versioned is the entire point.

**Layer 4** — track attempted, succeeded, rejected, quarantined and failed counts by
meaningful slice over time, plus freshness, duration, cost and retry rates. Alert on
a documented deviation from a versioned baseline. An alert on an arbitrary threshold
with no owner gets muted within a month, which is worse than not having it.

**Layer 5** — one or a few pinned cases with an explicit expected outcome, through
the real deployment path, with least-privilege test data and isolated state. It
verifies environment-specific integration and nothing else.

**Never infer yield or correctness from a canary.** One run through the real path
proves the path works. It says nothing about whether the output is right for the
other million rows, and reading it as broad evidence is the most expensive mistake
on this list, because it happens at the point of highest confidence.

## Record the baseline before changing behavior

```json
{
  "version": "<code-or-config-version>",
  "corpus_version": "<pinned-corpus-version>",
  "schema_version": "<schema-version>",
  "metrics": {
    "input_count": 0,
    "success_count": 0,
    "rejected_count": 0,
    "failed_count": 0
  },
  "runtime_seconds": 0,
  "created_at": "<timestamp>"
}
```

Version it alongside the code, and state any delta you expect the change to cause
*before* running the comparison. A baseline captured after the change, or an
expected delta decided once the numbers are in, cannot fail.

## Execution

Run applicable layers in order, and diagnose a failure before launching a more
expensive layer — a layer 3 run started while layer 1 is red usually just
rediscovers the same defect at fifty times the cost.

Show the exact command before running it. Require confirmation for production
access, paid high-cost runs, and anything mutating shared state. Preserve logs and
metrics, not secrets or raw data dumps.

## The report

```markdown
## Regression gates: <change>

### Layers run
| Layer | Why required | Command | Result |
|-------|--------------|---------|--------|

### Baseline comparison
| Metric | Baseline | Current | Delta | Within threshold? |
|--------|----------|---------|-------|-------------------|

### Findings
| Severity | Finding | Evidence | Action |
|----------|---------|----------|--------|

### Verdict
<PASS | FAIL | INSUFFICIENT EVIDENCE>

### Skipped layers
- <layer>: <why it was not needed, or why it could not run>
```

The skipped-layers section is not paperwork. A required layer that was skipped
because the environment was unavailable is an accepted risk, and it needs someone's
name on it — never a silent `PASS`.
