# Authoring artifacts

How to add an artifact to this catalog and get its matching metadata right.

This is the task-shaped companion to [`README.md`](../README.md), which is the reference: the `index.json` field table, the one-artifact-one-subtree contract, the path rules, and how consumers fetch. Read it first. This guide does not repeat it — it covers the decisions you have to make and the ways they go wrong.

For a shipped artifact to copy from, read [`artifacts/ETL-DECOMPOSITION`](../artifacts/ETL-DECOMPOSITION) — one dimension, one topic, `on-demand`, which is the shape most artifacts should have.

## The five decisions

Everything else about an artifact is mechanical. These five determine whether anyone ever sees it.

Schema 2 adds two more authoring decisions for questionnaire-ready artifacts:
scope and the presentation card. This catalog is schema 2. Schema 1 remains
valid for previously published tags, and the validator still accepts it.

### 0. `scope` — team or personal

| Value | Stored and reproduced as |
|---|---|
| `project` | Reviewed project selection, shared with the team and CI |
| `user` | Local developer overlay, absent from CI |

Every schema 2 artifact declares one. A user artifact must be `on-demand`:
personal tools require explicit consent and cannot claim baseline installation.

### 1. `strength` — `always` or `on-demand`

| | Installed when |
|---|---|
| `always` | Every project that passes `applies_to`, whether or not anyone asked for it |
| `on-demand` | Only when the artifact's `topics` intersect what the team said they wanted |

**Default to `on-demand`.** `always` is a claim on every matching user's agent context, and the burden of proof is on you.

The test:

> Would a developer who never heard of this artifact be right to have it?

If the honest answer is "only if they're doing X", then X is a topic and this is `on-demand`. `always` is for baseline hygiene — the thing you would be annoyed to find missing on a project you had never seen before.

**Why this matters more than it looks.** The failure mode is ordinary and predictable. Every author believes their artifact is essential. Marking it `always` costs *you* nothing — it costs every downstream user a slice of context they did not ask for. Repeat that across authors and the baseline set grows until it is effectively the whole catalog. At that point nothing breaks: sparse checkout still works, the installer still reports success, and the ~91% transport saving quietly returns to zero. Nobody gets an error. That is exactly the "success with missing value" outcome this system is built to avoid, arriving from the other direction.

There is an agreed ceiling of **≤ 15 `always` artifacts per typical profile**. **Nothing enforces it.** The validator does not count `always` artifacts and will not complain at any number. Review is the only thing standing between the catalog and baseline bloat.

### 2. `applies_to` — which dimensions to declare

Every dimension you declare must intersect the profile. An omitted dimension means *"I do not care about this dimension"*.

So **declaring more dimensions makes your artifact narrower, not better described.** This is the instinct to fight. Writing

```json
"applies_to": {
  "languages": ["typescript"],
  "frameworks": ["nestjs"],
  "layout": ["monorepo"],
  "agents": ["claude-code"]
}
```

feels thorough. What it actually says is: *skip me unless the project is TypeScript **and** NestJS **and** a monorepo **and** using Claude Code.* Drop a dimension unless its absence would make the artifact wrong.

For a genuinely universal artifact, write it explicitly:

```json
"applies_to": {}
```

Absent is not the same as `{}`. Omitting the field is an error, so that "applies to everything" can never be confused with "the author forgot".

### 3. `topics` — which intents select it

Values come from the closed `topics` vocabulary published in `index.json`. An `on-demand` artifact with **no** topics can never be selected by any profile — it is dead content in the catalog. The validator rejects it outright; this is not a subtle bug you have to reason about.

An `always` artifact does not need topics. Write `"topics": []`.

In schema 2, topics are the broad questions used for progressive disclosure.
They decide which cards the user opens, not which complete category is installed.
The final selection stores exact artifact ids.

### 4. `presentation` — the informed-consent card

Every schema 2 `on-demand` artifact declares:

```json
"presentation": {
  "name": "Humanizer",
  "summary": "Makes generated prose read naturally.",
  "benefits": [
    "Removes repetitive AI phrasing",
    "Preserves meaning"
  ]
}
```

Keep the name and summary short. Benefits must be concrete outcomes the skill
actually provides. The questionnaire uses this object verbatim and never reads
`SKILL.md` to invent benefits. Empty cards, empty benefits, and scalar
`presentation` values fail validation.

## The current vocabulary

Taken from `index.json` at the time of writing. **`index.json` is the source of truth — check it rather than this table**, which goes stale the moment the vocabulary grows.

| Dimension | Values |
|---|---|
| `languages` | `typescript`, `javascript`, `python`, `csharp`, `go`, `sql` |
| `frameworks` | `nestjs`, `react`, `django`, `aspnet`, `airflow`, `dbt`, `duckdb`, `spark`, `trino` |
| `layout` | `monorepo`, `single` |
| `agents` | `claude-code` |
| `topics` | `code-review`, `testing`, `documentation`, `refactoring`, `orchestration`, `data-modeling`, `data-quality`, `ingestion`, `performance`, `debugging`, `writing`, `development-process` |

`frameworks` is the loosest of the dimensions: it holds anything that identifies the
stack beyond the language, so orchestrators (`airflow`), transformation tools (`dbt`)
and engines (`duckdb`, `spark`, `trino`) all live there. Calling dbt a "framework" is
a stretch, and the accurate name would be something like `tools`. Renaming a
*dimension* is the installer's half of the contract and moves `schema_version`, so
the loose name is kept deliberately rather than paid for with a schema bump.

A value not in the vocabulary is a CI failure. That is deliberate: the alternative is an artifact that passes review and then matches nothing forever, with no error anywhere.

## Hard rules

- **Comparison is case-sensitive**, for values and for dimension names. `TypeScript` does not match `typescript`, and `Languages` is not a dimension. Both fail CI. The vocabulary is lower-case throughout.
- **`applies_to` and `strength` are required.** `applies_to: {}` must be written explicitly.
- **`applies_to` must be an object.** `"applies_to": "typescript"` is rejected — a scalar has no dimensions to intersect, so the installer would treat the artifact as applying to every profile.
- **Ids must be unique case-insensitively.** They become directory names; on Windows and default macOS `AS-0001` and `as-0001` are one directory, and one artifact silently overwrites the other.
- **The index entry and the artifact's own `metadata.json` must agree.** The index is authoritative for matching — it is the only file a consumer holds when it decides what to fetch. **Nothing checks this agreement.** A `metadata.json` that disagrees with the index passes CI, and the index wins at install time.
- **Never set `fixture: true`.** It is only for the `AS-SPIKE-*` transport fixtures, and it exempts an artifact from *all* matching validation. On a real artifact it would silently hide it from every install. The validator rejects it on any non-`AS-SPIKE-*` id, which is the only reason a typo here is survivable.
- **One artifact is exactly one self-contained directory.** See [the subtree contract](../README.md#the-subtree-contract). Breaking it does not fail loudly — the clone succeeds and the artifact arrives incomplete.

## Worked example

Adding a TypeScript code-review convention artifact, end to end.

### The decisions, made first

**`strength`.** Apply the test: would a developer who never heard of this be right to have it? No — this is one team's review conventions, useful when someone is reviewing TypeScript and noise otherwise. "Only if they're doing code review" means code review is a topic. → **`on-demand`**.

**`applies_to`.** The conventions are about TypeScript syntax and idiom, so `languages: ["typescript"]` is load-bearing — on a Python project the artifact is wrong, not merely unhelpful. Everything else is not: the conventions hold in React and in NestJS, in a monorepo and in a single repo. Declaring those would narrow the artifact for no gain. → **`{"languages": ["typescript"]}`**, one dimension.

**`topics`.** `code-review`. Not `testing` — the artifact does not talk about tests, and claiming a topic you do not serve is how a team that asked for testing help gets handed something irrelevant. → **`["code-review"]`**.

### 1. The directory

One self-contained directory, named for the id:

```text
artifacts/TS-REVIEW-CONVENTIONS/
  SKILL.md
  metadata.json
```

Nothing outside this directory, no `..` paths, no case-colliding filenames. See [path rules](../README.md#path-rules).

### 2. `artifacts/TS-REVIEW-CONVENTIONS/SKILL.md`

The artifact's actual content — what gets loaded into the agent's context.

```markdown
---
name: ts-review-conventions
description: TypeScript code review conventions - what to flag and what to leave alone.
---

# TypeScript review conventions

## Flag these

- `any` in a signature. Prefer `unknown` plus a narrowing check at the boundary.
- A non-null assertion (`!`) outside a test. It moves a runtime failure away
  from the code that caused it.
- An exported function with an inferred return type. Inference is fine
  internally; on an export it makes the public shape change silently.

## Leave these alone

- Inferred types on locals and on non-exported helpers.
- `as const` on literal config objects.
```

### 3. `artifacts/TS-REVIEW-CONVENTIONS/metadata.json`

The same matching fields as the index entry. Copy them across exactly — nothing checks that you did.

```json
{
  "id": "TS-REVIEW-CONVENTIONS",
  "version": "0.1.0",
  "source_path": "artifacts/TS-REVIEW-CONVENTIONS",
  "applies_to": {
    "languages": ["typescript"]
  },
  "strength": "on-demand",
  "topics": ["code-review"]
}
```

### 4. The `index.json` entry

Appended to the `artifacts` list:

```json
{
  "id": "TS-REVIEW-CONVENTIONS",
  "version": "0.1.0",
  "source_path": "artifacts/TS-REVIEW-CONVENTIONS",
  "applies_to": {
    "languages": ["typescript"]
  },
  "strength": "on-demand",
  "topics": ["code-review"]
}
```

Who gets this artifact: a TypeScript project whose team asked for code-review help. Not a TypeScript project that asked only for testing help — `on-demand` means the topic has to be wanted. Not a Python project that asked for code-review help — the declared `languages` dimension has to intersect.

### A variant, for contrast

Had this been `always`:

```json
"strength": "always",
"topics": []
```

then every TypeScript project would get it, asked for or not. That is a defensible call for, say, a repository-wide safety convention that a developer would be right to have without knowing it existed. It is not defensible for one team's review taste. When in doubt, `on-demand` — a wrong `on-demand` is invisible, a wrong `always` is on everyone's context budget.

## Check your work before pushing

Both commands run in CI ([`.github/workflows/validate.yml`](../.github/workflows/validate.yml)). Run them locally first.

### The validator

```powershell
./scripts/validate-catalog.ps1 -IndexPath ./index.json
```

Passing looks like this — `IsValid: True` and an empty `Errors` list:

```text
IsValid       : True
Errors        : {}
ArtifactCount : 13
```

Failing prints each fault to the host as it is found *and* returns them in `Errors`. Every fault is collected, so one run shows you everything rather than one typo per push:

```text
ERROR: Artifact TS-REVIEW-CONVENTIONS declares 'TypeScript' in dimension 'languages', which is not in the catalog vocabulary. Allowed: typescript, javascript, python, csharp, go.

IsValid       : False
Errors        : {Artifact TS-REVIEW-CONVENTIONS declares 'TypeScript' in dimension 'languages', which is not in the catalog vocabulary. Allowed: typescript, javascript, python, csharp, go.}
ArtifactCount : 51
```

The script returns an object; it does not set a non-zero exit code by itself. Check `IsValid`, as CI does.

### The test suite

Pester 5.6.1, matching CI:

```powershell
Import-Module Pester -RequiredVersion 5.6.1

$configuration = New-PesterConfiguration
$configuration.Run.Path = './tests'
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'

Invoke-Pester -Configuration $configuration
```

Passing:

```text
Tests Passed: 34, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
```

The run prints a wall of `ERROR:` lines. That is expected — the suite feeds deliberately broken indexes to the validator and asserts it complains. Read the final tally, not the noise.

You only need this suite if you changed the validator. Adding an artifact does not require it, but it is cheap and it is what CI runs.

## Troubleshooting

Every message below is produced by [`scripts/validate-catalog.ps1`](../scripts/validate-catalog.ps1), prefixed `ERROR: ` on the host.

| Message | What it means |
|---|---|
| `Artifact <id> declares '<value>' in dimension '<dim>', which is not in the catalog vocabulary. Allowed: ...` | The value is not in `vocabulary.<dim>`. Usually wrong case (`TypeScript` for `typescript`) or a value that needs adding to the vocabulary first. |
| `Artifact <id> declares unknown dimension '<dim>'. Known dimensions: languages, frameworks, layout, agents, topics.` | The dimension *name* is wrong — often case (`Languages`) or an invented dimension (`databases`). Names are case-sensitive too. |
| `Artifact <id> declares dimension '<dim>', which the catalog vocabulary does not publish.` | A known dimension that this index's `vocabulary` block omits. The vocabulary is at fault, not your artifact. |
| `Artifact <id> declares topic '<topic>', which is not in the catalog vocabulary. Allowed: ...` | Topic not in `vocabulary.topics`. Case-sensitive: `Code-Review` fails. |
| `Artifact <id> declares topics, which the catalog vocabulary does not publish.` | The index has no `topics` in its `vocabulary` block at all. |
| `Artifact <id> is missing required field 'applies_to'. Write applies_to as {} for a universally applicable artifact.` | You omitted `applies_to`. Write `{}` if it really is universal. |
| `Artifact <id> declares applies_to as the scalar '<value>' rather than an object. Write applies_to as {} for a universally applicable artifact.` | `applies_to` is a string, number, or array. It must be a JSON object. |
| `Artifact <id> is missing required field 'strength'. Expected 'always' or 'on-demand'.` | You omitted `strength`. There is no default. |
| `Artifact <id> has unknown strength '<value>'. Expected 'always' or 'on-demand'.` | Typo, or an invented level. Only two exist, both lower-case. |
| `Artifact <id> is on-demand but declares no topics, so no profile could ever select it.` | `on-demand` with `topics: []`. Give it topics, or make it `always` if it truly is baseline. |
| `Artifact <id> declares fixture: true, but only AS-SPIKE-* artifacts may. ...` | You set `fixture: true`. Remove it — it is transport test data only. |
| `Catalog index declares '<a>' and '<b>', which collide on a case-insensitive filesystem. Artifact ids must be unique.` | Two ids differ only in case. They would become one directory. |
| `Catalog index at <path> contains an artifact with no id (at index <n>).` | An entry has no `id`, a blank `id`, or is a bare string. Counted from 0. |
| `Catalog artifact at index <n> is not an object. ...` | An entry is a number or other non-object. |
| `Catalog index schema_version '<v>' is not covered by this validator (supports '1, 2').` | The index declares a schema version this validator does not cover. |
| `Catalog index at <path> has no vocabulary block. ...` | The `vocabulary` block is missing. Nothing can be validated without it. |
| `Catalog index at <path> has no artifacts list. Write an empty list for a catalog with no artifacts.` | The `artifacts` key is absent. |

These three are thrown, not collected — they mean a broken invocation rather than bad catalog content, and there is nothing in the catalog to fix:

| Message | What it means |
|---|---|
| `Catalog index not found: <path>` | Wrong `-IndexPath`. |
| `Catalog index at <path> is not valid JSON: ...` | Malformed JSON — usually a trailing comma after the last artifact. |
| `Catalog index at <path> is empty.` | The file parsed to nothing. |

## What is not checked

Green CI does not mean a correct artifact. These are enforced by review alone.

| Not checked | What slips through |
|---|---|
| **The `always` ceiling** | The validator never counts `always` artifacts. An index with 20 extra universal `always` artifacts validates clean. The ≤ 15 per profile ceiling is a review judgement with no gate behind it. |
| **Index ↔ `metadata.json` agreement** | The validator never opens an artifact directory. A `metadata.json` saying `strength: always` under an index entry saying `on-demand` passes CI. The index wins at install time, so the artifact behaves as the index says and the file in the directory lies. |
| **`source_path` points at anything** | Never resolved against the filesystem. An entry whose `source_path` names a directory that does not exist validates clean; the failure surfaces at install as an empty checkout. |
| **The [path rules](../README.md#path-rules)** | Case collisions, reserved device names (`CON`, `NUL`, `COM1`…), trailing dots or spaces, `..` segments, the 240-character limit — none are machine-checked. The case-collision rule is the dangerous one: the clone *succeeds* and one file silently disappears from the worktree on Windows. |
| **The subtree contract** | Nothing verifies an artifact is self-contained. An artifact depending on a file outside its directory clones successfully and arrives incomplete. |
| **`SKILL.md` content** | Not read, not linted, not required to exist. |

The pattern across all six: the failure is silent. Nothing errors, the install reports success, and the content is wrong or missing. That is why review is the gate here and why this list is worth re-reading before you approve someone else's artifact.

## Checklist

- [ ] Directory under `artifacts/`, named for the id, self-contained
- [ ] Schema 2: `scope` is `project` or `user`; user scope is never `always`
- [ ] `strength` defaulted to `on-demand` unless you can defend `always` against the test
- [ ] `applies_to` declares only the dimensions that would make the artifact *wrong* if absent; `{}` written explicitly if universal
- [ ] `topics` non-empty if `on-demand`, all values from the vocabulary, all lower-case
- [ ] Schema 2 `on-demand`: presentation card has a short name, truthful summary and concrete benefits
- [ ] `metadata.json` matches the index entry field for field
- [ ] No `fixture: true`
- [ ] `./scripts/validate-catalog.ps1 -IndexPath ./index.json` reports `IsValid: True`
