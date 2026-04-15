const ROI_COLOR: Record<string, string> = {
  reward: "#ff4d88",
  emotion: "#f59e0b",
  attention: "#7c5cff",
  language: "#22d3ee",
  visual: "#22c55e",
};

const ROI_ORDER = ["reward", "emotion", "attention", "language", "visual"];

export default function ROIBars({ data }: { data: Record<string, number> }) {
  return (
    <div className="space-y-3">
      {ROI_ORDER.map((k) => {
        const v = data[k] ?? 0;
        return (
          <div key={k}>
            <div className="flex justify-between text-xs text-muted mb-1">
              <span className="text-text capitalize">{k}</span>
              <span className="font-mono">{v.toFixed(2)}</span>
            </div>
            <div className="h-2 bg-panel2 rounded-full overflow-hidden">
              <div
                className="h-full rounded-full"
                style={{
                  width: `${Math.max(0, Math.min(100, v * 100))}%`,
                  background: ROI_COLOR[k] ?? "#7c5cff",
                }}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}
