# What Changed — PR #13

`d4cfe71` → `dd4dd41` · 9 commits · 83 files · +8071 / −2423

A file-by-file record of every change. For the narrative version see
[docs/RELEASE_NOTES_PR13.md](docs/RELEASE_NOTES_PR13.md).

---

## Scoreboard

| | Before | After |
|---|---:|---:|
| Backend tests | 142 | **265** |
| Flutter tests | 17 | **96** |
| Flutter analyze issues | 0 | **0** |
| Backend Release warnings | 0 | **0** |
| Flutter web release build in CI | ✗ | **✓** |

No tests were deleted. Existing tests were migrated to the new contracts.

---

## Three real bugs found by the new tests

These would have shipped:

1. **Every seed checkpoint was silently discarded.**
   `UsdaFoodSeeder` called `ChangeTracker.Clear()` after each batch, which
   detached the tracked `SeedHistory` entity, so no checkpoint write ever
   persisted. Resume could never have worked. Fixed by detaching only `Food`
   entries.

2. **All ProblemDetails went out as `application/json`.**
   `GlobalExceptionHandler` set `Response.ContentType` *before*
   `WriteAsJsonAsync`, which overwrites it. The content type has to be passed
   as an argument. Pre-existing defect, not introduced by this PR.

3. **The stats chart never reflected the server.**
   `stats_screen.dart` declared its own `weeklyStatsProvider` that read only
   local storage and shadowed the shared one — despite the repo claiming the
   server was source of truth. Removed.

---

## Backend

### New files

| File | Purpose |
|---|---|
| `Application/Validation/AuthValidationRules.cs` | Full register/login contract, enforced before BCrypt or any DB write |
| `Application/Validation/DiaryValidationRules.cs` | `LogMealRequest` contract + 90-day stats bound |
| `Application/Exceptions/AppExceptions.cs` | Typed exceptions driving HTTP status mapping |
| `Application/Abstractions/IUniqueConstraintTranslator.cs` | Classifies unique violations without leaking EF types into Application |
| `Infrastructure/Data/UniqueConstraintTranslator.cs` | Maps Postgres `23505` / SQLite `2067`,`1555` by **error code**, never message text |
| `Infrastructure/Data/MigrationPreflight.cs` | Reports case-insensitive user conflicts by name before the index rejects them |
| `Infrastructure/Data/Seeders/UsdaFoodSeeder.cs` | Resumable, idempotent, lease-guarded CSV import |
| `Domain/Entities/SeedHistory.cs` | Durable seed status, checkpoint, lease |

### Modified files

| File | Change |
|---|---|
| `Application/Services/AuthService.cs` | Validation before hashing; normalized-column lookups; `DbUpdateException` → 409 |
| `Application/Services/DiaryService.cs` | Bounded 3-attempt concurrency retry for `DailyLog` + custom `Food`; returns the authoritative diary |
| `Api/Controllers/DiaryController.cs` | Fail-fast validation; `{ message, diary }` response |
| `Api/Controllers/AnalysisController.cs` | Typed exceptions instead of anonymous `{ error }` objects |
| `Api/Controllers/FoodController.cs` | Query ≤100, limit clamped 1–50, SQL projection, escaped LIKE wildcards |
| `Api/Middleware/GlobalExceptionHandler.cs` | Type-based mapping; +503/+502/+504; fixed content type |
| `Domain/Entities/User.cs` | `NormalizedUsername`, `NormalizedEmail` |
| `Domain/Entities/Food.cs` | `NormalizedName` |
| `Infrastructure/Data/ApplicationDbContext.cs` | Unique + partial indexes, `SeedHistories` config |
| `Infrastructure/Repositories/*.cs` | Normalized lookups, `Detach`, `ClearChangeTracker` |
| `Infrastructure/Data/Seeders/DatabaseSeeder.cs` | Now detection-only: reports duplicate `FdcId`s, never merges or deletes |
| `Infrastructure/Services/GeminiFoodAnalysisService.cs` | Throws typed exceptions; names the rejected image format |

### Migrations

`AddNormalizedIdentityAndSeedHistory` for **both** SQLite and PostgreSQL:

- Adds the normalized columns and their unique indexes.
- **Backfills existing rows before creating the indexes** — without this every
  row would carry the empty-string default and the second row would collide.
- Converts `IX_Foods_FdcId` to partial (`WHERE "FdcId" IS NOT NULL`) and adds a
  partial unique index on custom-food names (`WHERE "FdcId" IS NULL`), so the
  USDA dataset keeps its legitimately repeated display names.
- The PostgreSQL migration raises a named exception reporting the conflict
  count. Conflicting rows are **never** merged, renamed, or deleted.

### Behaviour changes

| Area | Before | After |
|---|---|---|
| Username uniqueness | App-level pre-check only, case-sensitive | DB unique index on normalized column, case-insensitive |
| Concurrent registration | Both could insert | Loser gets **409**, no SQL leaked |
| Stats range | Unbounded; `MinValue` → ~740 000 iterations | Max **90 days**, defaults rejected |
| Concurrent diary write | Duplicate rows possible | Reloads the winner, bounded to 3 attempts |
| Seeder duplicate row | **Whole batch discarded** | Only that row skipped |
| Seeder non-duplicate error | Swallowed | Propagates |
| Seeder interruption | Restart from zero | Resumes from checkpoint |
| Error status mapping | Substring match on message text | Exception **type** |
| Food search `bún` vs `BÚN` | No match on SQLite | Matches on both providers |

---

## Flutter

### New files

| File | Purpose |
|---|---|
| `core/network/network_failure.dart` | Sealed failure hierarchy; parses RFC 7807 |
| `features/auth/utils/jwt_validator.dart` | Structural + `exp` validation, separately testable |
| `features/diary/services/meal_logger.dart` | The single server-first write contract |

### Modified files

| File | Change |
|---|---|
| `core/network/api_client.dart` | `UnauthorizedCoordinator`; GET-only bounded retry; injectable delay/transport |
| `features/auth/providers/auth_provider.dart` | `clearToken` flag; JWT validation on restore; listener deregistration |
| `features/diary/providers/diary_provider.dart` | `DiaryState<T>` with separate `data` / `cachedData` |
| `features/diary/services/diary_api_service.dart` | `logMeal` returns the server diary |
| `features/diary/screens/stats_screen.dart` | Removed the shadowing provider; retry UI |
| `features/home/screens/home_screen.dart` | Status banner + retry; no `$e` rendering |
| `features/food_search/screens/food_search_screen.dart` | Server-first via `MealLogger` |
| `features/scanner/screens/results_screen.dart` | Server-first via `MealLogger` |
| `features/scanner/services/gemini_vision_service.dart` | Typed failures; 5 MB message; 415; bounded retry |

### Behaviour changes

| Area | Before | After |
|---|---|---|
| Logout | `copyWith(token: null)` could not clear it | `clearToken: true` — token really becomes null |
| JWT missing `exp` | Treated as **valid** → 401 loop forever | Treated as invalid |
| Concurrent 401 | Static callback, one listener overwrote another | Single-flight logout, disposable listeners |
| GET retry | Up to 3× on **any** error, including 4xx | Only transient; 4xx never |
| POST retry | Retried | **Never** — no idempotency key exists |
| Connection error | Always relabelled "cold start" | Offline and cold start distinguished |
| HTTP 5xx on diary read | Shown as "offline" | Shown as **server error** |
| Empty server response | Replaced by stale local entries | Stays empty — deleted meals stay deleted |
| Save fails on server | Local entry written, **success shown** | Nothing written, failure shown, form stays open |
| Cache fails after server OK | Reported as failure → user retries → double-log | Reported as **success** |
| Gemini 413 message | "> 20 MB" (wrong) | "5 MB" (matches server) |
| Gemini 415 | Unhandled | Names JPEG / PNG / WebP |

---

## Deployment & CI

| File | Change |
|---|---|
| `scripts/vercel-build.sh` | Flutter pinned to **3.44.1** tag (was floating `stable`); strict `BACKEND_BASE_URL` validation; `set -x` removed (it printed env values into the build log); `flutter doctor -v` dropped |
| `vercel.json` | SPA rewrite excludes extensioned paths so assets are served before the fallback; `/assets/*` dropped from 1-year `immutable` to 1 h revalidate (filenames are **not** content-hashed); `$schema` added |
| `.github/workflows/flutter-ci.yml` | Adds `build web --release`, `vercel.json` JSON check, `bash -n` on the script, artifact upload; triggers on release-tooling files |
| `.github/workflows/deploy.yml` | GitHub Pages deprecated to `workflow_dispatch` only — two frontend paths needed two CORS origins but `render.yaml` declares one |
| `docs/DEPLOYMENT_GUIDE.md` | `JWT__KEY` / `GEMINI__APIKEY` corrected; unusable-looking key placeholder; `channel_binding=require`; Vercel Root Directory; 9 new smoke tests |
| `docs/DEPLOY_RENDER.md`, `README.md` | Vercel described consistently; GitHub Pages references removed |

### Deleted

`scripts/gemini_proxy.js`, `scripts/package.json`, `scripts/package-lock.json`,
`.env.example` — the superseded Node proxy and the env file that existed only
to configure it. `google_generative_ai` removed from `pubspec.yaml` and
`pubspec.lock`; no direct SDK import remained.

---

## Tests added

**Backend (+123)** — `AuthValidationRulesTests`, `AuthUniquenessTests` (real
two-context registration race against actual SQLite indexes),
`DiaryValidationRulesTests`, `DiaryConcurrencyTests`, `UsdaFoodSeederTests`
(fresh / interrupted / resumed / rerun / peer lease / expired lease / one
duplicate not killing its batch / non-duplicate error propagating),
`FoodSearchValidationTests`, `ProblemDetailsContractTests`,
`Support/SqliteTestDatabase`.

**Flutter (+79)** — `jwt_validator_test`, `api_client_retry_test` (exact attempt
counts, 1 s/2 s backoff, POST never retried, 8 statuses never retried,
cancellation mid-backoff, concurrent 401 → one logout), `diary_state_test`,
`meal_logger_test`, `vercel_build_url_validation_test` (drives the real shell
guard over 13 URL shapes), rewritten `gemini_vision_service_test`.

Tests use injected clocks, delays, transports, and repositories — no sleeps, no
network calls, no shared global state.

---

## Verification

```bash
dotnet build backend/CaloriesTracking.slnx -c Release   # 0 errors, 0 warnings
dotnet test  backend/CaloriesTracking.slnx -c Release   # 265 passed
flutter analyze                                          # No issues found
flutter test                                             # 96 passed
flutter build web --release --base-href / \
  --dart-define=BACKEND_BASE_URL=https://example.onrender.com   # succeeded
bash -n scripts/vercel-build.sh                          # OK
```

---

## Not done / still required

- **Docker build: not verified** — Docker unavailable in this environment.
- **PostgreSQL migration not executed against a real instance.** The backfill
  and duplicate-detection `DO` block are reviewed but need a staging run; no
  Neon project was created.
- **Gemini key rotation is still required.** The key appears in Git history;
  removing it from the current tree does not invalidate it. History was not
  rewritten.
- **Breaking:** `/api/analysis/food` changed from `{ error }` to RFC 7807
  ProblemDetails. External consumers of the old shape must be updated.
- No deployment was performed. Manual production smoke tests remain — see
  `docs/DEPLOYMENT_GUIDE.md` §5.
