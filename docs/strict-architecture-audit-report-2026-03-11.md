# Readless Strict Architecture Audit

Date: 2026-03-11
Repository: `/Users/wangyixiao/WorkSpace/readless`

## Scope

This audit was executed against the real repository state, not the architecture claims in docs.

Key code paths inspected:
- `backend/pyproject.toml`
- `backend/app/main.py`
- `backend/app/config.py`
- `backend/app/database.py`
- `backend/app/routers/content.py`
- `backend/app/routers/auth.py`
- `backend/app/routers/subscription.py`
- `backend/app/routers/search.py`
- `backend/app/services/pipeline.py`
- `backend/app/services/summarizer.py`
- `backend/app/services/search_agent.py`
- `backend/app/services/auth_service.py`
- `backend/app/services/storekit_receipt.py`
- `backend/app/models/content.py`
- `backend/app/models/refresh_token.py`
- `backend/app/admin.py`
- `backend/tests/conftest.py`
- `backend/tests/test_search.py`
- `macos/Package.swift`
- `macos/Sources/App/ReadlessApp.swift`
- `macos/Sources/App/Services/AuthService.swift`
- `macos/Sources/App/Services/ContentManager.swift`
- `macos/Sources/App/Services/TextCaptureService.swift`
- `macos/Sources/App/ViewModels/ReaderViewModel.swift`
- `macos/Sources/App/Views/ReaderView.swift`
- `macos/Sources/Networking/APIClient.swift`
- `macos/Sources/Storage/LocalDatabase.swift`
- `macos/Sources/Storage/HistoryManager.swift`
- `macos/Sources/AIServices/Providers/UnifiedAIProvider.swift`
- `macos/Sources/ReaderFeature/ReaderFeature.swift`
- `macos/Sources/LibraryFeature/LibraryFeature.swift`
- `README.md`

Commands executed:
- `cd backend && pytest -q`
  - Failed before tests started because `Settings()` requires `JWT_SECRET_KEY` and `ADMIN_TOKEN` at import time.
- `cd backend && JWT_SECRET_KEY=... ADMIN_TOKEN=... pytest -q`
  - Passed: `231 passed, 2 warnings in 14.62s`
- `cd backend && ruff check .`
  - Failed with 4 `E501` line-length errors.
- `cd macos && swift test`
  - Passed: `91 tests, 0 failures`
- `wc -l` on large macOS files
  - `ReadlessApp.swift`: 507 lines
  - `ReaderView.swift`: 450 lines
  - `ContentManager.swift`: 243 lines

## Prompt Self-Check

The prompt used for this audit was checked before execution and it did cover:
- backend and macOS
- command-based validation
- saving findings to one Markdown file
- a second-pass review of findings
- ROI-based solution selection
- file and line evidence

## Findings

### F1. Sign-out does not revoke server sessions, so refresh tokens remain valid after local logout

Severity: High
ROI: High

Evidence:
- Backend already supports revocation through `logout_user()` in `backend/app/services/auth_service.py:394-417`.
- Client `signOut()` only clears local state and explicitly leaves server logout as TODO in `macos/Sources/App/Services/AuthService.swift:93-96`.
- Refresh tokens remain valid as long as they still exist in the database and are not expired in `backend/app/services/auth_service.py:360-390`.

Why it matters:
- A user-visible "sign out" currently means "delete local token only", not "invalidate session".
- Any copied, extracted, or previously synced refresh token remains usable until expiry.
- This is a concrete auth gap, not just architecture debt.

Suggested direction:
- Call backend logout on sign-out.
- Revoke either the current device token or all tokens, but make the behavior explicit.

### F2. Refresh tokens are stored in plaintext and exposed in the admin UI

Severity: High
ROI: High

Evidence:
- Raw token is stored directly in `backend/app/models/refresh_token.py:24`.
- Raw token is inserted unchanged in `backend/app/services/auth_service.py:176-188` and `backend/app/services/auth_service.py:323-332`.
- Raw token is displayed in admin detail view in `backend/app/admin.py:172-182`.

Why it matters:
- A database leak or admin-panel misuse directly becomes a session compromise.
- Admin currently exposes exactly the secret that should never be recoverable.

Suggested direction:
- Store only a hash or fingerprint of refresh tokens.
- Remove raw token display from admin.
- Rotate refresh tokens on use instead of treating them as long-lived bearer secrets.

### F3. Subscription lifecycle is incomplete; backend cannot track renewal, refund, or expiration events in real time

Severity: High
ROI: High

Evidence:
- App Store webhook endpoint is unimplemented in `backend/app/routers/subscription.py:75-93`.
- `SubscriptionService` hardcodes `auto_renew_enabled=True` with a TODO in `backend/app/services/subscription_service.py:91`.
- Current flow depends on explicit receipt verification calls through `backend/app/routers/subscription.py:20-47`.

Why it matters:
- Paid state can drift after renewal failures, refunds, plan changes, grace periods, or subscription expiration.
- The system is currently biased toward stale subscription truth.

Suggested direction:
- Implement App Store Server Notifications v2.
- Verify webhook signatures.
- Reconcile state by `originalTransactionId`, not just client push timing.

### F4. Content ingestion does too much synchronous work on the request path, including fan-out AI calls

Severity: High
ROI: High

Evidence:
- `create_content()` waits for the full pipeline synchronously in `backend/app/routers/content.py:74-90`.
- The pipeline performs extraction, summary generation, language detection, and L2 pre-generation before returning in `backend/app/services/pipeline.py:57-122`.
- `pre_generate_details()` may issue parallel AI expansion calls for multiple outline points in `backend/app/services/summarizer.py:183-226`.
- Search also performs up to three LLM calls per request in `backend/app/services/search_agent.py:35-52`.

Why it matters:
- User-facing latency and failure surface both expand with content length.
- Throughput collapses under load because expensive remote inference is done inline.
- "Generate L2 now just in case" is a poor trade on the hot path.

Suggested direction:
- Return early with a pending job state.
- Move L1/L2 generation to background work.
- Only generate L2 lazily or for top-priority points.

### F5. The default backend test path is broken by import-time settings requirements, despite docs claiming a simple `pytest` workflow

Severity: High
ROI: High

Evidence:
- `settings = Settings()` is created at import time in `backend/app/config.py:68`.
- `jwt_secret_key` and `admin_token` are required fields in `backend/app/config.py:41-42` and `backend/app/config.py:61-62`.
- Tests import `app.main` through `backend/tests/conftest.py:12-13`, which triggers settings validation before fixtures can override anything.
- `README.md:117-131` tells developers to run `pytest tests/`, but that command failed until dummy secrets were supplied.

Why it matters:
- This blocks zero-config local validation.
- It directly contradicts the repository's own "tests should not need real secrets" operating model.
- It creates unnecessary friction for humans and AI agents.

Suggested direction:
- Decouple settings construction from module import.
- Provide test-safe defaults or an explicit `.env.test` path.
- Make the documented default test command actually work.

### F6. The claimed macOS modular architecture is mostly aspirational; real UI and orchestration are still concentrated in `App`

Severity: Medium
ROI: Medium-High

Evidence:
- `Package.swift` declares `ReaderFeature` and `LibraryFeature` as real feature targets in `macos/Package.swift:76-114`.
- The actual feature targets are placeholders only in `macos/Sources/ReaderFeature/ReaderFeature.swift:1-11` and `macos/Sources/LibraryFeature/LibraryFeature.swift:1-11`.
- Real logic still sits in large `App` files:
  - `macos/Sources/App/ReadlessApp.swift`: 507 lines
  - `macos/Sources/App/Views/ReaderView.swift`: 450 lines
  - `macos/Sources/App/Services/ContentManager.swift`: 243 lines
- `ReadlessApp.swift` contains app boot, navigation, sidebar, filtering, auth wiring, command bar overlay, and settings entry in one file at `macos/Sources/App/ReadlessApp.swift:10-220` and beyond.

Why it matters:
- The codebase signals one set of boundaries to readers and tools, but implements another.
- That mismatch hurts maintainability, onboarding, and AI-assisted editing.
- Large mixed-responsibility files raise change risk and reduce local reasoning quality.

Suggested direction:
- Either make feature targets real, or stop pretending they already exist.
- Move navigation, sidebar, reader composition, and orchestration into feature modules with stable interfaces.

### F7. The macOS client relies on hidden global state, mutable singletons, and notification-based auth refresh coupling

Severity: Medium
ROI: Medium

Evidence:
- `APIClient` is a mutable singleton with `@unchecked Sendable`, mutable `authToken`, and in-flight task state in `macos/Sources/Networking/APIClient.swift:50-58`.
- Token refresh is coordinated through `NotificationCenter` in `macos/Sources/Networking/APIClient.swift:139-160` and `macos/Sources/App/Services/AuthService.swift:135-159`.
- `AuthService` and `ContentManager` are global shared instances in `macos/Sources/App/Services/AuthService.swift:8-23` and `macos/Sources/App/Services/ContentManager.swift:16-36`.

Why it matters:
- Hidden state transitions are easy to break and hard to reason about.
- `@unchecked Sendable` is an explicit promise the code does not really justify.
- This pattern is especially hostile to AI editing because state ownership is implicit.

Suggested direction:
- Replace notification-driven auth refresh with a typed session actor or injected session store.
- Remove mutable cross-cutting globals where possible.

### F8. There are crash-prone fail-fast paths in normal production code

Severity: Medium
ROI: Medium

Evidence:
- `TextCaptureService` force unwraps and force casts the focused accessibility element in `macos/Sources/App/Services/TextCaptureService.swift:26-27`.
- `LocalDatabase.shared` uses `try!` during startup in `macos/Sources/Storage/LocalDatabase.swift:11-20`.
- `HistoryManager.shared` also uses `try!` in `macos/Sources/Storage/HistoryManager.swift:14-17`.

Why it matters:
- Accessibility APIs and local database setup are both failure-prone in real user environments.
- These are not test-only shortcuts; they are on real app paths.

Suggested direction:
- Replace `try!` and force unwraps with explicit failure handling and degraded-mode behavior.

### F9. Test coverage is stronger than average, but still gives false confidence for the most production-specific paths

Severity: Medium
ROI: Medium-High

Evidence:
- Search tests are mostly structural and router-registration checks in `backend/tests/test_search.py:1-188`.
- The backend test harness manually creates simplified SQLite tables in `backend/tests/conftest.py:33-89`, bypassing PostgreSQL-specific behavior.
- Auth/subscription tests also patch around UUID and storage differences in `backend/tests/conftest.py:139-178`.
- Raw Postgres search SQL and FTS behavior in `backend/app/services/search_agent.py:85-121` are not meaningfully exercised by these tests.

Why it matters:
- The suite is good at catching schema and contract regressions, but weak on Postgres-specific semantics, FTS ranking, and multi-LLM orchestration behavior.
- Passing tests do not currently prove search correctness under production conditions.

Suggested direction:
- Add a small integration layer against real Postgres for search, FTS, JSONB, and transaction-sensitive flows.
- Keep the fast SQLite suite, but stop treating it as full confidence.

### F10. Documentation and architecture narration have drifted away from the code

Severity: Medium
ROI: Medium

Evidence:
- `README.md:159-175` still describes backend auth as "Clerk JWT verification" through `auth.py`, but the code uses local JWT auth, refresh tokens, Apple Sign-In, email codes, and subscription services.
- `README.md:54-65` presents a much smaller macOS layout than the actual package graph in `macos/Package.swift:17-141`.
- The observed backend test count is `231`, while multiple repo instructions still cite older lower counts.
- `ruff check .` is failing, so basic repo hygiene is not being enforced consistently.

Why it matters:
- Humans and AI assistants will form the wrong mental model before touching code.
- Drifted documentation is a multiplicative maintenance cost.

Suggested direction:
- Treat architecture docs as versioned artifacts that must be updated with structural changes.
- Put test and lint commands into CI and make the published instructions match the real defaults.

### F11. `UnifiedAIProvider` currently behaves like an architectural placeholder, not a dependable abstraction

Severity: Low-Medium
ROI: Medium

Evidence:
- Core chat and multimodal methods are still stubs in `macos/Sources/AIServices/Providers/UnifiedAIProvider.swift:50-90`.
- Yet the module is included as part of the app dependency graph in `macos/Package.swift:55-60` and `macos/Package.swift:92-103`.

Why it matters:
- Placeholder abstractions increase conceptual surface area without reducing coupling.
- They also mislead code readers into assuming there is a provider layer already available for reuse.

Suggested direction:
- Either implement the abstraction or narrow its surface and mark it clearly as experimental.

## Review of Findings

After a second pass, these findings split into three groups.

Must do:
- F1 sign-out/session revocation gap
- F2 plaintext refresh tokens
- F3 missing subscription webhook lifecycle
- F4 synchronous hot-path AI fan-out
- F5 broken default backend test path

Should do:
- F6 fake modularization and oversized `App` boundary
- F7 hidden global state and notification-coupled auth refresh
- F8 crash-prone fail-fast paths
- F9 production confidence gap in tests
- F10 documentation drift

Watch list:
- F11 `UnifiedAIProvider` placeholder status

What I intentionally did not over-report:
- The default production backend URL is a product choice, not automatically a defect.
- The many `print()` calls are noisy and should be cleaned up, but they are secondary compared with auth, subscription, and latency issues.
- Not every large file is automatically a problem; the problem is large files plus mixed responsibilities plus misleading modular claims.

## High-ROI Solutions

### S1. Harden session management end to end

Targets:
- F1
- F2

Plan:
1. Change refresh-token storage from raw token to hashed token plus token ID or fingerprint.
2. Rotate refresh tokens on refresh instead of reusing the same long-lived token forever.
3. Remove raw token visibility from SQLAdmin.
4. Make macOS `signOut()` call backend logout before clearing local state.
5. Add tests for logout invalidation and token rotation.

Expected payoff:
- Closes the cleanest current auth/security gap.
- Reduces blast radius of DB or admin exposure.
- Aligns user-visible logout with real server behavior.

Risk:
- Requires a migration path for existing sessions.

### S2. Split ingestion into a fast request path plus background processing

Targets:
- F4

Plan:
1. Persist content immediately as `pending`.
2. Move summary generation and L2 pre-generation to a background worker or job runner.
3. Return a lightweight response early and let the client poll or subscribe to status.
4. Generate L2 lazily on first expansion instead of precomputing all details.
5. Add timeouts and per-stage observability around extraction and AI calls.

Expected payoff:
- Largest combined gain in latency, reliability, and scale.
- Makes failures partial and recoverable instead of request-fatal.

Risk:
- Requires explicit job-state modeling and client-side progress handling.

### S3. Finish the subscription truth pipeline

Targets:
- F3

Plan:
1. Implement App Store Server Notifications v2 webhook verification.
2. Map events by `originalTransactionId`.
3. Persist subscription event history for debugging and replay.
4. Add reconciliation logic for restore and periodic status correction.
5. Stop returning hardcoded `auto_renew_enabled=True`.

Expected payoff:
- Prevents silent billing-state drift.
- Reduces support burden around paid access mismatches.

Risk:
- Requires careful Apple event modeling and test fixtures.

### S4. Make the default backend validation path actually work

Targets:
- F5
- F9
- F10

Plan:
1. Move settings initialization behind a getter or allow test-safe defaults when `ENV=test`.
2. Add `.env.test` or a test settings object.
3. Add one CI path that runs `ruff check .` and backend `pytest` from a documented clean environment.
4. Add a small real-Postgres integration suite for FTS and JSONB-sensitive behavior.
5. Update README and developer docs to match the real commands and real test counts.

Expected payoff:
- Immediate improvement to local developer speed and AI agent reliability.
- Reduces mismatch between "documented reality" and "actual reality".

Risk:
- Low implementation risk; mostly cleanup plus a narrow integration test layer.

### S5. Make the macOS module graph honest

Targets:
- F6
- F7
- F8
- F11

Plan:
1. Decide whether `ReaderFeature` and `LibraryFeature` are real now or later.
2. If now, move actual reader/library composition out of `App` into those targets.
3. Introduce typed dependency boundaries for auth/session state instead of notification-only coordination.
4. Remove `try!` and force unwraps from startup and accessibility capture paths.
5. Either implement `UnifiedAIProvider` or mark it as internal experimental code outside the main dependency story.

Expected payoff:
- Better maintainability and AI editability.
- Lower risk of incidental breakage during future UI or auth changes.

Risk:
- Medium; this is best done incrementally after the security and latency fixes.

## Validation Notes

Validated directly:
- macOS tests currently pass.
- Backend tests currently pass only when minimal required secrets are injected.
- Backend lint is currently not clean.
- macOS modularization claims do not match actual feature-module implementation.
- Session revocation, subscription webhook handling, and sync ingestion issues are grounded in real code paths, not speculative style opinions.

Still worth validating later:
- Real production latency distribution for `create_content`.
- Real Postgres query plans for search and tag fallback.
- End-to-end subscription event reconciliation under renewal and refund scenarios.

Overall assessment:
- The project is not unhealthy everywhere. It has decent test volume, a working backend/client split, and meaningful domain structure.
- But the highest-value paths still have several "looks complete, is not complete" gaps: auth logout semantics, token storage, subscription lifecycle truth, and sync AI hot paths.
- The largest AI-readability problem is not naming quality; it is the mismatch between declared architecture and actual code boundaries.
