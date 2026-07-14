# US-004 Design

## Domain Model

- Keep the provider-neutral `CloudEventExtracting` boundary.
- Rename the provider-specific extraction notice from Gemini to OpenRouter.
- Keep the versioned event proposal, evidence, confidence, and ambiguity rules.

## Application Flow

1. The service loads root `.env` without exposing values to the macOS process.
2. Accuracy Mode calls the existing loopback `/v1/extract` endpoint.
3. The proxy sends prompt text and a base64 data URL image to OpenRouter.
4. OpenRouter returns strict JSON Schema output from the configured model.
5. Pydantic validates the proposal before returning it to SnapCal.
6. SnapCal performs its existing client validation and local/cloud disagreement
   checks before review.

## Interface Contract

- The SnapCal-to-proxy request and response remain schema version `1`.
- `GET /health` reports `provider=openrouter`, configured model, and readiness.
- Provider authentication uses `Authorization: Bearer` only inside the proxy.
- Optional `HTTP-Referer` and `X-OpenRouter-Title` headers come from environment
  configuration.
- Stable proxy errors never echo provider bodies, image data, OCR, or secrets.

## Data Model

No persistence or migration. Requests and responses remain memory-only.

## UI / Platform Impact

- Accuracy Mode disclosure and review source identify OpenRouter.
- Local Only remains the default and makes no cloud request.

## Observability

No raw provider request/response logging. Health reports only provider, model,
and readiness.

## Alternatives Considered

1. Keep direct Google Gemini: rejected because the user selected OpenRouter.
2. Put the OpenRouter key in the macOS app: rejected because distributed client
   binaries cannot protect provider credentials.
3. Remove strict structured output: rejected because unvalidated model output
   cannot enter the event domain.
