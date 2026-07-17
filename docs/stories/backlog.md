# SnapCal Story Backlog

This is a candidate backlog derived from `SPEC.md`. Candidate rows are not
active Harness stories and do not authorize scaffolding. Select the smallest
vertical slice, run feature intake, and create its story packet before code.

## Epics

| Epic | Outcome | Candidate stories | Status |
| --- | --- | --- | --- |
| E00 Foundation | Convert the source spec into living contracts and equipped tooling | US-000 wire product contract | implemented |
| E01 Core Prototype | Prove screenshot -> draft -> review -> calendar | image validation/import; structured extraction; editable review; Google OAuth/create | US-001 implemented; US-002 code-proven with ad-hoc Keychain persistence, live relaunch proof pending |
| E02 Extraction Reliability | Make Vietnamese-English extraction measurable and safe | local OCR; Local Semantic with deterministic fallback; cloud Accuracy; date/time parser; multiple-event extraction; location parser; confidence/ambiguity; benchmark | US-003/004 live-proven; US-007 implemented; US-008 unified Local Semantic implementation in progress with live-model and provenance-aware benchmark proof open; US-013 code-proven; US-006 synthetic regression implemented |
| E03 macOS Experience | Deliver the menu-bar and top-center drop-zone workflow | MenuBarExtra shell; AppKit floating panel; drag/drop; clipboard; recent drafts; responsive visual system | US-009 and US-010 automated through status-item/clipboard/relaunch smoke; US-018 responsive washi redesign implemented with focused/full UI proof; US-019 koi pond visual mark active; direct notch drag smoke remains manual |
| E04 Trust Hardening | Protect users from wrong, duplicate, or retained data | reminders; duplicate warnings; location candidates; screenshot deletion; history controls; Local Semantic privacy boundary | US-011 implemented and code-proven; live MapKit candidate smoke remains manual |
| E07 Paid Beta And Production | Release a private paid macOS beta with provider-neutral accounts, Paddle entitlement, bounded quota, private hosted extraction, and reproducible delivery | US-014 production API; US-015 Paddle entitlement; US-016 macOS Pro account; US-017 production delivery | implementation and local proof in progress; live provider, domain, signing, and rollout activation pending |
| E05 Mobile | Reuse the extraction/review contract from native share surfaces | iOS Share Extension; iOS review; Android share target; Android review | unsliced |
| E06 Personalization | Reduce repeated edits without weakening confirmation | calendar/reminder preferences; duration preferences; App Intents/Shortcuts; draft-only automation | unsliced |

## Recommended Next Slice

US-019 is the active presentation slice: replace the abstract orbit/calendar
mark with a native koi-pond composition matching the supplied reference while
preserving extraction, retention, cloud, OAuth, accessibility, and
Calendar-confirmation behavior. US-018 remains implemented.

The user-selected bounded slice is US-008: replace the visible Local Only choice
with one Local Semantic mode, preserve deterministic fallback, add the
availability-gated Foundation Models boundary, and prove truthful provenance
without weakening zero-cloud or Calendar-confirmation rules. The adapter and
stubbed paths typecheck; live generation awaits Apple Intelligence, the full
Xcode suite awaits license acceptance, and the provenance-aware benchmark
schema remains open.

E07 Release and Monetization remains the broader release phase. Extraction
quality is accepted for the invited beta, and the licensed real-world benchmark
is deferred. The 20-request sanitized paid-beta calibration passed on
2026-07-16. After the selected US-008 slice, activation steps remain isolated
staging, Paddle sandbox and webhook validation, a signed/notarized internal
build, and the five-account internal wave. Staging deployment is temporarily
blocked by the operator's GCP billing issue.

A prior 2026-07-15 bounded acquisition pass created 180 rights-filtered, external
review candidates from Apify-discovered Wikimedia Commons files without adding
them to Git. Five focused Apify runs added 125 quarantined discovery records for
$0.012, then stopped when a targeted query remained low relevance. Local Apple
Vision triage found 32 likely event images but only one likely Vietnamese event
image. A 180-row external human-review template now exists with every approval
still false, and fail-closed promotion enforces the 20-item calibration and
100+ item acceptance contracts. That material remains quarantined and may
support a future real-world accuracy claim, but collection, labeling, and
independent review are no longer beta release blockers.

The user has completed a live Accuracy Mode run and one explicitly confirmed
Google Calendar creation. Those user-driven successes establish provider
operability and the Phase 1 core write path; they do not replace benchmark-wide
accuracy evidence.

US-013 is the explicit post-SPEC extension for one screenshot containing
multiple independently dated events. Its safe boundary is one-at-a-time review
and a separate confirmation per Calendar write; a batch `Create All` action is
not planned.

The remaining live Calendar platform checks are relaunch refresh-token reuse,
provider-link opening, signed Data Protection Keychain reuse, and
disconnect/reconnect.

The supplied Agentic AI Build Week poster's expected draft remains a focused
regression fixture:

```text
Agentic AI Build Week
July 8–12, 2026, all day
Ho Chi Minh, Vietnam
```

No benchmark command may create a Calendar event. Any future live Calendar
write remains user-confirmed from the review screen.

## Dependency Shape

```text
E01 typed draft and review
  -> E02 reliability and benchmark
  -> E03 polished macOS intake
  -> E04 trust hardening
  -> E07 paid beta and production release
  -> E05 mobile reuse
  -> E06 automation
```

E07 may ship without a new accuracy claim, but every paid request must still
pass quota, privacy, cost, latency, and explicit-confirmation release gates.
Any future model-quality claim must wait for a licensed versioned corpus and a
repeatable evaluation command.
