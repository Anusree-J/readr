# Pre-launch smoke test (run on a Mac, ~20 min)

The provider layer is fully unit-tested against mocks, but **no auth path has
ever been exercised against a real provider** (tracked in ROADMAP M2). Run this
before the Product Hunt post goes live. Use the shipping artifact, not a debug
build: download `Readr-macOS-v2.6.0.zip` from the latest release.

## 0. First-run experience (2 min)

1. Unzip, drag to `/Applications`, double-click.
2. Expected: Gatekeeper "could not verify" dialog → Settings → Privacy &
   Security → **Open Anyway** works, app launches to the library.
3. Drop in one EPUB and one PDF. Both open and paginate.

If the app won't launch at all after Open Anyway → launch blocker, stop here.

## 1. Anthropic API key (5 min)

1. Settings → AI Providers → Anthropic → paste a real API key (`sk-ant-…`).
2. Expected: key accepted, model list populates, no key visible in
   `~/Library/Preferences` or app logs (spot-check with `defaults read` — it
   must only be in Keychain Access under the app's item).
3. Open a book → select a sentence → Ask → ask "what does this passage mean?"
4. Expected: streamed answer with source citations. Watch for: instant 401
   (wrong header shape), hang (SSE parse), or missing citations.
5. Highlight 3 passages → Compose article. Expected: streamed Markdown draft.

## 2. OpenAI API key (3 min)

Repeat step 1 with an OpenAI key (`sk-…`). Same expectations.

## 3. Sign in with ChatGPT — HIGHEST RISK (5 min)

This flow reuses the Codex CLI OAuth client
(`app_EMoamEEZ73f0CkXaXp7hrann`, loopback `127.0.0.1:1455/auth/callback` —
`Sources/ReadrKit/Auth/OAuthClient.swift:26`). It has **never been run**.
Three distinct failure points; note which one you hit:

1. Settings → OpenAI → "Sign in with subscription".
2. **Browser opens** to auth.openai.com and shows a real login page (not
   `invalid_client` / `redirect_uri mismatch`).
3. **Redirect lands**: after login, the browser shows the app's "you can close
   this tab" page and the app UI flips to signed-in (loopback server + token
   exchange worked).
4. **Token actually works**: Ask a question in a book. A Codex-scoped token may
   be rejected by the plain API endpoint even if sign-in "succeeded" — this is
   the step most likely to fail.

### If step 3 fails at any point

Do NOT launch with the button visible. One-line fix: return `nil` for
`.openAI` in `SettingsModel.oauthConfig(for:)`
(`App/Settings/SettingsModel.swift:78`) — the "Sign in with subscription"
button disappears (`supportsOAuth` gates it), API-key path is untouched. Then
remove "sign in with a ChatGPT subscription" from README + PH listing copy.

### Even if it works — a decision to make

Borrowing OpenAI's first-party client ID is the same Terms-of-Service category
the project explicitly rejected for Anthropic
(`Sources/ReadrKit/Auth/OAuthClient.swift:34-42`). A PH commenter can spot the
client ID in the source. Either own it publicly ("Codex-pattern sign-in, may
break") or ship API-key-only and re-add OAuth when there's a registered
client. Consistency argument: Anthropic OAuth was cut on exactly these
grounds.

## 4. Local / Ollama (3 min)

1. `ollama serve` + `ollama pull llama3.2` (or any pulled model).
2. Settings → Local → connect, pick the model.
3. Turn OFF Wi-Fi. Ask a question in a book.
4. Expected: streamed answer with Wi-Fi off (the zero-egress claim in the
   README, verified live).

## 5. Token refresh (only if step 3 passed)

OAuth expiry wiring is listed as unfinished in ROADMAP M2. If ChatGPT sign-in
works, expect the session to die silently after the access token expires
(~hours). Acceptable for launch if disclosed; note it in the FAQ reply.

## Outcome matrix

| Result | Launch posture |
| --- | --- |
| 1, 2, 4 pass; 3 fails | Hide the OAuth button (one-liner above), launch. Listing says: API keys + local. |
| 1 or 2 fail | Launch blocker — the headline feature doesn't work. Debug before launching. |
| 4 fails | Remove "fully offline" claims from listing before launch. |
| All pass | Launch as written; disclose token-expiry caveat. |
