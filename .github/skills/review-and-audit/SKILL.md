---
name: review-and-audit
description: 'Review code changes or audit a codebase for correctness, regressions, maintainability, and defensive security risks. Use when asked to review, audit, inspect changes, find bugs, assess security, or check test coverage.'
argument-hint: 'What code, change, or risk area should I review?'
---

# Code Review and Audit

## Purpose

Produce an evidence-based review that helps the author fix the most important problems. Review code as it behaves in context, not as an isolated diff. Do not make changes unless the user asks for fixes.

## Procedure

1. **Establish scope and intent.** Identify the requested files, commit, pull request, feature, or whole-project audit. Read the relevant requirements and nearby implementation. For a change review, inspect the diff and its callers, data flow, and tests. Preserve unrelated work and do not assume the worktree is clean.
2. **Form a testable hypothesis.** State privately what behavior is expected and where a defect or risk could arise. Select the smallest relevant test, static check, or concrete code path that could disprove it. Avoid broad repository exploration when a local path answers the question.
3. **Trace behavior.** Follow inputs through validation, state changes, persistence, external calls, error handling, and outputs. Check boundary cases, null or missing values, concurrency and lifecycle behavior where relevant, and whether behavior is consistent across callers.
4. **Inspect tests and contracts.** Compare implementation against tests, schemas, API contracts, documentation, and compatibility requirements. Note missing coverage only when it leaves a meaningful risk unverified; do not report the mere absence of a test as a defect.
5. **Audit defensively when relevant.** Check authorization boundaries, authentication assumptions, input validation, injection and unsafe deserialization risks, secret handling, sensitive-data exposure, cryptographic use, dependency/configuration risks, and unsafe file or process operations. Keep analysis within the supplied code and authorized environment. Do not target third-party systems, expose secrets, or provide weaponized exploit steps.
6. **Verify candidate findings.** For each suspected issue, confirm the exact code path and a realistic trigger. Use the narrowest safe test or static check available. Do not execute destructive operations or access live systems without explicit authorization. If a concern cannot be verified, label it as a question or uncertainty rather than a confirmed finding.
7. **Prioritize and report.** Lead with actionable findings, ordered by severity. Each finding must identify the location, triggering conditions, concrete impact, and why the behavior is incorrect or risky. Keep each finding focused and avoid duplicates. If there are no findings, say so clearly and state what was and was not checked.
8. **Summarize verification and residual risk.** Name the checks run and their outcomes. Explicitly distinguish verified results from assumptions, and mention relevant test gaps or environmental limits. Do not claim a test or audit was performed when it was not.

## Severity Guide

- **Critical:** Likely, broad compromise or irreversible loss of important data; no meaningful preconditions beyond normal use.
- **High:** Serious security, data-integrity, or availability impact affecting a substantial workflow or user group.
- **Medium:** Material bug or risk with narrower scope, meaningful preconditions, or a practical workaround.
- **Low:** Limited impact, edge-case defect, or maintainability issue with a concrete likelihood of causing future faults.
- **Informational:** Useful observation that is not itself a defect; keep separate from findings.

Use the highest severity justified by evidence, not the most alarming conceivable outcome. Explain assumptions that affect severity.

## Response Format

1. Findings first, each with severity, concise title, location, impact, and evidence or trigger.
2. Open questions or assumptions that could change the assessment.
3. Checks performed and their results, including relevant unverified areas.
4. A brief change or scope summary only when useful.

If the review has no findings, state that explicitly before the checks and residual-risk note. Keep the report concise and do not bury actionable issues in a general summary.