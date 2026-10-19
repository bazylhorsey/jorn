// Tests for server/http.js, the XMLHttpRequest that lets elm/http run on the
// server. Requests go to a real HTTP server on a local port. Most of them go
// through `elm` below, which uses XMLHttpRequest the way elm/http does, so
// these check what elm/http relies on. http-elm.mjs runs elm/http itself.
//
// Usage: node server/test/http.mjs
// Build first: cd client/test/elm && elm make src/RuntimeSpec.elm --output=build/runtime.js

import { createRequire } from "node:module";
import { XMLHttpRequest } from "../http.js";
import { session } from "../jorn.js";
import { serve } from "./endpoints.mjs";

const require = createRequire(import.meta.url);

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

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// ---- A server to talk to -----------------------------------------------------

const endpoints = await serve();
const { base, nowhere } = endpoints;

// ---- What elm/http does --------------------------------------------------------

// The steps of _Http_toTask and _Http_track in elm/http 2.0.0's
// Elm/Kernel/Http.js, in the same order. `kill` is what Http.cancel and a
// killed task run. The kernel marks a killed request with a one-letter
// field in optimized builds, so this does too.
function elm({ method = "GET", url, headers = [], body = {}, timeout = 0, expect = "", track = false }) {
  const progress = [];
  let settled = false;
  let settle;
  const result = new Promise((resolve) => (settle = resolve));
  const done = (outcome) => {
    settled = true;
    settle(outcome);
  };
  const xhr = new XMLHttpRequest();
  xhr.addEventListener("error", () => done({ tag: "NetworkError" }));
  xhr.addEventListener("timeout", () => done({ tag: "Timeout" }));
  xhr.addEventListener("load", () => {
    const metadata = { url: xhr.responseURL, statusCode: xhr.status, statusText: xhr.statusText, headers: parseHeaders(xhr.getAllResponseHeaders()) };
    const value = expect === "arraybuffer" ? new DataView(xhr.response) : xhr.response;
    done({ tag: 200 <= xhr.status && xhr.status < 300 ? "GoodStatus" : "BadStatus", metadata, body: value });
  });
  if (track) {
    xhr.upload.addEventListener("progress", (event) => xhr.c || progress.push({ sent: event.loaded, size: event.total }));
    xhr.addEventListener("progress", (event) => xhr.c || progress.push({ received: event.loaded, size: event.lengthComputable ? event.total : null }));
  }
  const handle = { result, xhr, progress, kill: () => {}, settled: () => settled };
  try {
    xhr.open(method, url, true);
  } catch {
    done({ tag: "BadUrl", url });
    return handle;
  }
  for (const [name, value] of headers) xhr.setRequestHeader(name, value);
  xhr.timeout = timeout || 0;
  xhr.responseType = expect;
  xhr.withCredentials = false;
  body.type && xhr.setRequestHeader("Content-Type", body.type);
  xhr.send(body.value);
  handle.kill = () => {
    xhr.c = true;
    xhr.abort();
  };
  return handle;
}

// _Http_parseHeaders: lines from the end, repeated names joined with ", ".
function parseHeaders(raw) {
  const headers = {};
  if (!raw) return headers;
  const lines = raw.split("\r\n");
  for (let i = lines.length; i--; ) {
    const index = lines[i].indexOf(": ");
    if (index > 0) {
      const key = lines[i].substring(0, index);
      const value = lines[i].substring(index + 2);
      headers[key] = key in headers ? `${value}, ${headers[key]}` : value;
    }
  }
  return headers;
}

// ---- Responses -----------------------------------------------------------------

{
  const { result } = elm({ url: `${base}/text` });
  const response = await result;
  check(response.tag === "GoodStatus", "a request gets a response", response);
  check(response.body === "hello", "with its body as text", response);
  check(response.metadata.statusCode === 200 && response.metadata.statusText === "OK", "its status", response.metadata);
  check(response.metadata.url === `${base}/text`, "its URL", response.metadata);
  check(response.metadata.headers["x-one"] === "1" && response.metadata.headers["content-type"] === "text/plain; charset=utf-8", "and its headers, with lowercase names", response.metadata);
}

{
  const response = await elm({ url: `${base}/json` }).result;
  check(response.tag === "GoodStatus" && JSON.parse(response.body).a === 1, "JSON comes as text, for elm/http to decode", response);
}

{
  const response = await elm({ url: `${base}/missing` }).result;
  check(response.tag === "BadStatus" && response.metadata.statusCode === 404 && response.body === "nope", "an error status still has its body", response);
  check(response.metadata.statusText === "Not Found", "and status text", response.metadata);
}

{
  const response = await elm({ url: `${base}/redirect` }).result;
  check(response.tag === "GoodStatus" && response.body === "hello", "redirects are followed", response);
  check(response.metadata.url === `${base}/text`, "and the URL is where it ended up", response.metadata);
}

{
  const response = await elm({ url: `${base}/bytes`, expect: "arraybuffer" }).result;
  const bytes = response.body;
  check(bytes instanceof DataView && bytes.byteLength === 256, "a binary response comes as bytes", { length: bytes?.byteLength });
  check(bytes.getUint8(0) === 0 && bytes.getUint8(200) === 200 && bytes.getUint8(255) === 255, "all of them, in order");
}

{
  const response = await elm({ url: `${base}/empty`, expect: "arraybuffer" }).result;
  check(response.tag === "GoodStatus" && response.body.byteLength === 0, "an empty response is empty bytes, as Http.expectWhatever wants", response);
}

{
  const response = await elm({ url: `${base}/latin1` }).result;
  check(response.body === "café", "text is decoded with the charset the response names", { body: response.body });
}

{
  const request = elm({ url: `${base}/gzip`, track: true });
  const response = await request.result;
  check(response.body === "zipped", "compressed responses are unzipped", { body: response.body });
  // Content-Length counts the zipped bytes, and progress counts unzipped ones.
  check(request.progress.length > 0 && request.progress.every((event) => event.size === null), "so their progress has no size", request.progress);
}

{
  const response = await elm({ url: `${base}/many` }).result;
  check(response.metadata.headers["x-many"] === "a, b", "a header sent twice reads as one, joined", response.metadata.headers);
}

// ---- Requests --------------------------------------------------------------------

{
  const response = await elm({
    method: "POST",
    url: `${base}/echo`,
    headers: [["X-Custom", "yes"]],
    body: { type: "application/json", value: '{"b":2}' },
  }).result;
  const echo = JSON.parse(response.body);
  check(echo.method === "POST" && echo.text === '{"b":2}', "a string body is sent", echo);
  check(echo.contentType === "application/json" && echo.custom === "yes", "with its content type and headers", echo);
  check(echo.cookie === null, "and no cookies", echo);
}

{
  const bytes = new DataView(new Uint8Array([1, 2, 250]).buffer);
  const echo = JSON.parse((await elm({ method: "PUT", url: `${base}/echo`, body: { type: "application/octet-stream", value: bytes } }).result).body);
  check(echo.method === "PUT" && echo.length === 3 && echo.text === "\x01\x02\xfa", "a bytes body is sent as bytes", echo);
  check(echo.contentType === "application/octet-stream", "with its content type", echo);
}

{
  const form = new FormData();
  form.append("name", "jorn");
  form.append("file", new Blob(["contents"], { type: "text/plain" }), "notes.txt");
  const echo = JSON.parse((await elm({ method: "POST", url: `${base}/echo`, body: { type: "", value: form } }).result).body);
  check(/^multipart\/form-data; boundary=/.test(echo.contentType), "form data goes as multipart, with its boundary", echo);
  check(echo.text.includes('name="name"') && echo.text.includes("jorn") && echo.text.includes('filename="notes.txt"') && echo.text.includes("contents"), "and every part", echo);
}

{
  const echo = JSON.parse((await elm({ method: "DELETE", url: `${base}/echo` }).result).body);
  check(echo.method === "DELETE" && echo.length === 0 && echo.contentType === null, "Http.emptyBody sends nothing", echo);
}

{
  const xhr = new XMLHttpRequest();
  xhr.open("get", `${base}/echo`);
  const response = new Promise((resolve) => xhr.addEventListener("load", resolve));
  xhr.send("ignored");
  await response;
  const echo = JSON.parse(xhr.responseText);
  check(echo.method === "GET" && echo.length === 0, "GET has no body, as in a browser, and methods are uppercased", echo);
}

// ---- Failures ----------------------------------------------------------------------

{
  for (const url of ["/relative", "not a url", ""]) {
    const response = await elm({ url }).result;
    check(response.tag === "BadUrl" && response.url === url, "a URL that isn't absolute is a bad URL: there's no page to resolve it against", { url, response });
  }
}

{
  const response = await elm({ url: nowhere }).result;
  check(response.tag === "NetworkError", "nothing listening is a network error", response);
}

{
  const before = endpoints.hangUps;
  const started = performance.now();
  const response = await elm({ url: `${base}/slow`, timeout: 50 }).result;
  check(response.tag === "Timeout", "a slow response times out", response);
  check(performance.now() - started < 250, "on time", { ms: performance.now() - started });
  await wait(50);
  check(endpoints.hangUps === before + 1, "and the request is stopped", { hangUps: endpoints.hangUps, before });
}

{
  const request = elm({ method: "POST", url: `${base}/slow`, body: { type: "text/plain", value: "waiting" }, timeout: 50 });
  const events = [];
  for (const type of ["timeout", "error", "load", "loadend"]) request.xhr.upload.addEventListener(type, () => events.push(type));
  const response = await request.result;
  check(response.tag === "Timeout" && events.join() === "timeout,loadend", "a request that times out before its response tells its upload too", { response, events });
}

{
  const response = await elm({ url: `${base}/slow`, timeout: 1000 }).result;
  check(response.tag === "GoodStatus" && response.body === "late", "one that's slow but in time arrives", response);
}

{
  const before = endpoints.hangUps;
  const request = elm({ url: `${base}/slow`, track: true });
  const events = [];
  for (const type of ["abort", "loadend", "load", "error"]) request.xhr.addEventListener(type, () => events.push(type));
  await wait(20);
  request.kill();
  check(request.xhr.readyState === XMLHttpRequest.UNSENT, "a killed request goes back to unsent", { readyState: request.xhr.readyState });
  check(events.join() === "abort,loadend", "and says it was aborted, which elm/http doesn't listen for", { events });
  await wait(400);
  check(!request.settled(), "so elm/http hears nothing more about it");
  check(endpoints.hangUps === before + 1, "and the server sees it go", { hangUps: endpoints.hangUps, before });
  check(request.progress.length === 0, "no progress after it was killed", request.progress);
}

// ---- Progress ------------------------------------------------------------------------

{
  const request = elm({ url: `${base}/big`, expect: "arraybuffer", track: true });
  const response = await request.result;
  check(response.body.byteLength === 200_000, "a big response arrives whole", { length: response.body.byteLength });
  const received = request.progress.filter((event) => "received" in event);
  check(received.length >= 3, "with progress as it comes", { received });
  check(received.every((event) => event.size === 200_000), "out of its length", { received });
  check(received.at(-1)?.received === 200_000, "up to all of it", { received });
  check(received.every((event, i) => i === 0 || event.received >= received[i - 1].received), "never going backwards", { received });
  check(request.progress.every((event) => !("sent" in event)), "and nothing about sending when there's no body", request.progress);
}

{
  const request = elm({ url: `${base}/chunked`, track: true });
  const response = await request.result;
  check(response.body === "one two three", "a response without a length arrives whole", response);
  const received = request.progress.filter((event) => "received" in event);
  check(received.length >= 2 && received.every((event) => event.size === null), "and its progress has no size", { received });
}

{
  const request = elm({ method: "POST", url: `${base}/echo`, body: { type: "text/plain", value: "x".repeat(1000) }, track: true });
  await request.result;
  const sent = request.progress.filter((event) => "sent" in event);
  check(sent.length >= 1 && sent.at(-1).sent === 1000 && sent.at(-1).size === 1000, "sending a body reports its progress", { sent });
}

// ---- The rest of the standard ----------------------------------------------------------

{
  const xhr = new XMLHttpRequest();
  const states = [];
  const events = [];
  xhr.onreadystatechange = () => states.push(xhr.readyState);
  for (const type of ["loadstart", "progress", "load", "loadend"]) xhr[`on${type}`] = () => events.push(type);
  const loaded = new Promise((resolve) => xhr.addEventListener("loadend", resolve));
  xhr.open("GET", `${base}/chunked`);
  xhr.send();
  await loaded;
  check(states.join() === "1,2,3,4", "readyState goes through every state, once each", { states });
  check(events[0] === "loadstart" && events.at(-2) === "load" && events.at(-1) === "loadend" && events.includes("progress"), "and the onload style of handler works", { events });
  check(xhr.getResponseHeader("Content-Type") === "text/plain" && xhr.getResponseHeader("x-nothing") === null, "getResponseHeader ignores case", {});
}

{
  const xhr = new XMLHttpRequest();
  xhr.open("GET", `${base}/json`);
  xhr.responseType = "json";
  const loaded = new Promise((resolve) => (xhr.onload = resolve));
  xhr.send();
  await loaded;
  check(xhr.response?.a === 1, "responseType json parses the response", { response: xhr.response });
  let threw = false;
  try {
    xhr.responseText;
  } catch (error) {
    threw = error.name === "InvalidStateError";
  }
  check(threw, "and responseText isn't there for it");
}

{
  const xhr = new XMLHttpRequest();
  xhr.open("GET", `${base}/text`);
  xhr.responseType = "blob";
  const loaded = new Promise((resolve) => (xhr.onload = resolve));
  xhr.send();
  await loaded;
  check(xhr.response instanceof Blob && (await xhr.response.text()) === "hello" && xhr.response.type === "text/plain; charset=utf-8", "responseType blob gives a Blob", {});
}

{
  const xhr = new XMLHttpRequest();
  let threw = false;
  try {
    xhr.open("GET", `${base}/text`, false);
  } catch (error) {
    threw = error.name === "InvalidAccessError";
  }
  check(threw, "synchronous requests say they aren't supported");
  threw = false;
  try {
    xhr.send();
  } catch (error) {
    threw = error.name === "InvalidStateError";
  }
  check(threw, "send before open throws, as in a browser");
}

{
  // Opening again drops the request in flight without a word.
  const xhr = new XMLHttpRequest();
  const events = [];
  for (const type of ["abort", "error", "load"]) xhr.addEventListener(type, () => events.push(type));
  xhr.open("GET", `${base}/slow`);
  xhr.send();
  await wait(20);
  xhr.open("GET", `${base}/text`);
  xhr.send();
  await new Promise((resolve) => xhr.addEventListener("loadend", resolve));
  check(events.join() === "load" && xhr.responseText === "hello", "open replaces a request in flight", { events, text: xhr.responseText });
}

{
  const xhr = new XMLHttpRequest();
  xhr.onload = () => {
    throw new Error("a handler's own problem");
  };
  const errors = [];
  const listener = (error) => errors.push(error.message);
  process.prependListener("uncaughtException", listener);
  const ended = new Promise((resolve) => xhr.addEventListener("loadend", resolve));
  xhr.open("GET", `${base}/text`);
  xhr.send();
  await ended;
  await wait(10);
  process.off("uncaughtException", listener);
  check(xhr.readyState === XMLHttpRequest.DONE && errors.join() === "a handler's own problem", "a handler that throws doesn't break the request, and its error is reported", { errors });
}

// ---- Installing it ---------------------------------------------------------------------------

{
  const { Elm } = require("../../client/test/elm/build/runtime.js");
  const original = globalThis.XMLHttpRequest;
  const theirs = class {};
  globalThis.XMLHttpRequest = theirs;
  session(Elm.RuntimeSpec, { send: () => {}, flags: 1, log: { warn() {} } }).close();
  check(globalThis.XMLHttpRequest === theirs, "a session leaves an XMLHttpRequest the process already has alone");
  delete globalThis.XMLHttpRequest;
  session(Elm.RuntimeSpec, { send: () => {}, flags: 1, log: { warn() {} } }).close();
  check(globalThis.XMLHttpRequest === XMLHttpRequest, "and defines this one when there's none");
  globalThis.XMLHttpRequest = original;
}

await endpoints.close();

if (failed) {
  console.log(`FAILED: ${failed} problems`);
  process.exit(1);
}
console.log("PASSED: XMLHttpRequest on fetch does what elm/http needs: bodies, headers, statuses, redirects, bytes, timeouts, bad URLs, network errors, cancelling and progress.");
