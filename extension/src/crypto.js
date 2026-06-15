// crypto.js — zero-dependency crypto primitives built on the WebCrypto API.
//
// Everything here is shared by the background service worker, the popup, and
// the standalone verifier page. We deliberately avoid any external library so
// the extension stays auditable and small.
//
// Algorithm choices:
//   - Signatures: ECDSA over P-256 with SHA-256  ==  JOSE "ES256"
//   - Issuer identity: did:jwk (the public JWK, base64url-encoded into a DID)
//   - Credential envelope: a compact JWS (VC-JWT)

const ES256 = { name: "ECDSA", namedCurve: "P-256" };
const ES256_SIGN = { name: "ECDSA", hash: { name: "SHA-256" } };

// ---------------------------------------------------------------------------
// Encoding helpers
// ---------------------------------------------------------------------------

export function bytesToText(bytes) {
  return new TextDecoder().decode(bytes);
}

export function textToBytes(text) {
  return new TextEncoder().encode(text);
}

// base64url (RFC 4648 §5, no padding) — accepts an ArrayBuffer, a Uint8Array,
// or a string (which is first UTF-8 encoded).
export function b64uEncode(input) {
  let bytes;
  if (typeof input === "string") bytes = textToBytes(input);
  else if (input instanceof ArrayBuffer) bytes = new Uint8Array(input);
  else bytes = input;

  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Returns a Uint8Array.
export function b64uDecodeToBytes(str) {
  const padded = str.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((str.length + 3) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function b64uDecodeToText(str) {
  return bytesToText(b64uDecodeToBytes(str));
}

export function b64uDecodeToJSON(str) {
  return JSON.parse(b64uDecodeToText(str));
}

// ---------------------------------------------------------------------------
// Hashing
// ---------------------------------------------------------------------------

export async function sha256Hex(input) {
  const bytes = typeof input === "string" ? textToBytes(input) : input;
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ---------------------------------------------------------------------------
// Keys & DIDs
// ---------------------------------------------------------------------------

// Generate an extractable ES256 keypair, returned as JWKs so we can persist
// them in chrome.storage (CryptoKey objects are not serializable there).
export async function generateKeyPairJwk() {
  const pair = await crypto.subtle.generateKey(ES256, true, ["sign", "verify"]);
  const privateJwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
  const publicJwk = await crypto.subtle.exportKey("jwk", pair.publicKey);
  return { privateJwk, publicJwk };
}

export async function importPrivateKey(privateJwk) {
  return crypto.subtle.importKey("jwk", privateJwk, ES256, false, ["sign"]);
}

export async function importPublicKey(publicJwk) {
  return crypto.subtle.importKey("jwk", publicJwk, ES256, false, ["verify"]);
}

// The minimal public JWK (no private material, no metadata) used inside the DID.
export function toPublicJwk(jwk) {
  return { crv: jwk.crv, kty: jwk.kty, x: jwk.x, y: jwk.y };
}

// did:jwk — https://github.com/quartzjer/did-jwk/blob/main/spec.md
export function didJwkFromPublicJwk(publicJwk) {
  return "did:jwk:" + b64uEncode(JSON.stringify(toPublicJwk(publicJwk)));
}

export function publicJwkFromDidJwk(did) {
  if (!did.startsWith("did:jwk:")) throw new Error("Not a did:jwk: " + did);
  return b64uDecodeToJSON(did.slice("did:jwk:".length));
}

// ---------------------------------------------------------------------------
// JWS / VC-JWT
// ---------------------------------------------------------------------------

// Sign a compact JWS. WebCrypto ECDSA already emits the raw r||s form that
// JOSE expects, so no DER unwrapping is needed.
export async function signCompactJws(header, payload, privateKey) {
  const signingInput = b64uEncode(JSON.stringify(header)) + "." + b64uEncode(JSON.stringify(payload));
  const sig = await crypto.subtle.sign(ES256_SIGN, privateKey, textToBytes(signingInput));
  return signingInput + "." + b64uEncode(sig);
}

// Verify a compact JWS using the public key embedded in its issuer did:jwk.
// Returns { valid, header, payload, issuerDid, publicJwk }.
export async function verifyCompactJws(compact) {
  const parts = compact.trim().split(".");
  if (parts.length !== 3) throw new Error("A VC-JWT has three dot-separated parts.");
  const [headerB64, payloadB64, sigB64] = parts;

  const header = b64uDecodeToJSON(headerB64);
  const payload = b64uDecodeToJSON(payloadB64);

  // Resolve the verifying key from the credential's own issuer DID.
  const issuerDid = payload.iss || (payload.vc && payload.vc.issuer);
  if (!issuerDid) throw new Error("Credential has no issuer.");
  const publicJwk = publicJwkFromDidJwk(issuerDid);

  const key = await importPublicKey(publicJwk);
  const signingInput = textToBytes(headerB64 + "." + payloadB64);
  const valid = await crypto.subtle.verify(ES256_SIGN, key, b64uDecodeToBytes(sigB64), signingInput);

  return { valid, header, payload, issuerDid, publicJwk };
}
