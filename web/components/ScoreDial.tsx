export default function ScoreDial({ score }: { score: number }) {
  const clamped = Math.max(0, Math.min(100, score));
  const color =
    clamped >= 75 ? "#22c55e" : clamped >= 50 ? "#f59e0b" : "#ef4444";
  const circ = 2 * Math.PI * 46;
  const offset = circ * (1 - clamped / 100);
  return (
    <div className="flex items-center gap-4">
      <svg width="120" height="120" viewBox="0 0 120 120">
        <circle
          cx="60"
          cy="60"
          r="46"
          stroke="#24242f"
          strokeWidth="10"
          fill="none"
        />
        <circle
          cx="60"
          cy="60"
          r="46"
          stroke={color}
          strokeWidth="10"
          fill="none"
          strokeDasharray={circ}
          strokeDashoffset={offset}
          strokeLinecap="round"
          transform="rotate(-90 60 60)"
        />
        <text
          x="60"
          y="68"
          textAnchor="middle"
          fontSize="28"
          fontWeight={700}
          fill="#eaeaf1"
        >
          {Math.round(clamped)}
        </text>
      </svg>
      <div className="text-xs text-muted max-w-[140px]">
        <div className="text-text text-sm font-medium">Virality score</div>
        Predicted brain-engagement index, 0–100. Seed baseline ≈ 50.
      </div>
    </div>
  );
}
