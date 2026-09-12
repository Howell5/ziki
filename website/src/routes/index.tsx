import { createFileRoute } from "@tanstack/react-router";
import { Landing } from "../components/Landing";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Ziki — Speak freely. Write clearly." },
      {
        name: "description",
        content:
          "A quieter way to write on macOS. Speak naturally, let Ziki turn your thoughts into clear text, and keep your flow.",
      },
      { property: "og:title", content: "Ziki — Speak freely. Write clearly." },
      {
        property: "og:description",
        content: "Native macOS voice typing, with a little more understanding.",
      },
      { property: "og:type", content: "website" },
    ],
  }),
  component: () => <Landing language="en" />,
});
