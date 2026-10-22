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

Or put it anywhere in a page, or in a Jorn app's view, as an element, with `Jorn.ServerComponent.element` and `defineServerComponent` from `client/jorn.js`:

```html
<jorn-server-component route="/app"></jorn-server-component>
```

Install the one dependency, [ws](https://github.com/websockets/ws), with `npm install` in this folder. It needs Node 22 or newer.

## What runs where

- `update`, `view`, subscriptions and Elm commands (HTTP, time, random, tasks) run on the server. [Commands on the server](#commands-on-the-server) says what that changes.
- Focus, blur, scrolling, `Effect.event` and `Effect.client` run in the page, right after the patches they arrived with. Register `Effect.client` functions with `stream`'s `effects`.
- Messages that arrive close together are rendered once, at most once every 16 ms, so a burst of events costs one diff, as it does in the browser.
- Event handlers only get the event fields they ask for with `Event.include`. The helpers in `Jorn.Event` already ask for what they decode.

## Commands on the server

Commands run where the program runs, so its requests, clock and randomness are the server's.

- **HTTP** works through `elm/http` as it does in the page. `elm/http` needs the browser's `XMLHttpRequest`, so the first session defines one built on Node's `fetch` ([http.js](http.js)), unless the process already has one. The requests are made by your server, not the visitor's browser, which changes three things:
  - URLs must be absolute. There's no page to resolve `/api/todos` against, so a relative URL fails with `Http.BadUrl`. Pass your API's address in the flags.
  - Requests carry no cookies, so `Http.riskyRequest` is the same as `Http.request`. To call an API as the visitor, have `flags` take what you need from the request that opened the socket, and send it with `Http.header`.
  - They can reach anything your server can, including addresses on your private network. Build URLs from values you trust, not from what a visitor typed.
- **Time** is the server's. `Time.now` and `Time.every` work as usual, but `Time.here` gives the server's time zone. If your view shows local times, pass the page's offset in the flags (`-new Date().getTimezoneOffset()`, in minutes) and make a zone with `Time.customZone`.
- **Random** works as usual, seeded from the server's clock.
- `File.Select` and `File.Download` from `elm/file` need a page, so they don't work on the server. `Debug.log` prints on the server.

## URL routing

An app made with `Jorn.Navigation.application` runs on the server like any other. The page sends its address when it connects, so the session's `init` gets the URL, and after that the page reports every change of address and every link someone clicks, and runs the navigation the app asks for. A page that reconnects after moving, say with the back button while it was offline, tells its session where it is now. Each navigation costs a round trip, since the page changes the address and the server hears where it landed.

## Flags and security

`flags` decides what each session's `init` gets. It receives the HTTP request that opened the socket, so it can read cookies or the URL, and `page`, the flags the page passed to `stream`. Treat `page` as untrusted: anyone can open a socket and send anything. If `flags` throws or the flags don't fit `init`, the socket closes and the error is logged.

Browsers send cookies with a websocket from any site, so `attach` only accepts pages from the server's own origin. If your pages are served from somewhere else, list them in `origins: ["https://example.com"]`. Clients that aren't browsers send no origin and are let in, since they can't carry a visitor's cookies.

For more than that, give `attach` an `authorize` function. It gets the request and the CSRF token the page sent (from `stream`'s `csrfToken` or the element's `csrf-token`), runs before `flags`, and closes the socket if it returns false:

```js
attach(server, {
  path: "/app",
  program: Elm.Main,
  authorize: ({ request, csrfToken }) => csrfToken === tokenFor(request),
});
```

## Talking to sessions

Server code reaches a running session through the program's own ports, the ones it declares besides `toJorn` and `fromJorn`. `onSession` is called as each session starts, with those ports, the flags its `init` got, and the request that opened the socket. What it returns, if it's a function, is called when the session ends:

```js
const everyone = new Set();

attach(server, {
  path: "/chat",
  program: Elm.Main,
  flags: ({ request }) => ({ name: userFor(request) }),
  onSession({ ports, flags }) {
    const say = (text) => {
      for (const other of everyone) other.hear.send({ name: flags.name, text });
    };
    ports.say.subscribe(say);
    everyone.add(ports);
    return () => {
      everyone.delete(ports);
      ports.say.unsubscribe(say);
    };
  },
});
```

That's a chat room: `say` is a port the program sends on when someone posts, and `hear` one it subscribes to. [examples/chat](../examples/chat) is the whole thing. A session lasts as long as its page, through reconnects, so `onSession` runs once per page. If it throws, the session doesn't start and the socket closes, as when `flags` throws.

`session` returns the same ports, for hosts that run sessions themselves. Elm leaves out ports the program never uses, and a closed session ignores its ports.

## Dropped connections and limits

A page whose connection drops reconnects by itself and resumes its session. The session waits `linger` milliseconds for it (30 seconds by default), keeping its last `replay` messages (256) to catch the page up. A page that missed more gets the whole view again. A page that closes on purpose, or a tab that closes, ends its session straight away.

The server pings every socket every `heartbeat` milliseconds (30 seconds) and drops one that didn't answer the last ping, so dead connections don't hold sessions forever.

| Option | Default | |
|---|---|---|
| `linger` | `30_000` | How long a session waits for its page to reconnect, in ms. 0 ends it at once |
| `replay` | `256` | How many recent messages a session keeps for a reconnecting page |
| `heartbeat` | `30_000` | How often to ping each socket, in ms |
| `maxSessions` | `Infinity` | More pages than this are told to try later (close code 1013) |
| `maxMessagesPerSecond` | `100` | A page that sends faster than this, with bursts of up to twice it, is disconnected |
| `maxPayload` | `1 MiB` | A bigger message disconnects the page |

Each session gets a number in the logs. `attach` logs to `log.info` when a session starts, resumes or ends and why, and to `log.warn` and `log.error` when something goes wrong. Pass your own `log` to send these elsewhere. One Node process can't measure how much memory each session uses, so to bound memory, bound `maxSessions`.

## API

| | |
|---|---|
| `attach(server, { program, path, flags, authorize, origins, ports, onSession, linger, replay, heartbeat, maxSessions, maxMessagesPerSecond, maxPayload, log })` | Serve `program` to pages that connect to `path` on an HTTP server. Leaves other paths alone. Returns `{ sessions, close() }`. |
| `session(program, { send, flags, url, ports, log })` | Start one instance of `program` with no transport. Hand the page's messages to `.receive(message)` and call `.close()` when it goes away. `url` is the page's address, which an app with URL routing needs to start. `.ports` are the program's own ports. For hosts that move the messages themselves. |
| `XMLHttpRequest` | The one the first session defines for `elm/http` when the process has none. Set `globalThis.XMLHttpRequest` to it yourself if something needs it before then. |

If your program's ports aren't called `toJorn` and `fromJorn`, pass `ports: { toJorn: "...", fromJorn: "..." }`.

## Tests

`test/run.mjs` runs a session on its own, then pages in jsdom against a real server over real sockets: batching, every kind of effect, separate sessions, and the refusals. `test/reconnect.mjs` puts a TCP proxy between the pages and the server and silences or cuts it, including halfway through a patch, to check that pages resume, catch up, remount or start over, that heartbeats find silent connections, and that the limits hold. `test/http.mjs` uses the `XMLHttpRequest` the way `elm/http` does, against a local HTTP server, and `test/http-elm.mjs` runs `elm/http` itself in a server component. `test/chat.mjs` runs the chat example with three pages. `client/test/example.mjs server` runs the todos example on the server, and `client/test/routing.mjs server` an app with URL routing. See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to run them.
