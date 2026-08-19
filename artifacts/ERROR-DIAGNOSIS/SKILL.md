---
name: error-diagnosis
description: Finding the cause of a failure systematically - reproducing it, narrowing the search space, testing falsifiable hypotheses, and proving the cause before changing any code.
---

# Diagnosing a failure

The expensive mistake in debugging is not being wrong about the cause. It is
**changing code before knowing the cause** — the symptom disappears, the defect
stays, and now there is an unexplained edit in the codebase that the next person
will be afraid to remove.

Diagnosis ends when you can explain every symptom. Not when the error stops
appearing.

For a dbt build that failed, see
[dbt-error-debugging](../DBT-ERROR-DEBUGGING/SKILL.md). For wrong data produced by a
pipeline that reported success, see
[data-incident-debugging](../DATA-INCIDENT-DEBUGGING/SKILL.md). This covers the
general case.

## Establish the facts before theorising

Collect these first. Guessing at any of them sends the whole investigation in a
direction it will not return from.

- The exact error text and full stack trace, copied rather than paraphrased
- What was expected, and what happened instead
- When it started, and what changed around then — deploy, config, data, dependency,
  infrastructure
- Whether it is universal or conditional: which environment, which user, which
  input, what proportion of requests
- Whether it ever worked, and the last known-good version
- What has already been tried, and what happened

**"It doesn't work" is not a symptom.** Get the specific observable. The difference
between "returns 500", "returns an empty list", and "hangs for 30 seconds" points at
three unrelated causes, and the wrong one costs hours.

## Reproduce it first

A reliable reproduction is worth more than any amount of code reading. It converts
every hypothesis into a cheap experiment, and it is the only way to know when the
defect is actually fixed.

Aim for the smallest reproduction that still fails: the fewest steps, the smallest
input, the least infrastructure. Reducing it *is* diagnosis — each element you remove
without the failure disappearing is a whole class of cause eliminated.

**If it does not reproduce, that is a finding, not a setback.** Something differs
between where it fails and where it does not: environment, configuration, data, load,
timing, permissions, version. Enumerate the differences and test them one at a time.
The difference is the lead.

For an intermittent failure, do not conclude "flaky" and move on. Intermittency
usually means timing, ordering, concurrency, resource exhaustion, or a dependence on
data that varies — all real defects, and all likely to reach production. Record the
frequency; it constrains the cause.

## Narrow before you dig

Bisect the search space rather than reading everything.

**In time**, when it used to work:

```bash
git log --oneline <last-good>..<first-bad>
git bisect start && git bisect bad && git bisect good <last-good>
```

`git bisect` is the highest-value tool available when a known-good version exists.
It answers "which change caused this" in a handful of steps regardless of repository
size. Use it before reading code.

**In space**, along the path from input to failure. Find a point in the middle and
determine whether the data is already wrong there. Correct at the midpoint means the
defect is downstream; wrong means upstream. Repeat.

**In configuration**, when it works in one environment and not another. Move one
difference at a time toward the failing setup until the failure appears. The variable
that flips it is the lead.

## Write hypotheses that can be killed

A hypothesis must be specific enough that one observation can rule it out.

```text
Weak:   "Something's wrong with the caching."
Strong: "The cache returns a stale entry because invalidation is keyed on
         user_id and this write changes a field keyed on tenant_id.
         Killed by: logging the cache key on write and on read - if they
         match, the hypothesis is wrong."
```

Write the kill condition **before** running the check. Deciding afterwards whether a
result supports the theory is how an investigation confirms whatever it started with
and stops looking.

Keep the ones you eliminated and why. Without that record, an investigation returns
to a dead theory two hours later because nobody remembers ruling it out.

Prefer hypotheses that are cheap to test and that eliminate a large space when
false. Test the most likely and the cheapest first — usually the same one, since the
most common causes are the recent change, the boundary condition, and the
environment difference.

## Read the evidence properly

**Read the whole stack trace, and start at the bottom.** The top frame is where the
error surfaced; the cause is usually further down. In wrapped exceptions the original
is at the innermost "caused by".

**The error location is not the defect location.** A null dereference is where the
null was *used*; the defect is wherever it was allowed to be null.

**Check your assumptions about what the code does.** Read the actual version that is
running, not the one on your branch, and confirm which version is deployed. A
surprising number of investigations are into code that is not executing.

**Distrust the error message when it does not fit.** Messages are written by people
who did not know this would happen. "Connection refused" can be DNS, a firewall, a
crashed process, or the wrong port.

**Add observation before adding changes.** Logging, a breakpoint, printing the value
at the boundary — these are reads. They tell you what is happening without altering
it. A speculative fix alters behaviour and destroys the reproduction you were
relying on.

## Confirm the cause before fixing

The cause is proven when all of these hold:

1. It explains **every** symptom, including the odd details. A cause that explains
   the main error but not why it only happens on Tuesdays is incomplete — the
   Tuesday detail is a clue, not noise.
2. It explains why it worked before, if it did.
3. You can **make the failure appear and disappear on demand** by manipulating the
   cause. This is the strongest available evidence.
4. The mechanism is traceable in the code, not just correlated with it.

If a symptom remains unexplained, keep going. Two defects at once is uncommon but
real, and it is exactly the case where a partial fix ships and the incident recurs.

## Then fix, and prove the fix

- Fix the cause, not the symptom. A retry around a call that fails deterministically
  is not a fix.
- Change one thing. If the failure persists, revert it before trying the next thing
  — accumulated speculative edits are how a small defect becomes an unreviewable diff.
- **Verify with the reproduction**: it must fail before and pass after. Anything else
  is a guess that happened to coincide with the symptom going away.
- Add a regression test that fails without the fix. Without it, nothing prevents the
  defect returning.
- Check whether the same defect exists elsewhere. Causes rarely occur once.

## The report

```markdown
## Diagnosis: <symptom>

### Symptom
- Observed: <exact error / behaviour>
- Conditions: <environment, input, frequency>
- Reproduction: <steps, or "not reproduced - see differences below">

### Cause
<the mechanism, traced to specific code>

### Evidence
| Hypothesis | Test | Result |
|------------|------|--------|
| <ruled out> | <what was checked> | eliminated: <why> |
| <confirmed> | <what was checked> | confirmed: <how> |

### Symptoms explained
- <each symptom, and how the cause accounts for it>

### Still unexplained
- <anything the cause does not account for>

### Fix
- <what changed, and why it addresses the cause>
- Verified: reproduction fails before, passes after
- Regression test: <name, or "none - why">

### Same defect elsewhere
- <other locations, or "checked, none found" / "not checked">
```

**"Still unexplained" is a required section.** An empty one is a claim that the cause
accounts for everything; a populated one is an honest handover. A report that quietly
drops the inconvenient symptom is how a partial fix gets treated as complete.

## Guardrails

- Do not change code before the cause is proven.
- Do not report a cause you have not confirmed by manipulating it, unless you say
  plainly that it is unconfirmed.
- Do not dismiss an intermittent failure as flaky without finding what varies.
- Do not stop at the first plausible explanation. Plausible is not proven.
- Do not silently drop a symptom that does not fit the theory.
- In a shared or production environment, prefer read-only observation, and confirm
  before running anything that mutates state.
- Never invent log output, timings, or results you did not observe. If a check could
  not be run, that is what the report says.
