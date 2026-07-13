# SnapCal Story Backlog

This is a candidate backlog derived from `SPEC.md`. Candidate rows are not
active Harness stories and do not authorize scaffolding. Select the smallest
vertical slice, run feature intake, and create its story packet before code.

## Epics

| Epic | Outcome | Candidate stories | Status |
| --- | --- | --- | --- |
| E00 Foundation | Convert the source spec into living contracts and equipped tooling | US-000 wire product contract | implemented |
| E01 Core Prototype | Prove screenshot -> draft -> review -> calendar | image validation/import; structured extraction; editable review; Google OAuth/create | US-001 implemented; US-002 code-proven, live proof pending |
| E02 Extraction Reliability | Make Vietnamese-English extraction measurable and safe | local OCR; cloud fallback; date/time parser; location parser; confidence/ambiguity; benchmark | unsliced |
| E03 macOS Experience | Deliver the menu-bar and top-center drop-zone workflow | MenuBarExtra shell; AppKit floating panel; drag/drop; clipboard; recent drafts | unsliced |
| E04 Trust Hardening | Protect users from wrong, duplicate, or retained data | reminders; duplicate warnings; location candidates; screenshot deletion; history controls; local-only mode | unsliced |
| E05 Mobile | Reuse the extraction/review contract from native share surfaces | iOS Share Extension; iOS review; Android share target; Android review | unsliced |
| E06 Personalization | Reduce repeated edits without weakening confirmation | calendar/reminder preferences; duration preferences; App Intents/Shortcuts; draft-only automation | unsliced |

## Recommended Next Slice

US-002 is implemented through the automated and build proof layers. Its final
Phase 1 check is a user-driven live proof:

```text
Given an edited draft in the review screen,
when the user explicitly confirms creation and completes Google consent,
then SnapCal creates one Google Calendar event, reports success, and opens the
provider link on request.
```

The high-risk story packet, decision, scheduler spy, confirmation-state tests,
Keychain ownership, and provider failure/retry proof are present. The live
write cannot be performed by an agent because the product contract requires the
user to inspect and confirm the exact event.

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
