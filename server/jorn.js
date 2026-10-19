// Jorn server runtime, for Node.
//
// Runs a compiled Jorn program (Jorn.simple or Jorn.application) on the
// server, one instance per connected page, and streams it to the page over a
// websocket in the wire format of PROTOCOL.md. The page side is `stream` in
// client/jorn.js.
//
//   import { createServer } from "node:http";
//   import { attach } from "./jorn.js";
//
//   const server = createServer(servePage);
//   attach(server, { path: "/app", program: Elm.Main });
//   server.listen(8000);
//
// `session` is the part underneath: one running program and no transport,
// for hosts that move the messages themselves.

import { WebSocketServer } from "ws";

// The version of the server mode messages in PROTOCOL.md. A page that speaks
// another one is turned away instead of half working.
const PROTOCOL = 0;

// At most one render per frame's worth of time, as in a browser. A lone event
// still renders right away, and a `beforePaint` loop can't spin the server.
const FRAME_MS = 16;

/**
 * Start one instance of `program` and connect it to `send`. Hand everything
 * the page sends to `receive`, and call `close` when the page goes away.
 *
 * Throws if the program won't start, for example when `flags` don't match
 * what its `init` expects.
 *
 * @param {{ init: (options: { flags?: unknown }) => { ports: Record<string, any> } }} program
 * @param {{ send: (message: object) => void, flags?: unknown, ports?: { toJorn?: string, fromJorn?: string }, log?: Pick<Console, "warn"> }} options
 * @returns {{ receive: (message: unknown) => void, close: () => void }}
 */
export function session(program, { send, flags, ports = {}, log = console } = {}) {
  if (typeof send !== "function") {
    throw new TypeError("Jorn: session needs a send function");
  }
  const { toJorn = "toJorn", fromJorn = "fromJorn" } = ports;
  const app = program.init(flags === undefined ? {} : { flags });
  const out = app.ports?.[toJorn];
  const into = app.ports?.[fromJorn];
  if (!out?.subscribe || !into?.send) {
    throw new TypeError(`Jorn: session needs a program with ports called ${toJorn} and ${fromJorn}`);
  }

  let running = true;
  let frame = null;
  let lastFrame = -Infinity;

  function requestFrame() {
    if (frame) return;
    const wait = Math.max(0, lastFrame + FRAME_MS - performance.now());
    frame = setTimeout(() => {
      frame = null;
      lastFrame = performance.now();
      if (running) into.send({ frame: true });
    }, wait);
  }

  // Frames are kept here and errors are logged here. Only what the page
  // needs to draw goes over the wire.
  function fromProgram(message) {
    if (!running) return;
    if (message.frame) requestFrame();
    if (message.error) log.warn(`Jorn: ${message.error}`);
    if (message.mount) send({ mount: message.mount });
    if (message.patches) {
      send({ patches: message.patches, instructions: message.instructions ?? [], painted: message.painted === true });
    }
  }
  out.subscribe(fromProgram);

  return {
    /** Pass on a message from the page: an event, or word that it painted. */
    receive(message) {
      if (!running || message === null || typeof message !== "object") return;
      // Only these two. Frames and shutdown are the server's to decide.
      if (message.event !== undefined) into.send({ event: message.event });
      else if (message.painted === true) into.send({ painted: true });
    },

    /** Stop the program. Anything after this is ignored. */
    close() {
      if (!running) return;
      running = false;
      clearTimeout(frame);
      out.unsubscribe(fromProgram);
      into.send({ shutdown: true });
    },
  };
}

/**
 * Serve `program` to pages that connect to `path` on `server`, one session
 * per page.
 *
 * `flags` decides what each session's `init` gets. It's given the HTTP
 * request that opened the socket and whatever flags the page passed to
 * `stream`, and can return a promise. The page's flags are untrusted input:
 * anyone can send anything. Without `flags`, `init` gets none.
 *
 * Browsers attach cookies to websockets from any site, so only pages from the
 * server's own origin may connect, unless `origins` lists others. Clients that
 * aren't browsers send no origin and are let in. For more, `authorize` gets
 * the request and the page's `csrfToken` before anything starts, and turns the
 * page away if it returns false.
 *
 * @param {import("node:http").Server} server
 * @param {{ program: object, path?: string, flags?: (context: { request: import("node:http").IncomingMessage, page: unknown }) => unknown, authorize?: (context: { request: import("node:http").IncomingMessage, csrfToken: string | undefined }) => boolean | Promise<boolean>, origins?: string[], ports?: { toJorn?: string, fromJorn?: string }, maxPayload?: number, log?: Pick<Console, "warn" | "error"> }} options
 * @returns {{ readonly sessions: number, close: () => Promise<void> }}
 */
export function attach(server, { program, path = "/", flags, authorize, origins = [], ports, maxPayload = 1 << 20, log = console } = {}) {
  if (!program || typeof program.init !== "function") {
    throw new TypeError("Jorn: attach needs a compiled program, like Elm.Main");
  }
  const sockets = new WebSocketServer({ noServer: true, maxPayload });
  const allowed = new Set(origins);

  function upgrade(request, socket, head) {
    if (new URL(request.url, "http://localhost").pathname !== path) return; // Someone else's.
    const origin = request.headers.origin;
    if (origin !== undefined && !allowed.has(origin) && !sameOrigin(origin, request)) {
      log.warn(`Jorn: refused a connection from ${origin}`);
      socket.end("HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n");
      return;
    }
    sockets.handleUpgrade(request, socket, head, (ws) => sockets.emit("connection", ws, request));
  }
  server.on("upgrade", upgrade);

  sockets.on("connection", (socket, request) => {
    let current = null;
    let joined = false;

    socket.on("message", async (data, isBinary) => {
      let message;
      try {
        message = JSON.parse(isBinary ? Buffer.from(data).toString() : data.toString());
      } catch {
        socket.close(1007, "Messages must be JSON");
        return;
      }

      if (joined) {
        current?.receive(message);
        return;
      }
      // The first message says which protocol the page speaks and carries its flags.
      const join = message?.join;
      if (join?.protocol !== PROTOCOL) {
        socket.close(1002, `Expected a join for protocol ${PROTOCOL}`);
        return;
      }
      joined = true;
      try {
        const csrfToken = typeof join.csrfToken === "string" ? join.csrfToken : undefined;
        if (authorize && !(await authorize({ request, csrfToken }))) {
          socket.close(1008, "Not allowed");
          return;
        }
        const value = flags ? await flags({ request, page: join.flags }) : undefined;
        if (socket.readyState !== socket.OPEN) return;
        // Nothing the page sends before its first mount can refer to it, so
        // there's nothing to queue while `flags` runs.
        current = session(program, {
          flags: value,
          ports,
          log,
          send: (out) => {
            if (socket.readyState === socket.OPEN) socket.send(JSON.stringify(out));
          },
        });
      } catch (error) {
        log.error(`Jorn: couldn't start a session: ${error?.message ?? error}`);
        socket.close(1011, "The session couldn't start");
      }
    });

    socket.on("close", () => {
      current?.close();
      current = null;
    });
    socket.on("error", (error) => log.warn(`Jorn: ${error.message}`));
  });

  return {
    /** How many pages are connected. */
    get sessions() {
      return sockets.clients.size;
    },

    /** Stop accepting pages and disconnect the ones here. */
    close() {
      server.off("upgrade", upgrade);
      for (const socket of sockets.clients) socket.terminate();
      return new Promise((resolve) => sockets.close(() => resolve()));
    },
  };
}

function sameOrigin(origin, request) {
  try {
    return new URL(origin).host === request.headers.host;
  } catch {
    return false;
  }
}
