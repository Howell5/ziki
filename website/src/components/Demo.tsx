import { useEffect, useRef, useState } from "react";
import { copy, type Language } from "../content";

export function Demo({ language }: { language: Language }) {
  const c = copy[language];
  return (
    <section className="demo-section" id="demo" aria-labelledby="demo-title">
      <div className="section-intro">
        <span className="eyebrow">{c.demoEyebrow}</span>
        <h2 id="demo-title">{c.demoTitle}</h2>
        <p>{c.demoIntro}</p>
      </div>
      <div className="demo-examples">
        {c.examples.map((_, scenario) => (
          <DemoExample
            key={`${language}-${scenario}`}
            language={language}
            scenario={scenario}
          />
        ))}
      </div>
      <p className="demo-disclaimer">{c.sample}</p>
    </section>
  );
}

function DemoExample({
  language,
  scenario,
}: {
  language: Language;
  scenario: number;
}) {
  const c = copy[language];
  const shell = useRef<HTMLElement>(null);
  const started = useRef(false);
  const [visible, setVisible] = useState(false);
  const [foreground, setForeground] = useState(true);
  const [reducedMotion, setReducedMotion] = useState(false);
  const [phase, setPhase] = useState(0);
  const active = phase === 1 || phase === 2;
  const playing = active && visible && foreground;
  const example = c.examples[scenario];

  useEffect(() => {
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const updateMotion = () => setReducedMotion(media.matches);
    const updateVisibility = () => setForeground(!document.hidden);
    updateMotion();
    updateVisibility();
    media.addEventListener("change", updateMotion);
    document.addEventListener("visibilitychange", updateVisibility);
    const observer = new IntersectionObserver(
      ([entry]) => {
        setVisible(entry.isIntersecting && entry.intersectionRatio >= 0.35);
      },
      { threshold: [0, 0.35] },
    );
    if (shell.current) observer.observe(shell.current);
    return () => {
      observer.disconnect();
      media.removeEventListener("change", updateMotion);
      document.removeEventListener("visibilitychange", updateVisibility);
    };
  }, []);

  useEffect(() => {
    if (visible && foreground && !started.current) {
      started.current = true;
      setPhase(reducedMotion ? 3 : 1);
    }
    if (reducedMotion && started.current) setPhase(3);
  }, [visible, foreground, reducedMotion]);

  // Cancel the pending stage when off-screen, hidden, stopped, or unmounted.
  useEffect(() => {
    if (!playing) return;
    if (phase === 1) {
      const timer = setTimeout(() => setPhase(2), 2800);
      return () => clearTimeout(timer);
    }
    if (phase === 2) {
      const timer = setTimeout(() => setPhase(3), 1300);
      return () => clearTimeout(timer);
    }
  }, [phase, playing]);

  return (
    <article
      ref={shell}
      className="demo-shell"
      aria-labelledby={`scenario-${scenario}`}
      data-phase={phase}
      data-playing={playing}
    >
      <div className="demo-toolbar">
        <span className="window-dots" aria-hidden="true">
          <i />
          <i />
          <i />
        </span>
        <h3 className="scenario-title" id={`scenario-${scenario}`}>
          <span aria-hidden="true">0{scenario + 1}</span>
          {c.scenarios[scenario]}
        </h3>
        <span className="demo-wordmark" aria-hidden="true">
          Ziki
        </span>
      </div>
      <div
        className={`demo-columns phase-${phase} ${playing ? "is-playing" : ""}`}
      >
        <div className="demo-input">
          <span className="panel-label">
            <span className="tiny-dot" />
            {c.heard}
          </span>
          <p className="spoken-text">“{example.raw}”</p>
          <div
            className={`waveform ${phase === 1 && playing ? "is-listening" : ""}`}
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
          <div className={`output-content ${active ? "is-pending" : ""}`}>
            <div
              className="output-placeholder"
              aria-hidden="true"
              hidden={!active}
            >
              <i />
              <i />
              <i />
            </div>
            <div className="output-result" aria-hidden={active}>
              {scenario === 0 ? (
                <ol className="clean-list">
                  {example.result.map((text) => (
                    <li key={text}>{text}</li>
                  ))}
                </ol>
              ) : (
                <p className="clean-prose">{example.result[0]}</p>
              )}
            </div>
            <span className="output-signature">
              {active ? "···" : "↳ Ziki"}
            </span>
          </div>
        </div>
      </div>
      <div className="demo-bottom">
        <div className="demo-status">
          <kbd>fn</kbd>
          <span className={`status-dot ${playing ? "active" : ""}`} />
          <span role="status" aria-live="polite">
            {c.states[phase]}
          </span>
        </div>
        <button
          className="demo-play"
          aria-label={`${active ? c.stop : c.replay} — ${c.scenarios[scenario]}`}
          onClick={() => {
            started.current = true;
            setPhase(active || reducedMotion ? 3 : 1);
          }}
        >
          <span aria-hidden="true">{active ? "■" : "↻"}</span>
          {active ? c.stop : c.replay}
        </button>
      </div>
    </article>
  );
}
