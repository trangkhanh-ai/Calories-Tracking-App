# PR14 Controlled Production Release Notes

## Release intent

PR14 prepares the Calories Tracking App for a controlled Render + Neon + Vercel
release. It does not deploy, merge, or authorize production traffic by itself.
The release commit must pass CI and then complete the manual provider checks in
this document and `docs/DEPLOYMENT_GUIDE.md`.

## Verified in repository and CI

- Release build and backend tests run on Ubuntu.
- A required tracked-file scanner rejects current credentials, tracked
  symlinks, partial placeholder bypasses, and credential-bearing PostgreSQL
  values without printing their contents.
- PostgreSQL 16 CI uses ephemeral certificates, TLS, SCRAM-SHA-256, and required
  channel binding. Integration tests cannot skip in the dedicated job.
- The production Docker image is built but never pushed. CI verifies its exec
  entrypoint, non-default `PORT`, loopback-only host publishing, USDA CSV,
  health endpoints, fail-fast configuration, and graceful SIGTERM shutdown.
- Production configuration requires secure PostgreSQL, a sufficiently strong
  JWT key, Gemini key, safe HTTPS CORS origin, explicit proxy mode, and explicit
  seeding mode.

## Deployment configuration

The Render Blueprint sets:

```text
ASPNETCORE_ENVIRONMENT=Production
HOSTING__BEHINDTLSTERMINATINGPROXY=true
SEEDING__ENABLED=true
```

These values remain dashboard-managed with `sync: false`:

```text
ConnectionStrings__DefaultConnection
JWT__KEY
GEMINI__APIKEY
CORS__ALLOWEDORIGINS__0
```

Render prompts for `sync: false` values only when it first creates the Blueprint
resource. Existing services must have these values verified or updated in the
Dashboard because a later Blueprint sync does not prompt again.

The Neon credential must be supplied only through the Render dashboard and must
preserve both query parameters:

```text
postgresql://<user>:<password>@<neon-host>/<database>?sslmode=require&channel_binding=require
```

Use a newly created, dedicated, empty Neon database for the first deployment.
Reusing a legacy, shared, or manually initialized schema is outside the verified
release path.

## Render proxy and client-IP behavior

Render terminates HTTPS before forwarding traffic to the HTTP container.
`HOSTING__BEHINDTLSTERMINATINGPROXY=true` enables that explicit trust boundary.
Only the immediate proxy hop is trusted (`ForwardLimit=1`). Forwarded headers
are processed before rate limiting so the resolved client address, not the
Render proxy address, partitions unauthenticated limits. Do not use this setting
for a directly exposed container or unreviewed multi-proxy topology.

## Health and startup acceptance

- `/health/live`: liveness only; expected HTTP 200 and `{"status":"ok"}` while
  the process serves, regardless of database readiness.
- `/health`: Neon readiness; expected HTTP 200 and `{"status":"ok"}` only when
  the database is reachable. Render monitors this endpoint.

Before approving traffic, inspect sanitized Render startup logs for successful
EF Core migrations and `USDA seed completed` with a plausible row count. Restart
once and confirm `already completed`; repeated full imports, missing dataset
warnings, migration failures, or seed failures block release.

## Manual checks still required

No authorized real staging environment is represented by repository CI. An
operator must still validate:

- Render Blueprint values, TLS termination, cold start, logs, and rollback UI.
- Real Neon connectivity, empty-database status, permissions, persistence, and
  recovery point/branch.
- Vercel `BACKEND_BASE_URL`, exact production CORS, SPA deep links, and browser
  mixed-content behavior.
- Authentication, seeded food search, diary write/read persistence, rate-limit
  client-IP behavior, and one authorized Gemini request.

If access is unavailable, record each item as `NOT RUN`. Do not infer a passing
staging deployment from CI container tests.

## Rollback

1. Stop promotion and record the failing Render deploy, commit, health results,
   and sanitized migration/seed logs.
2. Redeploy the last known-good immutable commit/image in Render.
3. Do not delete Neon and do not automatically down-migrate. Confirm the older
   application is compatible with the current schema.
4. If compatibility is uncertain, restore or branch from the recorded Neon
   recovery point into a separate database, validate it, then update Render.
5. Re-run liveness, readiness, authentication, seeded search, and a database
   write/read smoke check. Record the final deployed commit and approver.

## Security release gate

The historical Gemini exposure is treated as real. Rotate/revoke the old key
before production and enter only the replacement in Render. Never put Gemini,
JWT, or Neon credentials in Git, Flutter build arguments, Vercel public
variables, logs, screenshots, issues, or release notes.
