# SnapCal Story Backlog

This is a candidate backlog derived from `SPEC.md`. Candidate rows are not
active Harness stories and do not authorize scaffolding. Select the smallest
vertical slice, run feature intake, and create its story packet before code.

## Epics

| Epic | Outcome | Candidate stories | Status |
| --- | --- | --- | --- |
| E00 Foundation | Convert the source spec into living contracts and equipped tooling | US-000 wire product contract | implemented |
| E01 Core Prototype | Prove screenshot -> draft -> review -> calendar | image validation/import; structured extraction; editable review; Google OAuth/create | US-001 implemented; US-002 code-proven with ad-hoc Keychain persistence, live relaunch proof pending |
| E02 Extraction Reliability | Make Vietnamese-English extraction measurable and safe | local OCR; cloud fallback; date/time parser; multiple-event extraction; location parser; confidence/ambiguity; benchmark | US-003/004 live-proven; US-007/008 implemented; US-013 code-proven; US-006 synthetic regression implemented, licensed real-world dual-mode acceptance open |
| E03 macOS Experience | Deliver the menu-bar and top-center drop-zone workflow | MenuBarExtra shell; AppKit floating panel; drag/drop; clipboard; recent drafts | US-009 and US-010 automated through status-item/clipboard/relaunch smoke; direct notch drag smoke remains manual |
| E04 Trust Hardening | Protect users from wrong, duplicate, or retained data | reminders; duplicate warnings; location candidates; screenshot deletion; history controls; local-only mode | US-011 implemented and code-proven; live MapKit candidate smoke remains manual |
| E07 Paid Beta And Production | Release a private paid macOS beta with provider-neutral accounts, Paddle entitlement, bounded quota, private hosted extraction, and reproducible delivery | US-014 production API; US-015 Paddle entitlement; US-016 macOS Pro account; US-017 production delivery | implementation and local proof in progress; live provider, domain, signing, and rollout activation pending |
| E05 Mobile | Reuse the extraction/review contract from native share surfaces | iOS Share Extension; iOS review; Android share target; Android review | unsliced |
| E06 Personalization | Reduce repeated edits without weakening confirmation | calendar/reminder preferences; duration preferences; App Intents/Shortcuts; draft-only automation | unsliced |

## Recommended Next Slice

The current phase is E07 Release and Monetization. Extraction quality is
accepted for the beta, and the licensed real-world benchmark is deferred. The
next slice is paid-beta activation: finish local proof, provision isolated
staging, run the 20-request sanitized cost/latency calibration, validate Paddle
sandbox and webhook ownership, produce a signed/notarized internal build, and
complete the five-account internal wave before enabling live checkout.

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
