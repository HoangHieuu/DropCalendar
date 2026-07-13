# Product Specification: SnapCal — Screenshot-to-Google-Calendar Event Creator

## 1. Product Summary

**SnapCal** is a lightweight app that lets users create Google Calendar events from screenshots of event posts, posters, stories, reels, websites, or social media content.

The core user flow is:

```text
Capture event screenshot
→ Drop/share into SnapCal
→ OCR + vision-language extraction
→ Vietnamese/English date-time-location normalization
→ User reviews extracted event
→ Create Google Calendar event
→ Reminder is automatically configured
```

The product must be optimized first for **Vietnamese and English**, because the main target user will often save local Vietnamese events from Facebook, TikTok, Instagram, university pages, clubs, workshops, hackathons, concerts, and community posts.

The first production target should be **macOS**, using a menu-bar utility and a top-center floating drop zone that visually behaves like a “notch box.” Apple provides SwiftUI support for menu bar utilities through `MenuBarExtra`, and SwiftUI supports drag-and-drop/drop destination behavior for app views.

For mobile, the input mechanism should be **Share Sheet / Share Target**, not a Dynamic Island-style drop zone. iOS share extensions are designed for sharing content such as images, links, videos, and files into another app; Android uses intents such as `ACTION_SEND` to send data between apps.

---

## 2. Product Goals

### Primary goals

1. Let users create a Google Calendar event from a screenshot with minimal manual typing.
2. Extract event title, date, time, location, description, and reminder settings from Vietnamese and English screenshots.
3. Make extraction safe through a mandatory review screen before event creation.
4. Avoid critical mistakes in date, time, and location.
5. Support messy real-world screenshots from Facebook, TikTok, Instagram, websites, university pages, and event posters.
6. Preserve privacy by minimizing screenshot retention and avoiding unnecessary logging.

### Secondary goals

1. Support both macOS and mobile.
2. Provide duplicate detection.
3. Provide location validation.
4. Support local-first OCR where possible.
5. Support automation through shortcuts or app intents later.

---

## 3. Non-Goals

SnapCal will not initially:

1. Scrape Facebook, TikTok, Instagram, or private social media content directly.
2. Automatically create calendar events without user confirmation.
3. Register for events or buy tickets.
4. Guarantee perfect extraction from poor-quality screenshots.
5. Handle multiple events from one screenshot in the MVP.
6. Fully replace Google Calendar or Apple Calendar.
7. Read the user’s entire calendar unless duplicate detection requires explicit user permission.

---

## 4. Target Users

### Primary persona: Vietnamese student / young professional

The user often sees events in Vietnamese or mixed Vietnamese-English format:

```text
Workshop: AI Agent for Students
20h ngày 15/8
Đại học Bách Khoa TP.HCM
Đăng ký tại link bio
```

Pain points:

* Manually copying date, time, venue, and address is slow.
* Vietnamese date-time formats are often informal.
* Event posts may be images, not selectable text.
* Social platforms often make it annoying to copy event details.

### Secondary persona: English-speaking event follower

The user sees English event content:

```text
AI Founder Meetup
Friday, August 16, 7:00 PM
Dreamplex, District 1, Ho Chi Minh City
```

Pain points:

* Event details are scattered across poster text.
* User does not want to switch apps and type everything manually.

### Tertiary persona: mobile-first user

The user mainly captures screenshots on iPhone or Android and wants to share them directly into SnapCal.

---

## 5. Core User Journey

## 5.1 macOS journey

1. User sees an event on Facebook, TikTok, Instagram, a website, or a PDF/poster.
2. User captures a screenshot.
3. User drags the screenshot into the SnapCal top-center drop zone.
4. SnapCal processes the image.
5. SnapCal shows a review screen with extracted fields.
6. User edits uncertain fields if needed.
7. User selects calendar and reminders.
8. User clicks **Create Event**.
9. SnapCal creates the event in Google Calendar.
10. SnapCal confirms success.

## 5.2 mobile journey

1. User captures screenshot on iOS or Android.
2. User opens the system share sheet.
3. User selects **SnapCal**.
4. SnapCal extracts event details.
5. User reviews and confirms.
6. SnapCal creates the Google Calendar event.

---

# 6. Core Product Requirements

## 6.1 Screenshot Intake

SnapCal must accept event screenshots from:

### macOS

* Drag-and-drop into top-center drop zone.
* Import from menu-bar utility.
* Paste from clipboard.
* File picker fallback.

### iOS

* Share Extension from Photos, Safari, social apps, or files.
* In-app image picker.
* Optional App Intent / Shortcut later.

### Android

* Share Target using Android send intents.
* In-app image picker.
* Optional notification/quick action later.

### Acceptance Criteria

* Given the user drops a PNG, JPG, JPEG, or HEIC image into SnapCal, when the file is valid, then extraction starts automatically.
* Given the user pastes an image from clipboard on macOS, when clipboard contains image data, then SnapCal imports it.
* Given the uploaded file is corrupted or unsupported, then SnapCal shows a clear error and does not call the extraction service.
* Given multiple images are dropped, then MVP processes only the first image and informs the user that multi-image extraction is not yet supported.
* Given the user cancels import, then no draft is created.

---

## 6.2 Vietnamese-English OCR Pipeline

The OCR pipeline must be designed for Vietnamese and English from the beginning.

Vietnamese text recognition is harder than plain English OCR because of diacritics, informal abbreviations, tonal marks, decorative poster fonts, mixed casing, low-resolution screenshots, and common date-time expressions such as `20h`, `Thứ 7`, `CN`, `ngày mai`, and `Q.1`.

SnapCal should not rely on only one OCR engine. It should use a **multi-stage extraction pipeline**:

```text
Image validation
→ Image preprocessing
→ Local OCR
→ Cloud OCR fallback if needed
→ Vision-language model extraction
→ Vietnamese-English normalization
→ Date/time/location parser
→ Field-level confidence scoring
→ User review
```

### Recommended OCR components

1. **Apple Vision OCR for macOS/iOS local pre-pass**
   Apple Vision text recognition provides recognized text strings, confidence, and bounding boxes; language ordering can be configured through recognition language settings.

2. **ML Kit OCR for mobile fallback**
   ML Kit Text Recognition v2 supports Latin-character text recognition, but Vietnamese should be treated carefully because Google’s ML Kit supported-language page lists Vietnamese under experimental languages.

3. **Google Cloud Vision OCR as accuracy fallback**
   Google Cloud Vision OCR lists Vietnamese as a supported OCR language, so it is a strong cloud fallback for Vietnamese-heavy screenshots.

4. **Vision-language model extraction**
   A multimodal model should receive both the original image and OCR text. OpenAI supports image input for vision tasks and Structured Outputs for schema adherence; Gemini also supports image understanding and structured JSON output.

### OCR modes

SnapCal should support two extraction modes.

#### Fast Mode

```text
Local OCR
→ Vision-language extraction
→ Normalization
→ Review
```

Use when:

* Screenshot is clear.
* OCR confidence is high.
* Required fields are visible.

#### Accuracy Mode

```text
Local OCR
→ Cloud OCR
→ Vision-language extraction
→ Normalization
→ Review
```

Use when:

* Screenshot is low quality.
* Vietnamese diacritics are missing or corrupted.
* Date/time/location confidence is low.
* Poster layout is complex.
* Local OCR output is too short or fragmented.

### Acceptance Criteria

* Given a Vietnamese screenshot with clear text, SnapCal must extract title, date, time, and location when visible.
* Given an English screenshot with clear text, SnapCal must extract title, date, time, and location when visible.
* Given local OCR confidence is low, SnapCal must trigger cloud OCR or vision-language fallback.
* Given OCR loses Vietnamese diacritics, SnapCal must attempt Vietnamese normalization before field extraction.
* Given OCR and vision-language model disagree on date or time, SnapCal must mark the field as ambiguous and require user confirmation.
* Given the screenshot contains mixed Vietnamese and English, SnapCal must preserve both languages and output one normalized event object.
* Given the screenshot contains decorative poster typography, SnapCal must still attempt extraction using both layout-aware vision and OCR evidence.
* Given the screenshot contains no event-like information, SnapCal must return “No event detected” instead of hallucinating an event.

---

## 6.3 Vietnamese-English Normalization

SnapCal must include a language-aware normalization layer after OCR.

### Vietnamese normalization examples

```text
"20h ngay 15/8"       → "20h ngày 15/8"
"Thu 7"               → "Thứ 7"
"T7"                  → "Thứ 7" or "Saturday", depending on context
"CN"                  → "Chủ nhật", when used as weekday
"TP HCM"              → "TP.HCM"
"HCM"                 → "Ho Chi Minh City", when used as location
"Q1" / "Q.1"          → "Quận 1"
"20:OO"               → "20:00"
"l5/8"                → "15/8", only if confidence is high
"8 gio toi"           → "8 giờ tối"
```

### English normalization examples

```text
"Fri Aug 16 7PM"      → "Friday, August 16, 19:00"
"7 pm onwards"        → "start time: 19:00, end time: unknown"
"Aug 16th"            → "August 16"
"tonight 8pm"         → resolved using captured_at
```

### Critical rule

SnapCal may normalize noisy text, but it must preserve the original OCR evidence for every critical field.

Each extracted field must store:

```json
{
  "value": "2026-08-15",
  "evidence_text": "20h ngày 15/8",
  "source": "ocr+vlm",
  "confidence": 0.91,
  "is_inferred": false
}
```

### Acceptance Criteria

* Given the OCR output loses Vietnamese accents, SnapCal must still attempt to recover common date-time phrases.
* Given normalization changes a critical date/time/location token, SnapCal must preserve both raw and normalized text.
* Given normalized output is uncertain, SnapCal must mark the field as low confidence.
* Given normalized output changes `15/8` into a date, SnapCal must use the user’s locale and timezone.
* Given the model cannot safely distinguish `8h sáng` from `8h tối`, SnapCal must ask the user to confirm.
* Given Vietnamese abbreviation `CN` appears near a date/time phrase, SnapCal may interpret it as Sunday; if used in another context, it must not force a weekday interpretation.

---

## 6.4 Date, Time, and Timezone Parsing

Date and time parsing is the highest-risk part of the product. Wrong title is acceptable; wrong date or time is not.

SnapCal must support both Vietnamese and English event formats.

### Vietnamese formats to support

```text
20h ngày 15/8
19:30, thứ Sáu, 22/08
Thứ 7 tuần này
Chủ nhật, 8 tháng 9
Từ 8h đến 11h30
8h sáng
8h tối
Cả ngày
Ngày mai lúc 9h
Tối nay 20h
T7, 15/8
CN 20/8
15.08.2026
15/08/26
```

### English formats to support

```text
Friday, August 16, 7 PM
Aug 16, 2026 at 7:00 PM
16 Aug, 19:00
Tomorrow at 8 PM
Tonight 7:30
All day
From 9 AM to 12 PM
Doors open at 6 PM, show starts at 7 PM
```

### Default rules

* Default timezone should be the user’s current timezone.
* For Vietnam-based users, the default timezone should normally be `Asia/Ho_Chi_Minh`.
* If location strongly indicates another timezone, SnapCal may suggest changing timezone but must not silently change it.
* If only start time exists, SnapCal should infer duration based on event type.
* If the event is all-day, SnapCal should create an all-day calendar event.
* If the event is in the past, SnapCal must warn the user.

Google Calendar distinguishes timed events using `start.dateTime` / `end.dateTime` and all-day events using `start.date` / `end.date`.

### Default duration policy

```text
Webinar / livestream: 1 hour
Workshop / seminar: 2 hours
Meetup / networking: 2 hours
Concert / performance: 3 hours
Festival / exhibition: all-day or 4 hours, depending on evidence
Generic event: 1 hour
```

### Acceptance Criteria

* Given `20h ngày 15/8`, SnapCal extracts start time `20:00` and date `15/08`.
* Given `Thứ 7, 15/8`, SnapCal validates that the weekday and numeric date are consistent.
* Given weekday and numeric date conflict, SnapCal must flag the conflict.
* Given `8h` with no AM/PM context, SnapCal must mark the time as ambiguous unless event context makes it clear.
* Given `8h tối`, SnapCal extracts `20:00`.
* Given `8h sáng`, SnapCal extracts `08:00`.
* Given `tonight` or `ngày mai`, SnapCal resolves the date using screenshot capture time.
* Given the screenshot contains only a date and no time, SnapCal must offer all-day event or manual time entry.
* Given the event is already in the past, SnapCal must warn before event creation.
* Given the end time is not explicit, SnapCal must mark the end time as estimated.
* Given the event is all-day, SnapCal must create a Google Calendar all-day event.

---

## 6.5 Location and Address Extraction

SnapCal must extract and validate location details from messy text.

### Location types

1. Full address.
2. Venue name.
3. City or district only.
4. Online event.
5. Hybrid event.
6. Unknown location.

### Vietnamese location examples

```text
ĐH Bách Khoa TP.HCM
268 Lý Thường Kiệt, Q.10
Dreamplex, Quận 1
Nhà Văn hóa Thanh Niên
Online qua Zoom
Livestream trên TikTok
```

### English location examples

```text
Dreamplex D1
HCMC University of Technology
Zoom
Google Meet
District 1, Ho Chi Minh City
```

Google Maps APIs can be used to turn addresses into geocoded locations and resolve place candidates through Places/Geocoding workflows.

### Acceptance Criteria

* Given the screenshot contains a full address, SnapCal must extract it as the event location.
* Given the screenshot contains only a venue name, SnapCal must attempt to resolve a place candidate.
* Given multiple place candidates match, SnapCal must ask the user to choose.
* Given the event is online, SnapCal must set location to `Online` and put the meeting/link information in description.
* Given location confidence is low, SnapCal must preserve the raw location text instead of dropping it.
* Given a location is inferred but not explicit, SnapCal must mark it as inferred.
* Given the location parser fails, event creation may continue if date/time/title are valid, but the location field must be visibly incomplete.

---

## 6.6 Event Review and Editing

The review screen is mandatory.

SnapCal must never create a calendar event directly from AI extraction without user confirmation.

### Review screen fields

Required:

* Event title
* Start date
* Start time or all-day flag
* End time or estimated duration
* Calendar selection
* Create button

Optional:

* Location
* Address
* Description
* Source platform
* Source URL
* Reminder settings
* Original OCR evidence
* Confidence warnings

### Confidence levels

```text
High confidence: field looks reliable
Medium confidence: field is inferred or normalized
Low confidence: field may be wrong and needs review
Missing: field is required but unavailable
```

### Acceptance Criteria

* Given required fields are complete and high-confidence, Create Event is enabled.
* Given date or start time is missing, Create Event is disabled unless user selects all-day.
* Given a field is inferred, the UI must show it as inferred.
* Given a field has low confidence, the UI must highlight it.
* Given the user edits a field, the edited value must override extracted value.
* Given the user closes the review screen, SnapCal must save a draft unless the user discards it.
* Given the model reports ambiguity, the UI must show a concise explanation.
* Given the user wants to inspect evidence, SnapCal must show the OCR text that caused the extraction.

---

## 6.7 Google Calendar Integration

SnapCal must create events through Google Calendar.

Google Calendar’s `events.insert` endpoint is used to create events, and reminder overrides are supported with a maximum of 5 override reminders per event.

### Event mapping

```text
title          → summary
location       → location
description    → description
start date/time→ start
end date/time  → end
reminders      → reminders
source note    → description
```

### Description format

```text
Created by SnapCal from screenshot.

Source:
- Platform: Facebook / TikTok / Instagram / Web / Unknown
- Captured at: [timestamp]
- Extracted evidence:
  [short OCR excerpt]

Notes:
[optional extracted description]
```

### Acceptance Criteria

* Given user is not authenticated, SnapCal must start Google OAuth before event creation.
* Given user cancels OAuth, SnapCal must not create the event and must preserve the draft.
* Given user is authenticated, SnapCal must create the event in the selected calendar.
* Given event creation succeeds, SnapCal must show success state and calendar link if available.
* Given event creation fails, SnapCal must preserve the draft and offer retry.
* Given custom reminder overrides exceed 5, SnapCal must block save or ask user to reduce them.
* Given the event is all-day, SnapCal must use all-day event fields.
* Given the event is timed, SnapCal must use timed event fields.

---

## 6.8 Reminder System

SnapCal must automatically suggest reminders.

### Default reminder policy

```text
Generic event:
- 1 day before
- 1 hour before

Online event:
- 30 minutes before
- 5 minutes before

Workshop/seminar:
- 1 day before
- 2 hours before

Same-day event:
- 1 hour before
- 15 minutes before

All-day event:
- 1 day before, morning
```

### Acceptance Criteria

* Given event is more than 24 hours away, SnapCal suggests 1 day before and 1 hour before.
* Given event is less than 24 hours away, SnapCal must not create reminders in the past.
* Given event is online, SnapCal suggests short reminders.
* Given user changes reminder settings, SnapCal applies the selected reminders.
* Given user saves reminder preferences, SnapCal uses them for future events.
* Given reminders exceed Google Calendar limits, SnapCal must ask user to reduce them.

---

## 6.9 Duplicate Detection

Duplicate detection should start simple and become more advanced later.

### MVP duplicate signals

```text
screenshot hash
title + date + time
title + date + location
recent SnapCal drafts
recent SnapCal-created events
```

### Later duplicate signals

```text
read calendar events within ±3 days
semantic similarity
same source URL
same event poster hash
```

### Acceptance Criteria

* Given the same screenshot is imported twice, SnapCal must warn the user.
* Given the same title/date/location exists in local SnapCal history, SnapCal must warn the user.
* Given user confirms duplicate creation, SnapCal must allow event creation.
* Given calendar read permission is not granted, SnapCal must use only local duplicate detection.
* Given duplicate confidence is low, SnapCal should show a soft warning, not block creation.

---

## 6.10 Privacy and Data Retention

Screenshots may contain private messages, names, addresses, phone numbers, and social media content. Privacy must be part of the product design.

### Privacy requirements

1. No automatic event creation.
2. Raw screenshots deleted by default after successful extraction.
3. Local drafts stored securely.
4. Backend logs must not store raw screenshots or full OCR text.
5. User can delete local history.
6. User can disable screenshot history.
7. User can choose local-first OCR mode later.
8. Third-party AI usage must be disclosed.

### Acceptance Criteria

* Given extraction succeeds, SnapCal deletes the raw screenshot unless screenshot history is enabled.
* Given extraction fails, SnapCal asks whether to keep the image for retry.
* Given user deletes history, local drafts and screenshots are deleted.
* Given backend logging is enabled, logs must not contain raw image data.
* Given cloud OCR or AI model is used, SnapCal must disclose that the image or OCR text may be sent to a third-party service.
* Given user disables cloud processing, SnapCal must only run local OCR and show reduced accuracy warning.

---

# 7. Data Model

## 7.1 Extracted Event Draft

```json
{
  "draft_id": "uuid",
  "created_at": "ISO-8601",
  "source": {
    "platform": "facebook|tiktok|instagram|web|photo|unknown",
    "source_url": "string|null",
    "captured_at": "ISO-8601",
    "input_type": "screenshot|shared_image|clipboard|file"
  },
  "language": {
    "detected": ["vi", "en"],
    "primary": "vi|en|mixed|unknown"
  },
  "title": {
    "value": "string|null",
    "evidence_text": "string|null",
    "confidence": 0.0,
    "is_inferred": false
  },
  "start": {
    "date": "YYYY-MM-DD|null",
    "time": "HH:mm|null",
    "timezone": "IANA timezone",
    "is_all_day": false,
    "evidence_text": "string|null",
    "confidence": 0.0,
    "is_inferred": false
  },
  "end": {
    "date": "YYYY-MM-DD|null",
    "time": "HH:mm|null",
    "timezone": "IANA timezone",
    "is_estimated": true,
    "evidence_text": "string|null",
    "confidence": 0.0
  },
  "location": {
    "name": "string|null",
    "address": "string|null",
    "raw_text": "string|null",
    "place_id": "string|null",
    "is_online": false,
    "confidence": 0.0
  },
  "description": {
    "value": "string|null",
    "evidence_text": "string|null",
    "confidence": 0.0
  },
  "reminders": [
    {
      "method": "popup|email",
      "minutes_before": 60
    }
  ],
  "ambiguities": [
    {
      "field": "date|time|location|title",
      "message": "string",
      "severity": "low|medium|high"
    }
  ],
  "overall_confidence": 0.0,
  "requires_user_confirmation": true
}
```

---

# 8. Recommended Technical Architecture

## 8.1 High-Level Architecture

```text
Client App
  ├── macOS Menu Bar Utility
  ├── macOS Top-Center Drop Zone
  ├── iOS Share Extension
  └── Android Share Target

Input Processing Layer
  ├── Image validation
  ├── Image compression
  ├── Orientation correction
  ├── Optional crop/text-region detection
  └── Metadata capture

OCR Layer
  ├── Apple Vision OCR
  ├── ML Kit OCR
  ├── Google Cloud Vision OCR fallback
  └── OCR confidence aggregation

AI Extraction Layer
  ├── Vision-language model
  ├── Structured JSON output
  ├── Field-level evidence extraction
  └── Ambiguity detection

Normalization Layer
  ├── Vietnamese-English text normalization
  ├── Vietnamese date/time parser
  ├── English date/time parser
  ├── Timezone resolver
  ├── Location resolver
  └── Reminder generator

Calendar Layer
  ├── Google OAuth
  ├── Calendar selection
  ├── Google Calendar events.insert
  ├── Retry handling
  └── Duplicate detection

Review UI
  ├── Editable fields
  ├── Confidence warnings
  ├── Evidence viewer
  ├── Create Event button
  └── Success confirmation
```

## 8.2 Recommended Stack

### macOS app

```text
SwiftUI
AppKit bridge for floating drop zone
MenuBarExtra for menu-bar utility
Apple Vision for local OCR
Keychain for token storage
SQLite for local drafts
```

### Backend

```text
FastAPI or Node.js
PostgreSQL for user/draft metadata
Object storage only if screenshot history is enabled
Queue worker for async extraction
Google Calendar API client
Google Maps/Places integration
```

### AI/OCR

```text
Apple Vision OCR: local first pass
Google Cloud Vision OCR: Vietnamese-heavy fallback
OpenAI or Gemini vision model: screenshot understanding
Structured JSON schema: strict event draft output
Custom Vietnamese-English parser: date/time/location normalization
```

### Best MVP stack

```text
macOS: SwiftUI + AppKit + Apple Vision
Backend: FastAPI
AI: OpenAI or Gemini vision model with structured output
OCR fallback: Google Cloud Vision OCR
Calendar: Google Calendar API
Location: Google Places / Geocoding
Storage: SQLite local first, PostgreSQL later
```

---

# 9. Phased Product Plan

## Phase 1 — Core Extraction and Calendar Prototype

### Objective

Validate the core pipeline:

```text
manual screenshot upload
→ event extraction
→ review
→ Google Calendar creation
```

No notch UI yet. No mobile yet. The goal is to prove that extraction and calendar creation work.

### User Story 1.1 — Upload an event screenshot

As a user, I want to upload a screenshot of an event so that SnapCal can extract event details.

Acceptance Criteria:

* Given I upload a valid image, SnapCal starts extraction.
* Given the image is unsupported, SnapCal shows an error.
* Given extraction is running, SnapCal shows a loading state.
* Given extraction finishes, SnapCal shows an event draft.
* Given extraction fails, SnapCal shows retry and does not lose the uploaded image unless privacy settings require deletion.

### User Story 1.2 — Extract event fields

As a user, I want SnapCal to extract title, date, time, and location so that I do not type them manually.

Acceptance Criteria:

* Given the screenshot contains a visible event title, SnapCal fills the title field.
* Given the screenshot contains a visible date, SnapCal fills the date field.
* Given the screenshot contains a visible time, SnapCal fills the time field.
* Given the screenshot contains a visible location, SnapCal fills the location field.
* Given a required field is missing, SnapCal marks it as missing.
* Given SnapCal estimates a field, it must mark that field as inferred or estimated.

### User Story 1.3 — Create Google Calendar event

As a user, I want to create a Google Calendar event from the extracted draft.

Acceptance Criteria:

* Given I am not authenticated, SnapCal starts Google OAuth.
* Given I am authenticated, SnapCal creates the event in my selected Google Calendar.
* Given event creation succeeds, SnapCal shows success confirmation.
* Given event creation fails, SnapCal preserves the draft and offers retry.
* Given the event has missing date/time, SnapCal blocks creation.

### Phase 1 Exit Criteria

* Manual upload works.
* Basic extraction works for both Vietnamese and English screenshots.
* Google OAuth works.
* Google Calendar event creation works.
* No event is created without user review.

---

## Phase 2 — Vietnamese-English OCR and Parsing Reliability

### Objective

Make Vietnamese and English extraction reliable enough for real event screenshots.

### User Story 2.1 — Extract Vietnamese event screenshots

As a Vietnamese user, I want SnapCal to understand Vietnamese event posters and screenshots.

Acceptance Criteria:

* Given the screenshot contains `20h ngày 15/8`, SnapCal extracts the correct date and 24-hour time.
* Given the screenshot contains `Thứ 7`, `T7`, or `Thứ bảy`, SnapCal interprets it as Saturday when used in a date-time context.
* Given the screenshot contains `CN`, SnapCal interprets it as Sunday only when used in a date-time context.
* Given the screenshot contains `8h tối`, SnapCal extracts `20:00`.
* Given the screenshot contains `8h sáng`, SnapCal extracts `08:00`.
* Given the screenshot contains Vietnamese without diacritics, SnapCal attempts normalization.
* Given the screenshot contains mixed Vietnamese-English text, SnapCal extracts one coherent event.

### User Story 2.2 — Extract English event screenshots

As a user, I want SnapCal to understand English event formats.

Acceptance Criteria:

* Given the screenshot contains `Friday, August 16, 7 PM`, SnapCal extracts date and time.
* Given the screenshot contains `Tomorrow at 8 PM`, SnapCal resolves the date using capture time.
* Given the screenshot contains `All day`, SnapCal creates an all-day draft.
* Given the screenshot contains `Doors open at 6 PM, show starts at 7 PM`, SnapCal prefers event start time and preserves door time in description.

### User Story 2.3 — Handle OCR uncertainty

As a user, I want SnapCal to warn me when extraction may be wrong.

Acceptance Criteria:

* Given OCR confidence is low, SnapCal triggers fallback extraction.
* Given date and weekday conflict, SnapCal flags the conflict.
* Given OCR reads `20:OO`, SnapCal normalizes to `20:00` only if confidence is high.
* Given OCR reads `l5/8`, SnapCal must not silently convert it to `15/8` unless supported by context.
* Given two possible dates exist, SnapCal asks user to choose.

### User Story 2.4 — Build a Vietnamese-English benchmark

As a product team, we want a benchmark dataset so that OCR reliability can be measured.

Acceptance Criteria:

* Benchmark includes at least 100 screenshots.
* At least 50 screenshots must be Vietnamese or Vietnamese-English mixed.
* Benchmark includes Facebook, TikTok, Instagram, website, university, workshop, hackathon, concert, and poster screenshots.
* Benchmark includes low-resolution and decorative-font examples.
* Each benchmark item has ground-truth title, date, time, location, and language labels.
* Extraction metrics are tracked separately for Vietnamese and English.

### Phase 2 Exit Criteria

* Vietnamese date/time parser works for common real-world formats.
* English date/time parser works for common real-world formats.
* OCR fallback is triggered when local OCR is weak.
* Field-level confidence and evidence are available.
* Benchmark results are measurable.

---

## Phase 3 — macOS Notch-Style MVP

### Objective

Build the real macOS user experience:

```text
drag screenshot
→ drop into top-center SnapCal zone
→ review
→ create event
```

### User Story 3.1 — Use a top-center drop zone

As a macOS user, I want to drag a screenshot into a notch-style drop zone so that I can start extraction quickly.

Acceptance Criteria:

* Given SnapCal is running, a menu-bar item is available.
* Given I drag an image near the top-center area, the drop zone appears or expands.
* Given I drop a valid image, extraction starts.
* Given I drop an invalid file, SnapCal shows a clear error.
* Given extraction starts, SnapCal shows processing state.

### User Story 3.2 — Import from clipboard

As a macOS user, I want to paste a screenshot into SnapCal so that I do not need to save it as a file.

Acceptance Criteria:

* Given clipboard contains an image, SnapCal can import it.
* Given clipboard does not contain an image, SnapCal shows a helpful message.
* Given pasted image is valid, extraction starts.
* Given pasted image is invalid, SnapCal does not create a draft.

### User Story 3.3 — Access recent drafts from menu bar

As a user, I want to access recent extraction drafts from the menu bar.

Acceptance Criteria:

* Given I have recent drafts, SnapCal lists them in the menu-bar app.
* Given I select a draft, SnapCal opens the review screen.
* Given I delete a draft, it is removed locally.
* Given a draft was already created as a calendar event, SnapCal marks it as completed.

### Phase 3 Exit Criteria

* macOS menu-bar utility works.
* Top-center drop zone works.
* Drag-and-drop image intake works.
* Clipboard import works.
* Review screen opens after extraction.
* Local draft history exists.

---

## Phase 4 — Review UX, Reminders, Location, Duplicate Detection, and Privacy

### Objective

Make the MVP trustworthy and safe.

### User Story 4.1 — Review and edit all fields

As a user, I want to review and edit the event before creation.

Acceptance Criteria:

* Given extraction succeeds, the review screen displays all extracted fields.
* Given date/time is missing, Create Event is disabled.
* Given location is missing, Create Event remains available but location is marked incomplete.
* Given a field is low-confidence, it is highlighted.
* Given I edit a field, the edited value is used in the calendar event.
* Given I close the review screen, SnapCal saves the draft.

### User Story 4.2 — Configure reminders

As a user, I want SnapCal to suggest reminders automatically.

Acceptance Criteria:

* Given event is more than 24 hours away, SnapCal suggests 1 day before and 1 hour before.
* Given event is same-day, SnapCal avoids past reminders.
* Given event is online, SnapCal suggests short reminders.
* Given I modify reminders, SnapCal uses my selected reminders.
* Given reminder count exceeds Google Calendar limits, SnapCal blocks save and asks for reduction.

### User Story 4.3 — Resolve locations

As a user, I want SnapCal to clean up venue and address information.

Acceptance Criteria:

* Given a full address is detected, SnapCal uses it.
* Given only venue name is detected, SnapCal suggests candidate places.
* Given multiple candidates exist, SnapCal asks user to choose.
* Given no reliable location is found, SnapCal preserves raw text.
* Given event is online, SnapCal sets location to Online.

### User Story 4.4 — Detect duplicates

As a user, I want SnapCal to warn me before creating duplicate events.

Acceptance Criteria:

* Given the same screenshot is imported twice, SnapCal warns me.
* Given same title/date/time/location exists locally, SnapCal warns me.
* Given I confirm duplicate creation, SnapCal allows it.
* Given duplicate confidence is low, SnapCal shows a soft warning only.

### User Story 4.5 — Protect screenshot privacy

As a user, I want SnapCal to avoid storing sensitive screenshots unnecessarily.

Acceptance Criteria:

* Given extraction succeeds, raw screenshot is deleted by default.
* Given screenshot history is enabled, SnapCal stores screenshots locally.
* Given I delete history, SnapCal removes local screenshots and drafts.
* Given cloud AI is used, SnapCal clearly discloses it.
* Given local-only mode is enabled, SnapCal does not send images to cloud services.

### Phase 4 Exit Criteria

* Review screen is safe and clear.
* Reminders are configurable.
* Location handling works.
* Duplicate warnings work.
* Privacy settings are implemented.
* Raw screenshot deletion works by default.

---

## Phase 5 — Mobile Support

### Objective

Support iOS and Android screenshot-to-calendar workflows.

### User Story 5.1 — iOS Share Extension

As an iPhone user, I want to share a screenshot to SnapCal from Photos or another app.

Acceptance Criteria:

* Given I tap Share on a screenshot, SnapCal appears as a share option.
* Given I share an image to SnapCal, extraction starts.
* Given extraction succeeds, SnapCal opens the review screen.
* Given I confirm, SnapCal creates a Google Calendar event.
* Given extraction fails, SnapCal shows retry.

### User Story 5.2 — Android Share Target

As an Android user, I want to send a screenshot to SnapCal from the Android share sheet.

Acceptance Criteria:

* Given I share an image from Gallery or another app, SnapCal receives the image.
* Given the image is valid, extraction starts.
* Given extraction succeeds, SnapCal opens the review screen.
* Given I confirm, SnapCal creates a Google Calendar event.
* Given the image is invalid, SnapCal shows an error.

### User Story 5.3 — Mobile review screen

As a mobile user, I want to review and correct extracted fields before event creation.

Acceptance Criteria:

* Given extraction succeeds, mobile review screen displays title, date, time, location, reminders, and calendar.
* Given a required field is missing, Create Event is disabled.
* Given I edit fields, the edits are used.
* Given I close the app, draft is preserved.
* Given event creation succeeds, SnapCal shows success state.

### Phase 5 Exit Criteria

* iOS Share Extension works.
* Android Share Target works.
* Mobile review screen works.
* Shared backend supports desktop and mobile.
* Vietnamese-English extraction quality remains consistent across platforms.

---

## Phase 6 — Personalization and Automation

### Objective

Reduce repeated manual edits and support power-user workflows.

### User Story 6.1 — Remember user preferences

As a user, I want SnapCal to remember my default calendar, reminder settings, and event duration.

Acceptance Criteria:

* Given I select a default calendar, future events use it.
* Given I set reminder preferences, future events use them.
* Given I set default duration, inferred events use it.
* Given I change preferences, new drafts use the updated settings.

### User Story 6.2 — Local-first extraction mode

As a privacy-conscious user, I want SnapCal to process screenshots locally when possible.

Acceptance Criteria:

* Given local-only mode is enabled, SnapCal does not send screenshots to cloud OCR or AI.
* Given local OCR is insufficient, SnapCal shows a reduced-accuracy warning.
* Given user allows cloud fallback for one image, SnapCal may process that image in cloud mode.
* Given cloud fallback completes, SnapCal returns to local-only mode afterward.

### User Story 6.3 — Automation shortcuts

As a power user, I want to trigger SnapCal through shortcuts or app intents.

Acceptance Criteria:

* Given an image is passed into the shortcut, SnapCal creates an event draft.
* Given the shortcut is configured for review mode, SnapCal opens review screen.
* Given the shortcut is configured for draft-only mode, SnapCal saves the draft.
* Given required fields are missing, SnapCal does not auto-create an event.

### Phase 6 Exit Criteria

* Preferences are persistent.
* Local-only mode exists.
* Shortcut/app-intent workflow exists.
* Draft-only automation is supported.
* Auto-create remains disabled unless the product later introduces a very strict trusted mode.

---

# 10. Success Metrics

## 10.1 Product Metrics

```text
screenshot_to_preview_success_rate
preview_to_event_creation_rate
average_manual_corrections_per_event
median_time_from_import_to_created_event
duplicate_warning_accuracy
user_correction_rate_by_field
```

## 10.2 Extraction Metrics

Measure Vietnamese and English separately.

```text
title_accuracy_vi
date_accuracy_vi
time_accuracy_vi
location_accuracy_vi
title_accuracy_en
date_accuracy_en
time_accuracy_en
location_accuracy_en
critical_field_error_rate
ambiguous_field_detection_rate
```

### Critical field definition

Critical fields are:

```text
date
start time
timezone
location, if travel is required
```

Wrong critical fields are more serious than missing fields. SnapCal should prefer asking for confirmation over silently creating a wrong event.

## 10.3 MVP Quality Targets

```text
Vietnamese title extraction accuracy: ≥ 85%
Vietnamese date extraction accuracy: ≥ 85%
Vietnamese time extraction accuracy: ≥ 80%
English title extraction accuracy: ≥ 90%
English date extraction accuracy: ≥ 90%
English time extraction accuracy: ≥ 85%
Critical wrong-date/wrong-time rate: ≤ 3%
Median extraction latency: ≤ 10 seconds
Google Calendar creation success after OAuth: ≥ 95%
```

---

# 11. Test Plan

## 11.1 Benchmark Dataset

The benchmark should contain at least 100 screenshots initially, then expand to 300+.

Minimum composition:

```text
50 Vietnamese or Vietnamese-English screenshots
30 English screenshots
20 noisy / low-resolution / decorative-font screenshots
```

Sources:

```text
Facebook event posts
TikTok event screenshots
Instagram stories
University seminar posters
Hackathon posters
Workshop posters
Concert posters
Webinar posters
Website event pages
Online event screenshots
```

## 11.2 Required Test Cases

```text
Clear Vietnamese event with full date/time/location
Clear English event with full date/time/location
Vietnamese event without diacritics
Vietnamese event with abbreviations: T7, CN, Q.1, TP.HCM
Event with no end time
Event with no location
Online event
All-day event
Past event
Multiple dates in one screenshot
Multiple times in one screenshot
Weekday/date conflict
Low-resolution screenshot
Decorative poster font
Same screenshot imported twice
```

## 11.3 Test Acceptance Criteria

* Every benchmark image produces either a valid draft or a clear failure reason.
* No draft may invent a date when no date evidence exists.
* No draft may create an event without user confirmation.
* Every critical field must include evidence text.
* Vietnamese and English metrics must be reported separately.
* Regression tests must run whenever extraction prompts, OCR engines, or parsers change.

---

# 12. Final MVP Definition

The MVP is complete when SnapCal can:

1. Accept a screenshot on macOS through drag-and-drop or clipboard.
2. Extract Vietnamese and English event details.
3. Normalize Vietnamese-English date/time/location expressions.
4. Show an editable review screen.
5. Highlight ambiguous or low-confidence fields.
6. Create a Google Calendar event after user confirmation.
7. Add reasonable reminders.
8. Preserve local drafts.
9. Warn about duplicate screenshots.
10. Delete raw screenshots by default after successful extraction.
11. Report benchmark quality separately for Vietnamese and English.

---

# 13. Recommended Build Priority

## Priority 1 — Extraction correctness

Build the extraction pipeline first. The product is only useful if date, time, and location are reliable.

## Priority 2 — Review safety

Build a strong review screen before optimizing UX. Wrong automatic calendar events will destroy trust.

## Priority 3 — macOS drop-zone UX

After extraction and review work, build the notch-style drop zone.

## Priority 4 — Mobile support

Mobile is important, but it should reuse the same backend and extraction logic.

## Priority 5 — Automation

Only add automation after the product is reliable enough to avoid dangerous calendar mistakes.

---

# 14. Key Product Decision

SnapCal should be designed as a **Vietnamese-English event extraction system**, not as a generic OCR wrapper.

The highest-risk problem is not OCR itself. The highest-risk problem is converting messy screenshot text into a correct calendar object:

```text
Vietnamese/English text
→ normalized event semantics
→ correct date
→ correct start time
→ correct timezone
→ correct location
→ safe calendar creation
```

Therefore, the core intellectual property of the product should be:

1. Vietnamese-English OCR fallback pipeline.
2. Vietnamese-English date/time parser.
3. Field-level evidence and confidence scoring.
4. Human-in-the-loop review UX.
5. Calendar-safe event creation.
