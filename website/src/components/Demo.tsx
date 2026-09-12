import { useEffect, useState } from "react";
import { copy, type Language } from "../content";

export function Demo({ language }: { language: Language }) {
  const c = copy[language];
  const [scenario, setScenario] = useState(0);
  const [phase, setPhase] = useState(0);
  const active = phase === 1 || phase === 2;
  const example = c.examples[scenario];
  useEffect(() => {
    if (phase === 1) {
      const timer = setTimeout(() => setPhase(2), 2800);
      return () => clearTimeout(timer);
    }
    if (phase === 2) {
      const timer = setTimeout(() => setPhase(3), 1300);
      return () => clearTimeout(timer);
    }
  }, [phase]);

  return (
    <section className="demo-section" id="demo" aria-labelledby="demo-title">
      <div className="section-intro">
        <span className="eyebrow">{c.demoEyebrow}</span>
        <h2 id="demo-title">{c.demoTitle}</h2>
        <p>{c.demoIntro}</p>
      </div>
      <div className="demo-shell">
        <div className="demo-toolbar">
          <span className="window-dots" aria-hidden="true">
            <i />
            <i />
            <i />
          </span>
          <div
            className="scenario-buttons"
            aria-label={language === "en" ? "Demo scenarios" : "演示场景"}
          >
            {c.scenarios.map((name, index) => (
              <button
                key={name}
                aria-pressed={scenario === index}
                onClick={() => {
                  setScenario(index);
                  setPhase(0);
                }}
              >
                {name}
              </button>
            ))}
          </div>
          <span className="demo-wordmark" aria-hidden="true">
            Ziki
          </span>
        </div>
        <div className={`demo-columns phase-${phase}`}>
          <div className="demo-input">
            <span className="panel-label">
              <span className="tiny-dot" />
              {c.heard}
            </span>
            <p className="spoken-text">“{example.raw}”</p>
            <div
              className={`waveform ${phase === 1 ? "is-listening" : ""}`}
              aria-hidden="true"
            >
              {Array.from({ length: 35 }, (_, i) => (
                <i
                  key={i}
                  style={{
                    height: `${8 + ((i * 17 + 7) % 31)}px`,
                    animationDelay: `${i * 33}ms`,
                  }}
                />
              ))}
            </div>
          </div>
          <div className="demo-output">
            <span className="panel-label">
              <span className="output-spark" aria-hidden="true">
                ✳
              </span>
              {c.written}
            </span>
            {active ? (
              <div className="output-placeholder" aria-hidden="true">
                <i />
                <i />
                <i />
              </div>
            ) : scenario === 0 ? (
              <ol className="clean-list">
                {example.result.map((text) => (
                  <li key={text}>{text}</li>
                ))}
              </ol>
            ) : (
              <p className="clean-prose">{example.result[0]}</p>
            )}
            <span className="output-signature">
              {active ? "···" : "↳ Ziki"}
            </span>
          </div>
        </div>
        <div className="demo-bottom">
          <div className="demo-status">
            <kbd>fn</kbd>
            <span className={`status-dot ${active ? "active" : ""}`} />
            <span role="status" aria-live="polite">
              {c.states[phase]}
            </span>
          </div>
          <button
            className="demo-play"
            onClick={() => setPhase(active ? 0 : 1)}
          >
            <span aria-hidden="true">
              {active ? "■" : phase === 3 ? "↻" : "▷"}
            </span>
            {active ? c.stop : phase === 3 ? c.replay : c.play}
          </button>
        </div>
      </div>
      <p className="demo-disclaimer">{c.sample}</p>
    </section>
  );
}
