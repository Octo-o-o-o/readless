# Readless Test Coverage Plan

Date: 2026-03-25

## Baseline

- Backend: `276` existing pytest cases, current line coverage `68%`
- macOS SPM tests: `93` existing XCTest cases
- macOS SPM line coverage over linked package code: about `26%`
- `macos/Sources/App` logic is largely outside the current SPM test graph

## Review Summary

The project already has a non-trivial test base, but it is uneven:

- Backend has strong coverage on auth/subscription happy paths and core content flows.
- Backend is weak on actual router behavior for tags/podcast, orchestration edge cases, and service wrappers around external APIs.
- Swift package tests cover model smoke tests and a few storage flows, but most `Networking` and `Storage` code paths are not exercised.
- App-layer macOS logic with real state coordination is mostly untested because it is not exposed as a package target.

The plan below prioritizes high-risk behavior over mechanical coverage.

## Backend Coverage Targets

### Priority 1

- `app/routers/tags.py`
  - Success paths for list/create/delete/get-content-tags/update-content-tags/get-contents-by-tag
  - Error mapping from service `ValueError` to `HTTPException`
- `app/routers/podcast.py`
  - Missing content ownership checks
  - Duplicate podcast conflict
  - Latest podcast retrieval behavior
- `app/worker.py`
  - Startup recovery / purge / clear-body sequencing
  - Worker slot idle loop and stop behavior
- `app/services/search_agent.py`
  - CJK query splitting/basic intent
  - AI parse fallback
  - ranking fallback on malformed model output
  - answer fallback and source serialization

### Priority 2

- `app/services/content_response.py`
  - tag fetch failure fallback
  - list/detail payload assembly
  - stable outline handling
- `app/services/auth_service.py`
  - email login throttling
  - invalid code attempts and lockout
  - resend verification failure cases
  - expired / missing password reset branches
  - account deletion and logout error branches
- `app/services/email_service.py`
  - configuration validation
  - upstream HTTP error mapping
- `app/services/translator.py`
  - fence stripping
  - language detection fallback
  - same-language no-op
  - translated summary/text parsing

### Priority 3

- `app/auth.py`
  - missing credentials / invalid token / expired token / missing `sub`
- `app/main.py`
  - HTTPS redirect header fix behavior
- `app/routers/subscription.py`
  - invalid UUID handling
  - webhook environment routing

## macOS Coverage Targets

### Priority 1

- `Sources/Networking/APIClient.swift`
  - request success/error mapping
  - backend error detail parsing
  - refresh-and-retry flow
  - tag/search/content helper endpoints
- `Sources/Networking/AuthRefreshCoordinator.swift`
  - shared in-flight refresh behavior
  - timeout behavior
- `Sources/Storage/CacheManager.swift`
  - size limit clamping
  - touch/clear/stats paths
  - user-scoped eviction/clearing
- `Sources/Storage/LocalSearchService.swift`
  - FTS search
  - query preparation
  - sync + `hasFullDataCached`

### Priority 2

- `Sources/Core/Models/SearchMode.swift`
- `Sources/Core/Models/Tag.swift`
- `Sources/Core/Models/User.swift`
- `Sources/Networking/APIClient+Auth.swift`
- `Sources/Networking/APIClient+Subscription.swift`
- `Sources/Networking/HTTPTransport.swift`

### Priority 3

- Expose selected `Sources/App` logic as a package target when practical:
  - `Services/ImportTrackingCoordinator.swift`
  - `Services/TagManager.swift`
  - optionally `Services/ContentRepository.swift`

This is only worth doing for pure coordination/state logic. UI-heavy SwiftUI view code is lower value for the first expansion round.

## Implementation Rules

- Prefer deterministic tests with local DB / local transport stubs / local notification centers.
- Avoid tests that merely mirror third-party SDK internals.
- Favor direct router/service invocation for backend when HTTP transport adds no value.
- Avoid changing production logic solely to chase coverage unless the change improves testability and design.

## Success Criteria

- Backend coverage materially increases in low-covered orchestration/router modules.
- macOS package coverage materially increases in `Networking` and `Storage`.
- Newly added tests are isolated, fast, and runnable with:
  - `cd backend && pytest`
  - `cd backend && pytest --cov=app`
  - `cd macos && swift test`
  - `cd macos && swift test --enable-code-coverage`

## Residual Gaps To Re-evaluate After This Round

- Full `Sources/App` coverage without restructuring the app target
- UI rendering / SwiftUI interaction tests
- End-to-end production-like integration with real PostgreSQL, Clerk, OpenAI, ElevenLabs, and StoreKit
