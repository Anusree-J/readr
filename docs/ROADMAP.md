# Roadmap

The first milestone builds the reader and **both** AI features (ask-the-book and
highlights→article) together, per project direction.

## M0 — Foundation ✅
- [x] Repo, license, docs, architecture
- [x] Context strategy research + decision
- [x] `ReadrKit` package skeleton with core protocols & models
- [x] XcodeGen `project.yml` + SwiftUI app shell
- [x] CI building the package

## M1 — Reading (in progress)
- [x] Library shelf + basic reader view (SwiftUI)
- [x] Import plain-text / Markdown (parser + registry, tested)
- [x] Import PDF via PDFKit (rejects encrypted/locked; tested on device)
- [x] Reading position persistence (store + reader wiring)
- [x] Highlights & notes — service + on-disk persistence (`FileLibraryStore`, tested)
- [x] Highlight/note capture UI in the reader (selectable text view)
- [x] UI test: open seeded book → navigate chapters (`-uiTestSeed`)
- [x] EPUB import — container/OPF/spine/TOC parser in `ReadrKit` (tested) +
  ZIPFoundation archive adapter in the app; DRM (encryption.xml) rejected

### M1 done. Optional polish carried forward:
- [ ] Readium paginated navigator (reflow/fonts/decorations) as a rendering upgrade
- [ ] TOC/outline-aware chaptering for PDFs
- [ ] iCloud-synced store (SwiftData/GRDB) to replace the JSON file store

## M2 — Connect an LLM (in progress)
- [x] PKCE (S256) + OAuth client (authorize/callback/token exchange/refresh)
- [x] Credential stores: in-memory + Keychain
- [x] Providers: Anthropic, OpenAI, Local (Ollama) with SSE streaming
- [x] Provider catalog + manager (selection, factory, local-mismatch guard)
- [x] Provider settings UI: API key, OAuth sign-in, local model, model picker
- [x] Loopback OAuth server + browser coordinator (app)
- [ ] Verify Anthropic OAuth client id/endpoints (placeholder today)
- [ ] Manual J5 walk on a Mac with a real provider; token-refresh-on-expiry wiring

## M3 — Ask the book
- [ ] Select text → Ask panel → streamed answer
- [ ] Adaptive context router (Tier 1 whole-book + prompt caching)
- [ ] RAG index build + hybrid retrieval (Tier 2) for large books
- [ ] On-device embeddings for local mode

## M4 — Highlights → article
- [ ] Collect & order highlights/notes
- [ ] `ArticleComposer` → editable Markdown article
- [ ] Export (Markdown / PDF / share sheet)

## M4 — Polish & OSS health
- [ ] iCloud sync of library/annotations
- [ ] Accessibility & localization passes
- [ ] Issue templates, discussions, release process

## Open questions / decisions to revisit
- OAuth feasibility for "log in with Claude / ChatGPT" vs. API keys only.
- SwiftData vs. GRDB for persistence.
- Local LLM runtime: MLX vs. llama.cpp vs. Ollama bridge.
