---
name: change-review
description: Reviewing a code change - establishing intent first, then correctness, blast radius, compatibility and test coverage, with findings someone can act on.
---

# Reviewing a change

A review answers one question: **does this change do what it is supposed to do,
without breaking something else?** Everything below serves that question. Style
opinions, naming preferences and "I would have written it differently" do not, and
they crowd out the findings that matter.

This is the review of code. For reviewing the *data* a pipeline produced — row
accounting, drift against a baseline — see
[pipeline-output-review](../PIPELINE-OUTPUT-REVIEW/SKILL.md). The two are
complementary and neither substitutes for the other.

## Collect the inputs, and name the ones you did not get

- the diff, and the commit or branch it belongs to
- the stated intent: the issue, ticket, or description of what it should do
- the code around the change, not only the changed lines
- the callers of anything whose signature or behaviour moved
- the test suite, and whether it currently passes
- the project's own conventions, from neighbouring code

**The intent is not optional.** Without it there is no standard to review against,
and the review degrades into taste. If no description exists, say so and review only
what can be judged without it — internal consistency, obvious defects — and mark the
rest as unassessed. Do not infer an intent from the diff and then congratulate the
diff for matching it.

## Read the change three times

Once for what it claims to do. Once for what it actually does. Once for what it
touches that nobody mentioned.

The third pass is the one that finds real defects. A change to a shared helper is
small in the diff and large in effect; the diff shows you the helper, not the eleven
callers that now behave differently.

```bash
git diff --stat main...HEAD        # the shape of the change
git log -p --follow -- <file>      # how this file got here
```

## Correctness

Work through the change's own logic before anything else.

| Look for | Typical symptom |
|---|---|
| Boundary conditions | Empty collection, single element, zero, maximum, first and last iteration |
| Null and absent values | A value that is optional upstream treated as present here |
| Error paths | An exception caught and swallowed, or a failure that leaves state half-written |
| Concurrency and ordering | Shared state mutated without synchronisation; assumed ordering that is not guaranteed |
| Resource lifetime | A handle, connection or lock that is not released on the failure path |
| Off-by-one and inclusive/exclusive ranges | Slices, pagination, date windows |

The failure path deserves as much attention as the success path, and usually gets
less. Most code is written and tested along the path where everything works.

## Blast radius

Establish what depends on the changed code before judging whether the change is
safe.

```bash
git grep -n "functionName"          # direct references
git grep -n "ClassName"             # type references
```

`grep` finds direct callers. It does not find dynamic dispatch, reflection,
configuration-driven wiring, or calls from another repository. When a change
modifies something exported or public, the honest position is that the caller set is
**not fully known from this repository**, and the review says so rather than implying
it checked.

## Backward compatibility

This is where an approved change becomes an incident, because the diff looks correct
in isolation and the breakage is in a consumer nobody opened.

Check each of these that applies:

- **Function and method signatures.** A new required parameter breaks every caller.
  A new optional one with a default does not.
- **Return shapes.** A removed field breaks consumers that read it; an added field is
  usually safe, unless something validates strictly against a schema.
- **Public API and event payloads.** Consumers may be deployed separately and on a
  different release cycle.
- **Persisted data and schemas.** Old rows written by the previous version are still
  there. Code that assumes the new shape will meet them.
- **Configuration.** A renamed key silently falls back to a default in most config
  systems — no error, wrong behaviour.
- **Defaults.** Changing a default changes behaviour for everyone who never set it,
  which is usually most users.

If a break is necessary, the finding is not "do not do this" — it is "this breaks X,
and the change needs a migration path or a coordinated release".

## Test coverage

The question is not whether the diff added tests. It is **whether a test would fail
if this code were wrong.**

- Is the new behaviour covered, or only the code path exercised?
- Does the test assert the outcome, or only that nothing threw?
- Are the boundaries from the correctness pass tested, or only the typical case?
- If this is a bug fix, is there a test that fails without the fix? Without it,
  nothing stops the bug returning.
- Do the tests still test something after the change, or did an assertion get
  relaxed to make them pass?

That last one is worth checking explicitly. A weakened assertion and a genuine fix
produce the same green suite.

For designing the cases themselves, see
[test-design-review](../TEST-DESIGN-REVIEW/SKILL.md).

## Run what you can

Run the project's tests, linters and type checks against the change. Record the
exact commands and what they returned.

**Do not report a check as passing when you did not run it.** If the suite could not
run — missing dependencies, no credentials, wrong environment — that is `SKIPPED`
with a reason. A review that cannot distinguish "passed" from "never ran" is worse
than no review, because it carries authority it did not earn.

## Write findings someone can act on

Each finding needs three parts: **where**, **what goes wrong**, and **what would fix
it**. A finding without a concrete failure is an opinion.

```text
Weak:   "This error handling could be better."
Better: "src/sync.ts:88 - if writeBatch throws, the offset is already advanced,
         so the next run skips those records permanently. Advance the offset
         after the write succeeds."
```

Separate findings by severity, and be strict about the top category:

| Severity | Meaning |
|---|---|
| Blocking | Wrong results, data loss, a break for existing callers, or a security defect |
| Should fix | A real problem with a bounded cost of leaving it — merge is a judgement call |
| Consider | Genuine improvement, no defect. The author may decline it |

Anything that is purely preference belongs in `Consider` or nowhere. Marking taste
as blocking is how reviews stop being read.

## The report

```markdown
## Review: <change>

### Verdict
<APPROVE | APPROVE WITH COMMENTS | CHANGES REQUESTED | INSUFFICIENT EVIDENCE>

### Intent
<what the change is supposed to do, and where that came from>

### Checks
| Check | Result | Evidence |
|-------|--------|----------|
| Tests | PASS/FAIL/SKIPPED | command and outcome |
| Lint / types | PASS/FAIL/SKIPPED | |
| Manual reasoning through failure paths | done / partial | |

### Findings
| Severity | Location | Finding | Suggested fix |
|----------|----------|---------|---------------|

### Compatibility
- <breaking changes, or "none identified in this repository">

### Not verified
- <callers outside this repository, environments not available, paths not exercised>
```

`INSUFFICIENT EVIDENCE` is the honest verdict when the intent is unknown or the
tests could not run. Reaching for `APPROVE` because nothing looked obviously wrong
converts a review into a rubber stamp, and the next person will trust it.

## Guardrails

- Review the change that was made, not the change you would have made.
- A large diff is not automatically wrong, and a small diff is not automatically
  safe. Judge by blast radius, not line count.
- Do not invent a requirement to justify a finding. If the behaviour is merely
  surprising rather than incorrect, say that.
- Do not claim a defect you have not traced to a concrete failure. "This looks
  risky" without a mechanism wastes the author's time and dilutes the real findings.
- When you do not understand a piece of code, ask. An unasked question becomes an
  approval of code nobody reviewed.
