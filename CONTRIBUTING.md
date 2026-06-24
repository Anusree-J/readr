# Contributing to Reader

Thanks for your interest! Reader is an open-source, native iOS/macOS AI reading app.

## Project layout

- `Sources/ReaderKit/` — platform-agnostic core (parsing, context router, RAG,
  LLM providers, article composer). Builds & tests on any Swift platform.
- `Tests/ReaderKitTests/` — unit tests for the core.
- `docs/` — architecture and the context-strategy rationale. **Read
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before sizable changes.**
- The SwiftUI app target is generated from `project.yml` via XcodeGen (added in M0).

## Building & testing

The core package builds anywhere Swift is installed:

```sh
swift build
swift test
```

The full app requires **macOS + Xcode 15+**.

## Ground rules

- Keep external dependencies (Readium, vendor SDKs, vector stores) behind the
  `ReaderKit` protocols so they stay swappable and mockable.
- Add tests for core logic — especially context routing and retrieval.
- No secrets in the repo. API keys live in the Keychain at runtime.
- Privacy is a feature: don't add network calls to the local-LLM path.

## Pull requests

Small, focused PRs that map to a roadmap item ([docs/ROADMAP.md](docs/ROADMAP.md))
are easiest to review. Describe the user-facing change and how you tested it.
