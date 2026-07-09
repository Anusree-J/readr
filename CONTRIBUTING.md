# Contributing to Readr

Thanks for your interest! Readr is an open-source, native iOS/macOS AI reading app.

## Project layout

- `Sources/ReadrKit/` — platform-agnostic core (parsing, context router, RAG,
  LLM providers, article composer). Builds & tests on any Swift platform.
- `Tests/ReadrKitTests/` — unit tests for the core.
- `docs/` — architecture and the context-strategy rationale. **Read
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before sizable changes.**
- The SwiftUI app target is generated from `project.yml` via XcodeGen (added in M0).

## Building & testing

The core package builds anywhere Swift is installed:

```sh
swift build
swift test
```

The full app requires **macOS + Xcode 15+**:

```sh
xcodegen generate && open Readr.xcodeproj   # run the Readr scheme (macOS or iOS)
```

Simulator builds need no signing setup. To run on a physical iPhone/iPad,
pick your team once in Xcode's Signing & Capabilities pane after generating
(the setting lives in the generated project, so regeneration clears it), or
pass it on the command line: `xcodebuild ... DEVELOPMENT_TEAM=<your team id>`.
The team ID is intentionally never committed — release signing happens in CI
(see `.github/workflows/testflight.yml` and `release.yml`).

## Ground rules

- Keep external dependencies (Readium, vendor SDKs, vector stores) behind the
  `ReadrKit` protocols so they stay swappable and mockable.
- Add tests for core logic — especially context routing and retrieval.
- No secrets in the repo. API keys live in the Keychain at runtime.
- Privacy is a feature: don't add network calls to the local-LLM path.

## Pull requests

Small, focused PRs that map to a roadmap item ([docs/ROADMAP.md](docs/ROADMAP.md))
are easiest to review. Describe the user-facing change and how you tested it.
