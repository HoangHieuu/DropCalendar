# SnapCal Next-Step Plan: Close Phase 2 and Certify the macOS MVP

## Summary

SnapCal’s implementation is effectively at the end of Phase 4, but the product cannot honestly claim MVP completion because the Phase 2 real-world quality gate remains open.

The immediate next phase is therefore:

> **Phase 2 quality closure, followed by final Phase 3–4 native macOS validation.**

Phase 5 mobile development must not begin until these gates pass.

The selected release target is a **proof-ready macOS MVP**:

- Private, licensed real-world benchmark.
- Accuracy Mode as the full semantic extraction experience.
- Deterministic Local Only as the privacy-first reduced-accuracy option.
- Developer-run localhost extraction service.
- No deployment, notarization, App Store submission, iOS, Android, or bundled local LLM yet.
- Maximum authorized OpenRouter benchmark spend: **US$5 total**.

## SPEC Strategy

Continue following [SPEC.md](/Users/hieu/Desktop/DropCalendar/SPEC.md) for product outcomes, safety rules, benchmark composition, quality targets, and user-visible behavior. Use the living product documents and accepted architecture decisions for implementation details.

### Requirements to preserve

- At least 100 real, licensed, sanitized screenshots.
- At least 50 Vietnamese or mixed-language examples.
- At least 30 English examples.
- At least 20 noisy, low-resolution, or decorative-font examples.
- All required event-source categories.
- Separate Vietnamese and English metrics.
- Evidence for every critical extracted field.
- No invented date or time without supporting evidence.
- No calendar write before explicit user confirmation.
- Accuracy Mode must meet the SPEC title/date/time, critical-error, and latency targets.
- Review, reminders, duplicates, privacy, deletion, OAuth, and macOS intake must remain functional.

### Intentional flexibility

- Keep OpenRouter and `google/gemini-3.1-flash-lite` as the Accuracy provider instead of rebuilding the SPEC’s suggested Google Cloud Vision/Gemini pipeline.
- Do not automatically send low-confidence Local Only results to the cloud. Offer “Try Accuracy Mode” and require explicit cloud consent.
- Do not add Google Cloud Vision unless benchmark evidence proves that OCR loss—not semantic interpretation—is the remaining blocker.
- Do not describe Local Only as an LLM. It remains Apple Vision OCR plus deterministic Vietnamese-English rules.
- Defer Apple Foundation Models until the installed SDK/runtime supports it. Do not raise the macOS 14 minimum or bundle a third-party local model now.
- Keep the real-world corpus outside Git. Private benchmark permission is sufficient; redistribution rights are not required.
- Treat the SPEC’s 95% live Calendar creation target as a post-release operational SLO. Pre-release proof will use mocked reliability coverage plus explicitly confirmed live smoke tests rather than generating many real calendar events.
- Keep Postgres, production hosting, notarization, mobile clients, and server deployment outside this milestone.

## Implementation Plan

### Gate 0 — Establish the release baseline

1. Run and record the existing macOS, FastAPI, and benchmark suites.
2. Capture the exact source revision, dirty-worktree status, macOS version, Xcode version, benchmark model, and current service configuration.
3. Reproduce the outstanding native issue where the signed menu-bar status item is reported as not hittable.
4. Re-run the notch hover regression to confirm that panel resizing no longer oscillates or distorts.
5. Record all remaining manual-proof gaps without marking their stories complete.

Exit criteria:

- Existing automated suites pass or every failure has an assigned remediation.
- The menu-bar failure is reproducible or conclusively identified as test-environment-only.
- No current behavior is overstated in the roadmap or test matrix.

### Gate 1 — Build the licensed real-world benchmark

Create two private datasets outside the repository:

- A 20-item calibration set for checking the pipeline, labels, and estimated Accuracy Mode cost.
- A frozen 100-item acceptance set that independently satisfies the full SPEC composition.

For every screenshot:

1. Confirm ownership, license, or written benchmark permission.
2. Confirm explicit authorization to process it through OpenRouter.
3. Remove names, email addresses, QR payloads, account identifiers, private meeting links, and unrelated personal content.
4. Preserve event content needed to judge title, date, time, timezone, and location.
5. Calculate and lock the image SHA-256.
6. Record capture timestamp and IANA timezone so relative expressions such as “tomorrow” can be resolved correctly.
7. Annotate the canonical title, start, end, all-day state, location, language, source category, and difficulty labels.
8. Record expected ambiguity fields for screenshots containing competing dates, times, or locations.
9. Require a second review of date, time, timezone, and travel-critical location labels.
10. Freeze the acceptance manifest before its first final Accuracy run.

The private corpus, predictions, and item-level failure reports remain outside Git. Only redacted aggregate reports may enter the repository.

Exit criteria:

- 20 calibration and at least 100 acceptance items validate successfully.
- The 100 acceptance items contain at least 50 Vietnamese/mixed, 30 English, and 20 challenging examples.
- Every required source category is represented.
- Every item is sanitized, non-synthetic, hash-verified, benchmark-authorized, and OpenRouter-authorized.
- Every critical label has completed second review.

### Gate 2 — Correct the benchmark contract

Introduce benchmark manifest schema version 2 while retaining version 1 compatibility for the checked-in synthetic corpus.

Schema version 2 adds:

- `processing_authorization`
  - `benchmark_use: true`
  - `cloud_processors: ["openrouter"]`
  - An opaque authorization reference.
- `expected_ambiguity_fields`
  - Any of `title`, `start`, `end`, or `location`.
- `annotation`
  - `critical_fields_second_reviewed`
  - `reviewed_at`
- Permission for `provenance.redistributable` to be `false` when the corpus is external and private.

Validation rules:

- Version 1 remains valid for synthetic regression.
- Real-world acceptance requires schema version 2.
- Accuracy Mode additionally requires explicit OpenRouter authorization.
- Private non-redistributable images must never be copied into repository-owned directories.
- A missing authorization, missing image, hash mismatch, incomplete label, or failed second review stops the run before extraction begins.

Add validation switches equivalent to:

```text
--require-complete
--require-real-world
--require-cloud-authorized openrouter
--require-second-reviewed
```

### Gate 3 — Enforce the US$5 Accuracy budget

Keep the normal `POST /v1/extract` response unchanged for the macOS application.

Add a loopback-only benchmark interface:

```text
POST /v1/benchmark/extract
```

It is enabled only when the service starts with benchmark mode explicitly set. Its response contains the normal extraction result plus:

```text
usage.request_cost_usd
usage.cumulative_cost_usd
usage.budget_remaining_usd
```

Budget enforcement:

1. Use a dedicated OpenRouter API key with a provider-side limit of no more than US$5 and no unrelated traffic.
2. Verify that limit during benchmark preflight through OpenRouter’s [API-key limit endpoint](https://openrouter.ai/docs/api/reference/limits).
3. Read actual request cost from the non-streaming usage response.
4. If cost is absent, retrieve it from the [generation metadata endpoint](https://openrouter.ai/docs/api/api-reference/generations/get-generation).
5. Abort immediately if cost cannot be determined.
6. Maintain a cumulative process-local counter and refuse further requests at the configured ceiling.
7. Treat the provider-side key limit as the final protection against a single-request overshoot.
8. Start a dedicated benchmark service process on a free loopback port and terminate only that process after the run.
9. Store aggregate cost, model, request count, manifest hash, source revision, latency, and abort reason. Never store the API key in reports.

Run sequence:

- Run the 20-item calibration set first.
- Project the 100-item cost with a 20% safety reserve.
- Start the frozen acceptance run only if the projected total remains below the remaining US$5 budget.
- If the run exhausts the budget or becomes incomplete, it does not qualify as an acceptance report.
- Any additional cloud rerun beyond this authorized budget requires separate approval.

### Gate 4 — Produce the dual-mode baseline

Run Local Only over the calibration and acceptance corpora first. Then run the authorized Accuracy benchmark.

Each mode must produce:

- Complete predictions or an explicit failure reason for every item.
- Vietnamese and English title/date/time/location metrics.
- Critical wrong-date and wrong-time rate.
- Ambiguity detection results.
- Missing-versus-wrong critical-field counts.
- Median and percentile extraction latency.
- Failure counts by language, source, and difficulty.
- Redacted aggregate report with no screenshot or OCR text.

Quality gates:

**Accuracy Mode**

- Vietnamese title accuracy ≥85%.
- Vietnamese date accuracy ≥85%.
- Vietnamese time accuracy ≥80%.
- English title accuracy ≥90%.
- English date accuracy ≥90%.
- English time accuracy ≥85%.
- Critical wrong-date/wrong-time rate ≤3%.
- Median latency ≤10 seconds.
- Every critical value has evidence.
- No unsupported date invention.

**Local Only**

- Report all the same accuracy metrics, but do not require semantic accuracy equal to Accuracy Mode.
- Critical wrong-date/wrong-time rate ≤3%.
- Median latency ≤10 seconds.
- No silent cloud requests.
- No unsupported date invention.
- Missing or ambiguous output is preferred over a confident wrong value.
- The UI clearly identifies reduced semantic capability and offers an explicitly consented Accuracy retry.

This preserves the SPEC’s system-level quality target through Accuracy Mode without falsely representing deterministic Local Only as an LLM.

### Gate 5 — Harden only benchmark-proven failures

Classify failures into:

- OCR text or layout loss.
- Vietnamese normalization.
- Relative date resolution.
- Multiple-date/time ambiguity.
- Event-start versus doors/opening time.
- Location ranking.
- Evidence propagation.
- Provider schema/output failure.
- Latency or service reliability.

Remediation order:

1. Correct invalid ground truth or annotation disagreements.
2. Improve general Apple Vision layout/OCR handling.
3. Add deterministic Local Only rules only when they represent a reusable language pattern demonstrated by multiple examples.
4. Improve Accuracy prompt, schema, normalization, and evidence requirements.
5. Consider a provider/model change only if the current fixed model cannot satisfy the gate.
6. Consider separate cloud OCR only if measured failures prove that image text remains unreadable to both Apple Vision and the current vision model.

Every extraction change must:

- Add a synthetic regression case.
- Pass the complete existing synthetic corpus.
- Avoid screenshot-specific strings, titles, venues, or dates.
- Preserve ambiguity rather than forcing a value.
- Re-run the relevant calibration slice.
- Avoid another full cloud acceptance run unless budget authorization remains.

If the frozen acceptance set fails after the authorized run, keep Phase 2 open, publish the redacted failure analysis, and request a new cloud budget before rerunning it.

### Gate 6 — Close the native macOS proof gaps

After the extraction gate passes, complete the signed macOS acceptance checklist.

**Menu bar and notch**

- Fix the status-item hittability failure.
- Verify click, keyboard access, recent-draft selection, and reopen behavior.
- Repeatedly cross the notch hover boundary without panel-size oscillation or distortion.
- Confirm stable compact/expanded geometry across Spaces and screen changes.
- Drag a real image from Finder into the notch.
- Test unsupported files, multiple-file drops, cancellation, and processing state.
- Confirm only the first supported image is processed.

**Clipboard and review**

- Import a real clipboard image.
- Verify empty/invalid clipboard messaging.
- Confirm the review opens with editable fields, evidence, ambiguities, reminders, calendar selection, duplicates, and cloud disclosure.
- Confirm low-confidence Local Only results offer an explicit Accuracy retry.

**OAuth and Calendar**

- Complete one Google reconnect.
- Relaunch the signed app and verify the refresh token survives without another browser login or Keychain prompt.
- Open the provider calendar link.
- Test disconnect, relaunch, and reconnect.
- Use mocked adapters for automated create/retry/failure coverage.
- Perform a live event creation only after the user explicitly confirms the exact test event and calendar.
- Delete the test event manually after verification if requested.

**Location and privacy**

- Perform an explicit MapKit candidate lookup and selection.
- Verify no lookup happens while typing.
- Confirm default extraction retains no app-owned screenshot.
- Enable history, verify encrypted storage, reopen it, and delete it.
- Run Clear All and verify drafts, encrypted screenshot copies, and the vault key are removed.
- Confirm user-owned source files and existing Google Calendar events are untouched.

Exit criteria:

- Signed automated suites pass.
- Menu-bar item and notch remain stable.
- Finder drop, clipboard import, review, relaunch, deletion, and OAuth lifecycle have recorded proof.
- No automated test creates a Google Calendar event.
- Any live Calendar write has explicit user confirmation.

### Gate 7 — Declare the proof-ready macOS MVP

Update the living roadmap, test matrix, architecture decisions, and active story packets only after all prior gates pass.

The MVP claim must include:

- Exact source revision and environment.
- Redacted Local Only and Accuracy reports.
- OpenRouter model and total benchmark cost.
- Known Local Only limitations.
- Native macOS proof checklist.
- Remaining production-distribution limitations.
- Explicit statement that the service is developer-run and loopback-only.

The MVP claim must not include:

- Production-ready distribution.
- Notarization or App Store readiness.
- Local LLM semantics.
- Mobile support.
- A 95% live Calendar success claim without real operational volume.
- Real-world accuracy derived from synthetic fixtures.

## Next Phase After macOS Proof

Once Gate 7 passes:

1. Start a separate distribution architecture decision:
   - Native Google Sign-In versus hosted authenticated token broker.
   - Hosted Accuracy service authentication, abuse prevention, privacy, retention, and cost control.
2. Complete packaging, hardened runtime, notarization, and update strategy if external macOS distribution is desired.
3. Begin Phase 5 with iOS Share Extension first.
4. Reuse the same review, confirmation, extraction, and benchmark contracts.
5. Begin Android `ACTION_SEND` only after the shared mobile/backend contract is stable.
6. Re-evaluate Apple Foundation Models separately when the installed toolchain can compile and run it.

## Assumptions and Defaults

- Accuracy Mode is the semantic product path and must satisfy the original SPEC quality thresholds.
- Local Only is a safe reduced-accuracy privacy path; it is not blocked for lower recall if it remains evidence-backed and avoids critical false confidence.
- The licensed corpus remains private and external.
- All 100 acceptance images are authorized for OpenRouter processing.
- The current Accuracy model remains fixed for the first acceptance run.
- The entire authorized cloud benchmark budget is US$5, enforced both locally and through a dedicated provider-limited key.
- The localhost service remains acceptable for proof-ready MVP validation but not public distribution.
- Phase 5, production hosting, notarization, third-party local models, Cloud Vision, and new persistence infrastructure remain out of scope until the macOS MVP gates pass.
