# Release Notes — PR #13: Complete Release Blockers

Branch: `pr13/complete-release-blockers` → `main`

Completes the remaining production-readiness work. Every earlier partial
implementation on this branch was audited and corrected in place rather than
reverted.

## Test coverage

| Suite | Before | After |
|---|---|---|
| Backend (`CaloriesTracking.Api.Tests`) | 119 | 242 |
| Backend (`CaloriesTracking.Application.Tests`) | 23 | 23 |
| **Backend total** | **142** | **265** |
| **Flutter** | **17** | **96** |

No tests were deleted. Existing tests were migrated to the new typed-exception
and ProblemDetails contracts.

---

## Backend

### Authentication validation and uniqueness

- Added `AuthValidationRules` enforcing the full contract: username 3–50
  characters restricted to letters/digits/underscore/dot/hyphen; email trimmed,
  lowercased, max 254; password 8–128; displayName 1–150. All validation runs
  **before** password hashing or any database write, so a malformed request
  never costs a BCrypt work factor.
- Case-insensitive uniqueness is now **enforced by the database** through
  persisted `NormalizedUsername` and `NormalizedEmail` columns carrying unique
  indexes. This works identically on SQLite (development) and PostgreSQL
  (production). Original casing is preserved for display and response
  contracts.
- The registration race condition is handled: when two concurrent requests both
  pass the advisory pre-check, the unique index rejects the loser and the
  failure is translated to **HTTP 409** without exposing SQL, constraint names,
  provider messages, connection strings, or stack traces.
- Login failures return a single generic message for both "user not found" and
  "wrong password", so the endpoint cannot be used to enumerate accounts.

### Diary validation

- Added `DiaryValidationRules` centralising the `LogMealRequest` contract:
  foodName required and max 200; caloriesPer100g in (0, 10 000]; quantity in
  (0, 100 000]; mealType restricted to Breakfast/Lunch/Dinner/Snack; date valid,
  not `DateTime.MinValue`, and at most 1 day in the future.
- `GET /api/diary/stats` is bounded to a **90-day inclusive range**. Defaulted
  dates are rejected outright — an unvalidated `DateTime.MinValue` start
  previously drove roughly 740 000 iterations of the day loop.
- Validation runs in both the controller (fail fast, no transaction opened) and
  the service (defence in depth when called from tests or any future transport).

### Diary concurrency

- `LogMealAsync` handles concurrent creation of both `DailyLog` (unique on
  `UserId, Date`) and custom `Food`. On a unique violation the winning row is
  reloaded instead of duplicated. Retries are bounded to 3 attempts, run inside
  the existing transaction, and honour `CancellationToken`.
- Custom foods use a **partial unique index** on `NormalizedName WHERE FdcId IS
  NULL`, so USDA rows keep their legitimately repeated display names.
- No orphan `MealItem` and no partially created `Food` survive a failure — the
  transaction rolls back both.
- `POST /api/diary` now returns the authoritative `DailyDiaryDto` alongside the
  existing `message` field. This is additive, so already-deployed clients that
  only read `message` keep working.

### USDA seeder (rewritten)

The previous implementation caught any `DbUpdateException` and skipped the
entire batch, which could silently discard thousands of valid foods.

- Added a `SeedHistory` table recording name, version, status, timestamps,
  processed rows, checkpoint position, and a sanitized error summary, with a
  unique `(Name, Version)` index.
- A duplicate row now costs **one row**, not the whole batch: the batch falls
  back to per-row inserts and only the genuinely conflicting row is skipped.
- Non-duplicate database errors propagate instead of being swallowed.
- The import resumes from its checkpoint after an interruption, is idempotent
  on re-run, never marks Completed before the whole CSV succeeds, and does not
  load every existing `FdcId` into memory.
- A lease prevents two application instances from seeding simultaneously; an
  expired lease from a crashed instance is taken over.
- Logging moved from `Console.WriteLine` to `ILogger`.
- Fixed a bug where `ChangeTracker.Clear()` detached the tracked `SeedHistory`
  entity, causing every checkpoint write to be silently discarded.

### Migration safety

- `AddNormalizedIdentityAndSeedHistory` (SQLite and PostgreSQL) backfills the
  normalized columns **before** creating the unique indexes; without this every
  existing row would carry the empty-string default and collide immediately.
- The PostgreSQL migration raises a named exception reporting the number of
  case-insensitive duplicate usernames or emails. `MigrationPreflight` provides
  the same diagnostic on both providers before `MigrateAsync` runs.
- Duplicate non-null `FdcId` values are detected and reported by value.
- Conflicting rows are **never** merged, renamed, or deleted — resolution is an
  operator decision.

### Error handling

- `GlobalExceptionHandler` now maps by exception **type** instead of searching
  for words inside exception messages. Substring matching silently reclassified
  unrelated failures whenever a string was reworded.
- Added 503 for an unavailable Gemini upstream, 502 for an unexpected upstream
  response, and 504 for a server-side timeout. Client aborts are distinguished
  from server deadlines.
- Fixed ProblemDetails responses being emitted as `application/json`: the
  content type must be passed to `WriteAsJsonAsync`, not set on `Response`
  beforehand. This was a pre-existing defect.
- `AnalysisController` and `FoodController` no longer return ad-hoc anonymous
  error objects. **Breaking for external consumers** of the old `{ error }`
  shape on `/api/analysis/food`.
- Production responses never contain a stack trace, provider text, SQL, file
  path, connection string, API key, JWT, or raw upstream body.

### Food search

- Query is trimmed and capped at 100 characters; limit is clamped to 1–50.
- Projection and deduplication are pushed into SQL instead of materialising
  candidate rows and grouping them in memory.
- LIKE wildcards in user input are escaped, so a query of `%` cannot match
  everything.
- Search matches the persisted normalized column rather than relying on the
  provider's LIKE collation. SQLite folds case for ASCII only, so `bún`
  previously failed to match `BÚN` — unacceptable for a Vietnamese-first
  dataset.

---

## Flutter

### Unified network failure model

- Added `NetworkFailure`, a sealed hierarchy covering timeout, unauthorized,
  forbidden, validation, conflict, rate limit, server, cold start, unsupported
  media, payload too large, unreachable, and cancelled.
- RFC 7807 ProblemDetails are parsed consistently, capturing status, title,
  detail, traceId, and `Retry-After`.
- Raw backend text and `.toString()` output never reach the user; every failure
  carries a Vietnamese, user-facing message.

### Retry policy

- Only `GET`, `HEAD`, and `OPTIONS` are retried. `POST`, `PUT`, `PATCH`, and
  `DELETE` are **never** retried automatically, because no endpoint carries an
  idempotency key and a retried write could double-log a meal.
- Only connection errors, timeouts, and HTTP 502/503/504 are retried.
  400, 401, 403, 404, 409, 413, 415, 429 and client cancellation are not.
- Bounded at 1 original attempt plus 2 retries, with 1 s then 2 s backoff.
- Cancellation during the backoff abandons the chain immediately, and the final
  attempt's `DioException` metadata is preserved rather than the first
  attempt's.
- The delay function and HTTP transport are injectable, so tests run instantly
  instead of sleeping.
- Replaced the previous behaviour, which retried up to 3 times on any GET error
  including 4xx, and rewrote every connection failure into a "cold start"
  message even when the device was simply offline.
- Connect and receive timeouts remain at 60 s to accommodate Render cold starts.

### JWT lifecycle

- `AuthState.copyWith` gained an explicit `clearToken` flag. A nullable `token`
  parameter alone cannot distinguish "leave the token unchanged" from "clear
  it", which is why logout previously failed to null it out. Logout now
  guarantees `token == null` and `isAuthenticated == false`.
- `JwtValidator` validates the stored token: exactly three segments, a
  base64url-decodable payload, valid JSON, and a numeric `exp` in the future
  with a 30-second clock-skew allowance. A missing or non-numeric `exp` is now
  treated as **invalid** — it was previously treated as valid, letting a
  malformed token live forever and trigger a 401 loop on every request.
- An invalid or expired token is removed from storage and auth state is cleared,
  with redirection handled by the normal router guard.

### Concurrent 401 handling

- Replaced the mutable `static void Function()? onUnauthorized` callback, where
  one listener silently overwrote another and state leaked between test cases.
- `UnauthorizedCoordinator` returns a disposer on registration, collapses
  overlapping 401 responses into a **single** logout run, and clears the token
  once. Listeners are deregistered on dispose.
- Logout is awaited rather than fire-and-forget, so auth state and router
  navigation stay consistent.
- Tokens are never logged.

### Diary read states

- `DiaryState<T>` carries status, fresh data, and stale cache as **separate**
  fields (`data`, `cachedData`, `isShowingStaleData`), so the UI can never
  mistake a fallback for a fresh success.
- HTTP 5xx now maps to `serverError`, **never** `cachedOffline`. Labelling a
  backend outage as "offline" hid real outages from users.
- `cachedOffline` is claimed only for a genuine connectivity failure, and only
  when a cache actually exists.
- A successful **empty** response stays empty instead of being replaced by stale
  local entries, which previously resurrected meals deleted elsewhere.
- Home and Stats screens render Vietnamese status banners with retry buttons.
  A 401 offers re-login via `goNamed` rather than `pushNamed`, so repeated 401s
  cannot stack login routes into a navigation loop. No screen renders `$e`.
- Removed a duplicate `weeklyStatsProvider` declared in `stats_screen.dart`. It
  shadowed the shared provider and read only from local storage, so the stats
  chart never reflected the server at all.

### Server-first diary writes

- Added `MealLogger`, a single implementation shared by the scanner and food
  search screens so the two cannot drift apart.
- The backend is written first and its success is what the user is told about.
  The local cache is a best-effort mirror updated afterwards.
- On server failure: nothing is written locally, no success is shown, and the
  form stays open so the user can correct and resubmit deliberately. The POST is
  never retried automatically.
- On cache failure **after** a successful server save: success is still
  reported, because the meal genuinely was saved. Reporting failure here would
  push the user into a retry that double-logs. Only a sanitized debug warning is
  emitted — never the token, request body, or image data.
- The client adopts the authoritative server diary instead of appending a
  locally generated fake id.

### Gemini client

- Removed the `google_generative_ai` dependency from `pubspec.yaml` and
  `pubspec.lock`. No direct SDK import remained; every analysis goes through
  `POST /api/analysis/food`, so no API key can reach the client.
- Deleted the obsolete Node proxy (`scripts/gemini_proxy.js`) along with its
  `package.json`, `package-lock.json`, and the `.env.example` that existed only
  to configure it. All references were updated.
- Corrected the 413 message from 20 MB to **5 MB**, matching the server's actual
  decoded-image budget.
- Added 415 handling with a message naming JPEG, PNG, and WebP.
- Retry is restricted to transient network and 5xx failures with a bounded
  count. 400, 401, 413, 415, 429, cancellation, and a 200 response with a
  malformed body are all terminal. The previous code wrapped even deliberate
  validation throws in a catch-all retry branch.

---

## Deployment and CI

### Vercel build

- Flutter is pinned to the **3.44.1** tag instead of cloning the floating
  `stable` branch, so the same commit builds against the same SDK tomorrow.
  Kept in sync with `.github/workflows/flutter-ci.yml`.
- `BACKEND_BASE_URL` validation rejects: missing, non-HTTPS, trailing slash,
  `/api` or any other path, query string, fragment, embedded credentials, and
  loopback hosts (`localhost`, `127.*`, `0.0.0.0`, `::1`).
- Removed `set -x`, which printed `BACKEND_BASE_URL` and every other environment
  value into the build log. Now uses `set -euo pipefail` with safe quoting.
- Dropped `flutter doctor -v`, which cost build minutes and printed noise.
- Documented that the Vercel **Root Directory must remain the repository root**,
  because the Flutter project lives there.

### Vercel routing and caching

- The SPA rewrite now excludes paths with a file extension, so real assets are
  served before the `index.html` fallback instead of being rewritten to it.
- `index.html`, the service worker, and the JS entry points must revalidate.
- `/assets/*` dropped from a one-year `immutable` cache to 1 hour with
  revalidation: Flutter asset filenames are **not** content-hashed, so
  `immutable` would pin users to stale assets across deploys. Only the
  version-pinned `/canvaskit/*` path stays `immutable`.
- Added `$schema`.

### Flutter CI

- Triggers now include `vercel.json`, `scripts/vercel-build.sh`,
  `docs/DEPLOYMENT_GUIDE.md`, and `docs/DEPLOY_RENDER.md`, so release tooling
  changes are verified by the pipeline that builds the bundle.
- Runs `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test`,
  and a real `flutter build web --release`.
- Validates that `vercel.json` is valid JSON and that the build script passes
  `bash -n`. The script itself is never executed in CI, since `flutter-action`
  has already installed the SDK.
- Verifies the lockfile and the repository do not drift.
- Uploads `build/web` as an inspection artifact. It is never deployed from CI.

### Single frontend deployment path

- `.github/workflows/deploy.yml` (GitHub Pages) is deprecated: the automatic
  push-to-`main` trigger was removed, leaving only `workflow_dispatch`.
- Two live frontend deploy paths meant two origins to whitelist, while
  `render.yaml` declares only `CORS__ALLOWEDORIGINS__0` — so whichever origin
  lost that slot would silently fail every API call.
- README and the deployment docs now describe Vercel consistently.

### Documentation

- Corrected environment variable names to `JWT__KEY` and `GEMINI__APIKEY`. The
  inconsistent `Jwt__Key` and `Gemini__ApiKey` variants were removed.
- The JWT placeholder is now
  `<GENERATE_A_RANDOM_SECRET_OF_AT_LEAST_32_CHARACTERS>`, which cannot be
  mistaken for a usable signing key.
- The Neon URI is documented with both `sslmode=require` and
  `channel_binding=require`.
- Health check expectation corrected to `{"status":"ok"}`.
- Added smoke-test procedures for deep links, CORS preflight, JWT expiration,
  concurrent 401, Render cold start, Gemini 413/415/429/503, the
  diary-failure-shows-no-false-success case, and Neon persistence across a
  Render restart.

---

## Security status

- **No runtime secret exists in tracked files.** The scan matched only
  placeholders (`<user>:<password>`), test fixtures, and a usage comment in the
  Dockerfile.
- **Historical Gemini key exposure: Yes.** A Gemini API key appears in the
  repository's Git history. **Rotating the key is required before production** —
  removing it from the current tree does not invalidate the exposed key. Git
  history was not rewritten as part of this work.

---

## Known limitations

- **Docker build: not verified** — Docker was unavailable in the environment
  where this work was validated.
- The PostgreSQL migration path (backfill plus the duplicate-detection `DO`
  block) is reviewed but **not executed against a real PostgreSQL instance**;
  no Neon project was created. It needs a staging run before production.
- The `/api/analysis/food` error contract changed from `{ error }` to RFC 7807
  ProblemDetails. Any external consumer of the old shape must be updated.

## Manual production tests still required

None of the following were run — no deployment was performed. The full
checklist lives in `docs/DEPLOYMENT_GUIDE.md` §5.

1. Rotate the Gemini API key, then verify `/api/analysis/food`.
2. `GET /health` returns HTTP 200 with `{"status":"ok"}`.
3. CORS preflight from the Vercel origin returns HTTP 204.
4. Deep-link refresh on `/login`, `/profile`, `/diary`, `/goal-setup`,
   `/results`; confirm static assets are not rewritten to `index.html`.
5. JWT expiration produces a clean redirect with no loop; two tabs expiring
   together produce exactly one logout.
6. Render cold start shows the cold-start message, not "no network".
7. A diary write during a backend outage shows no false success and produces no
   duplicate entry on manual retry.
8. Gemini 413, 415, 429, and 503 messages.
9. Restart Render and confirm Neon persistence, and that the seeder reports
   `already completed` rather than re-importing.
