// Tests for the app runtime (Jorn.application and start in client/jorn.js),
// in jsdom, with animation frames under the test's control.
//
// Usage: node client/test/runtime.mjs
// Build first: cd client/test/elm && elm make src/RuntimeSpec.elm --output=build/runtime.js

import { JSDOM } from "jsdom";
import { createRequire } from "node:module";
import { start } from "../jorn.js";

const { window } = new JSDOM("<!doctype html><html><body></body></html>");
const { document } = window;
const frames = [];
window.requestAnimationFrame = (callback) => frames.push(callback);

const require = createRequire(import.meta.url);
const { Elm } = require("./elm/build/runtime.js");

let failed = 0;
function check(condition, what, detail = {}) {
  if (!condition) {
    failed++;
    console.log(`FAILED: ${what}`, JSON.stringify(detail));
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

// Watch what the program sends, alongside start.
const sent = [];
const program = {
  init(options) {
    const app = Elm.RuntimeSpec.init(options);
    app.ports.toJorn.subscribe((message) => sent.push(message));
    return app;
  },
};

const container = document.createElement("div");
document.body.appendChild(container);
const recorded = [];
const opened = [];
document.body.addEventListener("opened", (event) => opened.push(event.detail));

const $ = (id) => document.getElementById(id);
const click = (id) => $(id).dispatchEvent(new window.Event("click"));
const press = (key) => {
  const event = new window.KeyboardEvent("keydown", { key, bubbles: true, cancelable: true });
  $("keys").dispatchEvent(event);
  return event;
};
// A client effect runs while the program is handing over its commands. A key
// pressed then still gets its answer in time.
const pressedDuringEffect = [];
const record = (payload) => {
  recorded.push(payload);
  pressedDuringEffect.push(press("Enter").defaultPrevented);
};
const app = start(program, container, { flags: 5, effects: { record } });
await tick();

check($("increment")?.textContent === "5", "mounts the initial view with flags", { html: container.innerHTML });

// Several messages before a frame: one diff, one patch message.
sent.length = 0;
click("increment");
click("increment");
click("increment");
await tick();
check($("increment").textContent === "5", "nothing renders before the frame");
check(frames.length === 1, "one frame requested for three messages", { frames: frames.length });
await flushFrames();
check($("increment").textContent === "8", "the frame renders all three", { got: $("increment").textContent });
const patchMessages = sent.filter((message) => message.patches);
check(patchMessages.length === 1, "one patch message", { sent });

// Effects.
click("open");
await flushFrames();
check($("field") !== null, "the input appears");
check(document.activeElement === $("field"), "focus runs after the patch that created the element");
check(JSON.stringify(opened) === "[8]", "custom event from the container", { opened });
check(JSON.stringify(recorded) === '["opened"]', "named client effect", { recorded });
const log = $("log").textContent.split(",");
check(log.includes("before"), "beforePaint ran before the render", { log });
check(log.includes("painted"), "afterPaint ran once the patches were on the page", { log });
check(log.includes("task"), "an Elm command's result comes back", { log });
check(log.indexOf("before") < log.indexOf("painted"), "before comes before after", { log });

// Events route through the runtime with the live event in client mode.
$("field").value = "Jorn";
$("field").dispatchEvent(new window.Event("input"));
await flushFrames();
check($("name").textContent === "Jorn", "input routes to its handler", { got: $("name").textContent });

// An advanced handler decides preventDefault and stopPropagation per event,
// before its listener returns.
check(JSON.stringify(pressedDuringEffect) === "[true]", "answered during a client effect", { pressedDuringEffect });
check(press("Enter").defaultPrevented, "the program prevents Enter as it fires");
check(!press("a").defaultPrevented, "and lets other keys through");
press("Escape");
await flushFrames();
check($("pressed").textContent === "Enter,bubbled Enter,Enter,bubbled Enter,a,bubbled a,Escape", "every key arrives, and Escape stops at the input", {
  got: $("pressed").textContent,
});
check(!sent.some((message) => message.error), "no errors", { sent });

// Shutdown.
app.shutdown();
check(container.childNodes.length === 0, "shutdown empties the container");
app.shutdown();
check(true, "a second shutdown is harmless");

let threw = false;
try {
  start({ init: () => ({ ports: {} }) }, container);
} catch {
  threw = true;
}
check(threw, "a program without the ports is refused");

if (failed) {
  console.log(`FAILED: ${failed} problems`);
  process.exit(1);
}
console.log("PASSED: the runtime batches messages into one render per frame and runs every kind of effect.");
