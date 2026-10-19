// Tests for the server runtime (server/jorn.js): a session on its own, then
// pages in jsdom streaming a program from a real server over real sockets.
//
// Usage: node server/test/run.mjs
// Build first: cd client/test/elm && elm make src/RuntimeSpec.elm --output=build/runtime.js

import { JSDOM } from "jsdom";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { WebSocket } from "ws";
import { defineServerComponent, stream } from "../../client/jorn.js";
import { attach, session } from "../jorn.js";

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

// Waits for something that happens over a socket, without guessing how long.
async function until(condition, what, ms = 2000) {
  const end = Date.now() + ms;
  while (!condition()) {
    if (Date.now() > end) {
      check(false, `timed out: ${what}`);
      return;
    }
    await wait(5);
  }
}

function quietLog() {
  const lines = [];
  return { lines, warn: (line) => lines.push(line), error: (line) => lines.push(line) };
}

// ---- A session on its own ---------------------------------------------------

{
  const sent = [];
  const log = quietLog();
  const s = session(Elm.RuntimeSpec, { flags: 5, send: (message) => sent.push(message), log });
  await wait(1);
  check(sent.length === 1 && sent[0].mount?.children?.[0]?.children?.[0]?.text === "5", "mounts with the flags", { sent });

  const click = (path) => s.receive({ event: { path, name: "click", event: {} } });
  sent.length = 0;
  click([0]);
  click([0]);
  click([0]);
  await until(() => sent.length > 0, "patches after three clicks");
  await wait(40);
  check(sent.length === 1, "three events, one patch message", { sent });
  check(JSON.stringify(sent[0]?.patches) === '[{"op":"set-text","path":[0,0],"text":"8"}]', "the patch sets the count", { sent });
  check(sent.every((message) => !("frame" in message) && !("error" in message)), "frames and errors stay on the server", { sent });

  // Effects: instructions go to the page with their patches, and afterPaint
  // waits for the page to say it painted.
  sent.length = 0;
  click([1]);
  await until(() => sent.length > 0, "patches after Open");
  const opened = sent[0];
  check(JSON.stringify(opened?.instructions?.map((instruction) => instruction.effect)) === '["focus","event","client"]', "instructions in order", { opened });
  check(opened?.painted === true, "asks the page to say when it painted", { opened });
  await wait(40);
  const logText = () => JSON.stringify(sent.at(-1)?.patches ?? []);
  check(!logText().includes("painted"), "afterPaint waits for the page", { sent });
  s.receive({ painted: true });
  await until(() => logText().includes("painted"), "afterPaint after the page painted");
  check(logText().includes("before") && logText().includes("task"), "beforePaint and commands ran", { sent });

  // The page only gets to send events and paint confirmations.
  s.receive({ shutdown: true });
  s.receive({ frame: true });
  s.receive("nonsense");
  s.receive(null);
  sent.length = 0;
  click([0]);
  await until(() => sent.length > 0, "still running after a page sent shutdown");

  // A bad event is logged on the server and goes nowhere else.
  sent.length = 0;
  click([9]);
  await wait(40);
  check(sent.length === 0, "nothing goes to the page for a bad event", { sent });
  check(log.lines.some((line) => line.includes("No node at path [9]")), "the bad event is logged", { lines: log.lines });

  s.close();
  click([0]);
  await wait(40);
  check(sent.length === 0, "a closed session ignores the page", { sent });
  s.close();
  check(true, "a second close is harmless");

  let threw = false;
  try {
    session(Elm.RuntimeSpec, { flags: "five", send: () => {} });
  } catch {
    threw = true;
  }
  check(threw, "bad flags stop the session from starting");
}

// ---- Pages streaming from a server ----------------------------------------------

const log = quietLog();
const server = createServer((request, response) => response.writeHead(404).end());
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;
const origin = `http://127.0.0.1:${port}`;

const app = attach(server, { path: "/app", program: Elm.RuntimeSpec, flags: ({ page }) => page, log });
const guarded = attach(server, {
  path: "/guarded",
  program: Elm.RuntimeSpec,
  flags: () => 1,
  authorize: ({ csrfToken }) => csrfToken === "secret",
  log,
});
const broken = attach(server, {
  path: "/broken",
  program: Elm.RuntimeSpec,
  flags: () => {
    throw new Error("no database");
  },
  log,
});

{
  const { window } = new JSDOM("<!doctype html><html><body></body></html>", { url: `${origin}/` });
  const { document } = window;
  const container = document.createElement("div");
  document.body.appendChild(container);
  const $ = (id) => document.getElementById(id);
  const recorded = [];
  const opened = [];
  document.body.addEventListener("opened", (event) => opened.push(event.detail));

  const page = stream(container, "/app", { flags: 3, effects: { record: (payload) => recorded.push(payload) } });
  await until(() => $("increment")?.textContent === "3", "mounts with the page's flags");
  check(app.sessions === 1, "one session per page", { sessions: app.sessions });

  const click = (id) => $(id).dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
  click("increment");
  click("increment");
  click("increment");
  await until(() => $("increment").textContent === "6", "events go to the server and patches come back");

  click("open");
  await until(() => $("log").textContent.includes("painted"), "afterPaint over the socket");
  check(document.activeElement === $("field"), "focus runs after the patch that created the element");
  check(JSON.stringify(opened) === "[6]", "custom event from the container", { opened });
  check(JSON.stringify(recorded) === '["opened"]', "named client effect runs in the page", { recorded });
  check(["before", "painted", "task"].every((entry) => $("log").textContent.includes(entry)), "every kind of effect", { log: $("log").textContent });

  // In server mode the event carries only the fields the handler asked for.
  $("field").value = "Jorn";
  $("field").dispatchEvent(new window.Event("input", { bubbles: true }));
  await until(() => $("name").textContent === "Jorn", "input reaches its handler with target.value");

  // A second page gets a session of its own.
  const other = new JSDOM("<!doctype html><html><body><div id=app></div></body></html>", { url: `${origin}/` });
  const otherPage = stream(other.window.document.getElementById("app"), "/app", { flags: 10 });
  await until(() => other.window.document.getElementById("increment")?.textContent === "10", "a second page");
  check($("increment").textContent === "6", "sessions don't share state");
  check(app.sessions === 2, "two sessions", { sessions: app.sessions });

  page.close();
  check(container.childNodes.length === 0, "close empties the container");
  await until(() => app.sessions === 1, "closing a page ends its session");
  otherPage.close();
  await until(() => app.sessions === 0, "every session ends");
  window.close();
  other.window.close();
}

// ---- <jorn-server-component> ----------------------------------------------------

{
  const { window } = new JSDOM(
    `<!doctype html><html><body>
      <div id=outer><jorn-server-component id=one route="/app" flags="4"></jorn-server-component></div>
      <div id=elsewhere></div>
    </body></html>`,
    { url: `${origin}/` },
  );
  const { document } = window;
  const recorded = [];
  const opened = [];
  document.addEventListener("opened", (event) => opened.push(event.detail));
  defineServerComponent({ window, effects: { record: (payload) => recorded.push(payload) } });
  defineServerComponent({ window });
  check(true, "defining twice is harmless");

  const host = document.getElementById("one");
  const $ = (id) => host.querySelector(`#${id}`);
  await until(() => $("increment")?.textContent === "4", "the element streams its route with its flags");
  $("increment").dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
  await until(() => $("increment").textContent === "5", "events from inside the element");

  $("open").dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
  await until(() => opened.length === 1, "Effect.event bubbles out of the element");
  check(JSON.stringify(opened) === "[5]" && JSON.stringify(recorded) === '["opened"]', "and the defined effects run", { opened, recorded });

  // Moved by removing and adding back, as a keyed list without moveBefore
  // does: still the same session.
  const sessions = app.sessions;
  document.getElementById("elsewhere").appendChild(host);
  await wait(50);
  check(app.sessions === sessions && $("increment")?.textContent === "5", "moving the element keeps its session", { sessions: app.sessions });

  host.remove();
  await until(() => app.sessions === sessions - 1, "removing the element ends its session");

  // An element made later, the way a Jorn app makes it.
  const later = document.createElement("jorn-server-component");
  later.setAttribute("route", "/guarded");
  later.setAttribute("csrf-token", "secret");
  document.body.appendChild(later);
  await until(() => later.querySelector("#increment")?.textContent === "1", "the csrf token reaches authorize");
  later.remove();
  window.close();
}

// ---- Refusals ----------------------------------------------------------------------

function connectRaw(path, options = {}) {
  return new WebSocket(`ws://127.0.0.1:${port}${path}`, options);
}

function closed(socket) {
  return new Promise((resolve) => {
    socket.on("close", (code, reason) => resolve({ code, reason: reason.toString() }));
    socket.on("error", () => {});
    socket.on("unexpected-response", (request, response) => resolve({ status: response.statusCode }));
  });
}

{
  const evil = connectRaw("/app", { origin: "https://evil.example" });
  check((await closed(evil)).status === 403, "a page from another site is refused");

  const old = connectRaw("/app", { origin });
  old.on("open", () => old.send(JSON.stringify({ join: { protocol: 99 } })));
  check((await closed(old)).code === 1002, "a page speaking another protocol is turned away");

  const garbled = connectRaw("/app");
  garbled.on("open", () => garbled.send("not json"));
  check((await closed(garbled)).code === 1007, "a message that isn't JSON closes the socket");

  const forged = connectRaw("/guarded");
  forged.on("open", () => forged.send(JSON.stringify({ join: { protocol: 0, csrfToken: "guess" } })));
  check((await closed(forged)).code === 1008, "a page authorize turns down is closed");

  const failing = connectRaw("/broken");
  failing.on("open", () => failing.send(JSON.stringify({ join: { protocol: 0 } })));
  check((await closed(failing)).code === 1011, "a session that can't start closes the socket");
  check(log.lines.some((line) => line.includes("no database")), "and says why in the log", { lines: log.lines });

  // Not every socket on the server is Jorn's.
  const others = [];
  server.on("upgrade", (request, socket) => request.url === "/elsewhere" && others.push(socket));
  const elsewhere = connectRaw("/elsewhere");
  const timeout = wait(200).then(() => "still waiting");
  const outcome = await Promise.race([closed(elsewhere), timeout]);
  check(outcome === "still waiting", "upgrades on other paths are left alone", { outcome });
  elsewhere.terminate();
  for (const socket of others) socket.destroy();
}

await app.close();
await broken.close();
await guarded.close();
await new Promise((resolve) => server.close(resolve));

if (failed) {
  console.log(`FAILED: ${failed} problems`);
  process.exit(1);
}
console.log("PASSED: the server runs one program per page, batches renders, runs every kind of effect over the socket, and refuses what it should.");
