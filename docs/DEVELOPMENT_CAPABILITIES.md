# Development Capabilities

Snapshot date: 2026-07-13.

This file maps the capabilities available in the current Codex environment to
SnapCal work. Availability can drift; run `harness-cli tool check` and confirm
the live tool before relying on it.

## Project-Registered Capabilities

The Harness registry currently marks these as present:

| Capability | Provider | Use in SnapCal |
| --- | --- | --- |
| Apple build/debug | XcodeBuildMCP | discover, scaffold, build, test, run, inspect, debug, and capture Apple app proof |
| SwiftUI implementation | `swiftui-ui-patterns` | review form, menu-bar state, navigation, and drop-zone composition |
| SwiftUI performance | `swiftui-performance-audit` | code-first audit before ETTrace profiling |
| Design translation | `figma-swiftui` | translate approved Figma screens and SwiftUI components |
| macOS UI inspection | Computer Use | inspect native app UI when a direct API or Xcode snapshot is insufficient |
| Browser E2E | Playwright | backend/admin surfaces, OAuth test pages, docs, and web-based review prototypes |
| OpenAI docs | `openai-docs` | current official image-input and structured-output API guidance |
| Repository collaboration | GitHub plugin | issues, PRs, reviews, checks, and workflow evidence |
| Visual assets | ImageGen | concepts, empty states, onboarding art, and launch assets—not code-native icons |
| Benchmark analysis | Spreadsheets | corpus labels, accuracy calculations, error slices, and metric workbooks |

Query the live set:

```bash
scripts/bin/harness-cli tool check
scripts/bin/harness-cli query tools --summary
```

## Installed Plugin And Skill Inventory

One hundred skill entrypoints were found across the configured skill roots.
They are grouped here so future work selects the smallest applicable set.

### Build iOS Apps

`ios-app-intents`, `ios-debugger-agent`, `ios-ettrace-performance`,
`ios-memgraph-leaks`, `ios-simulator-browser`, `swiftui-liquid-glass`,
`swiftui-performance-audit`, `swiftui-ui-patterns`, and
`swiftui-view-refactor`.

Highest SnapCal value: SwiftUI composition and refactoring, Xcode/Simulator
debugging, leak/performance proof, Share Extension/App Intent work, and live
preview iteration. Liquid Glass is optional polish, never a Phase 1 dependency.

### Figma

`figma-code-connect`, `figma-create-new-file`, `figma-generate-design`,
`figma-generate-diagram`, `figma-generate-library`, `figma-implement-motion`,
`figma-swiftui`, `figma-use`, `figma-use-figjam`, `figma-use-motion`, and
`figma-use-slides`.

Use for a review-screen system, drop-zone states, prototypes, architecture
diagrams, and design/code parity. Figma write tools have mandatory prerequisite
skills; load those instructions before calls.

### Build Web Apps

`frontend-app-builder`, `frontend-testing-debugging`, `react-best-practices`,
`shadcn`, `stripe-best-practices`, and `supabase-postgres-best-practices`.

Only frontend testing and PostgreSQL guidance are plausibly relevant early.
React/shadcn are appropriate only if a real web surface is accepted; Stripe is
out of scope.

### Vercel

`agent-browser`, `agent-browser-verify`, `ai-elements`, `ai-gateway`,
`ai-generation-persistence`, `ai-sdk`, `auth`, `bootstrap`, `chat-sdk`, `cms`,
`cron-jobs`, `deployments-cicd`, `email`, `env-vars`, `geist`, `geistdocs`,
`investigation-mode`, `json-render`, `marketplace`, `micro`, `ncc`,
`next-forge`, `nextjs`, `observability`, `payments`, `react-best-practices`,
`routing-middleware`, `runtime-cache`, `satori`, `shadcn`,
`sign-in-with-vercel`, `swr`, `turbopack`, `turborepo`, `v0-dev`,
`vercel-agent`, `vercel-api`, `vercel-cli`, `vercel-firewall`, `vercel-flags`,
`vercel-functions`, `vercel-queues`, `vercel-sandbox`, `vercel-services`,
`vercel-storage`, `verification`, and `workflow`.

This is optional backend/deployment leverage, not the selected architecture.
Relevant candidates if the backend moves to Vercel are AI routing,
observability, environment management, functions/services, queues/workflows,
storage, CI/CD, and full-story verification. Do not let available Vercel skills
silently replace the spec's FastAPI-first direction.

### GitHub

`github`, `gh-address-comments`, `gh-fix-ci`, and `yeet` cover repository
orientation, review feedback, CI diagnosis, and intentional publish/PR flow.

### Browser And Mac Control

`control-in-app-browser`, `control-chrome`, `computer-use`, and `playwright`
cover local or signed-in browser state, native Mac UI, and repeatable browser
automation. Prefer XcodeBuildMCP for Apple targets and purpose-built connectors
for provider operations.

### Sites And Visual Communication

`sites-building`, `sites-hosting`, `visualize`, `imagegen`, and
`remotion-product-video` can support a landing page, interactive explanation,
visual assets, or product video after a real product surface exists.

### Documents And Data

`documents`, `pdf`, `Presentations`, `Spreadsheets`, `excel-live-control`,
`template-creator`, `latex-compile`, `latex-doctor`, and
`texlive-runtime-installer` support benchmark reports, technical documents,
decks, spreadsheets, and rendered verification.

### Codex Extension Skills

`find-skills`, `skill-creator`, `skill-installer`, `plugin-creator`, and
`openai-docs` support discovery, custom capability packaging, installation,
plugin authoring, and official OpenAI guidance.

## Callable Tool Families

The current session exposes 278 callable/deferred tool entries, including:

- 44 XcodeBuildMCP operations for Apple project discovery, build/test/run,
  Simulator UI automation, coverage, logs, LLDB, screenshots, and video;
- 89 GitHub connector operations for repositories, issues, PRs, reviews,
  commits, checks, logs, and artifacts;
- 19 Figma operations and 19 Sites operations;
- 24 Playwright operations and 24 Vercel operations;
- official OpenAI documentation search/fetch/OpenAPI tools and Context7 library
  documentation lookup;
- filesystem, patch, shell, local image inspection, web research, image
  generation, Codex task coordination, and document-control tools.

Tool presence is not provider configuration. No Google Calendar, Google Cloud
Vision, Google Places, Gemini, OAuth credential, or production hosting
connector is configured by this repository.

## Recommended Usage By Phase

| Phase | Primary capabilities |
| --- | --- |
| Contract and design | Harness CLI, Figma/diagram tools, OpenAI docs, Context7 |
| macOS prototype | XcodeBuildMCP, SwiftUI skills, Figma-SwiftUI, Computer Use |
| extraction backend | official provider docs, Context7, shell/tests; add a vetted FastAPI skill only if needed |
| benchmark | Spreadsheets, filesystem fixtures, provider contract tests, visualization |
| release | GitHub checks/PR workflows, Xcode platform proof, observability/deploy tools selected by hosting decision |
| launch | Sites or web builder, ImageGen, Remotion video—only from verified product truth |

## Capability Gaps And Installation Policy

- Google Calendar and Google cloud provider integrations still need first-party
  SDK/API implementation and test doubles.
- The skills marketplace search found a Google Calendar skill with more than
  1,000 installs, but its source repository has only 3 stars and one listed
  security audit fails. Do not install it without a separate security review.
- FastAPI and Vietnamese OCR marketplace results were low-adoption or weakly
  matched. Existing general tools plus official docs are safer for now.
- Prefer official/bundled plugins. For third-party skills, verify install count,
  source reputation, repository activity/stars, and security audits before
  installation.
- Create a project-specific skill only after repeated SnapCal work reveals a
  stable workflow that general tools do not capture.
