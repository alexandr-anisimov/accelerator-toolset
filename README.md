# Accelerator Toolset

The artifact catalog. Consumers fetch selected artifacts from this repository using Git partial clone with cone-mode sparse checkout, so a client downloads only the artifacts it needs rather than the whole catalog.

**Most contents are still a transport fixture.** Of the 50 `AS-SPIKE-*` directories, `AS-SPIKE-009` through `AS-SPIKE-050` exist only to validate selective transport and are marked `"fixture": true`. `AS-SPIKE-001` through `AS-SPIKE-008` carry real matching metadata and are treated as catalog content; their payloads are still placeholders.

## Layout

```text
index.json                      # catalog root — the only file fetched unconditionally
artifacts/
  AS-SPIKE-001/
    SKILL.md
    metadata.json
    payload.txt
  ... AS-SPIKE-050/
```

## `index.json`

```json
{
  "schema_version": "1",
  "toolset_ref": "refs/tags/v0.0.1-spike",
  "vocabulary": {
    "languages": ["typescript", "javascript", "python", "csharp", "go"],
    "frameworks": ["nestjs", "react", "django", "aspnet"],
    "layout": ["monorepo", "single"],
    "agents": ["claude-code"],
    "topics": ["code-review", "testing", "documentation", "refactoring"]
  },
  "artifacts": [
    {
      "id": "AS-SPIKE-001",
      "version": "0.0.1",
      "source_path": "artifacts/AS-SPIKE-001",
      "applies_to": {},
      "strength": "always",
      "topics": []
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `schema_version` | Index format version. Currently `"1"` |
| `toolset_ref` | The ref this index describes |
| `vocabulary` | The closed set of legal values per dimension. Dimensions are exactly `languages`, `frameworks`, `layout`, `agents`, `topics` |
| `artifacts[].id` | Unique artifact identifier; matches the directory name. Unique case-insensitively, since ids become directory names |
| `artifacts[].version` | Artifact version |
| `artifacts[].source_path` | Repository-relative path to the artifact directory |
| `artifacts[].applies_to` | Which projects the artifact is applicable to. Required. `{}` means universally applicable and must be written explicitly |
| `artifacts[].strength` | `always` or `on-demand`. Required |
| `artifacts[].topics` | Intents that select an `on-demand` artifact. Must be non-empty when `strength` is `on-demand` |
| `artifacts[].fixture` | `true` marks transport test data, exempt from all matching validation. Permitted only on `AS-SPIKE-*` ids |

Every value in `applies_to` and `topics` must appear in `vocabulary`. Comparison is case-sensitive: `TypeScript` does not match `typescript`.

`id`, `version`, and `source_path` are the transport inputs. The matching fields live in the index as well — not only inside the artifact — because a consumer doing a partial clone holds `index.json` alone at the moment it decides what to fetch. Reading matching metadata from inside artifact directories would require fetching every candidate's blobs before choosing which to fetch, which is the cost partial clone exists to avoid.

An artifact's `metadata.json` carries the same `applies_to`, `strength`, and `topics` as its index entry. The two must agree; the index is authoritative for matching.

## The subtree contract

**One artifact is exactly one self-contained directory.** `source_path` must point at that directory, and the artifact must not depend on files outside it.

This is not a style preference. Cone-mode sparse checkout selects whole directories:

```bash
git sparse-checkout set artifacts/AS-SPIKE-001 artifacts/AS-SPIKE-002
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
git -C <dst> sparse-checkout set artifacts/AS-SPIKE-001 artifacts/AS-SPIKE-002
```

Pin to a tag or commit SHA, never a moving branch. Unselected artifacts are absent from the local object store, not merely from the worktree — verified under `GIT_NO_LAZY_FETCH=1`. Reading a missing blob triggers a lazy fetch from the promisor remote.

Measured against a full shallow clone of this fixture: selecting 5 of 50 artifacts transferred ~91% less compressed pack payload. Sparse selection is *slower* than a full clone at this scale because of the extra round trip — the benefit is disk and context, not speed.

## Related

- Adding an artifact — the `strength`, `applies_to`, and `topics` decisions, a worked example, and how to validate before pushing: [`docs/authoring-artifacts.md`](docs/authoring-artifacts.md)
- Transport evidence, measurements, and the GO verdict: `spikes/infra-transport/coder-infra-spike-report.md` in [`accelerator-installation`](https://github.com/alexandr-anisimov/accelerator-installation)
- Installer delivery and installation instructions: same repository

## Tags

| Tag | Contents |
|---|---|
| `v0.0.0-spike` | Initial fixture |
| `v0.0.1-spike` | Representative deterministic payloads — the ref all published measurements were taken against |
| `v0.1.0` | Matching vocabulary published; `AS-SPIKE-001`–`008` promoted to real catalog metadata |
