// A small server for the examples. Serves the repository root, so a page can
// load ../../client/jorn.js, and runs the todos app on the server for
// examples/todos/server.html.
//
//   node examples/serve.mjs        then open http://localhost:8000/examples/todos/
//
// Server mode needs the todos example built and `npm install` run in server/.
// Restart this after rebuilding, since the server loads the build once.

import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const port = Number(process.env.PORT ?? 8000);
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json",
};

const server = createServer(async (request, response) => {
  let path = normalize(decodeURIComponent(new URL(request.url, "http://x").pathname));
  if (path.endsWith("/")) path += "index.html";
  try {
    const body = await readFile(join(root, path));
    response.writeHead(200, { "content-type": types[extname(path)] ?? "application/octet-stream" });
    response.end(body);
  } catch {
    response.writeHead(404).end("Not found");
  }
});

let todosOnServer = false;
try {
  const { attach } = await import("../server/jorn.js");
  const { Elm } = createRequire(import.meta.url)("./todos/build/main.js");
  // The saved list comes from the page. That's fine here, since it's the
  // user's own list, but flags from a page are whatever the page says.
  attach(server, { path: "/examples/todos/socket", program: Elm.Main, flags: ({ page }) => page });
  todosOnServer = true;
} catch (error) {
  console.log(`The todos app won't run on the server: ${error.message}`);
}

server.listen(port, () => {
  console.log(`Serving ${root} at http://localhost:${port}/examples/todos/`);
  if (todosOnServer) console.log(`The same app on the server: http://localhost:${port}/examples/todos/server.html`);
});
