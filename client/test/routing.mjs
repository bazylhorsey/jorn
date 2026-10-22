// Tests for URL routing (Jorn.Navigation): a program made with
// Navigation.application in jsdom, clicking every kind of link and running
// every navigation effect. With `server`, the program runs on a server and
// the page streams it, and the same checks have to pass.
//
// Usage: node client/test/routing.mjs [server]
// Build first: cd client/test/elm && elm make src/RouterSpec.elm --output=build/router.js
// Server mode also needs `npm install` in server/.

import { JSDOM, VirtualConsole } from "jsdom";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { start, stream } from "../jorn.js";

const onServer = process.argv[2] === "server";

const require = createRequire(import.meta.url);
const { Elm } = require("./elm/build/router.js");

let failed = 0;
function check(condition, what, detail = {}) {
  if (!condition) {
    failed++;
    console.log(`FAILED: ${what}`, JSON.stringify(detail));
  }
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function until(condition, what, detail = () => ({}), ms = 2000) {
  const end = Date.now() + ms;
  while (!condition()) {
    if (Date.now() > end) {
      check(false, `timed out: ${what}`, detail());
      return;
    }
    await wait(5);
  }
}

let server = null;
let attached = null;
let origin = "https://example.test";
if (onServer) {
  const { attach } = await import("../../server/jorn.js");
  server = createServer((request, response) => response.writeHead(404).end());
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
  attached = attach(server, { path: "/socket", program: Elm.RouterSpec, log: { info() {}, warn: console.warn, error: console.error } });
}

// jsdom can't load other pages. It says so here, which is how the test sees
// that the page tried.
const navigations = [];
const virtualConsole = new VirtualConsole();
virtualConsole.on("jsdomError", (error) => navigations.push(error.message));

const { window } = new JSDOM("<!doctype html><html><head><title>Before</title></head><body><div id=app></div></body></html>", {
  url: `${origin}/start`,
  virtualConsole,
});
const { document } = window;
const $ = (id) => document.getElementById(id);
const text = (id) => $(id)?.textContent;
const log = () => text("log")?.split("|").filter(Boolean) ?? [];

function click(id, init = {}) {
  const event = new window.MouseEvent("click", { bubbles: true, cancelable: true, button: 0, ...init });
  $(id).dispatchEvent(event);
  return event;
}

const app = onServer ? stream($("app"), "/socket") : start(Elm.RouterSpec, $("app"));

// init gets the page's address, and the view sets the title.
await until(() => text("path") === "/start", "init gets the URL the page is at", () => ({ html: $("app").innerHTML }));
check(document.title === "Page /start", "the view sets the title", { title: document.title });
check(text("changes") === "0", "no change of address yet");

// An internal link becomes a message, and pushUrl moves the page without
// loading anything.
const entries = window.history.length;
const about = click("about-text");
check(about.defaultPrevented, "a click inside an internal link is taken over");
await until(() => text("path") === "/about", "pushUrl goes to the link's address", () => ({ path: text("path"), log: log() }));
check(log()[0] === `internal ${origin}/about`, "onUrlRequest gets it as Internal", { log: log() });
check(window.location.pathname === "/about" && window.history.length === entries + 1, "the browser's address and history follow", {
  href: window.location.href,
  length: window.history.length,
});
check(text("changes") === "1", "onUrlChange once");
await until(() => document.title === "Page /about", "the title follows the view", () => ({ title: document.title }));

// A relative link is resolved against the page, as the browser would.
click("relative");
await until(() => text("path") === "/items/7?sort=new", "a relative link", () => ({ path: text("path") }));

// An external link is handed to the program, which decides.
const external = click("external");
check(external.defaultPrevented, "an external link is taken over too");
await until(() => log().at(-1) === "external https://elsewhere.example/page", "onUrlRequest gets it as External", () => ({ log: log() }));
check(window.location.pathname === "/items/7", "and the page stays where it is");

// Clicks the browser wouldn't follow in this tab are left alone.
const before = log().length;
for (const [id, init, why] of [
  ["about", { ctrlKey: true }, "with a modifier key"],
  ["about", { button: 1 }, "with the middle button"],
  ["blank", {}, "with a target"],
  ["download", {}, "with download"],
  ["nested", {}, "inside a server component in the app"],
]) {
  check(!click(id, init).defaultPrevented, `a link ${why} is left to the browser`);
}
check(click("handled").defaultPrevented, "a link whose handler prevents the default");
await until(() => log().at(-1) === "clicked handled", "gets only its own message", () => ({ log: log() }));
check(log().length === before + 1, "and none of the others made a message", { log: log() });

// pushUrl with a relative address, then replaceUrl.
click("push");
await until(() => text("path") === "/items/7?page=2", "pushUrl with a query", () => ({ path: text("path") }));
const length = window.history.length;
click("replace");
await until(() => text("path") === "/replaced", "replaceUrl", () => ({ path: text("path") }));
check(window.history.length === length, "replaceUrl adds no history entry", { length: window.history.length });

// back and forward, and the browser's own back button.
click("back");
await until(() => text("path") === "/items/7?sort=new", "back", () => ({ path: text("path") }));
click("forward");
await until(() => text("path") === "/replaced", "forward", () => ({ path: text("path") }));
window.history.back();
await until(() => text("path") === "/items/7?sort=new", "the browser's back button", () => ({ path: text("path") }));
await until(() => document.title === "Page /items/7", "and the title follows", () => ({ title: document.title }));
const changes = Number(text("changes"));
check(changes === 7, "onUrlChange for every change of address", { changes });

// load leaves the app.
navigations.length = 0;
click("load");
await until(() => navigations.some((message) => message.includes("navigation")), "load asks the browser to load the page", () => ({ navigations }));

// Shutdown stops following links.
if (onServer) app.close();
else app.shutdown();
const leftover = document.createElement("a");
leftover.id = "leftover";
leftover.href = "#after";
$("app").appendChild(leftover);
check(!click("leftover").defaultPrevented, "a stopped app doesn't take over links");

// Not every app routes: one made with Jorn.application leaves links alone,
// and ignores the address the page sends it.
if (!onServer) {
  const { Elm: Runtime } = require("./elm/build/runtime.js");
  const plain = document.createElement("div");
  document.body.appendChild(plain);
  const other = start(Runtime.RuntimeSpec, plain, { flags: 1 });
  await until(() => plain.querySelector("#increment") !== null, "an app without routing starts");
  const link = document.createElement("a");
  link.href = "#plain";
  plain.appendChild(link);
  const event = new window.MouseEvent("click", { bubbles: true, cancelable: true });
  link.dispatchEvent(event);
  check(!event.defaultPrevented, "an app without routing leaves links to the browser");
  other.shutdown();
}

// A page that reconnects after moving, with the back button while it was
// offline, tells its session where it is now.
if (onServer) {
  await until(() => attached.sessions === 0, "the page's session ends when it closes");
  const socket = () => new WebSocket(`${origin.replace("http", "ws")}/socket`);
  const opened = (ws) => new Promise((resolve) => ws.addEventListener("open", resolve));
  const heard = (ws) => {
    const messages = [];
    ws.addEventListener("message", ({ data }) => messages.push(JSON.parse(data)));
    return messages;
  };

  const first = socket();
  const firstHeard = heard(first);
  await opened(first);
  first.send(JSON.stringify({ join: { protocol: 0, url: `${origin}/one` } }));
  await until(() => firstHeard.some((message) => message.mount), "a session starts where the page says it is");
  const mount = firstHeard.find((message) => message.mount);
  check(mount.routing === true && mount.title === "Page /one", "its mount says it routes, with the title", { mount: { ...mount, mount: undefined } });
  const id = firstHeard[0].session;
  const seen = firstHeard.at(-1).seq;
  first.close(); // No status code, so the session waits for the page.
  await wait(50);
  check(attached.sessions === 1, "the session waits for its page", { sessions: attached.sessions });

  const second = socket();
  const secondHeard = heard(second);
  await opened(second);
  second.send(JSON.stringify({ join: { protocol: 0, session: id, seen, url: `${origin}/two` } }));
  await until(
    () => secondHeard.some((message) => message.patches && JSON.stringify(message.patches).includes("/two") && message.title === "Page /two"),
    "the resumed session hears where the page is now",
    () => ({ secondHeard }),
  );
  check(!secondHeard.some((message) => message.session !== undefined), "and it's the same session", { secondHeard });
  second.close(1000);
  await until(() => attached.sessions === 0, "every session ends");

  await attached.close();
  await new Promise((resolve) => server.close(resolve));
}
window.close();

if (failed) {
  console.log(`FAILED: ${failed} problems`);
  process.exit(1);
}
console.log(
  `PASSED: URL routing${onServer ? ", with the app on a server," : ""} starts at the page's address, takes over the links it should, and follows every navigation effect and the back button.`,
);
