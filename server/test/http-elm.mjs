// elm/http itself on the server: HttpSpec, a server component that makes
// every kind of request elm/http can, runs in a session that a page in jsdom
// streams. Each result shows up in the page, where this reads it.
//
// Usage: node server/test/http-elm.mjs
// Build first: cd server/test/elm && elm make src/HttpSpec.elm --optimize --output=build/http.js

import { JSDOM } from "jsdom";
import { createRequire } from "node:module";
import { stream } from "../../client/jorn.js";
import { attach } from "../jorn.js";
import { serve } from "./endpoints.mjs";

const require = createRequire(import.meta.url);
const { Elm } = require("./elm/build/http.js");

let failed = 0;
function check(condition, what, detail = {}) {
  if (!condition) {
    failed++;
    console.log(`FAILED: ${what}`, JSON.stringify(detail));
    annotate(`${what} ${JSON.stringify(detail)}`);
  }
}

// On GitHub, failures also show as annotations on the run and the pull request.
function annotate(message) {
  if (process.env.GITHUB_ACTIONS) console.log(`::error::${message.replace(/%/g, "%25").replace(/\r/g, "%0D").replace(/\n/g, "%0A")}`);
}
process.on("uncaughtException", (error) => {
  console.error(error);
  annotate(error.stack ?? String(error));
  process.exit(1);
});

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

delete globalThis.XMLHttpRequest; // In case anything defined one: this tests Jorn's.

const endpoints = await serve();
const { base, nowhere } = endpoints;
const warnings = [];
const app = attach(endpoints.server, {
  path: "/http",
  program: Elm.HttpSpec,
  flags: () => ({ base, nowhere }),
  log: { info() {}, warn: (line) => warnings.push(line), error: (line) => warnings.push(line) },
});

const { window } = new JSDOM("<!doctype html><html><body><div id=app></div></body></html>", { url: `${base}/` });
const { document } = window;
const page = stream(document.getElementById("app"), "/http");
const text = (id) => document.getElementById(id)?.textContent;

const expected = {
  text: "hello",
  json: "1",
  post: 'POST {"b":2}',
  headers: `200 OK application/json yes from ${base}/echo`,
  missing: "BadStatus 404",
  timeout: "Timeout",
  badurl: "BadUrl /relative",
  network: "NetworkError",
  bytes: "256 bytes, 0..255",
  upload: "3",
  "upload-sent": "sent 3 of 3",
  download: "200000 bytes, 0..3",
  "download-received": "received 200000 of 200000",
  multipart: "multipart, with its parts",
  task: "hello",
};
const what = {
  text: "Http.get with expectString",
  json: "expectJson",
  post: "Http.post with jsonBody",
  headers: "request headers, and the status, headers and URL in Metadata",
  missing: "an error status",
  timeout: "a timeout",
  badurl: "a relative URL, which is bad on the server",
  network: "a network error",
  bytes: "expectBytesResponse",
  upload: "bytesBody",
  "upload-sent": "Http.track while sending",
  download: "a big binary response",
  "download-received": "Http.track while receiving",
  multipart: "multipartBody with a string and a bytes part",
  task: "Http.task after Process.sleep, made from a timer instead of an update",
};

await until(() => Object.keys(expected).every((id) => text(id) !== undefined), "every request finishes");
for (const [id, value] of Object.entries(expected)) {
  check(text(id) === value, what[id], { id, got: text(id), expected: value });
}

document.getElementById("fetch").dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
await until(() => text("event") === "hello", "a request made in response to a click in the page");

await wait(400); // Longer than /slow takes.
check(text("cancelled") === undefined, "Http.cancel stops a tracked request, so its result never comes", { got: text("cancelled") });
check(endpoints.hangUps === 2, "and the server sees it go, along with the one that timed out", { hangUps: endpoints.hangUps });
check(warnings.length === 0, "nothing went wrong along the way", { warnings });

page.close();
window.close();
await app.close();
await endpoints.close();

if (failed) {
  console.log(`FAILED: ${failed} problems`);
  process.exit(1);
}
console.log("PASSED: elm/http works in a server component: every body, expect, error, header, progress, tasks and cancelling.");
