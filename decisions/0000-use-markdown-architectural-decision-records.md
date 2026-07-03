---
title: Use MADR
status: accepted
date: 2026-07-02
decision-makers: [{ name: Zayn Ramdass, email: ramdasszayn@gmail.com }]
consulted: [claude-sonnet-5, claude-fable-5]
---

## Context and Problem Statement

We want to record architectural decisions made in this project independent whether decisions concern the architecture ("architectural decision record"), the code, or other fields.
Which format and structure should these records follow?

## Considered Options

* [MADR](https://adr.github.io/madr/) 4.0.0 – The Markdown Architectural Decision Records
* [Michael Nygard's template](http://thinkrelevance.com/blog/2011/11/15/documenting-architecture-decisions) – The first incarnation of the term "ADR"
* [Sustainable Architectural Decisions](https://www.infoq.com/articles/sustainable-architectural-design-decisions) – The Y-Statements
* Other templates listed at <https://github.com/joelparkerhenderson/architecture_decision_record>
* Formless – No conventions for file format and structure

## Decision Outcome

Chosen option: "MADR 4.0.0", because

* Implicit assumptions should be made explicit.
  Design documentation is important to enable people understanding the decisions later on.
  See also ["A rational design process: How and why to fake it"](https://doi.org/10.1109/TSE.1986.6312940).
* MADR allows for structured capturing of any decision.
* The MADR format is lean and fits our development style.
* The MADR structure is comprehensible and facilitates usage & maintenance.
* The MADR project is vivid.

---

## Amendments

### 2026-07-02: Record Immutability

An ADR is frozen upon merging to `main` with `status: accepted`.
After freezing, the record may only change by:

* a superseding ADR (status transition to `superseded by ADR-XXXX`), or
* an explicit override: a commit whose message contains `[adr-amend]`,
  reserved for corrections that do not alter the decision or its rationale.

Enforcement: a committed git hook (activated via `core.hooksPath`,
see setup script) blocks commits modifying accepted records absent the
override token. Files carrying a `.draft.md` suffix are exempt (mutable phase).
