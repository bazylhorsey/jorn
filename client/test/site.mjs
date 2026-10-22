// Checks the example site (examples/site) that `jorn build` wrote: the files
// it has, the hashes in its pages' URLs, and each page in jsdom, where the
// app has to mount over the page's HTML without changing a thing, then take
// over its links.
//
// Usage: node client/test/site.mjs
// Build first: cd examples/site && node ../../cli/jorn.mjs build

import { JSDOM } from "jsdom";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { start } from "../jorn.js";

const out = new URL("../../examples/site/build/", import.meta.url);
const read = (path) => readFileSync(new URL(path, out), "utf8");

const require = createRequire(import.meta.url);
const { Elm } = require("../../examples/site/build/main.js");

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

// Each page, where a static host serves it, and the file it's in.
const posts = ["pages-from-a-list", "the-same-view-twice", "links-that-stay"];
const pages = [
  { at: "/", file: "index.html", h1: "Posts", title: "Notes" },
  { at: "/about/", file: "about/index.html", h1: "About", title: "About · Notes" },
  ...posts.map((slug) => ({ at: `/posts/${slug}/`, file: `posts/${slug}/index.html` })),
  // A host serves 404.html at any address without a page.
  { at: "/no/such/page/", file: "404.html", h1: "Not found", title: "Not found · Notes" },
];

// What's in the folder.
for (const file of [...pages.map((page) => page.file), "main.js", "jorn.js", "style.css", "sitemap.xml"]) {
  check(existsSync(new URL(file, out)), `the site has ${file}`);
}
check(read("jorn.js") === readFileSync(new URL("../jorn.js", import.meta.url), "utf8"), "jorn.js is client/jorn.js");
check(
  read("style.css") === readFileSync(new URL("../../examples/site/public/style.css", import.meta.url), "utf8"),
  "public/ is copied to the site's root",
);
const sitemap = read("sitemap.xml");
for (const page of pages.slice(0, -1)) {
  check(sitemap.includes(`<loc>https://example.com${page.at}</loc>`), `the sitemap lists ${page.at}`, { sitemap });
}

// Every page refers to the app, the patcher and the stylesheet with a hash of
// what's in them, in attributes and in the inline script's import.
const version = (file) => createHash("sha256").update(readFileSync(new URL(file, out))).digest("hex").slice(0, 10);
for (const page of pages) {
  const html = read(page.file);
  check(html.startsWith("<!doctype html><html lang=\"en\">"), `${page.file} is a whole document`, { start: html.slice(0, 40) });
  for (const ref of [
    `src="/main.js?v=${version("main.js")}"`,
    `href="/style.css?v=${version("style.css")}"`,
    `from "/jorn.js?v=${version("jorn.js")}"`,
  ]) {
    check(html.includes(ref), `${page.file} has ${ref}`, { html: html.slice(0, 400) });
  }
}

// What search engines and link previews read: each page's own description,
// canonical address and Open Graph tags, JSON-LD for posts, and noindex on
// the page for missing addresses.
for (const page of pages) {
  const { document } = new JSDOM(read(page.file)).window;
  const meta = (selector) => document.querySelector(`meta[${selector}]`)?.getAttribute("content");
  const canonical = document.querySelector('link[rel="canonical"]')?.getAttribute("href");
  if (page.file === "404.html") {
    check(meta('name="robots"') === "noindex", "the 404 page says noindex");
    check(canonical === undefined, "the 404 page has no canonical address", { canonical });
    continue;
  }
  const post = page.at.startsWith("/posts/");
  check(canonical === `https://example.com${page.at}`, `${page.file}'s canonical address is where it's served`, { canonical });
  check(meta('property="og:url"') === canonical, `${page.file}'s og:url is its canonical address`);
  check(meta('property="og:title"') === document.title, `${page.file}'s og:title is its title`);
  check((meta('name="description"') ?? "").length > 20, `${page.file} has a description`);
  check(meta('property="og:description"') === meta('name="description"'), `${page.file}'s og:description is its description`);
  check(meta('property="og:type"') === (post ? "article" : "website"), `${page.file}'s og:type`);
  const ld = document.querySelector('script[type="application/ld+json"]');
  if (post) {
    let data = {};
    try {
      data = JSON.parse(ld?.textContent);
    } catch {
      // Checked below.
    }
    check(data["@type"] === "BlogPosting", `${page.file} says it's a post in JSON-LD`, { ld: ld?.textContent });
    check(data.headline === document.querySelector("h1")?.textContent, `${page.file}'s JSON-LD has its headline`);
    check(data.url === canonical, `${page.file}'s JSON-LD has its address`);
  } else {
    check(ld === null, `${page.file} has no JSON-LD`);
  }
}

// In the browser, each page's app starts at the page's address and mounts
// the same view over the HTML, so nothing changes.
for (const page of pages) {
  const { window } = new JSDOM(read(page.file), { url: `https://example.com${page.at}` });
  const { document } = window;
  const container = document.getElementById("app");
  const html = container.innerHTML;
  const title = document.title;
  const prerendered = container.firstChild;
  check(container.childElementCount === 1, `${page.file} has the app's view in #app`);
  if (page.h1) check(document.querySelector("h1")?.textContent === page.h1, `${page.file} shows ${page.h1} before the app starts`);
  if (page.title) check(title === page.title, `${page.file} has its title`, { title });

  const app = start(Elm.Main, container);
  await until(() => container.firstChild !== prerendered, `the app mounts over ${page.file}`);
  check(container.innerHTML === html, `mounting over ${page.file} changes nothing`, { before: html, after: container.innerHTML });
  check(document.title === title, `the app keeps ${page.file}'s title`, { title: document.title });
  app.shutdown();
  window.close();
}

// Then the page is the app: links change the address and the view without
// loading a page, and the filter works.
{
  const { window } = new JSDOM(read("index.html"), { url: "https://example.com/" });
  const { document } = window;
  const container = document.getElementById("app");
  const prerendered = container.firstChild;
  start(Elm.Main, container);
  await until(() => container.firstChild !== prerendered, "the app mounts over the front page");

  const click = (element) => element.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true, button: 0 }));
  const h1 = () => document.querySelector("h1")?.textContent;

  click(document.querySelector('nav a[href="/about/"]'));
  await until(() => h1() === "About", "About shows after clicking its link", () => ({ h1: h1() }));
  check(window.location.href === "https://example.com/about/", "the address is About's", { href: window.location.href });
  check(document.title === "About · Notes", "the title is About's", { title: document.title });
  check(document.querySelector('nav a[aria-current="page"]')?.textContent === "About", "the nav marks About");

  window.history.back();
  await until(() => h1() === "Posts", "back goes to the posts", () => ({ h1: h1() }));
  check(window.location.href === "https://example.com/", "back to the front page's address", { href: window.location.href });

  const input = document.querySelector('input[type="search"]');
  input.value = "twice";
  input.dispatchEvent(new window.Event("input", { bubbles: true }));
  await until(
    () => document.querySelectorAll(".posts li").length === 1,
    "the filter leaves one post",
    () => ({ shown: document.querySelectorAll(".posts li").length }),
  );

  click(document.querySelector(".posts li a"));
  await until(() => h1() === "The same view, twice", "the post shows after clicking it", () => ({ h1: h1() }));
  check(window.location.href === "https://example.com/posts/the-same-view-twice/", "the address is the post's", {
    href: window.location.href,
  });
  window.close();
}

if (failed > 0) {
  console.log(`${failed} check(s) failed`);
  process.exit(1);
}
console.log("The example site builds, every page mounts without a change, and the app takes over.");
