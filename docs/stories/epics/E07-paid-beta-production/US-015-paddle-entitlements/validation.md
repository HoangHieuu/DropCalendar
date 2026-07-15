# Validation

## Proof Strategy

Use signed fixtures and a recording Paddle adapter without live purchases.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | entitlement-state matrix, signature timestamp/tolerance |
| Integration | duplicate and out-of-order webhooks, invite gating |
| E2E | checkout/portal URL and webhook-to-`/me` refresh |
| Platform | browser redirect alone never unlocks Accuracy |
| Performance | webhook returns within five seconds |
| Logs/Audit | no signature, email, customer payload, or secret leakage |

## Fixtures

Signed Paddle event samples covering all accepted subscription states.

## Commands

```text
.venv/bin/python -m pytest services/extraction-api/tests
```

## Acceptance Evidence

Implemented with signed fakes. Live Paddle sandbox checkout and webhook delivery
remain activation gates.
