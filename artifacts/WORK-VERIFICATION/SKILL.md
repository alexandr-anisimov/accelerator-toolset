---
name: work-verification
description: Confirming work is actually done before saying so - running the checks and reading the output, keeping passed/failed/skipped/never-run distinct, and reporting what was not verified.
---

# Verifying work before reporting it done

"Done" is a claim about reality. It is checkable, and the check is cheap compared to
what a false claim costs: the requester stops watching, the work moves downstream,
and the defect is found by someone with less context in a worse setting.

The rule this comes down to: **evidence before assertion.** Run the check, read the
output, then say what it showed. Never in the other order.

## The failure this prevents

It is rarely dishonesty. It is the ordinary sequence where the code looks right, the
change was small, the tests passed last time, and the report gets written from
expectation rather than observation. Every step is reasonable and the result is a
completion claim nobody verified.

Two specific patterns to watch for in your own reporting:

- **Assuming from the previous run.** The suite passed before the last three edits.
  That is not evidence about now.
- **Merging "did not fail" with "passed".** A suite that could not start did not
  fail. It also did not pass.

## What has to be observed

For each claim you are about to make, the corresponding observation:

| Claim | Requires |
|---|---|
| "Tests pass" | The suite run now, its output read, the count and result seen |
| "It builds" | The build run now, exit status seen |
| "Lint and types are clean" | Each tool run now, output read |
| "The bug is fixed" | The reproduction run: failing before, passing after |
| "Behaviour is unchanged" | The baseline comparison, against a record made before the change |
| "It works end to end" | The actual path exercised, not the units it is made of |
| "The requirement is met" | The original request re-read and compared to the result |

That last row is the one most often skipped, and it is where the expensive misses
happen. Everything can be green while the thing built is not the thing asked for.
Re-read the original request at the end, not only at the start.

## Read the output, not the exit code

An exit code is a summary and it can be wrong. Read what actually came back.

- How many tests ran? A suite that collected 3 tests instead of 300 "passes".
- Were any skipped? Skipped tests are frequently the ones covering your change.
- Did it run the code you changed, or a cached artifact, or a stale build?
- Are there warnings that indicate the check degraded — a config not found, a
  plugin failing to load, a file not matched?

A test command that matches no files exits successfully on several runners. So does
a linter with a broken configuration. Both look identical to success in a transcript
and neither checked anything.

## Keep the four outcomes distinct

Collapsing these is the core dishonesty, usually unintentional:

| Outcome | Meaning |
|---|---|
| **PASS** | Ran, and the result was correct |
| **FAIL** | Ran, and the result was wrong |
| **SKIPPED** | Deliberately not run, with a reason |
| **NOT RUN** | Could not run — missing dependency, no credentials, wrong environment |

`NOT RUN` is not a soft `PASS`. It is an absence of information, and it belongs in
the report as one. A reader who cannot tell "verified" from "unavailable" will treat
both as verified, which is precisely the wrong inference.

When a check could not run, say what stopped it. "Integration tests NOT RUN — require
database credentials not present in this environment" is useful; silence is not.

## Verify the requirement, not only the code

Green checks confirm the code does what the code does. They do not confirm it does
what was asked.

Go back to the original request and walk it point by point:

- Was every part addressed, or only the parts that were straightforward?
- Were any parts dropped or narrowed along the way? Was that stated?
- Do the edge cases mentioned in the request behave as described?
- Did anything that used to work stop working?

If part of the scope was not completed, that is reported explicitly — which part, and
why. Reporting overall success with a gap buried in the detail takes a decision that
belongs to the requester.

## Verify the environment matches the claim

Confirm you tested what you think you tested:

- The right branch and the right commit
- The changed code actually deployed or loaded, not a cached build
- The environment the claim is about — passing locally is not passing in CI
- No uncommitted edits that make it work on your machine only

```bash
git status                # nothing uncommitted that the check depended on
git log --oneline -1      # the commit the claim is about
```

## Reporting

State what was run, what it returned, and what was not covered.

```markdown
## Verification: <what>

### Checks
| Check | Command | Result |
|-------|---------|--------|
| Unit tests | `pytest tests/` | PASS - 214 passed, 0 failed, 3 skipped |
| Types | `mypy src/` | PASS - no issues |
| Integration | `pytest tests/integration/` | NOT RUN - no database credentials here |
| Reproduction | `pytest tests/test_sync.py::test_offset` | PASS - failed before the fix |

### Requirement
| Asked for | Status |
|-----------|--------|
| <each point of the request> | done / partial / not done |

### Not verified
- Integration path against a real database
- Behaviour under concurrent writes - not exercised by any test
```

The **Not verified** section is required and should rarely be empty. Something is
always outside what was checked, and naming it is what lets the reader judge how much
the rest is worth. An empty section asserts complete coverage, which is almost never
true.

Report the three skipped tests. Report the check that could not run. The small
inconvenience of an unclean report is the entire value of the report.

## Language that matches the evidence

Say what you observed:

```text
Not: "Everything works."
But: "214 unit tests pass; integration tests could not run here."

Not: "Fixed."
But: "The reproduction now passes and failed before the change. The same
      pattern appears in two other modules, which I have not checked."
```

Avoid hedging in the other direction too. When something has been verified, state it
plainly — "the suite passes" needs no softening. Unnecessary hedging on confirmed
results makes real uncertainty harder to spot.

## Guardrails

- Never state a check passed without having seen it pass, in this session, on this
  code.
- Never invent command output, test counts, timings or measurements.
- Never present `NOT RUN` or `SKIPPED` as a pass.
- Never report a task complete with a known gap left implicit.
- Do not let a green suite stand in for verifying the requirement.
- Do not verify only the parts that are easy to check.
- If a check is impossible in this environment, say so — and say what would be
  needed to run it.
