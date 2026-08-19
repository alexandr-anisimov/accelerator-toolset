---
name: technical-writing
description: Editing technical prose without changing what it says - cutting padding, keeping terminology exact, and flagging unclear meaning instead of guessing at it.
---

# Editing technical prose

The job is to make a technical text easier to read **while it continues to say
exactly what it said before**. Those two goals conflict more often than they look,
and when they do, meaning wins. A clearer sentence that is now slightly wrong is a
worse outcome than the awkward sentence it replaced.

This applies to READMEs, design documents, commit messages, pull request
descriptions, comments, error messages and release notes.

## The one rule

**Do not change technical content while editing style.**

Preserve exactly:

- Defined terms, and their capitalisation. If the document says `Job`, meaning a
  specific entity, it does not become "task" for variety.
- Identifiers, commands, flags, paths, versions, numbers, units.
- Qualifiers and hedges. "usually", "in most cases", "should" and "must" carry
  meaning in technical writing. Removing "usually" for tightness turns a
  qualified claim into an absolute one.
- The strength of a claim. "can cause data loss" is not "causes data loss".
- Conditions and scope. "on Linux" attached to a statement is not decoration.

If an edit requires deciding what the author meant, that is not an edit. See
[flag rather than guess](#flag-rather-than-guess).

## Cut what carries no information

Most technical prose gets shorter without losing anything. What goes first:

| Pattern | Example | Fix |
|---|---|---|
| Throat-clearing openers | "It is important to note that the cache expires after 5 minutes." | "The cache expires after 5 minutes." |
| Meta-commentary | "In this section, we will discuss the retry logic." | Delete. The heading already said it. |
| Empty intensifiers | "very fast", "quite significant", "extremely simple" | Delete the modifier, or give the number. |
| Stacked qualifiers | "It may potentially be possible that..." | "It may..." — one hedge, not three. |
| Nominalisation | "perform a validation of the input" | "validate the input" |
| Passive with a hidden actor | "The config is loaded at startup." | "The server loads the config at startup." — when who does it matters. |
| Filler transitions | "That being said," "At the end of the day," | Delete, or use a real connective. |

Passive voice is not banned. "The row is deleted after 30 days" is fine when the
actor is irrelevant or unknown. It is a problem only when the reader needs to know
who acts, and the sentence hides it.

## Fix what makes a reader re-read

Length is a symptom. These are the causes:

**A sentence carrying three ideas.** Split it. Technical readers scan; a sentence
with two subordinate clauses forces a second pass.

**The subject arriving late.** Put the actor at the front. "After the migration
completes and the health check passes, the router begins sending traffic" is
readable; the same content with four leading clauses is not.

**Undefined terms used before they are introduced.** Either define at first use or
move the definition earlier.

**Inconsistent naming for one thing.** "worker", "consumer", "processor" for the
same component makes a reader wonder whether they are three things. Pick the one the
code uses and use only that. This is the most common real defect in technical prose,
and it looks like harmless variety.

**Structure that does not match the content.** A procedure written as a paragraph
should be a numbered list. A comparison across three options should be a table. A
list of unordered facts should not be numbered, because numbering implies sequence.

## Remove machine-sounding phrasing

Text that reads as generated has recognisable tics. They are worth removing even
when the text was written by a person, because they add length and say nothing:

- Opening with a restatement of the question or heading
- Closing with a summary of what was just said, in a document short enough not to
  need one
- Three-item lists where the third item is filler ("fast, reliable, and scalable")
- Symmetrical hedging on both sides of every claim
- "It's not just X, it's Y" constructions
- Elaborate transitions between adjacent short paragraphs
- Sentences whose subject is an abstraction doing something active: "This approach
  enables teams to leverage..."
- Uniform paragraph length across an entire document

The replacement is how an engineer would say it to another engineer: the fact,
the condition it holds under, and the consequence.

## Flag rather than guess

When a sentence has more than one plausible reading, **do not pick one**. An editor
who resolves ambiguity by choosing is writing new technical content under the cover
of style work, and the author will not notice the change because the text got
better.

```text
Original: "The service retries failed requests up to three times before
           the timeout."

Ambiguous: three retries total, or three per attempt? Is the timeout per
           request or for the whole sequence?

Correct action: leave the sentence, add a note asking which is meant.
```

Flag, rather than rewrite:

- Sentences with two readings that imply different behaviour
- Claims that contradict something else in the same document
- Numbers, units or versions that look wrong
- References to things that do not appear elsewhere in the document
- Statements you believe are false

Report these as questions, not as edits. "Is this per attempt or in total?" is
useful. Silently choosing "in total" is a defect you introduced.

## The output

Return the edited text plus a short account of what changed:

```markdown
### Edited text
<the full text>

### Changes
- Cut ~30% padding: filler openers, stacked hedges, empty intensifiers.
- Split four sentences carrying multiple clauses.
- Standardised "worker" (was: worker/consumer/processor).
- Converted the setup steps to a numbered list.

### Preserved deliberately
- "should" in the retry section — kept as a qualified requirement.
- All command examples and version numbers, unchanged.

### Questions for the author
- "up to three times before the timeout" — per attempt or in total?
- The rate limit is 100/s here and 1000/s in the API section. Which is right?
```

The last two sections are not optional garnish. **Preserved deliberately** tells the
author you noticed something odd and left it alone on purpose, which stops them
"fixing" it back. **Questions** is where meaning-level problems go, and it is the
most valuable part of the output.

If the text needs no edits, say so. Rewriting good prose to demonstrate effort makes
it worse and wastes the author's review.

## Guardrails

- Never change a number, identifier, version or command.
- Never strengthen or weaken a claim to make a sentence cleaner.
- Never resolve an ambiguity by choosing — flag it.
- Never add information the source did not contain, including examples, reasons or
  caveats that seem obviously true.
- Never remove a qualifier because it reads as clutter. In technical writing it is
  usually load-bearing.
- Match the document's existing register. A terse internal runbook should not be
  edited into polished marketing prose.
- Keep the author's voice. The goal is their text, clearer — not your text.
