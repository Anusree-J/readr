// options.js — configure and publish to a DeDi directory.
const $ = (id) => document.getElementById(id);
const send = (msg) => chrome.runtime.sendMessage(msg);

const FIELDS = ["issuerName", "baseUrl", "namespaceId", "registryName", "apiKey", "addRecordPath", "lookupPath"];

async function load() {
  const id = await send({ type: "GET_IDENTITY" });
  if (id?.ok) $("didOut").value = id.did;

  const { config } = await send({ type: "GET_DEDI" });
  for (const f of FIELDS) if (config[f] != null) $(f).value = config[f];
  if (config.published) renderPublished(config.published);
}

function collect() {
  const patch = {};
  for (const f of FIELDS) patch[f] = $(f).value.trim();
  return patch;
}

$("saveBtn").addEventListener("click", async () => {
  await send({ type: "SET_DEDI", patch: collect() });
  show("ok", "Settings saved.");
});

$("publishBtn").addEventListener("click", async () => {
  const patch = collect();
  if (!patch.baseUrl || !patch.namespaceId || !patch.registryName) {
    return show("bad", "Fill in the base URL, namespace, and registry first.");
  }
  await send({ type: "SET_DEDI", patch });

  // Ask for permission to talk to this specific directory origin (the manifest
  // only declares optional access, so nothing is granted until the user agrees).
  let origin;
  try {
    origin = new URL(patch.baseUrl).origin + "/*";
  } catch {
    return show("bad", "That base URL is not valid.");
  }
  const granted = await chrome.permissions.request({ origins: [origin] });
  if (!granted) return show("bad", "Permission to reach " + origin + " was denied.");

  show("busy", "Publishing your public key to the directory…");
  const res = await send({ type: "PUBLISH_DEDI" });
  if (!res?.ok) return show("bad", "✕ " + res.error);

  show("ok", "✓ Public key published. New credentials will point verifiers to this record.");
  renderPublished(res.published);
});

function renderPublished(p) {
  $("publishedBox").hidden = false;
  const dl = $("publishedSummary");
  dl.innerHTML = "";
  for (const [k, v] of Object.entries({
    Record: p.recordName,
    "Lookup URL": p.lookupUrl,
    Published: new Date(p.publishedAt).toLocaleString(),
  })) {
    const dt = document.createElement("dt");
    dt.textContent = k;
    const dd = document.createElement("dd");
    dd.textContent = v;
    dl.append(dt, dd);
  }
  $("openLookup").href = p.lookupUrl;
  $("copyLookup").onclick = async () => {
    await navigator.clipboard.writeText(p.lookupUrl);
    $("copyLookup").textContent = "Copied!";
    setTimeout(() => ($("copyLookup").textContent = "Copy lookup URL"), 1200);
  };
}

function show(kind, text) {
  const el = $("status");
  el.className = "status " + kind;
  el.textContent = text;
  el.hidden = false;
}

load();
