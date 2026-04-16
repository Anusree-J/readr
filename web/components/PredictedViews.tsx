import type { PredictedViews } from "@/lib/api";

function humanInt(n: number) {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return `${Math.round(n)}`;
}

export default function PredictedViewsCard({ v }: { v?: PredictedViews }) {
  if (!v || !v.n) return null;
  return (
    <div className="card">
      <div className="label">Predicted views</div>
      <div className="mt-1 flex items-baseline gap-2">
        <span className="text-3xl font-semibold">{humanInt(v.mid)}</span>
        <span className="text-muted text-xs">
          band {humanInt(v.low)}–{humanInt(v.high)} · n={v.n}
        </span>
      </div>
      <div className="text-[11px] text-muted mt-2">
        Isotonic regression from score → log-views on the labeled set. 80%
        band from residual quantiles.
      </div>
    </div>
  );
}
