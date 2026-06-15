// verify.js — controller for the standalone verifier page.
import { verifyCompactJws, sha256Hex, b64uDecodeToText } from "./crypto.js";

const $ = (id) => document.getElementById(id);

$("verifyBtn").addEventListener("click", runVerify);
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

  if (!jwt) return show(out, "bad", "Paste a VC-JWT first.");
  show(out, "busy", "Verifying signature…");

  try {
    const { valid, header, payload } = await verifyCompactJws(jwt);
    const subj = payload.vc?.credentialSubject || {};

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

    render(summary, {
      Document: subj.name || "—",
      "SHA-256 (signed)": subj.sha256 || "—",
      Issuer: payload.iss || "—",
      Algorithm: header.alg,
      "Issued at": payload.iat ? new Date(payload.iat * 1000).toLocaleString() : "—",
      "Embedded content": contentNote,
      Subject: subj.url || subj.id || "—",
    });
    summary.hidden = false;

    $("raw").textContent = JSON.stringify({ header, payload }, null, 2);
    $("raw").hidden = false;
    $("rawHeading").hidden = false;
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
