---
status: accepted
edited: 2026-07-02
decided_by: Zayn Ramdass
consulted: claude-sonnet-5
---

# Use ProperDocs SSG

## Context and Problem Statement

We want the documentation to be accessible to external audiences independent whether they have a technical background without a high maintenance cost. What strategy and/or existing implementation should we adopt?

## Decision Drivers

* non-technical persons are seldom comfortable on the commandline
* cost of dual-maintenance across documentation in and out of code
* there is only a single maintainer responsible for all documentation
* the variety in our codebase language requires polyglot compatibility

## Considered Options

* nothing (no accessible layer)
* manually authored (i.e. GitBook, Notion, etc.)
* `mkdocs` (ssg)
* `properdocs` (ssg)
* `zensical` (ssg)

## Decision Outcome

Chosen option: **`properdocs`** (ssg), because static site generation is the only practical approach for solo-maintenance compared to manual authoring and `zensical` is a much younger candidate that does not have enough available at this stage to warrant adoption. The original `mkdocs` team has fractured after disagreements over the future of the project, so it was dropped from consideration due to the need for active maintenance.

### Consequences

* Good, because `properdocs` and `zeniscal` are tied to the original `mkdocs` project and provide at least some degree of backwards-compatibility.
* Good, becase we can reconsider `zeniscal` later down the line when the ecosystem has matured or the need otherwise arises.
* Bad, because `properdocs` has less momentum and less active support creating a longevity concern.

### Confirmation

Configuration file (`properdocs.yml`) exists at project root.

The `scripts` property in `package.json` contains these entries:

```json
{
  "build": "properdocs build",
  "publish": "properdocs gh-deploy",
  "serve": "properdocs serve"
}
```
