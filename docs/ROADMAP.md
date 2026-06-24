# Roadmap

The first milestone builds the reader and **both** AI features (ask-the-book and
highlights→article) together, per project direction.

## M0 — Foundation (this scaffold)
- [x] Repo, license, docs, architecture
- [x] Context strategy research + decision
- [ ] `ReaderKit` package skeleton with core protocols & models
- [ ] XcodeGen `project.yml` + SwiftUI app shell
- [ ] CI building the package

## M1 — Reading
- [ ] Import EPUB + PDF (DRM-free)
- [ ] Library shelf + reader view (Readium)
- [ ] Highlights & notes with persistence
- [ ] Reading position / progress

## M2 — Ask the book
- [ ] Provider settings: Anthropic key, OpenAI key, local model
- [ ] Keychain storage + provider switching
- [ ] Select text → Ask panel → streamed answer
- [ ] Adaptive context router (Tier 1 whole-book + prompt caching)
- [ ] RAG index build + hybrid retrieval (Tier 2) for large books
- [ ] On-device embeddings for local mode

## M3 — Highlights → article
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
