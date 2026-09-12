import { defineConfig } from "vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";

export default defineConfig({
  // Explicit loopback avoids localhost IPv4/IPv6 mismatches during prerendering.
  preview: { host: "127.0.0.1" },
  plugins: [
    tanstackStart({
      prerender: {
        enabled: true,
        autoSubfolderIndex: true,
        crawlLinks: true,
        failOnError: true,
      },
      pages: [{ path: "/" }, { path: "/zh" }],
    }),
    viteReact(),
  ],
});
