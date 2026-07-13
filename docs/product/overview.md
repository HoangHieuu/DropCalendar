# Product Overview

## Purpose

SnapCal creates a Google Calendar event from an event screenshot with minimal
typing. It is not a generic OCR wrapper: its product value is safely converting
messy Vietnamese or English evidence into correct event semantics.

## Primary Flow

```text
capture or receive screenshot
  -> validate image
  -> extract OCR and visual evidence
  -> normalize event fields
  -> surface ambiguity and confidence
  -> user reviews and edits
  -> user explicitly creates Google Calendar event
```

## Users

- Primary: Vietnamese students and young professionals who encounter local
  workshops, university events, hackathons, concerts, and community posts.
- Secondary: English-speaking event followers whose details are embedded in
  posters or social images.
- Tertiary: mobile-first users who start from the iOS or Android share sheet.

## Goals

- Extract title, date, time, timezone, location, description, and reminder
  suggestions from Vietnamese, English, and mixed-language screenshots.
- Minimize manual typing while requiring a review before calendar creation.
- Prefer missing or explicitly ambiguous critical data over a wrong silent
  inference.
- Support real, noisy screenshots and preserve the evidence behind each
  critical field.
- Minimize screenshot retention and sensitive logging.

## Non-Goals For The MVP

- Scraping private social platforms.
- Creating events without user confirmation.
- Registering for events or purchasing tickets.
- Processing multiple events from one screenshot.
- Replacing Google Calendar or Apple Calendar.
- Reading the user's full calendar without explicit permission.
- Guaranteeing correct extraction from every low-quality image.

## Critical Invariants

1. Review is mandatory before any external calendar write.
2. Date, start time, timezone, and travel-critical location are critical fields.
3. Critical fields retain raw evidence, normalized value, confidence, and
   inference state.
4. OCR/vision disagreement on a critical field becomes an ambiguity; it is not
   resolved silently.
5. A screenshot with no event evidence returns `No event detected`.
6. Raw screenshots are deleted by default after successful extraction.

## MVP Definition

The MVP is complete when macOS accepts an image by drag/drop or clipboard,
extracts Vietnamese and English event details, opens an editable review,
highlights uncertainty, creates a Google Calendar event after confirmation,
adds valid reminders, preserves local drafts, warns on duplicates, deletes raw
screenshots by default, and reports Vietnamese and English benchmark results
separately.
