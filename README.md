# Accelerator Toolset

The artifact catalog. Consumers fetch selected artifacts from this repository using Git partial clone with cone-mode sparse checkout, so a client downloads only the artifacts it needs rather than the whole catalog.

The catalog holds twenty-eight artifacts in two groups. Eighteen are data-engineering specific, covering dbt, Snowflake, Airflow, Python pipeline code, and stack-agnostic pipeline quality practice. Ten are general skills that apply to any stack: change review, project documentation, test design, refactoring, error diagnosis, technical writing, and the four development-process artifacts covering requirements, planning, execution and verification. Every entry has real content; the `AS-SPIKE-*` placeholders that proved the transport design have all been removed.

Every artifact is currently `on-demand`, so a profile receives only what its declared topics select and the user explicitly chooses. There is no baseline set — see [`docs/authoring-artifacts.md`](docs/authoring-artifacts.md) for what an `always` artifact would have to justify.

Twenty-seven artifacts are `project` scope. `TECHNICAL-WRITING` is the single `user`-scope artifact: a personal editing tool that does not belong in a shared project plan.

## Layout

```text
index.json                      # catalog root — the only file fetched unconditionally
artifacts/
  AIRFLOW-DAG-CONVENTIONS/
    SKILL.md
    metadata.json
  CHANGE-REVIEW/
  DATA-INCIDENT-DEBUGGING/
  DBT-ERROR-DEBUGGING/
  DBT-INCREMENTAL-MODELS/
  DBT-MODEL-CREATION/
  DBT-MODEL-DOCUMENTATION/
  DBT-MODEL-REFACTORING/
  DBT-MODEL-TESTING/
  DBT-PROJECT-CONVENTIONS/
  DBT-SQL-MIGRATION/
  ERROR-DIAGNOSIS/
  ETL-DECOMPOSITION/
  IMPLEMENTATION-PLANNING/
  PIPELINE-OUTPUT-REVIEW/
  PIPELINE-REGRESSION-GATES/
  PLAN-EXECUTION/
  PROJECT-DOCUMENTATION/
  PYTEST-DATA-PIPELINES/
  REFACTORING-SAFETY/
  REQUIREMENTS-BRAINSTORMING/
  SCD2-IMPLEMENTATION/
  SNOWFLAKE-EXPENSIVE-QUERIES/
  SNOWFLAKE-QUERY-BY-ID/
  SNOWFLAKE-QUERY-TEXT/
  TECHNICAL-WRITING/
  TEST-DESIGN-REVIEW/
  WORK-VERIFICATION/
```

## `index.json`

```json
{
  "schema_version": "2",
  "toolset_ref": "refs/tags/v0.6.0",
  "vocabulary": {
    "languages": ["typescript", "javascript", "python", "csharp", "go", "sql"],
    "frameworks": ["nestjs", "react", "django", "aspnet", "airflow", "dbt", "duckdb", "spark", "trino", "snowflake", "databricks"],
    "layout": ["monorepo", "single"],
    "agents": ["claude-code"],
    "topics": [
      "code-review", "testing", "documentation", "refactoring",
      "orchestration", "data-modeling", "data-quality", "ingestion", "performance",
      "debugging", "writing", "development-process"
    ]
  },
  "artifacts": [
    {
      "id": "AIRFLOW-DAG-CONVENTIONS",
      "version": "0.1.0",
      "source_path": "artifacts/AIRFLOW-DAG-CONVENTIONS",
      "applies_to": { "frameworks": ["airflow"] },
      "strength": "on-demand",
      "topics": ["orchestration"],
      "scope": "project",
      "presentation": {
        "name": "Airflow DAG conventions",
        "summary": "Structures Airflow DAGs so nothing expensive or fragile runs at import time.",
        "benefits": [
          "Keeps connections and queries out of module scope, where the scheduler re-runs them",
          "Applies consistent default_args, retries and scheduling across DAGs",
          "Flags import-time work that makes the scheduler slow or unstable"
        ]
      }
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `schema_version` | Index format version. Currently `"2"` |
| `toolset_ref` | The ref this index describes |
| `vocabulary` | The closed set of legal values per dimension. Dimensions are exactly `languages`, `frameworks`, `layout`, `agents`, `topics` |
| `artifacts[].id` | Unique artifact identifier; matches the directory name. Unique case-insensitively, since ids become directory names |
| `artifacts[].version` | Artifact version |
| `artifacts[].source_path` | Repository-relative path to the artifact directory |
| `artifacts[].applies_to` | Which projects the artifact is applicable to. Required. `{}` means universally applicable and must be written explicitly |
| `artifacts[].strength` | `always` or `on-demand`. Required |
| `artifacts[].topics` | Intents that select an `on-demand` artifact. Must be non-empty when `strength` is `on-demand` |
| `artifacts[].scope` | Schema 2: `project` or `user`. User artifacts are personal and require explicit selection |
| `artifacts[].presentation` | Schema 2 `on-demand`: questionnaire card with non-empty `name`, `summary`, and `benefits` |
| `artifacts[].fixture` | `true` marks transport test data, exempt from all matching validation. Permitted only on `AS-SPIKE-*` ids |

Every value in `applies_to` and `topics` must appear in `vocabulary`. Comparison is case-sensitive: `TypeScript` does not match `typescript`.

`id`, `version`, and `source_path` are the transport inputs. The matching fields live in the index as well — not only inside the artifact — because a consumer doing a partial clone holds `index.json` alone at the moment it decides what to fetch. Reading matching metadata from inside artifact directories would require fetching every candidate's blobs before choosing which to fetch, which is the cost partial clone exists to avoid.

An artifact's `metadata.json` carries the same `applies_to`, `strength`, `topics`, `scope`, and `presentation` as its index entry. The two must agree; the index is authoritative for matching.

### Questionnaire-ready schema 2

This catalog is schema 2, the contract for hierarchical general-skill selection.
The validator still accepts schema 1 for previously published tags:

```json
{
  "id": "HUMANIZER",
  "scope": "user",
  "applies_to": {},
  "strength": "on-demand",
  "topics": ["documentation"],
  "presentation": {
    "name": "Humanizer",
    "summary": "Makes generated prose read naturally.",
    "benefits": ["Removes repetitive AI phrasing", "Preserves meaning"]
  }
}
```

Topics are broad discovery categories. The final consent is the exact artifact
id. `project` selections are shared; `user` selections remain a local overlay.
An `always` artifact cannot use user scope.

## The subtree contract

**One artifact is exactly one self-contained directory.** `source_path` must point at that directory, and the artifact must not depend on files outside it.

This is not a style preference. Cone-mode sparse checkout selects whole directories:

```bash
git sparse-checkout set artifacts/DBT-MODEL-CREATION artifacts/DBT-MODEL-TESTING
```

An artifact whose files are scattered across the repository cannot be selected this way. The alternative — non-cone mode with per-file patterns — was rejected as a production default because it forces the installer to enumerate every file of every artifact, coupling transport to internal artifact layout.

Breaking this contract does not fail loudly. The clone succeeds and the artifact arrives incomplete.

## Path rules

Every `source_path` and every path inside an artifact must satisfy all of the following. These were derived from cloning deliberately invalid trees on Windows; see the spike report for the observed failures.

| Rule | Why |
|---|---|
| Repository-relative only, `/` separators | Absolute paths and `\` do not survive the transport boundary |
| No `.` or `..` segments | Path traversal |
| No case-insensitive collisions (`Case.md` vs `case.md`) | On Windows the clone succeeds with a warning and **one file silently disappears** from the worktree |
| No Windows reserved device names (`CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `LPT1`–`LPT9`) | Checkout fails with `invalid path`, exit 128 |
| No trailing dot or trailing space | Checkout fails with `invalid path`, exit 128 |
| Maximum 240 characters | A 244-character path worked on the test machine only because `core.longpaths=true` was set. That must not be assumed of every developer |

The case-collision rule is the dangerous one: it is the only violation that produces a successful clone with missing content.

**None of these rules is machine-checked yet.** A validator in catalog CI is outstanding work — until it exists, this table is enforced by review alone.

## Fetching artifacts

```bash
# 1. Partial clone, no blobs, pinned to an immutable ref
git clone --depth 1 --branch <tag> --filter=blob:none --sparse -- <toolset-url> <dst>

# 2. Read index.json — it materializes with the initial checkout

# 3. Select the artifacts you need, by directory
git -C <dst> sparse-checkout set artifacts/DBT-MODEL-CREATION artifacts/DBT-MODEL-TESTING
```

Pin to a tag or commit SHA, never a moving branch. Unselected artifacts are absent from the local object store, not merely from the worktree — verified under `GIT_NO_LAZY_FETCH=1`. Reading a missing blob triggers a lazy fetch from the promisor remote.

Measured against a full shallow clone of the 50-artifact fixture set this catalog carried at the time: selecting 5 of 50 artifacts transferred ~91% less compressed pack payload. That measurement is historical — the 42 pure transport fixtures have since been removed — and it is kept because it is the number the transport design was justified on, not a description of the catalog's current size. Sparse selection is *slower* than a full clone at this scale because of the extra round trip — the benefit is disk and context, not speed.

## Licence

This catalog is MIT licensed — see [`LICENSE`](LICENSE). Artifacts adapted from
third-party sources carry their own upstream attribution in [`NOTICE`](NOTICE);
that file travels with any copy of this repository, as the upstream licences
require.

## Related

- Contributing — commit and branch conventions, the PR process, dev setup: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Third-party attribution for artifacts derived from external sources: [`NOTICE`](NOTICE)
- Adding an artifact — the `strength`, `applies_to`, and `topics` decisions, a worked example, and how to validate before pushing: [`docs/authoring-artifacts.md`](docs/authoring-artifacts.md)
- Using this catalog without the installer: see [Fetching artifacts](#fetching-artifacts) above. The transport is plain Git against a public repository, so no credentials and no additional tooling are required

The installer that consumes this catalog is distributed inside Innowise, and its
repository is not public. The following references resolve for internal readers
only:

- Transport evidence, measurements, and the GO verdict: `spikes/infra-transport/coder-infra-spike-report.md` in `accelerator-installation`
- Installer delivery and installation instructions: same repository

## Tags

| Tag | Contents |
|---|---|
| `v0.0.0-spike` | Initial fixture |
| `v0.0.1-spike` | Representative deterministic payloads — the ref all published measurements were taken against |
| `v0.1.0` | Matching vocabulary published; `AS-SPIKE-001`–`008` promoted to real catalog metadata |
| `v0.2.0` | First artifacts with real content (five, data-engineering); vocabulary gains `sql`, the tool frameworks and the data topics; transport fixtures `AS-SPIKE-009`–`050` removed |
| `v0.3.0` | Ten dbt and Snowflake artifacts adapted from a third-party MIT source (see [`NOTICE`](NOTICE)); vocabulary gains the `snowflake` and `databricks` frameworks and the `debugging` topic; line endings pinned by `.gitattributes` |
| `v0.4.0` | Remaining `AS-SPIKE-001`–`008` matching examples removed; the catalog is fifteen real artifacts, all `on-demand`. The `fixture` field and its validation are retained for future transport work |
| `v0.5.0` | Three stack-agnostic pipeline quality artifacts, adapted from internal team practice; the first artifacts declaring `applies_to: {}`, and the first content under the `code-review` topic |
| `v0.5.1` | No catalog content change. Adds `LICENSE` (MIT) and marks the internal-only references in `Related`, so the catalog can be published as a public repository |
| `v0.6.0` | `schema_version` moves to `2`: every artifact declares `scope`, and every `on-demand` artifact carries a questionnaire `presentation` card. The eighteen existing artifacts are migrated additively, with no `SKILL.md` changed. Ten general skills added — six stack-independent engineering skills and four covering the development process — taking the catalog to twenty-eight. `TECHNICAL-WRITING` is the first `user`-scope artifact. Vocabulary gains the `writing` and `development-process` topics |

Tags are immutable. A published tag is never moved to a different commit: a consumer profile pins one of these, and repointing it would hand the same profile different artifacts with nothing anywhere reporting a change. Corrections ship as a new tag.
