// The HTTP server the HTTP tests send requests to, on a local port.

import { createServer } from "node:http";
import { gzipSync } from "node:zlib";

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Start the server. `base` is its address, `nowhere` is an address nothing
 * listens on, and `hangUps` counts requests whose connection closed before
 * their response ended.
 */
export async function serve() {
  let hangUps = 0;
  const routes = {
    "/text": (request, response) => response.writeHead(200, { "content-type": "text/plain; charset=utf-8", "x-one": "1" }).end("hello"),
    "/json": (request, response) => response.writeHead(200, { "content-type": "application/json" }).end('{"a":1}'),
    "/bytes": (request, response) => response.writeHead(200, { "content-type": "application/octet-stream" }).end(Buffer.from(Array.from({ length: 256 }, (_, i) => i))),
    "/missing": (request, response) => response.writeHead(404, { "content-type": "text/plain" }).end("nope"),
    "/redirect": (request, response) => response.writeHead(302, { location: "/text" }).end(),
    "/empty": (request, response) => response.writeHead(204).end(),
    "/latin1": (request, response) => response.writeHead(200, { "content-type": "text/plain; charset=iso-8859-1" }).end(Buffer.from([0x63, 0x61, 0x66, 0xe9])),
    "/gzip": (request, response) => {
      const zipped = gzipSync("zipped");
      response.writeHead(200, { "content-type": "text/plain", "content-encoding": "gzip", "content-length": zipped.length }).end(zipped);
    },
    "/many": (request, response) => {
      response.setHeader("x-many", ["a", "b"]);
      response.writeHead(200).end("ok");
    },
    "/echo": async (request, response) => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = Buffer.concat(chunks);
      response.writeHead(200, { "content-type": "application/json" }).end(
        JSON.stringify({
          method: request.method,
          contentType: request.headers["content-type"] ?? null,
          custom: request.headers["x-custom"] ?? null,
          cookie: request.headers.cookie ?? null,
          length: body.length,
          text: body.toString("latin1"),
        }),
      );
    },
    "/slow": (request, response) => {
      response.on("close", () => !response.writableFinished && hangUps++);
      setTimeout(() => response.writableEnded || response.destroyed || response.writeHead(200).end("late"), 300);
    },
    // 200,000 bytes, in four parts with pauses between, so progress shows.
    "/big": async (request, response) => {
      response.writeHead(200, { "content-type": "application/octet-stream", "content-length": "200000" });
      for (let i = 0; i < 4; i++) {
        response.write(Buffer.alloc(50_000, i));
        await wait(60);
      }
      response.end();
    },
    "/chunked": async (request, response) => {
      response.writeHead(200, { "content-type": "text/plain" });
      for (const part of ["one ", "two ", "three"]) {
        response.write(part);
        await wait(60);
      }
      response.end();
    },
  };

  const server = createServer((request, response) => {
    const route = routes[new URL(request.url, "http://localhost").pathname];
    if (route) route(request, response);
    else response.writeHead(500).end(`no route for ${request.url}`);
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  const closed = createServer();
  await new Promise((resolve) => closed.listen(0, "127.0.0.1", resolve));
  const nowhere = `http://127.0.0.1:${closed.address().port}/`;
  await new Promise((resolve) => closed.close(resolve));

  return {
    server,
    base: `http://127.0.0.1:${server.address().port}`,
    nowhere,
    get hangUps() {
      return hangUps;
    },
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}
