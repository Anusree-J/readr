"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import clsx from "clsx";
import { scoreFile, scoreText } from "@/lib/api";

type Tab = "text" | "image" | "ui" | "video";

export default function Home() {
  const [tab, setTab] = useState<Tab>("text");
  const [text, setText] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();

  const tabs: { id: Tab; label: string; accept: string; hint: string }[] = [
    { id: "text", label: "Tweet", accept: "", hint: "Paste tweet body." },
    { id: "image", label: "Image", accept: "image/*", hint: "Any image." },
    { id: "ui", label: "UI", accept: "image/*", hint: "UI/UX screenshot." },
    { id: "video", label: "Reel", accept: "video/mp4,video/quicktime", hint: "Short vertical video." },
  ];
  const current = tabs.find((t) => t.id === tab)!;

  async function submit() {
    setError(null);
    setLoading(true);
    try {
      const res =
        tab === "text"
          ? await scoreText(text)
          : await scoreFile(tab, file as File);
      router.push(`/score/${res.id}`);
    } catch (e) {
      setError(String(e));
      setLoading(false);
    }
  }

  const canSubmit =
    !loading && (tab === "text" ? text.trim().length > 0 : !!file);

  return (
    <div className="space-y-6">
      <section className="space-y-2">
        <h1 className="text-3xl font-semibold tracking-tight">
          Score virality before you post.
        </h1>
        <p className="text-muted max-w-2xl">
          Feeds your content through Meta&apos;s <span className="text-text">TRIBE v2</span>{" "}
          brain-response model, maps predicted fMRI activity to a 0–100 virality
          score, and suggests cuts. The scoring head improves itself overnight
          via a Karpathy-style autoresearch loop.
        </p>
      </section>

      <div className="card space-y-5">
        <div className="flex gap-2">
          {tabs.map((t) => (
            <button
              key={t.id}
              onClick={() => {
                setTab(t.id);
                setError(null);
              }}
              className={clsx("tab", tab === t.id ? "tab-active" : "tab-inactive")}
            >
              {t.label}
            </button>
          ))}
        </div>

        {tab === "text" ? (
          <textarea
            className="w-full bg-panel2 border border-border rounded-md p-3 h-40 font-mono text-sm focus:outline-none focus:border-accent2"
            placeholder="so meta just open-sourced a model that simulates how the human brain reacts to a video…"
            value={text}
            onChange={(e) => setText(e.target.value)}
          />
        ) : (
          <label className="block w-full border-2 border-dashed border-border rounded-md p-8 text-center cursor-pointer hover:border-accent2 transition">
            <input
              type="file"
              accept={current.accept}
              className="hidden"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            />
            {file ? (
              <div>
                <div className="text-sm">{file.name}</div>
                <div className="text-xs text-muted">
                  {(file.size / 1024).toFixed(1)} KB · click to change
                </div>
              </div>
            ) : (
              <div>
                <div className="text-sm">Click or drop a {current.label.toLowerCase()}</div>
                <div className="text-xs text-muted mt-1">{current.hint}</div>
              </div>
            )}
          </label>
        )}

        <div className="flex items-center justify-between">
          <div className="text-xs text-muted">{current.hint}</div>
          <button
            className="btn-primary"
            onClick={submit}
            disabled={!canSubmit}
          >
            {loading ? "Running TRIBE v2…" : "Predict virality"}
          </button>
        </div>

        {error && (
          <div className="text-bad text-sm font-mono whitespace-pre-wrap">{error}</div>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
        <div className="card">
          <div className="label">Model</div>
          <div className="mt-1">TRIBE v2 (Meta FAIR)</div>
          <div className="text-muted text-xs mt-1">
            fMRI foundation model · 720 subjects · 1,115 hours
          </div>
        </div>
        <div className="card">
          <div className="label">Scoring</div>
          <div className="mt-1">5 ROI head → 0–100 score</div>
          <div className="text-muted text-xs mt-1">
            reward · emotion · attention · language · visual
          </div>
        </div>
        <div className="card">
          <div className="label">Autoresearch</div>
          <div className="mt-1">Claude edits <span className="kbd">score.py</span></div>
          <div className="text-muted text-xs mt-1">
            Metric: Spearman vs log-views on held-out split
          </div>
        </div>
      </div>
    </div>
  );
}
