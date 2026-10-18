// Runs examples/todos the way its page does, in jsdom, and uses it like a
// person would: add, tick, edit, filter, delete. With `server`, the app runs
// on a server and the page streams it over a websocket, the way
// server.html does, and the same checks have to pass.
//
// Usage: node client/test/example.mjs [server]
// Build first: cd examples/todos && elm make src/Main.elm --output=build/main.js
// Server mode also needs `npm install` in server/.

import { JSDOM } from "jsdom";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { start, stream } from "../jorn.js";

const onServer = process.argv[2] === "server";

const require = createRequire(import.meta.url);
const { Elm } = require("../../examples/todos/build/main.js");

let server = null;
let origin = "http://localhost/";
if (onServer) {
  const { attach } = await import("../../server/jorn.js");
  server = createServer((request, response) => response.writeHead(404).end());
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  origin = `http://127.0.0.1:${server.address().port}/`;
  attach(server, { path: "/socket", program: Elm.Main, flags: ({ page }) => page });
}

const { window } = new JSDOM("<!doctype html><html><body><div id=app></div></body></html>", { url: origin });
const { document } = window;

let failed = 0;
function check(condition, what, detail = {}) {
  if (!condition) {
    failed++;
    console.log(`FAILED: ${what}`, JSON.stringify(detail));
  }
}

// In the page, frames come from setTimeout in jsdom, so a few ticks let one
// render land. Over a socket, wait until the page has been still for a while.
const settle = () =>
  new Promise((resolve) => {
    if (!onServer) return setTimeout(resolve, 20);
    let timer = setTimeout(done, 60);
    const observer = new window.MutationObserver(() => {
      clearTimeout(timer);
      timer = setTimeout(done, 60);
    });
    observer.observe(document.body, { subtree: true, childList: true, attributes: true, characterData: true });
    function done() {
      observer.disconnect();
      resolve();
    }
  });
const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const titles = () => $$("li label").map((label) => label.textContent);
const fire = (element, type, init = {}) => element.dispatchEvent(new window.Event(type, { bubbles: true, cancelable: true, ...init }));

async function type(input, text) {
  input.value = text;
  fire(input, "input");
  await settle();
}

async function submit(form) {
  fire(form, "submit");
  await settle();
}

async function click(element) {
  element.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true }));
  await settle();
}

const saved = [];
const options = {
  flags: [{ id: 1, title: "Read the docs", done: true }],
  effects: { save: (todos) => saved.push(todos) },
};
const app = onServer ? stream($("#app"), "/socket", options) : start(Elm.Main, $("#app"), options);
await settle();

check(JSON.stringify(titles()) === '["Read the docs"]', "starts from the saved list", { titles: titles() });
check($("[role=progressbar]").getAttribute("aria-valuenow") === "1", "progress counts the saved todo");

// Add two.
const draft = $("form input");
await type(draft, "Write an example");
await submit($("main > form"));
await type(draft, "  Ship v0.1  ");
await submit($("main > form"));
check(JSON.stringify(titles()) === '["Read the docs","Write an example","Ship v0.1"]', "adds todos, trimmed", { titles: titles() });
check(draft.value === "", "clears the field after adding", { value: draft.value });
check(saved.at(-1)?.length === 3, "saves after adding", { saved: saved.at(-1) });
await submit($("main > form"));
check(titles().length === 3, "ignores an empty todo");

// Tick one off, keeping the node it lives in.
const item = $$("li")[1];
const box = item.querySelector("input[type=checkbox]");
box.checked = true;
fire(box, "change");
await settle();
check(item.isConnected && item.classList.contains("done"), "ticking marks the item done");
check($("footer p").textContent === "1 left", "counts what's left", { text: $("footer p").textContent });
check(saved.at(-1)?.[1]?.done === true, "saves the change");

// Filter.
const button = (name) => $$("footer button").find((b) => b.textContent === name);
await click(button("Active"));
check(JSON.stringify(titles()) === '["Ship v0.1"]', "Active shows what's left", { titles: titles() });
check(button("Active").getAttribute("aria-pressed") === "true", "the chosen filter is pressed");
await click(button("All"));
check(titles().length === 3, "All shows everything");

// Edit: the field gets focus, Enter saves, Escape cancels.
await click($$("li")[2].querySelector("button[aria-label^=Edit]"));
const editor = $("#edit-3");
check(editor !== null && document.activeElement === editor, "Edit focuses the field", { active: document.activeElement?.outerHTML });
await type(editor, "Ship Jorn v0.1");
await submit(editor.form);
check(titles()[2] === "Ship Jorn v0.1", "Enter saves the new title", { titles: titles() });

await click($$("li")[0].querySelector("button[aria-label^=Edit]"));
await type($("#edit-1"), "Something else");
$("#edit-1").dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
await settle();
check(titles()[0] === "Read the docs", "Escape keeps the old title", { titles: titles() });
check($("#edit-1") === null, "Escape closes the editor");

// Delete, then clear completed.
await click($$("li")[1].querySelector("button[aria-label^=Delete]"));
check(JSON.stringify(titles()) === '["Read the docs","Ship Jorn v0.1"]', "deletes one", { titles: titles() });
await click(button("Clear completed"));
check(JSON.stringify(titles()) === '["Ship Jorn v0.1"]', "clears completed", { titles: titles() });
check(button("Clear completed") === undefined, "nothing left to clear");

await click($("li button[aria-label^=Delete]"));
check($("footer") === null, "the footer goes when the list is empty");
check(JSON.stringify(saved.at(-1)) === "[]", "saves the empty list");

if (onServer) {
  app.close();
  window.close();
  await new Promise((resolve) => server.close(resolve));
}

if (failed) {
  console.log(`FAILED: ${failed} problems`);
  process.exit(1);
}
console.log(`PASSED: the todos example${onServer ? ", running on a server," : ""} adds, ticks, edits, filters and deletes, and saves every change.`);
