"use client";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { Experiment } from "@/lib/api";

export default function SpearmanChart({ data }: { data: Experiment[] }) {
  const series = data
    .filter((e) => typeof e.spearman === "number")
    .map((e) => ({
      i: e.experiment,
      spearman: e.spearman!,
      best: e.best_so_far ?? e.spearman!,
    }));
  if (series.length === 0) {
    return (
      <div className="h-48 flex items-center justify-center text-muted text-sm">
        No experiments yet. Click &quot;Start run&quot;.
      </div>
    );
  }
  return (
    <div className="h-64">
      <ResponsiveContainer>
        <LineChart data={series} margin={{ top: 8, right: 16, left: 0, bottom: 4 }}>
          <CartesianGrid stroke="#24242f" strokeDasharray="3 3" />
          <XAxis dataKey="i" stroke="#8a8a99" fontSize={11} />
          <YAxis stroke="#8a8a99" fontSize={11} domain={[-1, 1]} />
          <Tooltip
            contentStyle={{
              background: "#17171f",
              border: "1px solid #24242f",
              fontSize: 12,
            }}
          />
          <Line
            type="monotone"
            dataKey="spearman"
            stroke="#7c5cff"
            strokeWidth={2}
            dot={{ r: 3 }}
            isAnimationActive={false}
          />
          <Line
            type="monotone"
            dataKey="best"
            stroke="#22c55e"
            strokeWidth={2}
            strokeDasharray="4 4"
            dot={false}
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
