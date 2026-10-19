// Tests for keeping sessions across a restart: a server closes with pages
// open, a new one starts with the same snapshot store, and the pages, in
// jsdom, pick up where they were, or start over when the saved model can't
// be read.
//
// Usage: node server/test/deploy.mjs
// Build first, in client/test/elm:
//   elm make src/RuntimeSpec.elm --output=build/runtime.js
//   elm make src/ResumableSpec.elm --output=build/resumable.js

import { JSDOM } from "jsdom";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { start, stream } from "../../client/jorn.js";
import { attach, session } from "../jorn.js";

const require = createRequire(import.meta.url);
const { Elm: Runtime } = require("../../client/test/elm/build/runtime.js");
const { Elm } = require("../../client/test/elm/build/resumable.js");

let failed = 0;
function check(condition, what, detail = {}) {
  if (!condition) {
    failed++;
    console.log(`FAILED: ${what}`, JSON.stringify(detail));
  }
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function until(condition, what, ms = 5000) {
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
const origin = `http://127.0.0.1:${server.address().port}`;

// The store outlives each server, as a file or a database would outlive a
// process.
const snapshots = new Map();
const serve = () => attach(server, { program: Elm.ResumableSpec, path: "/app", flags: ({ page }) => page, snapshots, heartbeat: 100, log });

function page({ flags = 3 } = {}) {
  const { window } = new JSDOM("<!doctype html><html><body><div id=app></div></body></html>", { url: `${origin}/` });
  const { document } = window;
  const container = document.getElementById("app");
  const app = stream(container, "/app", { flags, heartbeat: 100 });
  const $ = (id) => document.getElementById(id);
  const click = (id) => $(id).dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
  const type = (id, text) => {
    $(id).value = text;
    $(id).dispatchEvent(new window.Event("input", { bubbles: true }));
  };
  const status = () => container.getAttribute("data-jorn-connection");
  return { window, $, click, type, status, app };
}

// ---- A restart keeps what the page had --------------------------------------------

{
  const before = serve();
  const p = page();
  await until(() => p.$("increment")?.textContent === "3" && p.$("log").textContent === "started", "a resumable app starts like any other");
  p.click("increment");
  p.click("increment");
  p.type("field", "Ada");
  await until(() => p.$("increment").textContent === "5" && p.$("name").textContent === "Ada", "clicks and typing");

  const button = p.$("increment");
  await before.close();
  await until(() => p.status() === "reconnecting", "the page notices the server went away");
  check(snapshots.size === 1, "closing saves the session", { size: snapshots.size });
  await wait(20);
  check(!lines.some((line) => line.includes("lost its page")), "and ends it, without waiting for its page", { lines });
  check(lines.some((line) => line.includes("saved 1 session for pages to pick up after the restart")), "and says so", { lines });
  check(!JSON.stringify([...snapshots]).includes("undefined"), "as JSON", { snapshots: [...snapshots] });

  const after = serve();
  await until(() => p.$("increment") !== button, "the page comes back to the new server, and gets a new mount");
  await wait(50); // Long enough for init's effects to show, if they ran.
  check(p.$("increment").textContent === "5", "with the count it had", { count: p.$("increment").textContent });
  check(p.$("log").textContent === "started", "and init didn't run again, effects and all", { log: p.$("log").textContent });
  check(p.$("name")?.textContent === "Ada", "and the name it had", { name: p.$("name")?.textContent });
  check(lines.some((line) => line.includes("started from a session saved before a restart")), "the log says it was restored", { lines });
  check(snapshots.size === 0, "a saved session is used once", { size: snapshots.size });
  p.click("increment");
  await until(() => p.$("increment").textContent === "6", "and it carries on");

  p.app.close();
  p.window.close();
  await until(() => after.sessions === 0, "a page that closes on purpose ends its session");
  await after.close();
  check(snapshots.size === 0, "so there's nothing to save", { size: snapshots.size });
}

// ---- A model the new version can't read starts over ----------------------------------

{
  lines.length = 0;
  const before = serve();
  const p = page({ flags: 7 });
  await until(() => p.$("increment")?.textContent === "7", "mounts");
  p.click("increment");
  await until(() => p.$("increment").textContent === "8", "a click");
  await before.close();
  check(snapshots.size === 1, "saved", { size: snapshots.size });
  // As if the model had changed shape between versions.
  const [id] = snapshots.keys();
  snapshots.set(id, JSON.stringify({ count: "eight", secret: "hunter2" }));

  const after = serve();
  await until(() => p.status() === "open" && p.$("increment")?.textContent === "7" && p.$("log")?.textContent === "started", "the page starts over from init");
  const warning = lines.find((line) => line.includes("Couldn't read the saved session"));
  check(warning?.includes("so it started over. At .count: Expecting an INT"), "and the log says where the decoder failed", { lines });
  check(!warning?.includes("hunter2"), "without the saved model, which could be private", { warning });
  check(snapshots.size === 0, "the unreadable model is gone", { size: snapshots.size });
  p.app.close();
  p.window.close();
  await after.close();
}

// ---- A store that fails doesn't keep pages out ------------------------------------------

{
  lines.length = 0;
  const broken = { get: () => Promise.reject(new Error("store is down")), set: () => Promise.reject(new Error("store is down")), delete: () => {} };
  const before = attach(server, { program: Elm.ResumableSpec, path: "/broken", flags: () => 2, snapshots: broken, heartbeat: 100, log });
  const { window } = new JSDOM("<!doctype html><html><body><div id=app></div></body></html>", { url: `${origin}/` });
  const container = window.document.getElementById("app");
  const app = stream(container, "/broken", { heartbeat: 100 });
  await until(() => window.document.getElementById("increment")?.textContent === "2", "mounts");
  await before.close();
  await until(() => container.getAttribute("data-jorn-connection") === "reconnecting", "the page notices the server went away");
  check(lines.some((line) => line.includes("couldn't save session") && line.includes("store is down")), "a failed save is logged", { lines });
  const after = attach(server, { program: Elm.ResumableSpec, path: "/broken", flags: () => 2, snapshots: broken, heartbeat: 100, log });
  await until(() => lines.some((line) => line.includes("couldn't read a saved session: store is down")), "a failed read is logged");
  await until(() => after.sessions === 1 && window.document.getElementById("increment")?.textContent === "2", "and the page starts over");
  app.close();
  window.close();
  await after.close();
}

// ---- session() on its own ----------------------------------------------------------

{
  const sent = [];
  const resumed = session(Elm.ResumableSpec, { send: (message) => sent.push(message), flags: 1, restore: { count: 9, name: "Grace", log: ["started"] }, log });
  await until(() => sent.some((message) => message.mount), "a restored session mounts");
  const mount = JSON.stringify(sent.find((message) => message.mount));
  check(mount.includes('"9"') && mount.includes("Grace"), "with the saved model", { mount });
  check((await resumed.snapshot())?.count === 9, "snapshot gives the model back", {});
  resumed.receive({ event: { path: [0], name: "click", event: {} } });
  check((await resumed.snapshot())?.count === 10, "as it is now", {});
  resumed.close();
  check((await resumed.snapshot()) === undefined, "and nothing once closed");

  const plain = session(Runtime.RuntimeSpec, { send: () => {}, flags: 1, restore: { count: 9 }, log });
  await wait(20);
  check((await plain.snapshot()) === undefined, "a program that isn't resumable has no snapshot");
  check(lines.some((line) => line.includes("the program isn't Jorn.resumable, so a saved session started over")), "and a saved session for it starts over", { lines });
  plain.close();
}

// ---- In the page ----------------------------------------------------------------

{
  const { window } = new JSDOM("<!doctype html><html><body><div id=app></div></body></html>");
  const container = window.document.getElementById("app");
  const app = start(Elm.ResumableSpec, container, { flags: 4 });
  await until(() => window.document.getElementById("increment")?.textContent === "4" && window.document.getElementById("log").textContent === "started", "in client mode a resumable app starts fresh, and runs init's effects");
  app.shutdown();
  window.close();
}

await new Promise((resolve) => server.close(resolve));

if (failed) {
  console.log(`FAILED: ${failed} problems`);
  process.exit(1);
}
console.log("PASSED: resumable sessions survive a restart, start over when their model can't be read, and survive a broken store.");
