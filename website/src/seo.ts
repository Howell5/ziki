import type { Language } from "./content";

export const siteOrigin = "https://getziki.com";
const metadata = {
  en: {
    title: "Ziki — AI Voice Typing for Mac",
    description:
      "Turn natural speech into clear text with Ziki, a native Mac voice typing app. Clean up filler, organize tasks, and write where you work. Bring your own API key.",
    path: "/",
    locale: "en_US",
    imageAlt:
      "Ziki: a quiet ink-wash mountain and river, inspired by the story of Boya and Ziqi.",
  },
  zh: {
    title: "Ziki — Mac AI 语音输入与文字整理工具",
    description:
      "Ziki 是原生 Mac 语音输入工具。按下 Fn 自然口述，去除口头禅与重复，把任务整理成清单，让聊天保持自然。支持 macOS 13 及以上的 Apple Silicon Mac，需自备百炼 API Key。",
    path: "/zh/",
    locale: "zh_CN",
    imageAlt: "Ziki 水墨山水：灵感来自伯牙子期，听见声音，也关心你的意思。",
  },
};

export function pageHead(language: Language) {
  const m = metadata[language];
  const url = siteOrigin + m.path;
  return {
    meta: [
      { title: m.title },
      { name: "description", content: m.description },
      { name: "robots", content: "index, follow, max-image-preview:large" },
      { property: "og:type", content: "website" },
      { property: "og:site_name", content: "Ziki" },
      { property: "og:title", content: m.title },
      { property: "og:description", content: m.description },
      { property: "og:url", content: url },
      { property: "og:locale", content: m.locale },
      {
        property: "og:locale:alternate",
        content: metadata[language === "en" ? "zh" : "en"].locale,
      },
      { property: "og:image", content: `${siteOrigin}/social-card.jpg` },
      { property: "og:image:width", content: "1200" },
      { property: "og:image:height", content: "800" },
      { property: "og:image:alt", content: m.imageAlt },
      { name: "twitter:card", content: "summary_large_image" },
      { name: "twitter:title", content: m.title },
      { name: "twitter:description", content: m.description },
      { name: "twitter:image", content: `${siteOrigin}/social-card.jpg` },
      { name: "twitter:image:alt", content: m.imageAlt },
    ],
    links: [
      { rel: "canonical", href: url },
      { rel: "alternate", hrefLang: "en", href: `${siteOrigin}/` },
      { rel: "alternate", hrefLang: "zh-CN", href: `${siteOrigin}/zh/` },
      { rel: "alternate", hrefLang: "x-default", href: `${siteOrigin}/` },
    ],
  };
}
