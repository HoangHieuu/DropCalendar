# SnapCal Story Backlog

This is a candidate backlog derived from `SPEC.md`. Candidate rows are not
active Harness stories and do not authorize scaffolding. Select the smallest
vertical slice, run feature intake, and create its story packet before code.

## Epics

| Epic | Outcome | Candidate stories | Status |
| --- | --- | --- | --- |
| E00 Foundation | Convert the source spec into living contracts and equipped tooling | US-000 wire product contract | implemented |
| E01 Core Prototype | Prove screenshot -> draft -> review -> calendar | image validation/import; structured extraction; editable review; Google OAuth/create | US-001 implemented; US-002 code-proven with ad-hoc Keychain persistence, live relaunch proof pending |
| E02 Extraction Reliability | Make Vietnamese-English extraction measurable and safe | local OCR; cloud fallback; date/time parser; location parser; confidence/ambiguity; benchmark | US-003/004 live-proven; US-007/008 implemented; US-006 synthetic regression implemented, licensed real-world dual-mode acceptance open |
| E03 macOS Experience | Deliver the menu-bar and top-center drop-zone workflow | MenuBarExtra shell; AppKit floating panel; drag/drop; clipboard; recent drafts | US-009 and US-010 automated through status-item/clipboard/relaunch smoke; direct notch drag smoke remains manual |
| E04 Trust Hardening | Protect users from wrong, duplicate, or retained data | reminders; duplicate warnings; location candidates; screenshot deletion; history controls; local-only mode | US-011 implemented and code-proven; live MapKit candidate smoke remains manual |
| E05 Mobile | Reuse the extraction/review contract from native share surfaces | iOS Share Extension; iOS review; Android share target; Android review | unsliced |
| E06 Personalization | Reduce repeated edits without weakening confirmation | calendar/reminder preferences; duration preferences; App Intents/Shortcuts; draft-only automation | unsliced |

## Recommended Next Slice

US-006 now has a versioned 100-image generated corpus, integrity validation,
redacted scoring, a production-source Local Only runner, and an explicitly
cost-gated production-source Accuracy runner. The generated corpus passes its
regression gates but cannot support a real-world accuracy claim. The next slice
is licensed/sanitized non-synthetic corpus intake followed by both complete
mode runs and benchmark-driven fixes.

The user has completed a live Accuracy Mode run and one explicitly confirmed
Google Calendar creation. Those user-driven successes establish provider
operability and the Phase 1 core write path; they do not replace benchmark-wide
accuracy evidence.

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
  -> E05 mobile reuse
  -> E06 automation
```

E02 may begin benchmark-fixture design alongside E01, but model accuracy claims
must wait for a versioned corpus and repeatable evaluation command.
