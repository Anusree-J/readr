"use client";
import {
  Area,
  AreaChart,
  ReferenceArea,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

type Props = {
  timeline: number[];
  samplingHz: number;
  deadZones: [number, number][];
  hotspots: [number, number][];
};

export default function EngagementTimeline({
  timeline,
  samplingHz,
  deadZones,
  hotspots,
}: Props) {
  const data = timeline.map((y, i) => ({ t: i / samplingHz, y }));
  return (
    <div className="h-56">
      <ResponsiveContainer>
        <AreaChart data={data} margin={{ top: 6, right: 8, left: 0, bottom: 4 }}>
          <defs>
            <linearGradient id="eng" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#7c5cff" stopOpacity={0.8} />
              <stop offset="95%" stopColor="#7c5cff" stopOpacity={0.05} />
            </linearGradient>
          </defs>
          <XAxis
            dataKey="t"
            tickFormatter={(v) => `${v.toFixed(1)}s`}
            stroke="#8a8a99"
            fontSize={11}
          />
          <YAxis domain={[0, 1]} stroke="#8a8a99" fontSize={11} />
          <Tooltip
            contentStyle={{
              background: "#17171f",
              border: "1px solid #24242f",
              fontSize: 12,
            }}
            formatter={(v: number) => [v.toFixed(2), "engagement"]}
            labelFormatter={(l) => `${(+l).toFixed(2)} s`}
          />
          {deadZones.map(([s, e], i) => (
            <ReferenceArea
              key={`d${i}`}
              x1={s}
              x2={e}
              fill="#ef4444"
              fillOpacity={0.15}
            />
          ))}
          {hotspots.map(([s, e], i) => (
            <ReferenceArea
              key={`h${i}`}
              x1={s}
              x2={e}
              fill="#22c55e"
              fillOpacity={0.18}
            />
          ))}
          <Area
            type="monotone"
            dataKey="y"
            stroke="#7c5cff"
            fill="url(#eng)"
            strokeWidth={2}
            isAnimationActive={false}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
