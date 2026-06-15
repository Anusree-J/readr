# DocSigner — Verifiable Credentials for Google Docs

A Chrome (Manifest V3) extension that turns the **content of the Google Doc
you're viewing** into a **W3C Verifiable Credential**, secured as a **JWT
(VC-JWT)** and signed with a key that **never leaves your browser**.

> _“Whatever is on this Google Doc, signed by me, provably unmodified.”_

- ✍️ **One click** to issue a credential for the current document
- 🔑 **Local keys** — an ES256 (P-256) keypair generated with WebCrypto and
  stored in `chrome.storage`; nothing is sent to any server
- 🆔 **`did:jwk` issuer** — your public key _is_ your identity, embedded in
  every credential, so verification needs no network and no registry
- 📜 **W3C VC 2.0** data model, serialized as a JWS (`ES256`)
- 🔎 **Built-in verifier** that works fully offline

---

## How it works

```
 Google Doc ──export?format=txt──▶ plain text ──SHA-256──▶ digest
                                                    │
   did:jwk (your public key) ◀─derives─ local ES256 keypair
                                                    │
                          W3C VC ── signed (ES256) ──▶  VC-JWT
                                                    │
              anyone ──paste──▶ Verify page ──checks signature──▶ ✓ / ✕
```

1. **Read.** The extension asks Google Docs for the plain-text export of the
   open document (`/document/d/<id>/export?format=txt`) using your existing
   logged-in session — so it works for any doc you can already open, with **no
   OAuth and no Google Cloud project**.
2. **Hash.** It computes the `SHA-256` of that text. This digest is the
   integrity anchor: change one character and the hash changes.
3. **Build.** It wraps the title, URL, digest, and timestamp in a W3C
   Verifiable Credential (Data Model 2.0).
4. **Sign.** It signs the credential into a compact **VC-JWT** with your local
   `ES256` key. Your issuer identity is a `did:jwk` derived from your public key.
5. **Verify.** Anyone can paste the VC-JWT into the Verify tab (or the
   standalone verifier page). It extracts the public key from the credential's
   own `did:jwk`, checks the signature, and — if the content was embedded —
   re-hashes it to confirm it matches.

### What “verifiable” means here

The signature proves two things to anyone holding the VC-JWT:

- **Authenticity** — it was signed by the holder of *that specific* private key
  (identified by the `did:jwk` issuer).
- **Integrity** — neither the credential nor the document digest was altered
  after signing; any change invalidates the signature.

This is a **self-asserted** credential: the `did:jwk` is an anonymous key, not a
real-world identity vouched for by a third party. To bind it to a real identity
you'd publish your DID somewhere trusted (your website, a `did:web`, an
organizational registry). That's a natural next step — see below.

---

## Install (load unpacked)

1. Open `chrome://extensions` in Chrome (or any Chromium browser).
2. Toggle **Developer mode** (top-right).
3. Click **Load unpacked** and select the **`extension/`** folder of this repo.
4. Open any Google Doc. Click the extension icon (or the floating **🔏 Sign**
   button) and hit **Sign this document**.

---

## Using it

- **Sign tab** — signs the current doc. Optionally tick *Embed the document
  text* to make the credential self-contained (a verifier can then confirm the
  content offline, without re-opening the doc). Copy or download the `.vc.jwt`.
- **Identity tab** — view/copy your issuer **DID** and **public key (JWK)**, or
  reset to a fresh identity.
- **Verify tab** — paste any VC-JWT to check it. A full-page verifier also lives
  at `chrome-extension://<extension-id>/src/verify.html`.

---

## Project layout

```
extension/
  manifest.json          MV3 manifest
  src/
    crypto.js            Zero-dependency WebCrypto primitives (ES256, JWS, did:jwk)
    background.js        Service worker: key custody, doc export, VC issuance
    content.js           Floating "Sign" button injected into Google Docs
    popup.html/.css/.js  Toolbar popup: Sign / Identity / Verify
    verify.html/.js      Standalone offline verifier page
  icons/                 16/48/128 px action icons
  test/crypto.test.mjs   End-to-end sign → verify → tamper test
```

## Run the tests

```bash
cd extension
node test/crypto.test.mjs
```

Covers base64url, `did:jwk` round-tripping, a known SHA-256 vector, a full
sign→verify cycle, embedded-content re-hashing, and rejection of both tampered
credentials and impostor signatures.

---

## Design notes & trade-offs

- **Why the export endpoint instead of scraping the page?** Modern Google Docs
  renders text to a `<canvas>`, so the DOM no longer contains the document text.
  The export endpoint returns the authoritative plain text and respects your
  existing permissions and cookies.
- **Why `ES256` and not Ed25519?** `ES256` is universally supported by WebCrypto
  today and is the most widely interoperable JWT algorithm. WebCrypto's ECDSA
  output is already the raw `r‖s` form JOSE expects, so no DER juggling.
- **Why `did:jwk`?** It needs no resolver, registry, or network — the key
  travels inside the credential, which keeps verification fully offline.

## Possible next steps

- **`did:web`** issuer so a credential maps to a real domain you control.
- **Selective disclosure** (SD-JWT) to reveal only chosen fields.
- **Revocation** via a status list.
- **Sign uploaded files** (PDF/DOCX) by hashing raw bytes, not just Docs.
- **Anchor** the digest to a timestamping authority or ledger for proof-of-time.

## Security

Your private key is stored unencrypted in `chrome.storage.local`, readable by
anyone with access to your browser profile. Treat it like a browser-resident
key, not an HSM. For higher assurance, move signing to a backend or cloud KMS.
