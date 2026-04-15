export default function About() {
  return (
    <div className="max-w-2xl space-y-5 text-sm leading-relaxed">
      <h1 className="text-2xl font-semibold">About CBT</h1>
      <p>
        CBT scores tweets, images, UI screenshots, and reels against a model
        of predicted fMRI brain responses, then lets a Karpathy-style
        autoresearch agent rewrite the scoring head overnight to improve
        correlation with actual engagement.
      </p>

      <h2 className="text-lg font-semibold mt-6">The stack</h2>
      <ol className="list-decimal pl-5 space-y-2">
        <li>
          <span className="text-text">TRIBE v2 (Meta FAIR)</span> — the frozen
          oracle. Takes video / audio / text, returns a (T, 20484) response
          tensor on the fsaverage5 cortex at 2 Hz.
        </li>
        <li>
          <span className="text-text">Ingest</span> — text goes straight in;
          images become 5 s stare videos; UI screenshots become saliency-driven
          scanpath videos; reels split into video + audio.
        </li>
        <li>
          <span className="text-text">Scoring head</span> — five ROI masks
          (reward, attention, emotion, language, visual). A small Python
          function turns per-ROI peak responses, temporal variance, and a hook
          window into a 0–100 score plus dead-zone / hotspot callouts.
        </li>
        <li>
          <span className="text-text">Autoresearch loop</span> — Claude reads
          <span className="kbd">score.py</span>, recent experiments, and the
          rubric; proposes one focused edit; the runner applies, evaluates
          Spearman against a held-out labeled set, and keeps or reverts.
        </li>
      </ol>

      <h2 className="text-lg font-semibold mt-6">Credits</h2>
      <ul className="list-disc pl-5 space-y-1 text-muted">
        <li>TRIBE v2: ai.meta.com/research/publications</li>
        <li>Autoresearch pattern: github.com/karpathy/autoresearch</li>
        <li>Seed idea: @fuckgrowth on X</li>
      </ul>
    </div>
  );
}
