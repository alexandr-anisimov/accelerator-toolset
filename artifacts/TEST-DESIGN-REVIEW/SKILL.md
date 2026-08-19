---
name: test-design-review
description: Deciding what is worth testing and judging whether existing tests would catch a defect - deriving cases from behaviour, covering failure paths, and spotting tests that pass regardless of correctness.
---

# Designing and reviewing tests

Two questions, and they are the same question from opposite ends:

- **Designing:** what would have to be true for this code to be wrong, and what test
  would notice?
- **Reviewing:** if this code were wrong, would any of these tests fail?

A suite that answers "no" to the second is green, fast, and worth nothing. That is
the failure mode this guards against — not missing tests, which are at least
visible, but present tests that cannot fail.

This is framework-independent. For pytest mechanics in pipeline code see
[pytest-data-pipelines](../PYTEST-DATA-PIPELINES/SKILL.md); for dbt schema tests see
[dbt-model-testing](../DBT-MODEL-TESTING/SKILL.md); for choosing which *layer* of
check a pipeline change needs see
[pipeline-regression-gates](../PIPELINE-REGRESSION-GATES/SKILL.md).

## Start from behaviour, not from code shape

The common mistake is deriving tests from the implementation: one test per function,
one per branch, coverage as the target. That produces tests that mirror the code,
and tests that mirror the code cannot detect that the code is wrong — they were
written from the same misunderstanding.

Derive cases from **what the code is supposed to do**: the contract, the requirement,
the bug report. Then check the implementation for paths the contract did not
anticipate, and ask whether those paths should exist at all.

Coverage measures which lines ran. It does not measure whether anything was
asserted about them. Treat a coverage number as a way to find *untested* code, never
as evidence that tested code works.

## What to test, in priority order

1. **The contract.** The stated behaviour, on ordinary input. If nothing else is
   tested, this is.
2. **Boundaries.** Empty, one, many. Zero, negative, maximum. First and last
   element. The moment before and after a threshold. Defects cluster here more than
   anywhere else.
3. **Failure paths.** What happens when a dependency times out, returns an error,
   returns malformed data, or is slow. Most production incidents are here, and most
   suites test only the success path.
4. **Invariants.** Things that must hold across all inputs — a total that must
   reconcile, a state machine that must not skip a state, an operation that must be
   safe to retry.
5. **Regressions.** Every fixed bug gets a test that fails without the fix. This is
   the highest-value test in any suite and the easiest to skip.

Stop before testing the language, the framework, or a third-party library. A test
asserting that a mock returns what it was configured to return proves nothing about
your code.

## Tests that cannot fail

These pass whether or not the code is correct. Each is common enough to look for
explicitly when reviewing a suite.

| Pattern | Why it proves nothing |
|---|---|
| No assertion, only "it did not throw" | Any wrong-but-non-throwing result passes |
| Asserting on the mock, not the outcome | Confirms the test's own setup |
| Expected value computed by the code under test | Tautology: it always matches |
| `assert result is not None` as the whole check | Passes for every wrong non-null value |
| The mock replaces the logic being tested | The real behaviour never runs |
| Snapshot regenerated whenever it fails | The snapshot follows the bug |
| `try/except` swallowing the failure | Cannot fail by construction |
| Assertions loosened until the suite went green | Was a real test; is no longer |

The strongest check when reviewing: **change the implementation to something wrong,
and see whether the suite notices.** Invert a condition, return a constant, skip the
write. If everything still passes, the tests describe the code rather than
constraining it. This takes a minute and finds what reading cannot.

## What makes a test worth keeping

**One reason to fail.** When a test breaks, its name should be enough to know what
is wrong. A test that exercises six behaviours tells you only that something moved.

**Independent.** No dependence on execution order or on state another test left
behind. Ordering dependence surfaces as a failure that only reproduces in CI, which
is expensive to chase.

**Deterministic.** No real clock, no unseeded randomness, no network, no reliance on
timing. A flaky test is worse than no test: it trains everyone to re-run rather than
investigate, and it hides the real failure when it eventually arrives.

**Readable as a specification.** Arrange, act, assert — visibly separated. The
assertion should state the expected outcome literally rather than deriving it.

**Named for the behaviour.** `test_rejects_expired_token` tells you what broke;
`test_auth_2` does not.

## Deciding how much is enough

There is no universal number. Scale the depth to the cost of being wrong:

| Code | Depth |
|---|---|
| Money, permissions, data deletion, migrations | Contract, all boundaries, all failure paths, invariants |
| Core domain logic | Contract, boundaries, main failure paths |
| Glue and wiring | One integration test that the pieces connect |
| Generated or trivial delegation | Usually none |

Deliberately deciding not to test something is a legitimate outcome. Recording that
decision is what separates it from an oversight.

## When code resists testing

Difficulty testing is information about the code, not a reason to write a worse
test. The usual causes:

- I/O mixed into logic — the transform cannot run without a database
- Hidden dependencies constructed inside the function rather than passed in
- Global or static state carrying data between calls
- A function doing several things, so no single assertion describes success

The fix is the code, not an elaborate mock. Mocking heavily to test untestable code
produces a test coupled to the implementation, which then breaks on every refactor
while still not detecting defects. See
[refactoring-safety](../REFACTORING-SAFETY/SKILL.md) — though note the ordering
problem: refactoring safely wants tests first. Where both are missing, add a
coarse characterisation test at the outer boundary, refactor behind it, then write
the real tests.

## The report

When reviewing an existing suite:

```markdown
## Test review: <component or change>

### Verdict
<ADEQUATE | GAPS FOUND | INADEQUATE | INSUFFICIENT EVIDENCE>

### Ran
| Command | Result |
|---------|--------|
| <exact command> | PASS / FAIL / SKIPPED - reason |

### Coverage of behaviour
| Behaviour | Tested | Notes |
|-----------|--------|-------|
| <contract case> | yes / no / weakly | |
| <boundary> | | |
| <failure path> | | |

### Tests that would not catch a defect
| Test | Problem |
|------|---------|

### Gaps worth closing
| Priority | Missing case | Why it matters |
|----------|--------------|----------------|

### Not assessed
- <suites not run, environments unavailable, code not read>
```

Keep `PASS`, `FAIL`, `SKIPPED` and never-run distinct. A suite that could not run is
not a passing suite, and reporting it as one is the specific dishonesty this format
exists to prevent.

`INSUFFICIENT EVIDENCE` is correct when the suite could not be executed and the
tests were only read. Reading tests catches tautologies; it does not catch flakiness
or environment-dependent failures.

## Guardrails

- Never claim a test passes without having seen it pass.
- Never assert that untested code is broken, or that tested code is correct. Tests
  show the presence of behaviour, not the absence of defects.
- Do not invent a requirement in order to justify a missing test. If the intended
  behaviour is unknown, that is the finding.
- Do not propose deleting a test you do not understand. An odd-looking test is
  often a regression test for a bug that is not obvious from the code.
- Do not add tests purely to raise a coverage number.
