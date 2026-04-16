"use client";
import { useState } from "react";
import Link from "next/link";
import clsx from "clsx";
import {
  compareText,
  compareUpload,
  CompareResponse,
  ScoreResponse,
} from "@/lib/api";

type Mode = "text" | "image" | "ui" | "video";

export default function Compare() {
  const [mode, setMode] = useState<Mode>("text");
  const [variants, setVariants] = useState<string[]>(["", ""]);
  const [files, setFiles] = useState<(File | null)[]>([null, null]);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [res, setRes] = useState<CompareResponse | null>(null);

  function addSlot() {
    if (mode === "text") setVariants((v) => [...v, ""]);
    else setFiles((f) => [...f, null]);
  }
  function removeSlot(i: number) {
    if (mode === "text") setVariants((v) => v.filter((_, j) => j !== i));
    else setFiles((f) => f.filter((_, j) => j !== i));
  }

  async function submit() {
    setErr(null);
    setRes(null);
    setLoading(true);
    try {
      if (mode === "text") {
        const vs = variants.map((v) => v.trim()).filter(Boolean);
        if (vs.length < 2) throw new Error("need at least 2 non-empty variants");
        setRes(await compareText(vs));
      } else {
        const fs = files.filter((f): f is File => !!f);
        if (fs.length < 2) throw new Error("need at least 2 files");
        setRes(await compareUpload(mode, fs));
      }
    } catch (e) {
      setErr(String(e));
    } finally {
      setLoading(false);
    }
  }

  const count = mode === "text" ? variants.length : files.length;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">A/B compare drafts</h1>
        <p className="text-muted text-sm mt-1 max-w-2xl">
          Drop 2+ variations of the same piece of content. Each goes through
          TRIBE v2, the scoring head ranks them, and the winner gets flagged.
          The actual creator workflow from the @fuckgrowth tweet.
        </p>
      </div>

      <div className="card space-y-5">
        <div className="flex gap-2">
          {(["text", "image", "ui", "video"] as Mode[]).map((m) => (
            <button
              key={m}
              onClick={() => {
                setMode(m);
                setRes(null);
                setErr(null);
                if (m === "text") setVariants(["", ""]);
                else setFiles([null, null]);
              }}
              className={clsx("tab capitalize", mode === m ? "tab-active" : "tab-inactive")}
            >
              {m === "video" ? "Reel" : m}
            </button>
          ))}
        </div>

        <div className="space-y-3">
          {mode === "text"
            ? variants.map((v, i) => (
                <div key={i} className="flex gap-2 items-start">
                  <div className="text-xs text-muted mt-3 w-6 text-right">#{i + 1}</div>
                  <textarea
                    className="flex-1 bg-panel2 border border-border rounded px-3 py-2 h-20 text-sm font-mono focus:outline-none focus:border-accent2"
                    placeholder={`Variant ${i + 1} — e.g. a tweet draft`}
                    value={v}
                    onChange={(e) =>
                      setVariants((vs) => vs.map((x, j) => (j === i ? e.target.value : x)))
                    }
                  />
                  {count > 2 && (
                    <button
                      className="btn-ghost text-xs"
                      onClick={() => removeSlot(i)}
                      type="button"
                    >
                      ×
                    </button>
                  )}
                </div>
              ))
            : files.map((f, i) => (
                <div key={i} className="flex gap-2 items-center">
                  <div className="text-xs text-muted w-6 text-right">#{i + 1}</div>
                  <label className="flex-1 border border-dashed border-border rounded-md px-3 py-3 text-sm cursor-pointer hover:border-accent2 transition">
                    <input
                      type="file"
                      className="hidden"
                      accept={mode === "video" ? "video/*" : "image/*"}
                      onChange={(e) =>
                        setFiles((fs) => fs.map((x, j) => (j === i ? e.target.files?.[0] ?? null : x)))
                      }
                    />
                    {f ? (
                      <span>{f.name} <span className="text-muted">({(f.size / 1024).toFixed(0)} KB)</span></span>
                    ) : (
                      <span className="text-muted">click to pick a {mode}</span>
                    )}
                  </label>
                  {count > 2 && (
                    <button
                      className="btn-ghost text-xs"
                      onClick={() => removeSlot(i)}
                      type="button"
                    >
                      ×
                    </button>
                  )}
                </div>
              ))}
        </div>

        <div className="flex items-center justify-between">
          <button className="btn-ghost text-xs" onClick={addSlot}>+ add variant</button>
          <button className="btn-primary" onClick={submit} disabled={loading}>
            {loading ? "Scoring all variants…" : "Rank variants"}
          </button>
        </div>

        {err && (
          <div className="text-bad text-sm font-mono whitespace-pre-wrap">{err}</div>
        )}
      </div>

      {res && <Ranked res={res} />}
    </div>
  );
}

function Ranked({ res }: { res: CompareResponse }) {
  return (
    <div className="card space-y-3">
      <div className="flex items-center justify-between">
        <div className="label">Ranked results</div>
        <Link
          className="text-xs text-accent hover:underline"
          href={`/score/${res.winner_id}`}
        >
          open winner →
        </Link>
      </div>
      <div className="space-y-2">
        {res.results.map((r, i) => (
          <RankedRow key={r.id} r={r} winner={i === 0} />
        ))}
      </div>
    </div>
  );
}

function RankedRow({ r, winner }: { r: ScoreResponse; winner: boolean }) {
  const v = r.predicted_views;
  return (
    <Link
      href={`/score/${r.id}`}
      className={clsx(
        "flex items-center gap-4 rounded-lg p-3 border transition",
        winner
          ? "bg-accent/10 border-accent"
          : "bg-panel2 border-border hover:border-accent2",
      )}
    >
      <div
        className={clsx(
          "w-10 h-10 rounded-full flex items-center justify-center text-sm font-semibold",
          winner ? "bg-accent text-white" : "bg-bg text-text",
        )}
      >
        {winner ? "★" : `#${r.rank}`}
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-3">
          <div className="text-lg font-semibold">{r.score.toFixed(1)}</div>
          {v && v.n > 0 && (
            <div className="text-xs text-muted">
              ≈ <span className="text-text font-mono">{humanInt(v.mid)}</span> views
              <span className="text-muted">
                {" "}(band {humanInt(v.low)}–{humanInt(v.high)})
              </span>
            </div>
          )}
        </div>
        <div className="text-xs text-muted truncate mt-0.5">
          {r.input_preview ?? r.suggested_edits[0] ?? r.id}
        </div>
      </div>
      <div className="text-xs text-muted font-mono whitespace-nowrap hidden md:block">
        {r.hotspots.length} 🔥 · {r.dead_zones.length} 💤
      </div>
    </Link>
  );
}

function humanInt(n: number) {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return `${Math.round(n)}`;
}
