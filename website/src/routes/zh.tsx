import { createFileRoute } from "@tanstack/react-router";
import { Landing } from "../components/Landing";
import { pageHead } from "../seo";

export const Route = createFileRoute("/zh")({
  head: () => pageHead("zh"),
  component: () => <Landing language="zh" />,
});
