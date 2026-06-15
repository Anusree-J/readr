// content.js — injects a small floating "Sign" affordance into Google Docs so
// you can issue a credential without opening the popup. All crypto and network
// work happens in the background service worker; this file is just UI glue.

(function () {
  if (window.__docSignerInjected) return;
  window.__docSignerInjected = true;

  const COLORS = { accent: "#5b8def", ok: "#3fb950", bad: "#f85149", surface: "#1a2029", text: "#e6edf3", border: "#2d3744" };

  // Floating action button -------------------------------------------------
  const fab = document.createElement("button");
  fab.textContent = "🔏 Sign";
  Object.assign(fab.style, {
    position: "fixed", right: "20px", bottom: "20px", zIndex: 2147483647,
    background: COLORS.accent, color: "#fff", border: "none", borderRadius: "22px",
    padding: "10px 16px", fontSize: "13px", fontWeight: "600", cursor: "pointer",
    boxShadow: "0 4px 14px rgba(0,0,0,.35)", fontFamily: "system-ui, sans-serif",
  });
  fab.title = "Create a verifiable credential for this document";
  document.documentElement.appendChild(fab);

  fab.addEventListener("click", async () => {
    fab.disabled = true;
    fab.textContent = "Signing…";
    try {
      const res = await chrome.runtime.sendMessage({
        type: "SIGN_DOC",
        docUrl: location.href,
        title: document.title.replace(/ - Google Docs$/, ""),
      });
      if (!res?.ok) throw new Error(res?.error || "Signing failed.");
      showPanel(res);
    } catch (err) {
      toast("✕ " + err.message, COLORS.bad);
    } finally {
      fab.disabled = false;
      fab.textContent = "🔏 Sign";
    }
  });

  // Result panel -----------------------------------------------------------
  function showPanel(res) {
    document.getElementById("__docSignerPanel")?.remove();
    const panel = document.createElement("div");
    panel.id = "__docSignerPanel";
    Object.assign(panel.style, {
      position: "fixed", right: "20px", bottom: "70px", zIndex: 2147483647,
      width: "340px", background: COLORS.surface, color: COLORS.text,
      border: "1px solid " + COLORS.border, borderRadius: "12px", padding: "14px",
      boxShadow: "0 8px 28px rgba(0,0,0,.45)", fontFamily: "system-ui, sans-serif", fontSize: "13px",
    });
    panel.innerHTML =
      `<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
         <strong style="color:${COLORS.ok}">✓ Credential signed</strong>
         <span id="__dsClose" style="cursor:pointer;color:${COLORS.text};opacity:.6">✕</span>
       </div>
       <div style="font-size:11px;opacity:.7;margin-bottom:8px;word-break:break-all">
         SHA-256 ${res.hashHex.slice(0, 24)}…
       </div>
       <textarea readonly style="width:100%;height:88px;background:#0f1419;color:${COLORS.text};
         border:1px solid ${COLORS.border};border-radius:8px;padding:8px;font-family:ui-monospace,monospace;
         font-size:11px;word-break:break-all;box-sizing:border-box">${res.jwt}</textarea>
       <div style="display:flex;gap:8px;margin-top:8px">
         <button id="__dsCopy" style="flex:1;background:#232b36;color:${COLORS.text};border:1px solid ${COLORS.border};border-radius:8px;padding:7px;cursor:pointer">Copy</button>
         <button id="__dsDl" style="flex:1;background:#232b36;color:${COLORS.text};border:1px solid ${COLORS.border};border-radius:8px;padding:7px;cursor:pointer">Download</button>
       </div>`;
    document.documentElement.appendChild(panel);

    panel.querySelector("#__dsClose").onclick = () => panel.remove();
    panel.querySelector("#__dsCopy").onclick = async (e) => {
      await navigator.clipboard.writeText(res.jwt);
      e.target.textContent = "Copied!";
      setTimeout(() => (e.target.textContent = "Copy"), 1200);
    };
    panel.querySelector("#__dsDl").onclick = () => {
      const name = document.title.replace(/ - Google Docs$/, "").replace(/[^\w.-]+/g, "_") || "document";
      const blob = new Blob([res.jwt], { type: "application/jwt" });
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = name + ".vc.jwt";
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    };
  }

  // Transient toast --------------------------------------------------------
  function toast(text, color) {
    const t = document.createElement("div");
    t.textContent = text;
    Object.assign(t.style, {
      position: "fixed", right: "20px", bottom: "70px", zIndex: 2147483647,
      background: COLORS.surface, color: color || COLORS.text, border: "1px solid " + COLORS.border,
      borderRadius: "8px", padding: "10px 14px", fontSize: "13px", maxWidth: "320px",
      fontFamily: "system-ui, sans-serif", boxShadow: "0 4px 14px rgba(0,0,0,.4)",
    });
    document.documentElement.appendChild(t);
    setTimeout(() => t.remove(), 5000);
  }
})();
