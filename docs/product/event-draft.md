# Event Draft And Normalization

## Canonical Draft

An extracted draft owns:

- identifiers and timestamps;
- source platform, URL, capture time, and input type;
- detected language(s);
- title, start, end, location, description, and reminders;
- evidence, confidence, and inference metadata per field;
- ambiguities, overall confidence, and confirmation requirement;
- lifecycle state: draft, reviewed, creating, created, failed, or discarded.

The JSON shape in `SPEC.md` section 7 is the seed contract. Implementation must
turn it into typed domain/application models before choosing persistence or API
serialization details.

## Evidence-Bearing Field

Every critical field follows this logical shape:

```json
{
  "value": "normalized value or null",
  "evidence_text": "raw supporting excerpt or null",
  "confidence": 0.91,
  "is_inferred": false
}
```

Location additionally preserves raw text and any resolved place identifier.
End time records whether it was estimated. User edits replace the proposed
value but do not erase the extraction evidence.

## Normalization Rules

- Interpret Vietnamese abbreviations only in matching context: `T7`/`Thứ 7`,
  `CN`, `Q.1`, and `TP.HCM` are not unconditional substitutions.
- Resolve relative dates from `source.captured_at` in the user's timezone.
- Default to the current timezone, normally `Asia/Ho_Chi_Minh` for Vietnam; a
  location may suggest another timezone but cannot silently change it.
- Validate weekday and numeric-date consistency.
- `8h` without AM/PM context is ambiguous unless strong event context resolves
  it; `8h sáng` is `08:00`, while `8h tối` is `20:00`.
- All-day events use dates, not synthetic midnight timestamps.
- Past events produce a warning before creation.
- Missing end time may use a typed duration policy, but the result is estimated.

## Default Duration Policy

| Event type | Default |
| --- | --- |
| Webinar or livestream | 1 hour |
| Workshop or seminar | 2 hours |
| Meetup or networking | 2 hours |
| Concert or performance | 3 hours |
| Festival or exhibition | all-day or 4 hours, evidence-dependent |
| Unknown | 1 hour |

## Confidence And Ambiguity

- High: evidence and parsers agree.
- Medium: normalized or inferred but plausible.
- Low: likely requires correction.
- Missing: required value unavailable.

Confidence is not permission to create an event. `requires_user_confirmation`
remains true for every MVP draft.

## Draft Persistence

SQLite is the first local store for draft metadata. Raw screenshots are not
part of the durable draft by default. Provider DTOs, local rows, and future API
payloads must be parsed at their boundaries rather than shared as one mutable
model.
