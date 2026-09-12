import { createFileRoute } from "@tanstack/react-router";
import { Landing } from "../components/Landing";
import { pageHead } from "../seo";

export const Route = createFileRoute("/")({
  head: () => pageHead("en"),
  component: () => <Landing language="en" />,
});
