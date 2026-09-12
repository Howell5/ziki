import { useEffect, useId, useRef, useState } from "react";
import { copy, type Language } from "../content";

export function Brand({ language }: { language: Language }) {
  const c = copy[language];
  const id = useId();
  const [open, setOpen] = useState(false);
  const [pinned, setPinned] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const button = useRef<HTMLButtonElement>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const clearTimer = () => {
    if (timer.current) clearTimeout(timer.current);
  };

  useEffect(() => () => clearTimer(), []);
  useEffect(() => {
    if (!open) return;
    const close = () => {
      clearTimer();
      setOpen(false);
      setPinned(false);
    };
    const outside = (event: PointerEvent) => {
      if (!root.current?.contains(event.target as Node)) close();
    };
    const escape = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      // Only return focus when it was inside the card; hovering must not steal it.
      if (
        root.current
          ?.querySelector(".story-card")
          ?.contains(document.activeElement)
      )
        button.current?.focus();
      close();
    };
    document.addEventListener("pointerdown", outside);
    document.addEventListener("keydown", escape);
    return () => {
      document.removeEventListener("pointerdown", outside);
      document.removeEventListener("keydown", escape);
    };
  }, [open]);

  return (
    <div
      className="brand-wrap"
      ref={root}
      onPointerEnter={(event) => {
        if (event.pointerType !== "touch") {
          clearTimer();
          timer.current = setTimeout(() => setOpen(true), 180);
        }
      }}
      onPointerLeave={() => {
        clearTimer();
        if (!pinned && !root.current?.contains(document.activeElement))
          timer.current = setTimeout(() => setOpen(false), 200);
      }}
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget)) {
          clearTimer();
          setPinned(false);
          setOpen(false);
        }
      }}
    >
      <button
        className="brand"
        ref={button}
        aria-expanded={open}
        aria-controls={id}
        aria-label={`Ziki — ${c.storyHint}`}
        onFocus={() => {
          clearTimer();
          setOpen(true);
        }}
        onClick={() => {
          clearTimer();
          setPinned(!pinned);
          setOpen(!pinned);
        }}
      >
        <img src="/ziki-mark.png" alt="" width="40" height="40" />
        <span>Ziki</span>
        <span className="brand-spark" aria-hidden="true">
          ✳
        </span>
      </button>
      {open && (
        <section className="story-card" id={id} aria-labelledby={`${id}-title`}>
          <div className="story-art">
            <img src="/ink-landscape.webp" alt="" width="1536" height="1024" />
            <span>知音</span>
          </div>
          <button
            className="story-close"
            aria-label={c.close}
            onClick={() => {
              button.current?.focus();
              setPinned(false);
              setOpen(false);
            }}
          >
            ×
          </button>
          <div className="story-copy">
            <span className="eyebrow">BOYA & ZIQI · 伯牙子期</span>
            <h2 id={`${id}-title`}>{c.storyTitle}</h2>
            <p>{c.story}</p>
            <p className="story-foot">{c.storyFoot}</p>
          </div>
        </section>
      )}
    </div>
  );
}
