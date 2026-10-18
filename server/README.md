# server/jorn.js

The server side of Jorn. It runs a Jorn program on Node, one instance per connected page, and streams it to the page over a websocket, in [Jorn's wire protocol](../PROTOCOL.md). The page side is `stream` in [client/jorn.js](../client).

Your program doesn't change. A `Jorn.simple` or `Jorn.application` program that runs in the page with `start` runs here as it is.

## Serving an app

```js
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { attach } from "./jorn.js";

const { Elm } = createRequire(import.meta.url)("./build/main.js");

const server = createServer(servePage); // whatever serves your HTML and client/jorn.js
attach(server, {
  path: "/app",
  program: Elm.Main,
  flags: ({ request, page }) => loadUser(request), // optional, and can be async
});
server.listen(8000);
```

And in the page:

```js
import { stream } from "./jorn.js";

stream(document.getElementById("app"), "/app");
```

Install the one dependency, [ws](https://github.com/websockets/ws), with `npm install` in this folder. It needs Node 22 or newer.

## What runs where

- `update`, `view`, subscriptions and Elm commands (time, random, tasks) run on the server. HTTP comes with #22.
- Focus, blur, scrolling, `Effect.event` and `Effect.client` run in the page, right after the patches they arrived with. Register `Effect.client` functions with `stream`'s `effects`.
- Messages that arrive close together are rendered once, at most once every 16 ms, so a burst of events costs one diff, as it does in the browser.
- Event handlers only get the event fields they ask for with `Event.include`. The helpers in `Jorn.Event` already ask for what they decode.

## Flags and security

`flags` decides what each session's `init` gets. It receives the HTTP request that opened the socket, so it can read cookies or the URL, and `page`, the flags the page passed to `stream`. Treat `page` as untrusted: anyone can open a socket and send anything. If `flags` throws or the flags don't fit `init`, the socket closes and the error is logged.

Browsers send cookies with a websocket from any site, so `attach` only accepts pages from the server's own origin. If your pages are served from somewhere else, list them in `origins: ["https://example.com"]`. Clients that aren't browsers send no origin and are let in, since they can't carry a visitor's cookies.

Messages over 1 MiB close the socket. Change that with `maxPayload`.

## API

| | |
|---|---|
| `attach(server, { program, path, flags, origins, ports, maxPayload, log })` | Serve `program` to pages that connect to `path` on an HTTP server. Leaves other paths alone. Returns `{ sessions, close() }`. |
| `session(program, { send, flags, ports, log })` | Start one instance of `program` with no transport. Hand the page's messages to `.receive(message)` and call `.close()` when it goes away. For hosts that move the messages themselves. |

If your program's ports aren't called `toJorn` and `fromJorn`, pass `ports: { toJorn: "...", fromJorn: "..." }`.

## Tests

`test/run.mjs` runs a session on its own, then pages in jsdom against a real server over real sockets: batching, every kind of effect, separate sessions, and the refusals. `client/test/example.mjs server` runs the todos example through it. See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to run them.
