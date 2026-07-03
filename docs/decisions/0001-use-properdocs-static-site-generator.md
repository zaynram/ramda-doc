---
title: Use ProperDocs (SSG)
status: accepted
date: 2026-07-02
decision-makers: [{ name: Zayn Ramdass, email: ramdasszayn@gmail.com }]
consulted: [claude-sonnet-5, claude-fable-5]
---

## Context and Problem Statement

We want the documentation to be accessible to external audiences independent of whether they have a technical background without a high maintenance cost. What strategy and/or existing implementation should we adopt?

## Decision Drivers

* audiences need a rendered/browsable edition of codebase documentation
* repository files are not an accessible reading surface
* cost of maintaining documentation synchronization across two platforms
* a single maintainer bears responsibility for all documentation and ports

## Considered Options

* Nothing - No accessible layer to documentation
* Manually authored - Standalone accessible layer authored separately
* [`properdocs`](https://properdocs.org/) ==1.6.7 - Static site generator candidate
* [`mkdocs`](https://www.mkdocs.org) ==1.6.1 - Static site generator candidate
* [`zensical`](https://zensical.org/) >=0.0.46,<0.50.0 - Static site generator candidate

## Decision Outcome

---

Chosen option: **`properdocs`** (ssg), because a static site generator is the only option that provides an accessible layer without introducing dual-maintenance and `zensical` is a much younger candidate that does not have enough available at this stage to warrant adoption. Removed from consideration is the original `mkdocs` per its [option analysis](#mkdocs-ssg).

### Consequences

* Good, because `properdocs` originates from the original `mkdocs` project and preserves the inherited plugin API.
* Good, because `zensical` does not preserve the mkdocs plugin API, whereas `properdocs` functions as a drop-in replacement.
* Good, because we can reconsider `zensical` upon satisfaction of any of the established [criteria](#revisitation-criteria-zensical).
* Bad, because `properdocs` has less momentum and less active support than `zensical`, potentially creating a longevity concern.

### Confirmation

#### Wiring

Configuration file (`properdocs.yml`) exists at project root.

The `scripts` property in `package.json` contains these entries:

```json
{
  "build": "properdocs build",
  "publish": "properdocs gh-deploy",
  "serve": "properdocs serve"
}
```

#### Function

[![build](https://github.com/zaynram/ramda-doc/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/zaynram/ramda-doc/actions/workflows/build.yml)
[![pages-build-deployment](https://github.com/zaynram/ramda-doc/actions/workflows/pages/pages-build-deployment/badge.svg?branch=gh-pages)](https://github.com/zaynram/ramda-doc/actions/workflows/pages/pages-build-deployment)

The `build` workflow runs `properdocs build --strict` against `main` on every
push, confirming the site builds from current sources. The pages workflow
confirms the published site deployed. Together they cover build integrity
and publication; neither alone does.

## Pros and Cons of the Options

---

### Nothing

Refrain from implementing an accessible layer to the codebase documentation.

* Good, because has the lowest complexity of any option (default).
* Good, because does not rely on any external implementation or maintenance.
* Neutral, because it does not prescribe a structural contract to codebase documentation.
* Bad, because the codebase documentation remains inaccessible to non-technical individuals.

### Manually Authored

Maintain an accessible port of codebase documentation with synchronization managed manually (e.g. [GitBook](https://www.gitbook.com/), [Notion](https://www.notion.com/)).

* Good, because maintains a clear separation of concerns. Documentation originates in the codebase before it's published to the accessible port.
* Good, because decoupling frees the published layer from source-format constraints (content fitted to platform strengths).
* Neutral, because it does not require a custom implementation or configuration through a command line (no added complexity).
* Bad, because there are two documentation bases to maintain and introduces possibility of desynchronization.

### ProperDocs (SSG)

Use `properdocs` as a static site generator to create an accessible documentation layer from the existing codebase source material.

* Good, because it does not require extra documentation authoring to relay the same information.
* Good, because it inherits the full `mkdocs` ecosystem (plugins, themes, documentation) via drop-in compatibility.
* Neutral, because static site generation has stricter source material and organizational requirements to ensure build compatibility.
* Bad, because it relies on external implementations and maintenance.

### MkDocs (SSG)

Use `mkdocs` as a static site generator to create an accessible documentation layer from the existing codebase source material.

* Good, because it's the long-standing industry standard with a robust ecosystem.
* Bad, because it has been effectively unmaintained since mid-2024; the March 2026 governance rupture removed any realistic prospect of revival.

### Zensical (SSG)

Use `zensical` as a static site generator to create an accessible documentation layer from the existing codebase source material.

* Good, because it's the most promising candidate as the long-term replacement for `mkdocs` as the industry standard.
* Bad, because it does not maintain full `mkdocs` plugin API compatibility and currently only commits to supporting a limited set of `mkdocs` plugins.

## More Information

---

* `pipx` manages the local `properdocs` installation

### Revisitation Criteria (`zensical`)

* `properdocs` goes 6+ months without a substantive release
* a plugin we depend on drops `properdocs` support
* `zensical` reaches plugin-API parity for our plugin set

