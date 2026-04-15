import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "#0a0a0f",
        panel: "#111118",
        panel2: "#17171f",
        border: "#24242f",
        text: "#eaeaf1",
        muted: "#8a8a99",
        accent: "#ff4d88",
        accent2: "#7c5cff",
        ok: "#22c55e",
        warn: "#f59e0b",
        bad: "#ef4444",
      },
      fontFamily: {
        mono: ["ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
      },
    },
  },
  plugins: [],
};
export default config;
