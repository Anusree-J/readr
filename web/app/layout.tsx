import "./globals.css";
import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "CBT — Brain-Predicted Virality",
  description:
    "Score tweets, images, UI screenshots, and reels against a predicted-fMRI virality model. Autoresearch loop improves the scoring head.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="min-h-screen flex flex-col">
        <header className="border-b border-border">
          <div className="max-w-6xl mx-auto px-6 py-4 flex items-center justify-between">
            <Link href="/" className="flex items-center gap-2 font-semibold">
              <span className="text-accent">●</span> CBT
              <span className="text-muted text-sm font-normal">
                brain-predicted virality
              </span>
            </Link>
            <nav className="flex gap-6 text-sm">
              <Link href="/" className="hover:text-accent">
                Score
              </Link>
              <Link href="/compare" className="hover:text-accent">
                Compare
              </Link>
              <Link href="/autoresearch" className="hover:text-accent">
                Autoresearch
              </Link>
              <Link href="/about" className="hover:text-accent">
                About
              </Link>
            </nav>
          </div>
        </header>
        <main className="flex-1 max-w-6xl w-full mx-auto px-6 py-8">
          {children}
        </main>
        <footer className="border-t border-border">
          <div className="max-w-6xl mx-auto px-6 py-4 text-xs text-muted flex justify-between">
            <span>TRIBE v2 · fsaverage5 · 2 Hz</span>
            <span>Karpathy-style autoresearch on <span className="kbd">score.py</span></span>
          </div>
        </footer>
      </body>
    </html>
  );
}
