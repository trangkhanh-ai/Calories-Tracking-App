# Professional Repository Showcase Design

## Purpose

Redesign the public repository landing page so a visitor can quickly understand the product, open the live application, assess the engineering quality, and find deeper documentation. The README will serve both portfolio reviewers and developers without becoming a full replacement for the existing technical documents.

## Approved Direction

- Audience balance: product and engineering information receive equal overall weight.
- Visual style: Product-first Bento, using the application's matcha green, soft peach, off-white, slate, and simple geometric shapes.
- Content strategy: Balanced Product Showcase.
- Primary language: Vietnamese, with a concise English summary near the top.
- Primary CTA: `https://calories-tracking-app-ten.vercel.app/`.
- Screenshots: capture real public login and registration pages at desktop and mobile sizes when safe.

## Scope

The implementation may change:

- `README.md`
- `docs/assets/repository-banner.png`
- `docs/assets/github-social-preview.png`
- public, unauthenticated screenshots under `docs/screenshots/`
- this design specification and the implementation plan

The implementation must not change Flutter behavior, backend behavior, database behavior, migrations, deployment configuration, CI behavior, production environment variables, or production data. Repository metadata may be updated only when the authenticated GitHub identity has sufficient permission.

## README Information Architecture

The README will use this reading order:

1. Product-first hero and banner
2. Verified technology and CI badges
3. Prominent live-demo section
4. Product overview and completed feature highlights
5. Real public screenshots, when safe
6. Grouped technology stack
7. GitHub-compatible Mermaid production architecture
8. Production deployment summary
9. Concise quick start and environment-variable reference
10. Project structure
11. Testing, quality, and security practices
12. Documentation index
13. Real future roadmap items
14. Neutral contributors link and restrained footer

Long setup details will use `<details>` blocks or link to existing documents. The live-demo link will appear before the first long technical section.

## Hero And Visual Assets

### Repository banner

- Output: `docs/assets/repository-banner.png`
- Target size: approximately 1600 x 500
- Light Product-first Bento composition
- Text: project title, `AI-Powered Nutrition Tracking`, and the verified stack line
- Colors: `#2DCA8C`, `#1F9D6B`, `#FF9B71`, `#F7F9FC`, and slate text tones
- Decoration: calorie-ring and bento-inspired geometric shapes
- No stock photography, font files, fake logos, production URLs, or secrets in metadata
- The generic Flutter launcher icon will not be presented as the application's brand mark

### GitHub social preview

- Output: `docs/assets/github-social-preview.png`
- Exact size: 1280 x 640
- Uses the same visual system with a darker, high-contrast presentation suitable for link previews
- Remains a manual GitHub Settings upload unless repository administration can be completed safely through supported tooling

Images will be optimized without visible quality loss and checked in both light and dark GitHub contexts.

## Screenshot Plan

The implementation will inspect the public production frontend without authentication. If the pages are current, stable, and free from personal data, capture:

- `docs/screenshots/login-desktop.png` at 1440 x 900
- `docs/screenshots/login-mobile.png` at 390 x 844
- `docs/screenshots/register-desktop.png` at 1440 x 900
- `docs/screenshots/register-mobile.png` at 390 x 844

Browser chrome will be cropped where practical. No account will be created, no credentials will be entered, and no authenticated route will be opened. If a screenshot contains personal data, secrets, tokens, debugging UI, or an unstable/error state, it will not be committed. If no safe and meaningful screenshots can be captured, the gallery will be omitted completely and the Live Demo section will remain the visual entry point.

## Source-Backed Product Story

Only verified completed capabilities will be presented:

- Gemini-assisted food-image analysis through the backend
- Registration, login, JWT authentication, and BCrypt password hashing
- User profile data and calorie-goal calculations
- USDA nutrition-data search
- Server-first meal diary
- Seven-day nutrition statistics
- Rate limiting for sensitive or resource-intensive endpoints
- Production health checks and deployment topology

Planned work will remain explicitly labeled as future work. No metrics, test totals, awards, license, contributor roles, security guarantees, or completed features will be invented.

## Architecture And Technical Content

The Mermaid diagram will show:

```text
User -> Flutter Web on Vercel -> ASP.NET Core API on Render -> Neon PostgreSQL
                                      |
                                      +-> Gemini API
```

Labels will communicate HTTPS/JSON, JWT authentication, backend-only Gemini access, and the server diary as the source of truth. The diagram will remain intentionally small for reliable GitHub rendering and will link to `docs/SYSTEM_ARCHITECTURE.md` for detail.

The technology stack will be grouped into frontend, backend, data and AI, and infrastructure. Every listed technology must be present in project source, package configuration, deployment configuration, or CI.

## Development, Quality, And Security Content

Quick Start will include Flutter and .NET 9 prerequisites, backend user-secrets commands with non-secret placeholders, backend startup, Flutter Web startup, and the Android emulator backend URL. Configuration tables will distinguish .NET colon notation from environment-variable double-underscore notation.

Testing and quality content will describe the current CI capabilities without hardcoded test counts:

- Flutter analyze, tests, and release web build
- Vercel configuration validation
- backend Release build and tests
- PostgreSQL integration and TLS validation
- Docker production build and container smoke testing
- Render Blueprint validation
- tracked-secret scanning

Security text will remain factual and bounded: server-only Gemini credentials, no Flutter Web secrets, BCrypt password hashing, JWT production validation, PostgreSQL TLS/channel binding, CORS allowlisting, rate limiting, and tracked-secret scanning.

## Links, Contributors, And License

All relative documentation links and local images must exist with case-correct paths. The documentation index will include the verified architecture, API, deployment, Render deployment, development setup, and spec-driven-development documents.

Contributors will be represented through the repository contributors graph unless source history provides unambiguous GitHub attribution. Because no license file exists, the README will not claim MIT, Apache, open-source, or reuse rights and will omit a License section.

## Repository Metadata

When authenticated permissions allow, update only:

- Description: `AI-powered calorie and nutrition tracking with Flutter, ASP.NET Core, Gemini, and PostgreSQL.`
- Homepage: `https://calories-tracking-app-ten.vercel.app/`
- Valid, lowercase topics selected from the requested list within GitHub's limits

Visibility, default branch, branch protection, collaborators, Actions permissions, merge strategy, ownership, and GitHub App installations remain untouched. If permission is unavailable, report the exact proposed values and manual owner steps.

## Validation And Failure Handling

Before committing the final showcase:

- verify the public frontend and backend liveness links without authentication, retrying expected Render cold starts
- validate all relative links and image paths
- validate Markdown tables, headings, and Mermaid syntax
- confirm no placeholder screenshot text or `example.onrender.com` remains
- run the repository tracked-secret scanner
- run `git diff --check`
- confirm no `.env`, `.vercel`, credentials, build output, or personal information is staged
- visually review the rendered README for desktop, mobile, GitHub light mode, and GitHub dark mode

If production pages are unavailable or unsafe for screenshots, omit the gallery. If repository metadata cannot be changed, provide a manual handoff. Neither condition blocks the README redesign itself.

## Delivery

- Branch: `docs/professional-repository-showcase`
- Final implementation commit: `docs: create professional repository showcase`
- Pull request title: `docs: redesign repository landing page`
- Pull request base: `main`
- The pull request remains open for visual review and is not merged.
