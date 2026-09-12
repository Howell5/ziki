import { copy, release, type Language } from "../content";
import { Brand } from "./Brand";
import { Demo } from "./Demo";

function Download({
  label,
  light = false,
}: {
  label: string;
  light?: boolean;
}) {
  return (
    <a
      className={`button button-primary${light ? " button-light" : ""}`}
      href={release.download}
    >
      <svg
        viewBox="0 0 24 24"
        width="18"
        height="18"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.5"
        aria-hidden="true"
      >
        <path d="M12 3v12m-5-5 5 5 5-5M5 16v4h14v-4" />
      </svg>
      {label}
      <span aria-hidden="true">↗</span>
    </a>
  );
}

export function Landing({ language }: { language: Language }) {
  const c = copy[language];
  const setup = `${release.repository}/blob/main/${language === "en" ? "README.md" : "README.zh-CN.md"}#${language === "en" ? "install-the-github-preview" : "安装-github-预览版"}`;
  return (
    <div className={`site lang-${language}`}>
      <a className="skip-link" href="#main">
        {c.skip}
      </a>
      <header className="site-header frame">
        <Brand language={language} />
        <nav aria-label={language === "en" ? "Main navigation" : "主导航"}>
          {c.nav.map((label, i) => (
            <a
              key={label}
              href={["#how-it-works", "#details", "#questions"][i]}
            >
              {label}
            </a>
          ))}
        </nav>
        <div className="header-actions">
          <a
            className="language-switch"
            href={language === "en" ? "/zh/" : "/"}
            hrefLang={language === "en" ? "zh-CN" : "en"}
            lang={language === "en" ? "zh-CN" : "en"}
            aria-label={c.languageLabel}
          >
            {language === "en" ? "中文" : "EN"}
          </a>
          <a className="header-download" href={release.download}>
            {language === "en" ? "Get Ziki" : "下载 Ziki"}
            <span aria-hidden="true">↗</span>
          </a>
        </div>
      </header>
      <main id="main">
        <section className="hero frame" aria-labelledby="hero-title">
          <div className="hero-copy">
            <span className="eyebrow">
              <span className="tiny-dot" />
              {c.eyebrow}
            </span>
            <h1 id="hero-title">
              {c.headline[0]}
              <br />
              <em>{c.headline[1]}</em>
            </h1>
            <p className="hero-intro">{c.intro}</p>
            <div className="hero-actions">
              <Download label={c.download} />
              <a className="text-link" href="#demo">
                {c.watch}
                <span aria-hidden="true">↓</span>
              </a>
            </div>
            <p className="requirements">{c.requirements}</p>
          </div>
          <div className="hero-art" aria-hidden="true">
            <img
              src="/ink-landscape.webp"
              width="1536"
              height="1024"
              fetchPriority="high"
              alt=""
            />
            <span className="art-caption">{c.artCaption}</span>
            <span className="art-index">01 — A QUIETER WAY TO WRITE</span>
          </div>
          <a className="hero-margin-note" href="#origin">
            {c.storyHint}
            <span aria-hidden="true">↗</span>
          </a>
        </section>
        <div className="frame">
          <Demo language={language} />
          <section
            className="method section-rule"
            id="how-it-works"
            aria-labelledby="method-title"
          >
            <div className="section-heading">
              <span className="eyebrow">{c.methodEyebrow}</span>
              <h2 id="method-title">{c.methodTitle}</h2>
            </div>
            <div className="steps">
              {c.steps.map((step, index) => (
                <article key={step.title}>
                  <div className="step-top">
                    <span>0{index + 1}</span>
                    <span className="step-symbol" aria-hidden="true">
                      {["fn", "✳", "↵"][index]}
                    </span>
                  </div>
                  <h3>{step.title}</h3>
                  <p>{step.text}</p>
                </article>
              ))}
            </div>
          </section>
          <section
            className="details section-rule"
            id="details"
            aria-labelledby="details-title"
          >
            <div className="principle">
              <span className="eyebrow">THE ZIKI WAY</span>
              <h2 id="details-title">{c.principle}</h2>
              <p>{c.principleText}</p>
              <div className="ink-rule" aria-hidden="true" />
            </div>
            <div className="detail-grid">
              {c.details.map((detail, index) => (
                <article key={detail.title}>
                  <span className="detail-number">0{index + 1}</span>
                  <h3>{detail.title}</h3>
                  <p>{detail.text}</p>
                </article>
              ))}
            </div>
          </section>
          <section
            className="origin section-rule"
            id="origin"
            aria-labelledby="origin-title"
          >
            <span className="origin-character" aria-hidden="true">
              知音
            </span>
            <div>
              <span className="eyebrow">BEHIND THE NAME · 伯牙子期</span>
              <h2 id="origin-title">{c.storyTitle}</h2>
              <p>{c.storyFoot}</p>
            </div>
            <span className="origin-end" aria-hidden="true">
              山<br />水<br />之<br />间
            </span>
          </section>
          <section
            className="faq section-rule"
            id="questions"
            aria-labelledby="faq-title"
          >
            <h2 id="faq-title">{c.faqTitle}</h2>
            <div className="faq-items">
              {c.faqs.map((item) => (
                <details key={item.question}>
                  <summary>
                    {item.question}
                    <span aria-hidden="true">+</span>
                  </summary>
                  <p>{item.answer}</p>
                </details>
              ))}
              <a className="text-link faq-guide" href={setup}>
                {c.setup}
                <span aria-hidden="true">↗</span>
              </a>
            </div>
          </section>
          <section className="closing" aria-labelledby="closing-title">
            <span className="eyebrow">{c.endEyebrow}</span>
            <h2 id="closing-title">{c.endTitle}</h2>
            <p>{c.endIntro}</p>
            <Download label={c.download} light />
            <p className="closing-requirements">{c.requirements}</p>
            <div className="closing-links">
              <a href={setup}>{c.setup} ↗</a>
              <span aria-hidden="true">/</span>
              <a href={release.notes}>{c.notes} ↗</a>
            </div>
            <p className="preview-note">{c.preview}</p>
            <img
              className="closing-mark"
              src="/ziki-mark.png"
              width="256"
              height="256"
              alt=""
              loading="lazy"
            />
          </section>
        </div>
      </main>
      <footer className="site-footer frame">
        <a
          className="footer-brand"
          href={language === "en" ? "/" : "/zh/"}
          aria-label={language === "en" ? "Ziki home" : "Ziki 首页"}
        >
          Ziki<span>© {new Date().getFullYear()}</span>
        </a>
        <p>{c.footer}</p>
        <a href={release.repository}>{c.source} ↗</a>
      </footer>
    </div>
  );
}
