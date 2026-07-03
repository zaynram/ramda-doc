---
title: ADR Drafting Protocol
status: draft
date: 2026-07-02
applies-to: docs/decisions/*.md
---

## Purpose

A delegation plan for drafting Architectural Decision Records. Each step is a bounded
task with explicit subtask ownership, an exit gate, and a defined artifact. The protocol
governs the mutable phase of an ADR's lifecycle only; after the freeze event (see
ADR-0000 amendments), changes require a superseding record.

## Ownership Classes

| Tag   | Class     | Definition |
|-------|-----------|------------|
| `[M]` | Manual    | Human-only. Decision authority, commitments, and final sign-off. Non-delegable. |
| `[X]` | Augmented | Collaborative. Human supplies intent and context; LLM probes, structures, and challenges. Either party may originate; the human disposes. |
| `[A]` | Automated | LLM-only. Mechanical, verifiable, or generative work reviewed only at the gate. Claimed capabilities require demonstration, not assertion. |

Delegation rationale mirrors the documentation-system plan: tasks are `[M]` when they
carry switching cost or commitment, `[A]` when they are mechanical and checkable, and
`[X]` when correctness depends on context only the human holds.

---

## Step 0 - Scope Declaration

**Goal:** one sentence of the form "This ADR decides X and nothing else."
Everything downstream tests against this sentence.

| #   | Subtask                                                                                                           | Owner |
|-----|-------------------------------------------------------------------------------------------------------------------|-------|
| 0.1 | Write the scope sentence                                                                                          | `[M]` |
| 0.2 | Adversarial scope challenge: does the sentence smuggle a second decision, or depend on an undated prior decision? | `[A]` |
| 0.3 | Resolve challenge findings; split scope into many ADRs if needed                                                  | `[M]` |

**Exit gate:** a single-decision scope sentence exists and survived challenge.
**Artifact:** the sentence, recorded at the top of the working draft (removed at Step 7).

## Step 1 - Drivers with Owners

**Goal:** every decision driver enumerates and tags with where it resolves:
`this ADR`, `ADR-NNNN`, or `rejected as driver`.

| #   | Subtask                                                                                  | Owner |
|-----|------------------------------------------------------------------------------------------|-------|
| 1.1 | Enumerate candidate drivers (forces, concerns, constraints)                              | `[X]` |
| 1.2 | Probe for missing driver categories (cost, maintenance, audience, longevity, compliance) | `[A]` |
| 1.3 | Tag each driver with its resolution owner                                                | `[M]` |
| 1.4 | Generate More Information routing lines for drivers tagged to other ADRs                 | `[A]` |

**Exit gate:** zero untagged drivers. A driver without an owner is scope creep or a missing link.
**Artifact:** driver table (driver, owner, routing target).

## Step 2 - Options with Category Coverage

**Goal:** the option list demonstrably spans the decision space, so that
"only option which..." claims are true of a visibly complete set.

| #   | Subtask                                                                         | Owner |
|-----|---------------------------------------------------------------------------------|-------|
| 2.1 | Name the option categories the decision spans (before naming options)           | `[X]` |
| 2.2 | Ecosystem survey: candidate discovery per category, with sources and dates      | `[A]` |
| 2.3 | Coverage check: every category has at least one option or an explicit exclusion | `[A]` |
| 2.4 | Approve the final option list; pin versions evaluated                           | `[M]` |

**Exit gate:** every category is represented or excluded with a stated reason.
**Artifact:** dated survey brief (linked or archived), final option list with version pins.

## Step 3 - Claims Ledger

**Goal:** every factual bullet in Pros and Cons binned and disposed
before it enters the draft. A bullet that cannot be binned is not written.

**Bins:**

* **Measured** - verifiable facts (dates, versions, release activity, benchmarks).
  Disposition: cite a checked source at write time, or do not write it.
* **Designed** - what a project claims by architecture or stated intent.
  Disposition: attribute to the project ("advertised as", "commits to", "designed for").
* **Judged** - the decision-maker's assessment.
  Disposition: mark as ours ("we judge...", "we expect..."). Never dress as Measured.

| #   | Subtask                                                             | Owner |
|-----|---------------------------------------------------------------------|-------|
| 3.1 | Draft pros/cons bullets per option                                  | `[X]` |
| 3.2 | Bin each factual claim (Measured / Designed / Judged)               | `[X]` |
| 3.3 | Verify Measured claims against current sources; attach citations    | `[A]` |
| 3.4 | Reword Designed and Judged claims to carry their bin visibly        | `[A]` |
| 3.5 | Spot-check a sample of verifications (demonstration over assertion) | `[M]` |
| 3.6 | Ledger sign-off                                                     | `[M]` |

**Exit gate:** no bullet contains an unbinned claim; no superlative survives without
a Measured source or a Judged marker.
**Artifact:** the ledger (claim, bin, source or marker), retained alongside the draft.

## Step 4 - Decision Outcome (Written Last)

**Goal:** the outcome is assembled from already-verified parts and cites
drivers by name. It asserts nothing the analysis did not establish.

| #   | Subtask                                                                                                                | Owner |
|-----|------------------------------------------------------------------------------------------------------------------------|-------|
| 4.1 | Assemble draft outcome: chosen option + deciding driver(s) + one clause per eliminated option pointing to its analysis | `[A]` |
| 4.2 | Driver-citation check: each justification maps to a named driver                                                       | `[A]` |
| 4.3 | Edit for voice and approve                                                                                             | `[M]` |

**Exit gate:** every clause in the outcome traces to a driver or an option analysis section.

## Step 5 - Hedge Pass

**Goal:** vague future intentions become falsifiable triggers or are deleted.

**Hedge lexicon:** later, eventually, down the line, if needed, revisit, when mature,
as the need arises, at some point, in the future.

| #   | Subtask                                                                          | Owner |
|-----|----------------------------------------------------------------------------------|-------|
| 5.1 | Scan draft for hedge lexicon hits                                                | `[A]` |
| 5.2 | For each hit: author the observable trigger, or delete the hedge                 | `[M]` |
| 5.3 | Falsifiability check: could a stranger determine whether each trigger has fired? | `[A]` |

**Exit gate:** zero unresolved hedges. Triggers name observable events, not states of feeling.

## Step 6 - Confirmation as Executable Checks

**Goal:** confirmation distinguishes wiring (the decision was implemented)
from function (the implementation works), and prefers checks that fail loudly.

| #   | Subtask                                                                                | Owner |
|-----|----------------------------------------------------------------------------------------|-------|
| 6.1 | Enumerate candidate confirmation checks                                                | `[X]` |
| 6.2 | Stranger test: verifiable without the author, fails loudly if rotted                   | `[A]` |
| 6.3 | Implement executable checks (CI jobs, scripts, badges bound to the check that matters) | `[X]` |
| 6.4 | Approve the Wiring / Function split                                                    | `[M]` |

**Exit gate:** at least one Function check exists whose failure is visible without
manual inspection. Existence-only confirmations are Wiring, never Function.

## Step 7 - Trace, Copy, Freeze

**Goal:** final lint and lifecycle transition.

| #   | Subtask                                                                                                                                 | Owner |
|-----|-----------------------------------------------------------------------------------------------------------------------------------------|-------|
| 7.1 | Bidirectional trace: every driver maps to outcome content or a routing pointer; every outcome claim maps to a driver or option analysis | `[A]` |
| 7.2 | Copy pass: spelling (project names especially), link and anchor integrity, marker legend present if version-range notation is used      | `[A]` |
| 7.3 | Remove drafting scaffolding (scope sentence, ledger references) or relocate to More Information                                         | `[X]` |
| 7.4 | Flip status to accepted; drop the `.draft` suffix; merge to main                                                                        | `[M]` |
| 7.5 | Freeze machinery applies (pre-commit hook per ADR-0000 amendments)                                                                      | `[A]` |

**Exit gate:** merged to main with status accepted. The record is now immutable
except via superseding ADR or an explicit `[adr-amend]` override.

---

## Session Handoff

When drafting spans multiple LLM sessions, carry forward exactly these artifacts
rather than conversational summary:

1. The Step 0 scope sentence, verbatim
2. The Step 1 driver table with owner tags
3. The Step 2 option list with version pins and the dated survey brief
4. The Step 3 claims ledger (including bins and sources)
5. Current step number and any unresolved gate findings

A fresh session must re-verify, not inherit, any Measured claim whose source
predates the session: absence of contradiction in a stale source is not confirmation.

## Per-ADR Checklist (Copy Into Working Draft)

* [ ] 0: Scope sentence written and challenged
* [ ] 1: All drivers tagged with owners
* [ ] 2: Categories covered; versions pinned; survey dated
* [ ] 3: Claims ledger complete and signed off
* [ ] 4: Outcome assembled last; driver-cited
* [ ] 5: Hedges converted to triggers or deleted
* [ ] 6: Function check implemented and loud
* [ ] 7: Trace clean; copy clean; frozen on merge
