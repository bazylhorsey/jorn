// Memoized subtrees, counted: a list of 100 memoized rows, run through
// Jorn.application and start in jsdom, where building a row logs it.
//
// Usage: node client/test/memo.mjs
// Build first: cd client/test/elm && elm make src/MemoSpec.elm --output=build/memo.js

import { JSDOM } from "jsdom";
import { createRequire } from "node:module";
import { start } from "../jorn.js";

const { window } = new JSDOM("<!doctype html><html><body></body></html>");
const { document } = window;
const frames = [];
window.requestAnimationFrame = (callback) => frames.push(callback);

// Debug.log writes "built: <id>" each time a row is built.
const built = [];
const log = console.log;
console.log = (line, ...rest) => {
  const match = /^built: (\d+)$/.exec(line);
  if (match) built.push(Number(match[1]));
  else log(line, ...rest);
};

const require = createRequire(import.meta.url);
const { Elm } = require("./elm/build/memo.js");

let failed = 0;
function check(condition, what, detail = {}) {
  if (!condition) {
    failed++;
    log(`FAILED: ${what}`, JSON.stringify(detail));
  }
}

const tick = () => new Promise((resolve) => setTimeout(resolve, 0));
async function flushFrames() {
  await tick();
  while (frames.length) {
    frames.shift()();
    await tick();
  }
}

const container = document.createElement("div");
document.body.appendChild(container);
start(Elm.MemoSpec, container);
await tick();
const $ = (id) => document.getElementById(id);
const click = (id) => $(id).dispatchEvent(new window.Event("click"));
const labels = () => [...$("rows").children].map((li) => li.textContent);

check(built.length === 100, "the first view builds every row once", { built: built.length });
check(labels()[4] === "row 5", "and shows them", { labels: labels().slice(0, 6) });

// A change outside the rows builds none of them.
built.length = 0;
click("count");
await flushFrames();
check($("count").textContent === "1", "the count changed");
check(built.length === 0, "no row built for a change outside them", { built });

// An event inside a row is routed without building any row, and the row it
// changes is built once: the old one is kept, not built again to diff.
built.length = 0;
const row = $("row-5");
click("row-5");
check(built.length === 0, "routing an event into a row builds nothing", { built });
await flushFrames();
check(JSON.stringify(built) === "[5]", "only the changed row is built, once", { built });
check(labels()[4] === "row 5!", "and the page shows it", { labels: labels().slice(0, 6) });
check($("row-5") === row, "in the same DOM node");

built.length = 0;
click("row-5");
await flushFrames();
check(JSON.stringify(built) === "[5]", "and again for the next change", { built });
check(labels()[4] === "row 5!!", "which shows too", { labels: labels().slice(0, 6) });

// Reordering moves the rows without building them.
built.length = 0;
click("reverse");
await flushFrames();
check(built.length === 0, "reordering builds no row", { built });
check(labels()[0] === "row 100" && labels()[95] === "row 5!!", "the rows moved", { labels: labels().slice(0, 3) });
check($("row-5") === row, "keeping their DOM nodes");

if (failed) {
  log(`FAILED: ${failed} problems`);
  process.exit(1);
}
log("PASSED: memoized rows are built once, skipped while they're the same, and only the row that changes is built again.");
