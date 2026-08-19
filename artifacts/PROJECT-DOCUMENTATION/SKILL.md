---
name: project-documentation
description: Documenting a project at the level code cannot explain itself - decisions and their reasons, component boundaries, non-obvious constraints, and keeping all three true as the code changes.
---

# Documenting a project

Code states what the system does. It cannot state why it does it that way, which
alternatives were rejected, or which constraint makes an obvious-looking improvement
wrong. That gap is what project documentation is for, and nothing else fills it —
not comments, not tests, not commit messages that nobody reads two years later.

The failure this prevents is specific and expensive: someone deletes a workaround
because it looks unnecessary, and rediscovers the reason for it in production.

For column-level documentation inside a dbt project, see
[dbt-model-documentation](../DBT-MODEL-DOCUMENTATION/SKILL.md). This covers the
project level, in any stack.

## Write only what the code cannot say

The test before writing anything: **would a competent reader with the repository
open already know this?**

If yes, do not write it. Documentation that restates the code is worse than no
documentation — it takes the place where the useful sentence would have gone, it
makes coverage look complete, and it goes stale first, because it tracks details
that change most often.

```markdown
The UserService class has methods for creating, updating and deleting users.
```

That sentence costs maintenance and returns nothing. This one does not:

```markdown
User deletion is a soft delete. Hard deletes break the audit export, which
joins on user_id and is a regulatory requirement, so rows are never removed.
```

## Three things worth documenting

Almost everything valuable falls into one of these.

### 1. Decisions and their reasons

Not what was chosen — that is visible — but **why, and what was rejected.** The
reasons are what a future reader needs in order to know whether the decision still
holds.

Record a decision when it was hard to make, expensive to reverse, or when the
choice looks arbitrary from outside. Skip the ones with no real alternative.

A decision record is short. The format matters less than the four parts:

```markdown
# Sessions are stored in Redis, not in the database

**Status:** Accepted · 2026-03-14 · supersedes nothing

## Context
Sessions are read on nearly every request and written on most. The primary
database was already the throughput bottleneck at peak.

## Decision
Session state goes in Redis with a 24h TTL. The database holds no session rows.

## Consequences
Sessions do not survive a Redis flush; users are logged out. We accepted that
over adding read load to the primary. Anything needing durable per-user state
must not be put in the session — use the users table.

## Alternatives considered
- Database sessions: simplest, rejected on measured read load.
- Signed cookies: no server state, rejected because we need server-side
  revocation for the security requirement.
```

The **Alternatives considered** section is the part most often skipped and most
often needed. Without it, the next person re-proposes the rejected option, and
nobody remembers why it was rejected.

Keep records immutable. When a decision changes, write a new record and mark the old
one `Superseded by <id>`. Editing history to match the present destroys the reason
the record existed.

### 2. Component boundaries

For each significant component, state what it owns, what it exposes, what it depends
on, and — the load-bearing one — **what it deliberately does not do**.

```markdown
## Billing

Owns: subscription state, invoice generation, payment retries.
Exposes: `POST /billing/subscriptions`, `billing.invoice.created` event.
Depends on: Stripe API, users service (read-only, for email).

Does NOT own: pricing rules. Those live in the catalogue service, because
sales changes prices without a deploy. Billing reads a price by id and never
computes one.
```

That last paragraph is what stops the boundary eroding. A boundary with no stated
exclusions gets a little more logic each quarter until it owns everything.

Where a diagram helps, keep it in text (Mermaid, or ASCII) so it lives in the
repository and changes in the same commit as the code. A diagram in a separate tool
is stale within a release.

### 3. Non-obvious constraints

The ones that produce bugs when violated by someone who did not know:

- Ordering that must hold, and what breaks when it does not
- Idempotency requirements, and which operations are safe to retry
- Timeouts, rate limits and quotas imposed by something external
- Data that cannot be deleted, and the legal or audit reason
- Assumptions about scale — what was designed for what volume
- Anything that looks like dead code but is called by a scheduler, a webhook, or
  another repository

Put each constraint where the person about to violate it will be, not only in a
central document. A constraint that governs one module belongs next to that module
as well.

## Structure it so it is findable

Documentation that exists but is not found is documentation that does not exist.

```text
README.md                    what this is, how to run it, where to go next
docs/architecture.md         components, boundaries, how they communicate
docs/decisions/0001-*.md     one file per decision, numbered, immutable
docs/runbooks/*.md           what to do when a specific thing breaks
```

Match the project's existing layout before introducing a new one. Two competing
documentation structures are worse than one imperfect structure.

The README is the entry point and the most-read file by a wide margin. It should
answer, in the first screen: what this system does, how to run it locally, how to
run the tests, and where the deeper documentation lives.

## Keep it true

Documentation decays silently. Nothing fails when a document becomes wrong, and
wrong documentation is more expensive than absent documentation because it is
trusted.

The only mechanism that works reliably: **when a change invalidates a document, the
document changes in the same commit.** Not in a follow-up ticket, which does not get
done.

Treat these as documentation-affecting by default:

| Change | Update |
|---|---|
| New component, or one removed | Architecture, boundaries |
| Public API or event payload | Boundary contract, README if it is the main interface |
| A decision reversed | New decision record superseding the old |
| New external dependency or quota | Constraints |
| Setup or run steps changed | README |

When you find a document that is already wrong, fix it or delete it. Leaving a
statement you know to be false, on the grounds that it was not your change, is how
a documentation set becomes untrusted — and once it is untrusted, nobody reads any
of it, including the correct parts.

## Handling what you do not know

You will document systems whose history you do not have. State the uncertainty
rather than resolving it:

```markdown
The retry limit is 3. The reason for 3 specifically is not recorded;
it predates this repository's history. Do not treat it as tuned.
```

**Never invent a rationale.** A plausible reason written with confidence is worse
than an admitted gap, because it will be cited as authoritative by the next reader
and will foreclose a legitimate change. If the reason is unknown, "unknown" is the
correct and useful content.

The same applies to constraints you suspect but have not confirmed. Write "believed
to be required by the export job — unverified" rather than stating it flatly.

## Anti-patterns

- Restating the code in prose
- A decision record with no alternatives and no consequences
- Component descriptions with no stated exclusions
- Architecture diagrams maintained outside the repository
- A README that describes the vision and not how to run the thing
- Documenting every module uniformly instead of the parts where a reader could be
  confidently wrong
- Fabricating the reason behind a decision nobody recorded
- Leaving known-false statements in place because fixing them was not in scope
