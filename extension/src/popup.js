// popup.js — UI controller for the extension popup.
import {
  verifyCompactJws,
  sha256Hex,
  b64uDecodeToText,
} from "./crypto.js";

const $ = (id) => document.getElementById(id);
const send = (msg) => chrome.runtime.sendMessage(msg);

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------

document.querySelectorAll(".tab").forEach((tab) => {
  tab.addEventListener("click", () => activateTab(tab.dataset.tab));
});

function activateTab(name) {
  document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("is-active", t.dataset.tab === name));
  document.querySelectorAll(".panel").forEach((p) => p.classList.toggle("is-active", p.dataset.panel === name));
}

// ---------------------------------------------------------------------------
// Sign tab
// ---------------------------------------------------------------------------

let activeTab = null;

async function initSignTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  activeTab = tab;
  const info = $("docInfo");
  const isDoc = tab?.url && /^https:\/\/docs\.google\.com\/document\//.test(tab.url);

  if (isDoc) {
    info.classList.add("ready");
    info.innerHTML = `<strong>${escapeHtml(tab.title?.replace(/ - Google Docs$/, "") || "Google Doc")}</strong>` +
      `<span class="muted small">${escapeHtml(tab.url)}</span>`;
    $("signBtn").disabled = false;
  } else {
    info.textContent = "Open a Google Doc tab to sign it. (Current tab isn't a Google Doc.)";
    $("signBtn").disabled = true;
  }
}

$("signBtn").addEventListener("click", async () => {
  const btn = $("signBtn");
  const status = $("signStatus");
  btn.disabled = true;
  showStatus(status, "busy", "Reading the document and signing…");
  $("signResult").hidden = true;

  const res = await send({
    type: "SIGN_DOC",
    docUrl: activeTab.url,
    title: activeTab.title?.replace(/ - Google Docs$/, ""),
    embedContent: $("embedContent").checked,
  });

  btn.disabled = false;
  if (!res?.ok) {
    showStatus(status, "bad", "✕ " + (res?.error || "Signing failed."));
    return;
  }

  status.hidden = true;
  $("jwtOut").value = res.jwt;
  renderSummary($("summary"), {
    Document: res.payload.vc.credentialSubject.name,
    "SHA-256": short(res.hashHex),
    Issuer: short(res.did, 28),
    "Signed at": new Date(res.signedAt).toLocaleString(),
    Size: res.jwt.length + " chars",
  });
  $("signResult").hidden = false;
});

$("copyJwt").addEventListener("click", () => copy($("jwtOut").value, $("copyJwt"), "Copy"));
$("downloadJwt").addEventListener("click", () => {
  const name = (activeTab?.title?.replace(/ - Google Docs$/, "") || "document").replace(/[^\w.-]+/g, "_");
  download(`${name}.vc.jwt`, $("jwtOut").value);
});
$("verifyThis").addEventListener("click", () => {
  $("verifyIn").value = $("jwtOut").value;
  activateTab("verify");
  runVerify();
});

// ---------------------------------------------------------------------------
// Identity tab
// ---------------------------------------------------------------------------

let identity = null;

async function initIdentity() {
  identity = await send({ type: "GET_IDENTITY" });
  if (!identity?.ok) return;
  $("didOut").value = identity.did;
  $("keyCreated").textContent = "Key created " + new Date(identity.createdAt).toLocaleString();

  const { config } = await send({ type: "GET_DEDI" });
  if (config?.enabled && config.published) {
    $("dediStatus").textContent =
      `✓ Published to ${config.namespaceId}/${config.registryName}` +
      (config.issuerName ? ` as “${config.issuerName}”` : "");
    $("dediStatus").style.color = "var(--ok)";
  }
}

$("openOptions").addEventListener("click", () => chrome.runtime.openOptionsPage());

$("copyDid").addEventListener("click", () => copy(identity.did, $("copyDid"), "Copy DID"));
$("copyJwk").addEventListener("click", () =>
  copy(JSON.stringify(identity.publicJwk, null, 2), $("copyJwk"), "Copy public key (JWK)")
);
$("resetKey").addEventListener("click", async () => {
  if (!confirm("Create a new signing identity? Your current DID will be replaced.")) return;
  identity = await send({ type: "RESET_KEY" });
  $("didOut").value = identity.did;
  $("keyCreated").textContent = "Key created " + new Date(identity.createdAt).toLocaleString();
});

// ---------------------------------------------------------------------------
// Verify tab
// ---------------------------------------------------------------------------

$("verifyBtn").addEventListener("click", runVerify);

async function runVerify() {
  const out = $("verifyOut");
  const summary = $("verifySummary");
  const jwt = $("verifyIn").value.trim();
  summary.hidden = true;
  if (!jwt) {
    showStatus(out, "bad", "Paste a VC-JWT first.");
    return;
  }
  showStatus(out, "busy", "Verifying signature…");

  try {
    const { valid, payload } = await verifyCompactJws(jwt);
    const subj = payload.vc?.credentialSubject || {};

    // If the content is embedded, confirm it still hashes to the signed value.
    let contentNote = "not included in credential";
    if (subj.encodedContent?.startsWith("base64url,")) {
      const text = b64uDecodeToText(subj.encodedContent.slice("base64url,".length));
      const rehash = await sha256Hex(text);
      contentNote = rehash === subj.sha256 ? "✓ embedded content matches hash" : "✕ embedded content does NOT match hash";
    }

    if (valid) {
      showStatus(out, "ok", "✓ Signature is valid. The issuer's key signed this credential.");
    } else {
      showStatus(out, "bad", "✕ Signature is INVALID — do not trust this credential.");
    }

    const dir = payload.vc?.issuer?.directory;
    const issuerName = payload.vc?.issuer?.name;
    renderSummary(summary, {
      Document: subj.name || "—",
      "SHA-256": short(subj.sha256 || "—"),
      Issuer: (issuerName ? issuerName + " · " : "") + short(payload.iss || "—", 24),
      "Issued at": payload.iat ? new Date(payload.iat * 1000).toLocaleString() : "—",
      Content: contentNote,
      Directory: dir ? "hosted — open the full verifier to resolve" : "self-contained",
      Subject: subj.url || subj.id || "—",
    });
    summary.hidden = false;
  } catch (err) {
    showStatus(out, "bad", "✕ " + err.message);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function showStatus(el, kind, text) {
  el.className = "status " + kind;
  el.textContent = text;
  el.hidden = false;
}

function renderSummary(dl, pairs) {
  dl.innerHTML = "";
  for (const [k, v] of Object.entries(pairs)) {
    const dt = document.createElement("dt");
    dt.textContent = k;
    const dd = document.createElement("dd");
    dd.textContent = v;
    dl.append(dt, dd);
  }
}

function short(s, n = 18) {
  return s && s.length > n * 2 ? s.slice(0, n) + "…" + s.slice(-6) : s;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

async function copy(text, btn, label) {
  await navigator.clipboard.writeText(text);
  btn.textContent = "Copied!";
  setTimeout(() => (btn.textContent = label), 1200);
}

function download(filename, text) {
  const blob = new Blob([text], { type: "application/jwt" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

initSignTab();
initIdentity();
