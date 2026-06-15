import assert from "node:assert";
import {
  generateKeyPairJwk, importPrivateKey, didJwkFromPublicJwk, publicJwkFromDidJwk,
  toPublicJwk, signCompactJws, verifyCompactJws, sha256Hex, b64uEncode, b64uDecodeToText,
} from "../src/crypto.js";

let pass = 0;
const ok = (n) => { console.log("  ✓", n); pass++; };

// base64url roundtrip
const s = "héllo — wörld 🔏";
assert.equal(b64uDecodeToText(b64uEncode(s)), s); ok("base64url roundtrips UTF-8");

// did:jwk roundtrip
const { privateJwk, publicJwk } = await generateKeyPairJwk();
const did = didJwkFromPublicJwk(publicJwk);
assert.ok(did.startsWith("did:jwk:")); 
assert.deepEqual(publicJwkFromDidJwk(did), toPublicJwk(publicJwk)); ok("did:jwk encodes & decodes the public key");

// sha256 known vector
assert.equal(await sha256Hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"); ok("sha256 matches known vector");

// sign a VC-JWT and verify it
const priv = await importPrivateKey(privateJwk);
const docText = "The quick brown fox.\nSigned content body.";
const hash = await sha256Hex(docText);
const header = { alg: "ES256", typ: "vc+jwt", kid: did + "#0" };
const payload = {
  iss: did, sub: "https://docs.google.com/document/d/ABC", iat: 1700000000, jti: "urn:uuid:x",
  vc: { "@context": ["https://www.w3.org/ns/credentials/v2"], type: ["VerifiableCredential"],
        issuer: did, credentialSubject: { id: "x", name: "Test doc", sha256: hash,
        encodedContent: "base64url," + b64uEncode(docText) } },
};
const jwt = await signCompactJws(header, payload, priv);
assert.equal(jwt.split(".").length, 3); ok("signs a compact 3-part VC-JWT");

const v = await verifyCompactJws(jwt);
assert.equal(v.valid, true); ok("verifies a genuine credential");
assert.equal(v.issuerDid, did); ok("recovers issuer DID from the credential");

// embedded content re-hash matches
const embedded = b64uDecodeToText(v.payload.vc.credentialSubject.encodedContent.slice("base64url,".length));
assert.equal(await sha256Hex(embedded), v.payload.vc.credentialSubject.sha256); ok("embedded content re-hashes to signed value");

// tamper detection: flip a payload claim
const [h, p, sig] = jwt.split(".");
const tampered = JSON.parse(b64uDecodeToText(p));
tampered.vc.credentialSubject.name = "Forged title";
const forgedPayloadB64 = b64uEncode(JSON.stringify(tampered));
const forged = `${h}.${forgedPayloadB64}.${sig}`;
const vf = await verifyCompactJws(forged);
assert.equal(vf.valid, false); ok("rejects a tampered credential");

// wrong key can't impersonate the DID (sig fails against embedded key)
const other = await generateKeyPairJwk();
const otherPriv = await importPrivateKey(other.privateJwk);
const impostor = await signCompactJws({ ...header }, payload, otherPriv); // payload still claims original did
assert.equal((await verifyCompactJws(impostor)).valid, false); ok("rejects a signature from a non-issuer key");

console.log(`\nAll ${pass} assertions passed.`);
