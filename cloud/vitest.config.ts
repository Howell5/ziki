import path from "node:path";
import { fileURLToPath } from "node:url";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

const root = path.dirname(fileURLToPath(import.meta.url));

// Tests must not import the developer's real OAuth/model handoff credentials.
process.env.CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV = "false";

export default defineConfig({
  plugins: [
    cloudflareTest(async () => ({
      wrangler: { configPath: path.join(root, "wrangler.jsonc") },
      miniflare: {
        bindings: {
          // Explicit overrides also isolate a legacy .dev.vars from test requests.
          ENVIRONMENT: "local", CLOUD_ENABLED: "false", AUTH_ENABLED: "false",
          AUTH_ORIGIN: "http://127.0.0.1:8787",
          GOOGLE_CLIENT_ID: "", GOOGLE_CLIENT_SECRET: "", BETTER_AUTH_SECRET: "",
          EMAIL_LOGIN_ENABLED: "false", EMAIL_FROM: "login@getziki.com",
          TEST_MIGRATIONS: await readD1Migrations(path.join(root, "migrations")),
        },
      },
    })),
  ],
  test: {
    setupFiles: [path.join(root, "test/setup.ts")],
    include: ["test/**/*.test.ts"],
  },
});
