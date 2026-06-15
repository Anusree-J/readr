// background.js — the service worker.
//
// Responsibilities:
//   1. Own the signing keypair (generate once, persist in chrome.storage.local).
//   2. Fetch the current Google Doc's text via Docs' own export endpoint,
//      using the user's existing session cookies (no OAuth required).
//   3. Build a W3C Verifiable Credential and sign it into a VC-JWT.

import {
  generateKeyPairJwk,
  importPrivateKey,
  didJwkFromPublicJwk,
  toPublicJwk,
  signCompactJws,
  sha256Hex,
  b64uEncode,
} from "./crypto.js";

const KEY_STORAGE = "docsigner.key.v1";
const DEDI_STORAGE = "docsigner.dedi.v1";

// DeDi (Decentralized Directory — https://dedi.global) lets an organisation
// publish public keys, membership lists, etc. as records under a namespace, so
// they can be resolved and trusted by anyone. We host the issuer's public key
// there so a credential's anonymous did:jwk can be bound to a named directory
// entry. Endpoint templates are configurable because paths differ per instance.
const DEDI_DEFAULTS = {
  enabled: false,
  baseUrl: "https://dedi.global",
  apiKey: "",
  namespaceId: "",
  registryName: "docsigner-keys",
  issuerName: "",
  // {placeholders} are filled from the config at call time.
  addRecordPath: "/dedi/{namespaceId}/{registryName}/add-record",
  lookupPath: "/dedi/lookup/{namespaceId}/{registryName}/{recordName}",
  published: null, // { recordName, lookupUrl, publishedAt }
};

// ---------------------------------------------------------------------------
// Key lifecycle
// ---------------------------------------------------------------------------

async function getStoredKey() {
  const out = await chrome.storage.local.get(KEY_STORAGE);
  return out[KEY_STORAGE] || null;
}

async function getOrCreateKey() {
  let stored = await getStoredKey();
  if (!stored) {
    const { privateJwk, publicJwk } = await generateKeyPairJwk();
    stored = {
      privateJwk,
      publicJwk: toPublicJwk(publicJwk),
      did: didJwkFromPublicJwk(publicJwk),
      createdAt: new Date().toISOString(),
    };
    await chrome.storage.local.set({ [KEY_STORAGE]: stored });
  }
  return stored;
}

async function resetKey() {
  await chrome.storage.local.remove(KEY_STORAGE);
  return getOrCreateKey();
}

// ---------------------------------------------------------------------------
// DeDi directory hosting
// ---------------------------------------------------------------------------

async function getDediConfig() {
  const out = await chrome.storage.local.get(DEDI_STORAGE);
  return { ...DEDI_DEFAULTS, ...(out[DEDI_STORAGE] || {}) };
}

async function setDediConfig(patch) {
  const next = { ...(await getDediConfig()), ...patch };
  await chrome.storage.local.set({ [DEDI_STORAGE]: next });
  return next;
}

function fillTemplate(tpl, vars) {
  return tpl.replace(/\{(\w+)\}/g, (_, k) => encodeURIComponent(vars[k] ?? ""));
}

function dediHeaders(cfg) {
  const h = { "Content-Type": "application/json" };
  if (cfg.apiKey) h["Authorization"] = "Bearer " + cfg.apiKey;
  return h;
}

// Publish the issuer's public key as a DeDi record and remember its lookup URL.
async function publishKeyToDedi() {
  const cfg = await getDediConfig();
  const key = await getOrCreateKey();
  if (!cfg.baseUrl || !cfg.namespaceId || !cfg.registryName) {
    throw new Error("Set the DeDi base URL, namespace, and registry first.");
  }

  const base = cfg.baseUrl.replace(/\/+$/, "");
  const recordName = cfg.published?.recordName || "key-" + key.did.slice(-12);
  const lookupUrl = base + fillTemplate(cfg.lookupPath, { ...cfg, recordName });

  // The record carries everything a verifier needs to trust this key.
  const body = {
    record_name: recordName,
    description: `Document-signing public key for ${cfg.issuerName || "issuer"}`,
    details: {
      did: key.did,
      name: cfg.issuerName || undefined,
      type: "JsonWebKey",
      alg: "ES256",
      kid: key.did + "#0",
      publicKeyJwk: key.publicJwk,
    },
  };

  const url = base + fillTemplate(cfg.addRecordPath, { ...cfg, recordName });
  const res = await fetch(url, { method: "POST", headers: dediHeaders(cfg), body: JSON.stringify(body) });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`DeDi rejected the record (HTTP ${res.status}). ${text.slice(0, 200)}`);
  }

  const published = { recordName, lookupUrl, publishedAt: new Date().toISOString() };
  await setDediConfig({ enabled: true, published });
  return published;
}

// Fetch a published record and return its public key JWK (run from the worker
// so the user's granted host permission applies and CORS is a non-issue).
async function resolveDedi(lookupUrl) {
  const res = await fetch(lookupUrl, { headers: { Accept: "application/json" } });
  if (!res.ok) throw new Error(`Directory lookup failed (HTTP ${res.status}).`);
  const data = await res.json();
  // Be liberal about where the key sits in the response envelope.
  const details = data?.details || data?.record?.details || data?.data?.details || data;
  const publicKeyJwk = details?.publicKeyJwk || details?.publicJwk || data?.publicKeyJwk;
  if (!publicKeyJwk) throw new Error("No public key found in the directory record.");
  return { publicKeyJwk, did: details?.did, name: details?.name, raw: data };
}

// ---------------------------------------------------------------------------
// Reading a Google Doc
// ---------------------------------------------------------------------------

export function docIdFromUrl(url) {
  const m = /\/document\/d\/([a-zA-Z0-9_-]+)/.exec(url || "");
  return m ? m[1] : null;
}

// Pull the plain-text export of a doc. Cookies are attached automatically
// because docs.google.com is in host_permissions, so this works for any doc
// the signed-in user can already open.
async function fetchDocText(docId) {
  const url = `https://docs.google.com/document/d/${docId}/export?format=txt`;
  const res = await fetch(url, { credentials: "include" });
  if (!res.ok) {
    throw new Error(
      `Could not read the document (HTTP ${res.status}). Make sure you're signed in and have access.`
    );
  }
  const ct = res.headers.get("content-type") || "";
  const body = await res.text();
  // A redirect to the login/consent page comes back as HTML, not text/plain.
  if (!ct.includes("text/plain") && /<html/i.test(body)) {
    throw new Error("Got a sign-in page instead of the document. Open the doc and sign in, then retry.");
  }
  return body;
}

// ---------------------------------------------------------------------------
// Credential construction
// ---------------------------------------------------------------------------

async function buildAndSignCredential({ docId, docUrl, title, text, embedContent }) {
  const key = await getOrCreateKey();
  const privateKey = await importPrivateKey(key.privateJwk);
  const dedi = await getDediConfig();
  const hosted = dedi.enabled && dedi.published ? dedi : null;

  const hashHex = await sha256Hex(text);
  const now = new Date();
  const nowIso = now.toISOString();
  const nowSec = Math.floor(now.getTime() / 1000);
  const credentialId = "urn:uuid:" + crypto.randomUUID();
  const subjectId = `https://docs.google.com/document/d/${docId}`;

  const credentialSubject = {
    id: subjectId,
    type: "DigitalDocument",
    name: title || "Untitled document",
    url: docUrl || subjectId,
    encodingFormat: "text/plain",
    contentLength: text.length,
    // The integrity anchor: re-export the doc, hash the text, compare.
    digestSRI: "sha256-" + hashHex,
    sha256: hashHex,
  };
  if (embedContent) {
    // Self-contained verification: the exact signed bytes travel with the VC.
    credentialSubject.encodedContent = "base64url," + b64uEncode(text);
  }

  // The issuer is the did:jwk; when a directory record exists we name the issuer
  // and attach a resolution hint so verifiers can bind the key to that record.
  const issuer = hosted
    ? {
        id: key.did,
        name: hosted.issuerName || undefined,
        directory: {
          type: "DeDiDirectory",
          lookupUrl: hosted.published.lookupUrl,
          namespace: hosted.namespaceId,
          registry: hosted.registryName,
          record: hosted.published.recordName,
        },
      }
    : key.did;

  // W3C Verifiable Credentials Data Model 2.0 payload.
  const vc = {
    "@context": ["https://www.w3.org/ns/credentials/v2"],
    type: ["VerifiableCredential", "VerifiableDocumentCredential"],
    issuer,
    validFrom: nowIso,
    credentialSubject,
  };

  // JOSE/JWT envelope (VC secured with JOSE — "Securing VCs using JOSE & COSE").
  const header = {
    alg: "ES256",
    typ: "vc+jwt",
    kid: hosted ? hosted.published.lookupUrl : key.did + "#0",
  };
  const payload = {
    iss: key.did,
    sub: subjectId,
    nbf: nowSec,
    iat: nowSec,
    jti: credentialId,
    vc,
  };

  const jwt = await signCompactJws(header, payload, privateKey);
  return { jwt, vc, header, payload, hashHex, signedAt: nowIso, did: key.did };
}

// ---------------------------------------------------------------------------
// Message routing
// ---------------------------------------------------------------------------

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  (async () => {
    try {
      switch (msg?.type) {
        case "GET_IDENTITY": {
          const key = await getOrCreateKey();
          sendResponse({
            ok: true,
            did: key.did,
            publicJwk: key.publicJwk,
            createdAt: key.createdAt,
          });
          break;
        }
        case "RESET_KEY": {
          const key = await resetKey();
          sendResponse({ ok: true, did: key.did, publicJwk: key.publicJwk, createdAt: key.createdAt });
          break;
        }
        case "GET_DEDI": {
          sendResponse({ ok: true, config: await getDediConfig() });
          break;
        }
        case "SET_DEDI": {
          sendResponse({ ok: true, config: await setDediConfig(msg.patch || {}) });
          break;
        }
        case "PUBLISH_DEDI": {
          const published = await publishKeyToDedi();
          sendResponse({ ok: true, published });
          break;
        }
        case "RESOLVE_DEDI": {
          const result = await resolveDedi(msg.lookupUrl);
          sendResponse({ ok: true, ...result });
          break;
        }
        case "SIGN_DOC": {
          const docId = msg.docId || docIdFromUrl(msg.docUrl);
          if (!docId) throw new Error("That tab is not a Google Doc.");
          const text = await fetchDocText(docId);
          if (!text.trim()) throw new Error("The document appears to be empty.");
          const result = await buildAndSignCredential({
            docId,
            docUrl: msg.docUrl,
            title: msg.title,
            text,
            embedContent: !!msg.embedContent,
          });
          sendResponse({ ok: true, ...result });
          break;
        }
        default:
          sendResponse({ ok: false, error: "Unknown message type: " + msg?.type });
      }
    } catch (err) {
      sendResponse({ ok: false, error: err?.message || String(err) });
    }
  })();
  return true; // keep the message channel open for the async response
});
