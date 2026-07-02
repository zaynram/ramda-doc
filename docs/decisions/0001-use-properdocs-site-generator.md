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

* freeform (nothing)
* `mkdocs` (ssg)
* `properdocs` (ssg)
* `zensical` (ssg)

## Decision Outcome

Chosen option: **`properdocs`** (ssg), because static site generation is the only practical approach for solo-maintenance and `mkdocs` has entered maintenance mode since March 2026, with `zensical` being a much younger candidate that does not have enough available at this stage to warrant adoption. Additionally selected is the **`mkdocstring`** plugin as it's compatible with all SSG candidates conaidered and is the only documentation generation plugin that is language agnostic.

### Consequences

* Good, because `properdocs` and `zeniscal` are succesors to the original `mkdocs` project and provide backwards-compatibility.
* Good, becase we can revisit `zeniscal` later down the line when the ecosystem has matured or the need otherwise arises.
* Bad, because ProperDocs has less momentum and less available support creating a longevity concern.

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
