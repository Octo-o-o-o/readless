# Readless Refactor Plan (2026-03-12)

## Scope

This plan is based on a fresh reread of the current codebase on 2026-03-12.

Assumptions:

- Backend remains single-instance for now.
- FastAPI + async SQLAlchemy + PostgreSQL stay in place.
- macOS client remains SwiftUI + SPM + GRDB.
- The goal is not a rewrite. The goal is to reduce defect surface, make future changes cheaper, and keep rollout risk controllable.

This document includes only refactors with real payoff. It intentionally excludes broad cleanup that looks nice but has weak return.

## Current Architecture Snapshot

### Backend

- `backend/app/routers/content.py` mixes HTTP routing, content response assembly, in-process job scheduling, recovery, timeout handling, and summary gating.
- `backend/app/services/pipeline.py` already became a real application service, but the content orchestration boundary is still split between router and service.
- `backend/app/services/auth_service.py` combines too many responsibilities: credential auth, email code auth, refresh-token rotation, password reset, account deletion, and Apple Sign In.
- `backend/app/services/storekit_receipt.py` and `backend/app/services/subscription_service.py` rely heavily on untyped `dict` payloads, which raises regression risk when Apple payload mapping changes.
- Several routers still contain direct SQL and response shaping logic (`auth.py`, `content.py`, `tags.py`, `subscription.py`) instead of staying thin.

### macOS client

- `macos/Sources/App/Services/ContentManager.swift` owns content list loading, local cache writes, import workflow, import polling, capsule UI state, and toast behavior.
- `macos/Sources/App/ViewModels/ReaderViewModel.swift` mixes content loading, status polling, paragraph loading, expand/follow-up logic, and translation state.
- `macos/Sources/Networking/APIClient.swift` owns HTTP transport, error mapping, token refresh orchestration, and logging.
- App-level coordination still leans on `NotificationCenter` for cross-cutting events such as auth refresh and opening content.
- `LocalDatabase`, `ContentManager`, `ReaderViewModel`, and `LocalSearchService` all touch the same persistence concepts directly, so storage behavior is spread across several layers.

### Cross-layer contract

- The client models use enums for `ContentStatus` and `SourceType`, but backend request/response schemas still use raw strings.
- Some behavior is implicit rather than represented in data. Example: stuck content is inferred from timestamps instead of explicit processing metadata.
- Several large flows already cross service boundaries correctly, but the boundaries are not enforced by types or dedicated modules.

## Selection Rules

A refactor is included only if it meets all of the following:

- It reduces a real bug/regression surface that already exists in the current architecture.
- It can be shipped in additive steps without rewriting the app.
- It has a clear rollback story.
- It avoids increasing operational complexity beyond the current single-instance setup.

## Worth Doing

### P0. Split content orchestration out of the content router

Why it is worth doing:

- `content.py` is now the hottest change surface in the project.
- Every new behavior change in content import currently touches HTTP layer code, which increases regression risk.
- The router is carrying concerns that belong in an application service: scheduling, recovery, timeout policy, and response assembly.

What to do:

- Introduce a dedicated backend module, for example `app/services/content_jobs.py`.
- Move these responsibilities out of `backend/app/routers/content.py`:
  - in-process task registry
  - queue scheduling and deduplication
  - recovery replay for recoverable payloads
  - timeout-to-failed policy
- Introduce a `ContentQueryService` or `ContentResponseBuilder` for:
  - batch tag hydration
  - `ContentResponse` mapping
  - "content must be ready" guards
- Reuse that same response-assembly path from both `content.py` and `tags.py` so content DTO shaping is not duplicated across routers.
- Keep `ProcessingPipeline` as the core extract/summarize/store service.
- Reduce the router to:
  - parse request
  - call orchestration/query services
  - map domain errors to HTTP errors

Expected payoff:

- Lower content-path regression risk.
- Easier future work on import status, retries, and admin tooling.
- Better unit-test granularity.

Risk control:

- First extract code without behavior changes.
- Keep route paths and response shapes identical.
- Preserve all current tests and add new service-level tests before deleting router helpers.

Acceptance:

- `backend/app/routers/content.py` no longer owns task bookkeeping.
- The router becomes a thin transport layer.
- Existing content/import tests continue to pass unchanged or with strictly narrower fixtures.

### P0. Persist explicit content processing metadata

Why it is worth doing:

- Current timeout handling infers "stuck" from `created_at`/`updated_at`.
- That is workable in single-instance mode, but it is still only an approximation.
- The current model cannot explain why processing failed, how many times it ran, or whether it is safe to retry.

What to do:

- Add additive columns to `contents`:
  - `processing_started_at`
  - `processing_finished_at`
  - `processing_error`
  - `processing_attempts`
- Update `ProcessingPipeline` and the content job service so state transitions are explicit:
  - `pending -> processing`
  - `processing -> ready`
  - `processing -> failed`
- Keep the existing `status` field for API compatibility.
- Use these fields for timeout checks and later retry tooling.

Expected payoff:

- Better correctness than timestamp inference.
- Better observability for support and admin views.
- Safer retry/recovery later without guesswork.

Risk control:

- Add fields in a backward-compatible migration.
- Backfill nothing on first rollout; only new writes need to populate them.
- Do not remove the current timeout guard until explicit processing metadata is flowing correctly.

Acceptance:

- Timeout logic no longer depends on `updated_at`.
- Failed items expose a bounded error reason.
- Tests cover state transition timestamps and failure metadata.

### P0. Split client content state into repository and import tracker

Why it is worth doing:

- `ContentManager.swift` is currently both data layer and UI workflow state machine.
- This makes import behavior, list refresh, cache consistency, and UI side effects harder to reason about.
- The recent async import work increased the value of a cleaner boundary.

What to do:

- Introduce a `ContentRepository` on the macOS side for:
  - remote fetch/list operations
  - local cache writes and reads
  - single-content refresh
  - local search sync and paragraph/detail cache coordination
- Introduce an `ImportTrackingCoordinator` for:
  - tracking pending/processing IDs
  - polling lifecycle
  - import completion/failure callbacks
  - capsule behavior policy
- Keep `ContentManager` only as the top-level app-facing facade if desired, but make it delegate instead of owning all logic.
- Move `ReaderViewModel` polling to reuse the same tracking source rather than owning a second polling path.

Expected payoff:

- Fewer duplicated polling/state rules.
- Easier UI changes without storage regressions.
- Better testability of import behavior independent of view state.

Risk control:

- Do not change view APIs first.
- Start by moving implementation behind the existing `ContentManager` interface.
- Only unify `ReaderViewModel` polling after repository/tracker tests are in place.

Acceptance:

- `ContentManager.swift` no longer directly owns the full polling state machine.
- `ReaderViewModel.swift` does not need a second independent import-status polling implementation.
- Local cache logic is centralized in one client-side repository layer.

### P1. Decompose auth service around session issuance

Why it is worth doing:

- `auth_service.py` is the largest service in the backend and spans unrelated auth flows.
- Session issuance logic is duplicated across password login, email code login, and Apple Sign In.
- Security-sensitive changes become harder when every auth mode is in one file.

What to do:

- Extract a `SessionService` responsible for:
  - issuing access tokens
  - storing refresh tokens
  - rotating refresh tokens
  - revoking user sessions
- Extract separate services or modules for:
  - password auth
  - email code auth
  - password reset
  - Apple Sign In
- Keep `AuthService` only as a temporary facade if needed during migration.

Expected payoff:

- Lower security-change risk.
- Less duplicated token issuance logic.
- Cleaner test partition by auth mode.

Risk control:

- Move shared token issuance first.
- Keep route schemas unchanged.
- Preserve current auth integration tests before refactoring route handlers.

Acceptance:

- Token issuance and refresh-token persistence exist in one place only.
- Password reset and logout reuse the same session revocation path.
- `backend/app/services/auth_service.py` shrinks materially or becomes a facade.

### P1. Replace subscription dict plumbing with typed models and handler mapping

Why it is worth doing:

- App Store verification code is now functionally better, but still stringly typed.
- The risk is not current correctness; the risk is future payload drift and subtle field misuse.
- Notification handling logic is currently encoded through ad hoc `dict` access and `if` chains.

What to do:

- Introduce typed internal models, for example:
  - `VerifiedTransaction`
  - `VerifiedRenewalInfo`
  - `VerifiedNotification`
- Have `storekit_receipt.py` return typed objects instead of plain dictionaries.
- Replace notification-type `if` branching in `subscription_service.py` with a small handler table or explicit strategy methods.
- Keep the public API responses unchanged.

Expected payoff:

- Lower regression risk when Apple fields change.
- Better readability for subscription state rules.
- Easier onboarding for future receipt/subscription changes.

Risk control:

- First add typed wrappers while keeping old dict shape in tests.
- Convert consumers one layer at a time.
- Keep notification behavior identical until typed coverage is complete.

Acceptance:

- Receipt verification and notification application no longer rely on raw string-key dicts across service boundaries.
- Notification handlers are organized by event category, not one long branch chain.

### P1. Separate transport from auth-refresh coordination in APIClient

Why it is worth doing:

- `APIClient.swift` mixes request execution, error mapping, token refresh synchronization, and logging.
- This is a concurrency-sensitive file and deserves a smaller surface.
- The current `NotificationCenter`-driven refresh loop works, but it is fragile to change.

What to do:

- Extract a small `HTTPTransport` for raw requests and status/error normalization.
- Extract an `AuthRefreshCoordinator` (preferably an `actor`) for:
  - deduplicating refresh attempts
  - publishing refresh results
  - retry policy
- Replace ad hoc `print` logging with `Logger`.
- Keep the public `APIClient` call sites unchanged during the first step.

Expected payoff:

- Lower concurrency risk.
- Cleaner auth-refresh behavior.
- Better debug visibility without noisy console output.

Risk control:

- Preserve method signatures on `APIClient`.
- Keep current retry semantics and test behavior.
- Migrate logging after behavior-preserving transport extraction.

Acceptance:

- `APIClient.swift` is no longer the owner of refresh orchestration details.
- Token refresh logic is testable independent of raw HTTP requests.

### P2. Move tag business rules out of the tags router

Why it is worth doing:

- `tags.py` is already large and contains direct SQL plus content ownership checks plus auto-create behavior.
- Tags are becoming part of the knowledge organization layer, not just CRUD.

What to do:

- Introduce `TagService` with operations for:
  - tag creation and soft delete
  - content-tag replacement
  - tag auto-create rules
  - content ownership validation helper reuse
- Keep router endpoints thin.

Expected payoff:

- Cleaner place for future tag rules.
- Lower chance of repeating ownership/soft-delete bugs.

Risk control:

- Pure extraction first, no behavior changes.
- Reuse current router tests as acceptance tests.

Acceptance:

- The router no longer owns business rules for tag auto-creation or content-tag replacement.

## Not Worth Doing Now

These items were considered and intentionally excluded:

- Multi-instance durable queue or distributed job system.
- Full dependency injection framework across backend and macOS client.
- Event-sourcing, CQRS, or microservice-style decomposition.
- Whole-project repository abstraction for every model.
- Full rewrite of search architecture before core content/auth boundaries are cleaned up.
- Cosmetic file splitting without a real ownership boundary.

## Recommended Order

1. Extract content orchestration from the router.
2. Add explicit content processing metadata.
3. Split macOS content repository/import tracking.
4. Extract backend session issuance from auth service.
5. Type subscription verification payloads and handler flow.
6. Split API transport from auth refresh coordination.
7. Extract tag business logic from the router.

Reason for this order:

- Content import is the most active and highest-risk product path.
- Client content-state cleanup depends on backend content behavior being stable.
- Auth and subscription refactors are high value but more isolated.
- Tag extraction is useful, but not as urgent as content/auth boundaries.

## Rollout and Risk Controls

- Prefer extraction before redesign. First move code without changing behavior.
- Prefer additive schema changes. Do not remove current fields until new paths have been exercised.
- Keep API shapes stable during the refactor phases.
- Require tests at the same boundary being refactored:
  - router/service tests for backend extraction
  - integration tests for auth/session/subscription
  - unit tests for macOS import coordination and refresh coordination
- Keep each phase independently shippable. Do not stack multiple schema and behavior changes into one release.

## Success Criteria

- Content import logic no longer spans router + pipeline + client manager in duplicate ways.
- Authentication session issuance has a single authoritative implementation.
- Subscription verification is typed internally rather than dictionary-driven.
- Client content state and transport concurrency become testable in isolation.
- The largest hotspot files shrink because ownership changed, not because code was merely moved around.

## Self-review and Plan Update

After re-reading the project, the plan was updated in these ways:

- The earlier idea of a standalone "enum migration project" was downgraded. It is worth doing, but it should be folded into the content/auth/subscription refactors instead of becoming a separate initiative.
- Multi-instance queue work remains intentionally excluded because it adds operational complexity without matching the current deployment target.
- The already-fixed `pdf/image` base64 import bug is not included as future refactor work; it is implementation debt already retired.
- A generic app-wide DI or architecture rewrite was removed because it would add cost faster than value.

Net result:

- The plan focuses on six high-return refactors and one secondary refactor.
- Every included item has a bounded rollout path and a concrete benefit beyond code aesthetics.
