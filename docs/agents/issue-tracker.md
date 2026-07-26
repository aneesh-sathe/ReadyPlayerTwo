# Issue tracker: GitHub

Issues and PRDs for this repository live as GitHub issues in `aneesh-sathe/ReadyPlayerTwo`.

Use the connected GitHub app for issue reads and writes. The local `gh` CLI is a fallback after its authentication is repaired.

## Conventions

- Create PRDs and implementation work as GitHub issues.
- Apply `ready-for-agent` when an issue is fully specified and can be completed without additional human context.
- Publish implementation issues in dependency order so later issues can reference real blocker numbers.
- Do not close or rewrite a parent PRD issue when creating or completing child issues.
- Close an implementation issue only after its acceptance criteria pass and its atomic commit exists.

## Pull requests as a request surface

External pull requests are not a triage request surface.
