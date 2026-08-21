# Contributing

This covers how changes get made here: commit and branch conventions, the PR
process, and where to find everything else. It does not repeat what other
documents already own — follow the links instead of expecting a second copy.

- **Adding or changing an artifact** —
  [docs/authoring-artifacts.md](docs/authoring-artifacts.md).
- **Catalog schema, subtree contract, path rules, transport model** — the
  [README](README.md).

## Dev setup

This repository is JSON content plus PowerShell tooling — there is no CLI to
install. Clone it, install Pester once, and run the gate:

```powershell
Install-Module Pester -RequiredVersion 5.6.1 -Force -Scope CurrentUser

$result = ./scripts/validate-catalog.ps1 -IndexPath ./index.json
if (-not $result.IsValid) { throw "Catalog validation failed." }
Invoke-Pester -Path ./tests
```

## Commit messages

`type: lowercase description`, imperative mood, no trailing period. Types in
active use: `feat`, `docs`, `test`, `chore`, `ci`, `release`. Pick the one that
matches the change's actual nature.

## Branches

`type/slug`, e.g. `feat/dbt-snowflake-skills`. Use the same `type` values as
commits.

## Pull requests

- Work on a branch off `main`; never commit directly to `main`.
- Open a PR for review — don't push straight to `main` unless a maintainer
  explicitly asks for it.
- The gate above (validation + `Invoke-Pester -Path ./tests`) must pass before
  merge. CI (`.github/workflows/validate.yml`) runs the same two steps.
- For a new or changed artifact, manually verify the profile combinations that
  should select and exclude it — see the
  [checklist](docs/authoring-artifacts.md#checklist) in the authoring guide.
- Update the docs a change actually affects (README, authoring guide) in the
  same PR — don't leave them to drift.
- Commits are authored under your own git identity, with clear human-style
  messages. Don't add AI co-author trailers (`Co-Authored-By: Claude`/`Codex`/
  etc.) or "Generated with" lines, regardless of what wrote the change.
