// verify.js — controller for the standalone verifier page.
import {
  verifyCompactJws,
  sha256Hex,
  b64uDecodeToText,
  publicJwkFromDidJwk,
  publicJwkEqual,
} from "./crypto.js";

const $ = (id) => document.getElementById(id);
const send = (msg) => chrome.runtime.sendMessage(msg);

let currentDid = null; // issuer did:jwk of the last verified credential
let currentHint = null; // its DeDi directory hint, if any

// Pull a directory lookup URL out of a credential, if the issuer hosted one.
function dediHintFrom(header, payload) {
  const dir = payload.vc?.issuer?.directory;
  if (dir?.lookupUrl) return dir;
  if (typeof header.kid === "string" && /^https?:\/\//.test(header.kid)) {
    return { lookupUrl: header.kid };
  }
  return null;
}

$("verifyBtn").addEventListener("click", runVerify);
$("dediBtn").addEventListener("click", resolveIssuer);
$("loadFile").addEventListener("click", () => $("fileInput").click());
$("fileInput").addEventListener("change", async (e) => {
  const file = e.target.files[0];
  if (!file) return;
  $("verifyIn").value = (await file.text()).trim();
  runVerify();
});

async function runVerify() {
  const out = $("verifyOut");
  const summary = $("verifySummary");
  const jwt = $("verifyIn").value.trim();
  summary.hidden = true;
  $("raw").hidden = true;
  $("rawHeading").hidden = true;

  $("dediBox").hidden = true;
  $("dediOut").hidden = true;
  if (!jwt) return show(out, "bad", "Paste a VC-JWT first.");
  show(out, "busy", "Verifying signature…");

  try {
    const { valid, header, payload, issuerDid } = await verifyCompactJws(jwt);
    const subj = payload.vc?.credentialSubject || {};
    currentDid = issuerDid;
    currentHint = dediHintFrom(header, payload);

    let contentNote = "Not embedded in credential";
    if (subj.encodedContent?.startsWith("base64url,")) {
      const text = b64uDecodeToText(subj.encodedContent.slice("base64url,".length));
      const rehash = await sha256Hex(text);
      contentNote = rehash === subj.sha256
        ? "✓ Embedded content matches the signed hash"
        : "✕ Embedded content does NOT match the signed hash";
    }

    show(out, valid ? "ok" : "bad",
      valid
        ? "✓ Valid signature. This credential was signed by the holder of the issuer's private key and has not been altered."
        : "✕ INVALID signature. This credential is forged or was modified after signing — do not trust it.");

    const issuerName = payload.vc?.issuer?.name;
    render(summary, {
      Document: subj.name || "—",
      "SHA-256 (signed)": subj.sha256 || "—",
      Issuer: (issuerName ? issuerName + " · " : "") + (payload.iss || "—"),
      Algorithm: header.alg,
      "Issued at": payload.iat ? new Date(payload.iat * 1000).toLocaleString() : "—",
      "Embedded content": contentNote,
      Directory: currentHint ? currentHint.lookupUrl : "Not hosted (self-contained did:jwk)",
      Subject: subj.url || subj.id || "—",
    });
    summary.hidden = false;

    // Offer to bind the anonymous key to its directory record, when one exists.
    if (valid && currentHint) $("dediBox").hidden = false;

    $("raw").textContent = JSON.stringify({ header, payload }, null, 2);
    $("raw").hidden = false;
    $("rawHeading").hidden = false;
  } catch (err) {
    show(out, "bad", "✕ " + err.message);
  }
}

// Resolve the issuer's key from DeDi and confirm it matches the credential's key.
async function resolveIssuer() {
  const out = $("dediOut");
  if (!currentHint?.lookupUrl) return;
  try {
    const origin = new URL(currentHint.lookupUrl).origin + "/*";
    const granted = await chrome.permissions.request({ origins: [origin] });
    if (!granted) return show(out, "bad", "Permission to reach " + origin + " was denied.");

    show(out, "busy", "Looking up the issuer in the directory…");
    const res = await send({ type: "RESOLVE_DEDI", lookupUrl: currentHint.lookupUrl });
    if (!res?.ok) return show(out, "bad", "✕ " + res.error);

    const credentialKey = publicJwkFromDidJwk(currentDid);
    if (publicJwkEqual(res.publicKeyJwk, credentialKey)) {
      show(out, "ok",
        `✓ The signing key is published in the directory${res.name ? " under " + res.name : ""}. ` +
        "Issuer identity is directory-anchored.");
    } else {
      show(out, "bad",
        "✕ The directory record holds a DIFFERENT key than the one that signed this credential. Do not trust the claimed issuer.");
    }
  } catch (err) {
    show(out, "bad", "✕ " + err.message);
  }
}

function show(el, kind, text) {
  el.className = "status " + kind;
  el.textContent = text;
  el.hidden = false;
}

function render(dl, pairs) {
  dl.innerHTML = "";
  for (const [k, v] of Object.entries(pairs)) {
    const dt = document.createElement("dt");
    dt.textContent = k;
    const dd = document.createElement("dd");
    dd.textContent = v;
    dl.append(dt, dd);
  }
}
