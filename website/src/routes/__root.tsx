import {
  createRootRoute,
  HeadContent,
  Outlet,
  Scripts,
  useRouterState,
} from "@tanstack/react-router";
import stylesheet from "../styles.css?url";

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { name: "theme-color", content: "#f7f6f2" },
    ],
    links: [
      { rel: "stylesheet", href: stylesheet },
      { rel: "icon", type: "image/png", href: "/favicon.png" },
    ],
  }),
  component: Root,
  notFoundComponent: () => (
    <main className="not-found">
      <p>404</p>
      <h1>A little off the path.</h1>
      <a href="/">Back to Ziki →</a>
    </main>
  ),
});

function Root() {
  const path = useRouterState({ select: (state) => state.location.pathname });
  return (
    <html lang={path.startsWith("/zh") ? "zh-CN" : "en"}>
      <head>
        <HeadContent />
      </head>
      <body>
        <Outlet />
        <Scripts />
      </body>
    </html>
  );
}
