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
//
// elm/http needs XMLHttpRequest, so the first session defines the one in
// http.js globally if the process has none.

import { randomUUID } from "node:crypto";
import { WebSocketServer } from "ws";
import { XMLHttpRequest } from "./http.js";

export { XMLHttpRequest };

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
 * For a `Jorn.resumable` program, `snapshot` gets its model as its `encode`
 * writes it, and passing that back as `restore`, even to a newer version of
 * the program, starts it from that model instead of from `init`.
 *
 * Throws if the program won't start, for example when `flags` don't match
 * what its `init` expects.
 *
 * @param {{ init: (options: { flags?: unknown }) => { ports: Record<string, any> } }} program
 * @param {{ send: (message: object) => void, flags?: unknown, restore?: unknown, ports?: { toJorn?: string, fromJorn?: string }, log?: Pick<Console, "warn"> }} options
 * @returns {{ receive: (message: unknown) => void, snapshot: () => Promise<unknown>, close: () => void }}
 */
export function session(program, { send, flags, restore, ports = {}, log = console } = {}) {
  if (typeof send !== "function") {
    throw new TypeError("Jorn: session needs a send function");
  }
  const { toJorn = "toJorn", fromJorn = "fromJorn" } = ports;
  globalThis.XMLHttpRequest ??= XMLHttpRequest;
  const app = program.init(flags === undefined ? {} : { flags });
  const out = app.ports?.[toJorn];
  const into = app.ports?.[fromJorn];
  if (!out?.subscribe || !into?.send) {
    throw new TypeError(`Jorn: session needs a program with ports called ${toJorn} and ${fromJorn}`);
  }

  let running = true;
  let frame = null;
  let lastFrame = -Infinity;
  let resumable = false; // Set when the program says it's waiting to be told how to start.
  let mounted = false;
  const snapshots = []; // Waiting for the program's model.

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
    if (message.ready) {
      resumable = true;
      into.send(restore === undefined ? { fresh: true } : { restore });
      return;
    }
    if ("snapshot" in message) {
      for (const resolve of snapshots.splice(0)) resolve(message.snapshot ?? undefined);
      return;
    }
    if (message.mount && !mounted) {
      mounted = true;
      if (restore !== undefined && !resumable) log.warn("Jorn: the program isn't Jorn.resumable, so a saved session started over");
    }
    if (message.frame) requestFrame();
    if (message.error) log.warn(`Jorn: ${message.error}`);
    if (message.mount) send(message.painted ? { mount: message.mount, painted: true } : { mount: message.mount });
    if (message.patches) {
      send({ patches: message.patches, instructions: message.instructions ?? [], painted: message.painted === true });
    }
  }
  out.subscribe(fromProgram);

  return {
    /**
     * Pass on a message from the page: an event, word that it painted, or a
     * request for the whole view because it lost track.
     */
    receive(message) {
      if (!running || message === null || typeof message !== "object") return;
      // Only these. Frames and shutdown are the server's to decide.
      if (message.event !== undefined) into.send({ event: message.event });
      else if (message.painted === true) into.send({ painted: true });
      else if (message.remount === true) into.send({ remount: true });
    },

    /**
     * The program's model, as its `encode` writes it, to start it again from
     * later with `restore`. Undefined for a program that isn't
     * `Jorn.resumable`, or one that hasn't started yet.
     */
    snapshot() {
      if (!running || !resumable) return Promise.resolve(undefined);
      return new Promise((resolve) => {
        snapshots.push(resolve);
        into.send({ snapshot: true });
      });
    },

    /** Stop the program. Anything after this is ignored. */
    close() {
      if (!running) return;
      running = false;
      clearTimeout(frame);
      out.unsubscribe(fromProgram);
      into.send({ shutdown: true });
      for (const resolve of snapshots.splice(0)) resolve(undefined);
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
 * A page whose connection drops keeps its session for `linger` milliseconds.
 * If it comes back in time, it gets the messages it missed, or the whole view
 * when it missed too many to replay. A page that closes on purpose ends its
 * session straight away.
 *
 * With `snapshots`, a store such as a Map, `close` saves the model of every
 * `Jorn.resumable` session first, and a page that comes back to the next
 * server with the same store picks up where it was. Keep the store somewhere
 * that outlives the process to keep sessions across a deploy.
 *
 * @param {import("node:http").Server} server
 * @param {{
 *   program: object,
 *   path?: string,
 *   flags?: (context: { request: import("node:http").IncomingMessage, page: unknown }) => unknown,
 *   authorize?: (context: { request: import("node:http").IncomingMessage, csrfToken: string | undefined }) => boolean | Promise<boolean>,
 *   origins?: string[],
 *   ports?: { toJorn?: string, fromJorn?: string },
 *   heartbeat?: number,
 *   linger?: number,
 *   replay?: number,
 *   maxSessions?: number,
 *   maxMessagesPerSecond?: number,
 *   maxPayload?: number,
 *   snapshots?: { get: (id: string) => unknown, set: (id: string, model: string) => unknown, delete: (id: string) => unknown },
 *   log?: Pick<Console, "warn" | "error"> & Partial<Pick<Console, "info">>,
 * }} options
 * @returns {{ readonly sessions: number, close: () => Promise<void> }}
 */
export function attach(
  server,
  {
    program,
    path = "/",
    flags,
    authorize,
    origins = [],
    ports,
    heartbeat = 30_000,
    linger = 30_000,
    replay = 256,
    maxSessions = Infinity,
    maxMessagesPerSecond = 100,
    maxPayload = 1 << 20,
    snapshots,
    log = console,
  } = {},
) {
  if (!program || typeof program.init !== "function") {
    throw new TypeError("Jorn: attach needs a compiled program, like Elm.Main");
  }
  const sockets = new WebSocketServer({ noServer: true, maxPayload });
  const allowed = new Set(origins);
  const live = new Map(); // session id -> Session, connected or waiting for its page
  const info = (line) => log.info?.(line);
  let counter = 0;

  // A saved session's model, or undefined. A store that fails means starting
  // over, not turning the page away.
  async function recall(id) {
    if (!snapshots) return undefined;
    try {
      const saved = await snapshots.get(id);
      return saved == null ? undefined : JSON.parse(saved);
    } catch (error) {
      log.warn(`Jorn: couldn't read a saved session: ${error?.message ?? error}`);
      return undefined;
    }
  }

  async function forget(id) {
    try {
      await snapshots.delete(id);
    } catch (error) {
      log.warn(`Jorn: couldn't delete a saved session: ${error?.message ?? error}`);
    }
  }

  // Each resumable session's model, under the id its page will come back with.
  async function save() {
    let count = 0;
    await Promise.all(
      [...live.values()].map(async (current) => {
        try {
          const model = await within(1000, current.program?.snapshot());
          if (model === undefined) return;
          await snapshots.set(current.id, JSON.stringify(model));
          count++;
        } catch (error) {
          log.warn(`Jorn: couldn't save ${current.name}: ${error?.message ?? error}`);
        }
      }),
    );
    if (count) info(`Jorn: saved ${count} session${count === 1 ? "" : "s"} for pages to pick up after the restart`);
  }

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

  // Dead connections don't always say so. Browsers answer pings on their
  // own, so a socket that missed one is gone.
  const pulse = setInterval(() => {
    for (const socket of sockets.clients) {
      if (socket.missedPing) {
        socket.reason = "it stopped answering";
        socket.terminate();
      } else {
        socket.missedPing = true;
        socket.ping();
      }
    }
  }, heartbeat);
  pulse.unref?.();

  // One running program and the page it's drawing, if any. Its id is the
  // page's key to it when it reconnects, so it's random and never logged.
  class Session {
    constructor(socket) {
      this.id = randomUUID();
      this.name = `session ${++counter}`;
      this.socket = socket;
      this.seq = 0;
      this.sent = []; // The last `replay` messages, for a page that reconnects.
      this.expiry = null;
      this.program = null;
      live.set(this.id, this);
    }

    send(message) {
      const text = JSON.stringify({ seq: ++this.seq, ...message });
      this.sent.push({ seq: this.seq, text });
      if (this.sent.length > replay) this.sent.shift();
      if (this.socket?.readyState === this.socket?.OPEN) this.socket.send(text);
    }

    resume(socket, seen) {
      if (this.socket) {
        // The page reconnected before its old socket noticed it was dead.
        this.socket.reason = "the page reconnected";
        this.socket.terminate();
      }
      clearTimeout(this.expiry);
      this.socket = socket;
      const missed = this.sent.filter((message) => message.seq > seen);
      const replayable = Number.isInteger(seen) && seen <= this.seq && (seen === this.seq || missed[0]?.seq === seen + 1);
      info(`Jorn: ${this.name} resumed${replayable ? `, ${missed.length} messages behind` : ", too far behind to catch up, so it gets the whole view"}`);
      if (replayable) for (const message of missed) socket.send(message.text);
      else this.program.receive({ remount: true });
    }

    // The page's socket closed. Wait for it to come back, unless it said goodbye.
    detach(socket, code) {
      if (this.socket !== socket) return;
      this.socket = null;
      if (code === 1000 || code === 1001 || socket.refused || linger <= 0) {
        this.end(socket.reason ?? "the page closed");
      } else {
        info(`Jorn: ${this.name} lost its page (${socket.reason ?? `code ${code}`}), waiting ${linger} ms for it to come back`);
        this.expiry = setTimeout(() => this.end("the page didn't come back"), linger);
      }
    }

    end(reason) {
      clearTimeout(this.expiry);
      this.socket = null; // So its socket closing later doesn't wait for a page.
      live.delete(this.id);
      this.program?.close();
      info(`Jorn: ${this.name} ended: ${reason}`);
    }
  }

  sockets.on("connection", (socket, request) => {
    let current = null;
    let joined = false;
    // A token bucket: bursts of up to twice the rate are fine.
    let tokens = 2 * maxMessagesPerSecond;
    let lastRefill = performance.now();

    // Turned away on purpose, so there's nothing to wait for.
    function refuse(code, reason) {
      socket.reason = reason;
      socket.refused = true;
      socket.close(code, reason);
    }

    socket.on("pong", () => (socket.missedPing = false));

    socket.on("message", async (data, isBinary) => {
      socket.missedPing = false;
      const now = performance.now();
      tokens = Math.min(2 * maxMessagesPerSecond, tokens + ((now - lastRefill) * maxMessagesPerSecond) / 1000);
      lastRefill = now;
      if (tokens < 1) {
        log.warn(`Jorn: ${current?.name ?? "a page"} sent more than ${maxMessagesPerSecond} messages a second`);
        refuse(1008, "Too many messages");
        return;
      }
      tokens -= 1;

      let message;
      try {
        message = JSON.parse(isBinary ? Buffer.from(data).toString() : data.toString());
      } catch {
        refuse(1007, "Messages must be JSON");
        return;
      }

      if (joined) {
        if (message?.ping === true) socket.send(JSON.stringify({ pong: true }));
        else current?.program?.receive(message);
        return;
      }
      // The first message says which protocol the page speaks, carries its
      // flags, and names its session if it's coming back to one.
      const join = message?.join;
      if (join?.protocol !== PROTOCOL) {
        refuse(1002, `Expected a join for protocol ${PROTOCOL}`);
        return;
      }
      joined = true;
      try {
        const csrfToken = typeof join.csrfToken === "string" ? join.csrfToken : undefined;
        if (authorize && !(await authorize({ request, csrfToken }))) {
          refuse(1008, "Not allowed");
          return;
        }
        if (socket.readyState !== socket.OPEN) return;

        const known = typeof join.session === "string" ? live.get(join.session) : undefined;
        if (known) {
          current = known;
          known.resume(socket, join.seen);
          return;
        }
        if (live.size >= maxSessions) {
          log.warn(`Jorn: turned a page away, ${maxSessions} sessions is the most allowed`);
          refuse(1013, "Too many sessions");
          return;
        }

        // A page from before a restart can pick up the model its session had.
        const saved = typeof join.session === "string" ? await recall(join.session) : undefined;
        if (socket.readyState !== socket.OPEN) return;
        const value = flags ? await flags({ request, page: join.flags }) : undefined;
        if (socket.readyState !== socket.OPEN) return;
        // A page coming back to a session that's gone gets a new one, and a
        // fresh mount replaces whatever it was showing.
        current = new Session(socket);
        current.send({ session: current.id });
        try {
          current.program = session(program, { flags: value, restore: saved, ports, log, send: (out) => current.send(out) });
        } catch (error) {
          live.delete(current.id);
          current = null;
          throw error;
        }
        if (saved !== undefined) await forget(join.session);
        info(
          `Jorn: ${current.name} started${saved !== undefined ? " from a session saved before a restart" : join.session ? ", in place of one that had ended" : ""}`,
        );
      } catch (error) {
        log.error(`Jorn: couldn't start a session: ${error?.message ?? error}`);
        refuse(1011, "The session couldn't start");
      }
    });

    socket.on("close", (code) => current?.detach(socket, code));
    socket.on("error", (error) => log.warn(`Jorn: ${error.message}`));
  });

  return {
    /** How many sessions are running, counting ones waiting for their page to come back. */
    get sessions() {
      return live.size;
    },

    /**
     * Stop accepting pages, and end every session. With `snapshots`, each
     * resumable session's model is saved first.
     */
    async close() {
      server.off("upgrade", upgrade);
      clearInterval(pulse);
      if (snapshots) await save();
      for (const current of [...live.values()]) current.end("the server is closing");
      for (const socket of sockets.clients) socket.terminate();
      return new Promise((resolve) => sockets.close(() => resolve()));
    },
  };
}

// A promise's value, or undefined if it takes longer than `ms`.
function within(ms, promise) {
  let timer;
  return Promise.race([promise, new Promise((resolve) => (timer = setTimeout(resolve, ms)))]).finally(() => clearTimeout(timer));
}

function sameOrigin(origin, request) {
  try {
    return new URL(origin).host === request.headers.host;
  } catch {
    return false;
  }
}
