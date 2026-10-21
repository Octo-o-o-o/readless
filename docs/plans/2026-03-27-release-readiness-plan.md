# Readless Release Readiness Plan

## Goal

Before public release, tighten the parts of Readless that affect how other developers judge the project:

- Architecture should feel intentional instead of incidental.
- Core runtime behavior should be observable, debuggable, and predictable.
- Client and server contracts should be explicit and testable.
- Operational defaults should look like a production-ready open source project, not a prototype that happens to work.

## Current Assessment

### What is already strong

- Backend test coverage is unusually good for the project stage and currently passes cleanly.
- The backend already has sensible domain boundaries: routers, services, models, schemas.
- Content processing has a durable queue model rather than naive in-request work.
- The macOS app already separates `Core`, `Networking`, `Storage`, and feature code, which is the right direction.

### Release blockers or quality gaps worth fixing now

1. macOS network contract is not stable enough.
   - `swift test` currently fails.
   - Endpoint path construction is inconsistent and relies on implicit URL behavior.
   - Token refresh coordination has a race, which can surface as unnecessary sign-outs or failed retries.

2. Backend operational surface is too thin for a public release.
   - `/health` is only a liveness ping and does not help diagnose readiness.
   - Requests are not tagged with a request ID, which makes debugging production failures harder.
   - Security/operational response headers are not standardized.

3. The in-memory rate limiter has an avoidable long-run memory growth pattern.
   - Old identifiers can accumulate indefinitely in the bucket map.
   - That is small at first, but it is the kind of infrastructure detail reviewers notice in an otherwise polished project.

## Changes To Implement

### 1. Harden the macOS networking layer

- Introduce a canonical request builder in `APIClient`.
- Stop scattering raw string concatenation for paths and query parameters.
- Preserve route intent consistently across requests and tests.
- Fix `AuthRefreshCoordinator` so it subscribes before waiting and does not miss refresh completion notifications.
- Update tests so the networking layer has a reliable regression net.

Why this is worth doing:
This directly affects user experience, test credibility, and the perceived engineering quality of the client.

### 2. Add backend release-grade operational middleware and health endpoints

- Keep `/health` for compatibility.
- Add a readiness endpoint that checks the database connection.
- Attach a request ID to every response.
- Add small but standard hardening headers to API responses.

Why this is worth doing:
These are low-risk changes with high operational value. They make the project look and behave like a maintained production service.

### 3. Make the in-memory rate limiter self-pruning

- Remove empty buckets promptly.
- Periodically sweep stale buckets so long-running processes do not retain dead identifiers forever.
- Add explicit tests for cleanup behavior.

Why this is worth doing:
This is a small change, but it improves correctness and demonstrates attention to infrastructure details.

## Not Doing In This Pass

- Replacing core service choices like FastAPI, SQLAlchemy, or SwiftPM.
- Reworking the summarization pipeline prompts or AI provider abstraction.
- Large-scale UI redesign.
- Deep database/index redesign beyond readiness and operational safety.

Those may still be valuable later, but they are not the highest-value release pass relative to risk.

## Definition Of Done

- `backend` test suite passes.
- `macos` test suite passes.
- The networking layer has deterministic request construction and token refresh behavior.
- The backend exposes liveness plus readiness behavior without breaking current integrations.
- Middleware and rate limiter changes are covered by tests.

## Final Review Addendum

### Implemented in the second release-readiness pass

- Completed the email-verification product loop instead of leaving registration with a dead link.
  - Verification emails now point at a browser-safe backend route.
  - `GET /api/v1/auth/email/verify` renders a human-readable success or failure page.
  - Resend flow now keeps the previous token valid if delivery fails, instead of invalidating it first.

- Hardened email delivery behavior.
  - Resend HTTP/network failures are converted into stable application errors.
  - Verification resend now normalizes email addresses before lookup and delivery.

- Tightened macOS stability and release diagnostics.
  - Removed crash-prone AX force casts in text capture.
  - Replaced singleton `try!` initialization in storage setup with explicit fatal diagnostics.

- Cleaned release-facing documentation.
  - Replaced stale `swift run App` instructions with the actual Xcode/Xcodebuild flow.
  - Removed outdated Clerk references from release docs.
  - Standardized the repository license declaration at the root.

### What remains intentionally out of scope

- Large architectural rewrites of the AI pipeline or search stack.
- UI redesign beyond release-critical correctness and clarity.
- Changes that materially increase risk this close to release without comparable payoff.
