// Tests for the chat example (examples/chat): pages in jsdom on a real
// server, talking to each other through the program's own ports.
//
// Usage: node server/test/chat.mjs
// Build first: cd examples/chat && elm make src/Main.elm --output=build/main.js

import { JSDOM } from "jsdom";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { stream } from "../../client/jorn.js";
import { attachChat } from "../../examples/chat/chat.mjs";

const require = createRequire(import.meta.url);
const { Elm } = require("../../examples/chat/build/main.js");

let failed = 0;
function check(condition, what, detail = {}) {
  if (!condition) {
    failed++;
    console.log(`FAILED: ${what}`, JSON.stringify(detail));
  }
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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

const server = createServer((request, response) => response.writeHead(404).end());
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const chat = attachChat(server, { path: "/chat", program: Elm.Main, log: { info() {}, warn: console.warn, error: console.error } });

function open() {
  const { window } = new JSDOM("<!doctype html><html><body><div id=app></div></body></html>", { url: `${origin}/` });
  const { document } = window;
  const app = stream(document.getElementById("app"), "/chat");
  return {
    window,
    app,
    me: () => document.getElementById("me")?.textContent,
    lines: () => [...document.querySelectorAll("#lines li")].map((li) => li.textContent),
    // Typing, then pressing Enter a moment later, as a person would.
    async say(text) {
      const draft = document.getElementById("draft");
      draft.value = text;
      draft.dispatchEvent(new window.Event("input", { bubbles: true }));
      await wait(50);
      draft.form.dispatchEvent(new window.Event("submit", { bubbles: true, cancelable: true }));
    },
  };
}

const ada = open();
await until(() => ada.me() === "You're Guest 1", "the first page gets a name from the server");
await until(() => ada.lines().join() === "Guest 1 joined", "and hears itself join", { lines: ada.lines() });

const bob = open();
await until(() => bob.me() === "You're Guest 2", "the second page gets the next name");
await until(() => ada.lines().at(-1) === "Guest 2 joined", "the first page hears the second join", { lines: ada.lines() });

await ada.say("Hello, Bob");
const hello = "Guest 1 Hello, Bob";
await until(() => bob.lines().at(-1) === hello, "a message reaches the other page", { lines: bob.lines() });
await until(() => ada.lines().at(-1) === hello, "and comes back to the page that sent it", { lines: ada.lines() });
await until(() => ada.window.document.getElementById("draft").value === "", "sending clears the field");

await bob.say("Hi");
await until(() => ada.lines().at(-1) === "Guest 2 Hi" && bob.lines().at(-1) === "Guest 2 Hi", "and back the other way", { lines: ada.lines() });
check(JSON.stringify(ada.lines()) === JSON.stringify(bob.lines().slice(-4)), "both pages show the same lines in the same order", { ada: ada.lines(), bob: bob.lines() });

await ada.say("   ");
await wait(50);
check(bob.lines().at(-1) === "Guest 2 Hi", "a blank message isn't sent", { lines: bob.lines() });

bob.app.close();
await until(() => ada.lines().at(-1) === "Guest 2 left", "closing a page says who left", { lines: ada.lines() });
await until(() => chat.sessions === 1, "and ends its session");

// A page that joins late sees the recent lines.
const cy = open();
await until(() => cy.me() === "You're Guest 3", "a third page");
await until(() => cy.lines().includes(hello) && cy.lines().at(-1) === "Guest 3 joined", "sees what was said before it joined", { lines: cy.lines() });

ada.app.close();
cy.app.close();
await until(() => chat.sessions === 0, "every session ends");
for (const page of [ada, bob, cy]) page.window.close();
await chat.close();
await new Promise((resolve) => server.close(resolve));

if (failed) {
  console.log(`FAILED: ${failed} problems`);
  process.exit(1);
}
console.log("PASSED: pages in the chat example hear each other through the program's ports, in the same order, and late pages catch up.");
