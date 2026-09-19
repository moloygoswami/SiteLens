# SiteLens — Governing Development Instructions

Treat these as persistent, governing development-behavior rules for every task in
this project. They apply to the whole development lifecycle: planning, coding,
review, and verification.

## 1. Think Before Coding
- State assumptions explicitly.
- Surface ambiguity and competing interpretations.
- Ask rather than guess when important uncertainty exists.
- Push back when a simpler or safer approach is warranted.
- Stop and ask when confused.

## 2. Simplicity First
- Implement the minimum code required.
- No speculative features.
- No unnecessary abstractions.
- No unrequested flexibility/configurability.
- Prefer the simplest solution that satisfies the requirement.

## 3. Surgical Changes
- Change only what the task requires.
- Do not refactor adjacent code unnecessarily.
- Do not perform drive-by cleanup.
- Match the existing project style.
- Remove only orphaned code created by your own changes.

## 4. Goal-Driven Execution
- Define explicit success criteria before implementation.
- Prefer tests that demonstrate the requested behavior.
- For multi-step work, state the plan and verification for each step.
- Do not declare success until verification passes.

## 5. Evidence Integrity (SiteLens-specific)
- Never imply a stronger evidence, GPS, recording, provenance, integrity, or
  verification state than the system has actually established.

## 6. Installed Skills

Skills are installed under `.agents/skills/` and tracked in `skills-lock.json`.

### Ponytail (from `DietrichGebert/ponytail`)
- **ponytail** — lazy senior dev mode (YAGNI ladder)
- **ponytail-review** — over-engineering review
- **ponytail-audit** — whole-repo over-engineering audit
- **ponytail-debt** — harvest `ponytail:` shortcuts into a ledger
- **ponytail-gain** — impact scoreboard
- **ponytail-help** — quick reference

### Firebase (from `firebase/agent-skills`)
- **firebase-basics** — CLI login, project creation, config downloads
- **firebase-auth-basics** — Firebase Authentication setup
- **firebase-firestore** — Cloud Firestore data modeling, rules, queries
- **firebase-hosting-basics** — classic Firebase Hosting deploy
- **firebase-app-hosting-basics** — App Hosting for SSR apps
- **firebase-data-connect** — Firebase Data Connect / SQL Connect
- **firebase-ai-logic-basics** — Firebase AI Logic (Gemini API) integration
- **firebase-crashlytics** — crash reporting setup
- **firebase-remote-config-basics** — Remote Config templates and SDKs
- **firebase-security-rules-auditor** — Firestore/Storage rules audit
- **extension-to-functions-codebase** — convert Extensions to Cloud Functions
- **xcode-project-setup** — Swift Packages and Xcode project linking

### Design & Frontend (from `Leonxlnx/taste-skill`, `pbakaus/impeccable`, and `ibelick/ui-skills`)
- **design-taste-frontend** — anti-slop frontend skill (v2)
- **design-taste-frontend-v1** — original v1 taste-skill
- **full-output-enforcement** — override LLM truncation, enforce complete output
- **impeccable** — premium UI polish and design critique
- **improve-ui** — audit product surface against design evidence and write implementation plans
- **industrial-brutalist-ui** — Swiss/typographic brutalist interfaces
- **redesign-existing-projects** — upgrade existing sites to premium quality

### Lazyweb (from `aboul3ata/lazyweb-skill`)
- **lazyweb** — evidence-backed product UI, screen search, growth, and conversion decisions
- **lazyweb-growth-score** — score a website's growth readiness
- **lazyweb-growth-report** — evidence-backed growth report for product improvement
- **lazyweb-growth-backlog** — growth backlog management
- **lazyweb-search-experiments** — search product experiments & conversion decisions
- **lazyweb-search-flows** — search multi-step product user flows
- **lazyweb-search-screens** — search real product UI patterns & screenshots
- **lazyweb-propose-ui-changes** — structured visual change proposals
- **lazyweb-update** — sync and update local Lazyweb skill pack

### TypeSafe (from `typesafe-ai/skills`)
- **typesafe-ai** — typed judgments and probabilities from System One models (e.g., Jev) for routing, ranking, extraction, verification, and programmable common sense

<!-- LAZYWEB:ROUTER:BEGIN — managed by Lazyweb -->
## Use Lazyweb for ALL product UI work

Route product improvement, conversion research, website scoring, and growth work through `/lazyweb`. Choose the capability that best helps the user reach their goal; they do not need to know the feature name first.

Broad improvement requests may use a Growth Report when it best serves the user's goal. Use only the screens, experiments, and flows the task needs, finalize useful selected evidence into Agentic Search, and return its stable private link.

Available skills: `/lazyweb-growth-score`, `/lazyweb-growth-report`, `/lazyweb-growth-backlog`, `/lazyweb-search-experiments`, `/lazyweb-search-flows`, and `/lazyweb-search-screens`.

Skip Lazyweb for backend/CLI/infra work, prose editing, or non-product visuals.
<!-- LAZYWEB:ROUTER:END -->

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
