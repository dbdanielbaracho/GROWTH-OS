import React from "react";
import { createRoot } from "react-dom/client";
import "./styles.css";

function App() {
  return (
    <main className="page-shell">
      <section className="hero">
        <p className="eyebrow">Growth OS</p>
        <h1>Organic growth intelligence, from signal to learning.</h1>
        <p className="lede">
          Observe opportunities, decide what to create, publish through providers,
          measure outcomes, and improve the next decision.
        </p>
      </section>

      <section className="grid" aria-label="Growth OS core loop">
        {[
          ["Observe", "Collect platform and workspace signals."],
          ["Detect", "Surface opportunities, anomalies, and trend migration."],
          ["Recommend", "Turn evidence into explicit, reviewable actions."],
          ["Publish", "Execute through provider-neutral integrations."],
          ["Measure", "Track content and experiment outcomes."],
          ["Learn", "Feed results back into the next recommendation."]
        ].map(([title, description]) => (
          <article className="card" key={title}>
            <h2>{title}</h2>
            <p>{description}</p>
          </article>
        ))}
      </section>
    </main>
  );
}

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
