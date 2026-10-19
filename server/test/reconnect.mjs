// Tests for what happens when connections go wrong: pages in jsdom stream a
// program through a TCP proxy that the test can silence or cut, so sockets
// die the way they do on real networks, including halfway through a patch.
//
// Usage: node server/test/reconnect.mjs
// Build first: cd client/test/elm && elm make src/RuntimeSpec.elm --output=build/runtime.js

import { JSDOM } from "jsdom";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import net from "node:net";
import { WebSocket } from "ws";
import { stream } from "../../client/jorn.js";
import { attach } from "../jorn.js";

const require = createRequire(import.meta.url);
const { Elm } = require("../../client/test/elm/build/runtime.js");

let failed = 0;
function check(condition, what, detail = {}) {
  if (!condition) {
    failed++;
    console.log(`FAILED: ${what}`, JSON.stringify(detail));
  }
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function until(condition, what, ms = 3000) {
  const end = Date.now() + ms;
  while (!condition()) {
    if (Date.now() > end) {
      check(false, `timed out: ${what}`);
      return false;
    }
    await wait(5);
  }
  return true;
}

const lines = [];
const log = { info: (line) => lines.push(line), warn: (line) => lines.push(line), error: (line) => lines.push(line) };

const server = createServer((request, response) => response.writeHead(404).end());
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;

// Fast settings, so the test doesn't wait on production timeouts.
const common = { program: Elm.RuntimeSpec, flags: ({ page }) => page, heartbeat: 100, log };
const app = attach(server, { ...common, path: "/app" });
const short = attach(server, { ...common, path: "/short", replay: 1 });
const brief = attach(server, { ...common, path: "/brief", linger: 50 });
const limited = attach(server, { ...common, path: "/limited", maxSessions: 1, maxMessagesPerSecond: 50 });
const patient = attach(server, { ...common, path: "/patient", heartbeat: 60_000 });
const closing = attach(server, { ...common, path: "/closing" });

// A TCP proxy between the pages and the server. `silence` stops bytes in
// one or both directions without closing anything, `cut` kills every
// connection, and `refuse` turns new ones away.
function proxy() {
  const pairs = new Set();
  let refusing = false;
  const relay = net.createServer((page) => {
    if (refusing) {
      page.destroy();
      return;
    }
    const upstream = net.connect(port, "127.0.0.1");
    const pair = { page, upstream, up: true, down: true };
    pairs.add(pair);
    page.on("data", (data) => pair.up && upstream.write(data));
    upstream.on("data", (data) => pair.down && page.write(data));
    const end = () => {
      page.destroy();
      upstream.destroy();
      pairs.delete(pair);
    };
    for (const socket of [page, upstream]) {
      socket.on("close", end);
      socket.on("error", end);
    }
  });
  return {
    listen: () => new Promise((resolve) => relay.listen(0, "127.0.0.1", resolve)),
    get origin() {
      return `http://127.0.0.1:${relay.address().port}`;
    },
    silence({ up = true, down = true } = {}) {
      for (const pair of pairs) {
        if (up) pair.up = false;
        if (down) pair.down = false;
      }
    },
    cut() {
      for (const pair of [...pairs]) {
        pair.page.destroy();
        pair.upstream.destroy();
      }
    },
    set refusing(value) {
      refusing = value;
    },
    close: () => new Promise((resolve) => relay.close(resolve)),
  };
}

const network = proxy();
await network.listen();

function page(path, { flags = 3, heartbeat = 100 } = {}) {
  const { window } = new JSDOM("<!doctype html><html><body><div id=app></div></body></html>", { url: `${network.origin}/` });
  const { document } = window;
  const container = document.getElementById("app");
  const app = stream(container, path, { flags, heartbeat });
  const $ = (id) => document.getElementById(id);
  const click = (id) => $(id).dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
  const status = () => container.getAttribute("data-jorn-connection");
  return { window, document, container, app, $, click, status };
}

// ---- A dropped connection resumes the session and replays what it missed ----

{
  const p = page("/app");
  await until(() => p.$("increment")?.textContent === "3", "mounts");
  check(p.status() === "open", "says it's open", { status: p.status() });
  p.click("increment");
  await until(() => p.$("increment").textContent === "4", "a click");
  const button = p.$("increment");

  // The patch for this click never arrives, then the connection dies.
  network.silence({ up: false });
  p.click("increment");
  await wait(40);
  check(p.$("increment").textContent === "4", "the patch is lost in transit");
  network.cut();
  await until(() => p.status() === "reconnecting", "notices the drop");
  await until(() => p.$("increment").textContent === "5", "the missed patch is replayed after reconnecting");
  check(p.$("increment") === button, "replaying keeps the page's DOM nodes");
  check(p.status() === "open", "open again", { status: p.status() });
  check(app.sessions === 1, "still one session", { sessions: app.sessions });
  check(lines.some((line) => /session \d+ resumed, 1 messages behind/.test(line)), "the log says it resumed", { lines });

  p.click("increment");
  await until(() => p.$("increment").textContent === "6", "and it keeps working");
  p.app.close();
  await until(() => app.sessions === 0, "closing on purpose ends the session straight away");
  p.window.close();
}

// ---- Too far behind to replay: the whole view comes again ---------------------

{
  const p = page("/short");
  await until(() => p.$("increment")?.textContent === "3", "mounts");
  const button = p.$("increment");
  network.silence({ up: false });
  for (let i = 0; i < 3; i++) {
    p.click("increment");
    await wait(30); // One render each.
  }
  network.cut();
  await until(() => p.$("increment")?.textContent === "6", "a page too far behind gets the whole view");
  check(p.$("increment") !== button, "by mounting it again");
  check(lines.some((line) => line.includes("too far behind to catch up")), "the log says why", { lines });
  p.click("increment");
  await until(() => p.$("increment").textContent === "7", "and it keeps working");
  p.app.close();
  p.window.close();
}

// ---- A session that ended starts over ---------------------------------------------

{
  const p = page("/brief");
  await until(() => p.$("increment")?.textContent === "3", "mounts");
  p.click("increment");
  await until(() => p.$("increment").textContent === "4", "a click");
  network.refusing = true;
  network.cut();
  await until(() => brief.sessions === 0, "a session whose page doesn't come back ends");
  check(lines.some((line) => line.includes("ended: the page didn't come back")), "and says so", { lines });
  network.refusing = false;
  await until(() => p.$("increment")?.textContent === "3" && p.status() === "open", "the page gets a fresh session, never a stale one");
  check(lines.some((line) => line.includes("in place of one that had ended")), "the log says it replaced one", { lines });
  p.click("increment");
  await until(() => p.$("increment").textContent === "4", "and the fresh session works");
  p.app.close();
  p.window.close();
}

// ---- Heartbeats find connections that die silently -------------------------------

{
  // The server pings and notices. The page wouldn't for a minute.
  const p = page("/app", { heartbeat: 60_000 });
  await until(() => p.$("increment")?.textContent === "3", "mounts");
  p.click("increment");
  await until(() => p.$("increment").textContent === "4", "a click");
  network.silence(); // Nothing gets through, and nothing closes.
  await until(() => lines.some((line) => line.includes("(it stopped answering)")), "the server notices a page that stopped answering pings");
  await until(() => p.status() === "open" && p.$("increment").textContent === "4", "the page comes back");
  p.click("increment");
  await until(() => p.$("increment").textContent === "5", "to the same session");
  p.app.close();
  p.window.close();
}

{
  // The page pings and notices. The server wouldn't for a minute.
  const p = page("/patient");
  await until(() => p.$("increment")?.textContent === "3", "mounts");
  p.click("increment");
  await until(() => p.$("increment").textContent === "4", "a click");
  network.silence();
  await until(() => p.status() === "reconnecting", "the page notices a server that stopped answering");
  await until(() => p.status() === "open", "and reconnects");
  p.click("increment");
  await until(() => p.$("increment").textContent === "5", "to the same session");
  check(patient.sessions === 1, "one session, taken over from the dead socket", { sessions: patient.sessions });
  p.app.close();
  p.window.close();
}

// ---- A page that loses track asks for the whole view -------------------------------

{
  const p = page("/app");
  await until(() => p.$("increment")?.textContent === "3", "mounts");
  const warnings = [];
  const warn = console.warn;
  console.warn = (line) => warnings.push(line);
  p.$("increment").firstChild.remove(); // Something else changed the page.
  p.click("increment");
  await until(() => p.$("increment")?.textContent === "4", "a patch that doesn't fit gets the whole view instead");
  console.warn = warn;
  check(warnings.some((line) => line.includes("Asking the server for the whole view")), "and says so", { warnings });
  p.click("increment");
  await until(() => p.$("increment").textContent === "5", "and it keeps working");
  p.app.close();
  p.window.close();
}

// ---- Closing the server ----------------------------------------------------------

{
  const p = page("/closing");
  await until(() => p.$("increment")?.textContent === "3", "mounts");
  const mark = lines.length;
  await closing.close();
  await until(() => p.status() === "reconnecting", "the page notices the server closed");
  check(closing.sessions === 0, "closing ends every session", { sessions: closing.sessions });
  check(!lines.slice(mark).some((line) => line.includes("lost its page")), "without waiting for their pages to come back", { lines: lines.slice(mark) });
  p.app.close();
  p.window.close();
}

// ---- Limits ----------------------------------------------------------------------

function closed(socket) {
  return new Promise((resolve) => {
    socket.on("close", (code) => resolve(code));
    socket.on("error", () => {});
  });
}

{
  const first = new WebSocket(`ws://127.0.0.1:${port}/limited`);
  await new Promise((resolve) => first.on("open", resolve));
  first.send(JSON.stringify({ join: { protocol: 0, flags: 1 } }));
  await until(() => limited.sessions === 1, "the first session starts");

  const second = new WebSocket(`ws://127.0.0.1:${port}/limited`);
  second.on("open", () => second.send(JSON.stringify({ join: { protocol: 0, flags: 1 } })));
  check((await closed(second)) === 1013, "past maxSessions, a page is told to try later");

  const flooded = closed(first);
  for (let i = 0; i < 500; i++) first.send(JSON.stringify({ painted: true }));
  check((await flooded) === 1008, "a page sending too fast is closed");
  check(lines.some((line) => line.includes("more than 50 messages a second")), "and the log says why", { lines });
  await until(() => limited.sessions === 0, "and its session is gone after the page");
}

await Promise.all([app.close(), short.close(), brief.close(), limited.close(), patient.close()]);
await network.close();
await new Promise((resolve) => server.close(resolve));

if (failed) {
  console.log(`FAILED: ${failed} problems`);
  process.exit(1);
}
console.log("PASSED: pages resume their sessions after drops, catch up or remount, start over when a session is gone, and limits hold.");
