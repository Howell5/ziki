import { createFileRoute } from "@tanstack/react-router";
import { Landing } from "../components/Landing";

export const Route = createFileRoute("/zh")({
  head: () => ({
    meta: [
      { title: "Ziki — 自在说，清楚写。" },
      {
        name: "description",
        content:
          "让表达，少一点费力。Ziki 是原生 macOS 语音输入工具，将自然口述整理成清晰的文字。灵感来自伯牙子期，听见声音，也关心你的意思。",
      },
      { property: "og:title", content: "Ziki — 自在说，清楚写。" },
      {
        property: "og:description",
        content: "原生 macOS 语音输入工具。听见声音，也关心你的意思。",
      },
      { property: "og:type", content: "website" },
    ],
  }),
  component: () => <Landing language="zh" />,
});
