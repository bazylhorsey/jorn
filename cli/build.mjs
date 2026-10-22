// `jorn build`: run a Jorn.Static site and write the site it describes to a
// folder that any static host can serve as it is.
//
//   import { build } from "./build.mjs";
//
//   await build({ site: "src/Site.elm", out: "build" });
//
// The site is an Elm program, so it's compiled with `elm make` and run here,
// in Node. It sends its pages, already rendered to HTML, and its assets
// through its `toJorn` port. Everything is checked before anything is
// written, and the site is put together in a folder next to `out`, which
// only replaces `out` once it's whole. A build that fails leaves the last one
// where it was.

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { copyFile, mkdir, mkdtemp, readdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

// The browser patcher from the same checkout, so the page and the Elm code
// it was built with always match.
const patcher = fileURLToPath(new URL("../client/jorn.js", import.meta.url));

// Files whose URLs get a hash of their contents. Fonts and images keep their
// URLs, so a preload and the stylesheet that uses the file still agree.
const versioned = /\.(?:m?js|css)$/;

/**
 * Build the site that `site`, a Jorn.Static program, describes into `out`.
 * Paths are relative to `cwd`, which has the elm.json the site compiles
 * with. `elm` is the command to compile with: by default the one npm
 * installed here or in a folder above, or else `elm`.
 *
 * Throws an Error that says what went wrong, for people.
 *
 * @param {{ site?: string, out?: string, elm?: string, cwd?: string, log?: { info: Function, warn: Function } }} options
 * @returns {Promise<{ pages: string[], files: string[], warnings: string[] }>}
 */
export async function build({ site = "src/Site.elm", out = "build", elm, cwd = process.cwd(), log = console } = {}) {
  cwd = resolve(cwd);
  elm ??= findElm(cwd);
  const outDir = resolve(cwd, out);
  if (!existsSync(join(cwd, "elm.json"))) {
    throw new Error(`There's no elm.json in ${cwd}. Run jorn build in the folder with your app's elm.json.`);
  }
  if (!inside(outDir, cwd)) {
    throw new Error(`The site has to go in a folder inside this one, since jorn build replaces it. ${out} isn't one.`);
  }
  if (!existsSync(resolve(cwd, site))) throw new Error(`There's no site at ${site}.`);
  if (inside(resolve(cwd, site), outDir)) throw new Error(`${site} is inside ${out}, which jorn build replaces.`);

  const description = await describe(elm, cwd, site, log);
  const base = basePath(description.url);
  const plan = await planSite(description, cwd, outDir, out);

  const partial = join(dirname(outDir), `.${basename(outDir)}.partial`);
  await rm(partial, { recursive: true, force: true });
  await mkdir(partial, { recursive: true });
  const warnings = [];
  try {
    for (const step of plan.steps) {
      const target = join(partial, ...step.to);
      await mkdir(dirname(target), { recursive: true });
      if (step.copy) {
        await copyFile(step.copy, target);
      } else if (step.compile) {
        log.info(`Compiling ${step.compile} to /${step.to.join("/")}`);
        await elmMake(elm, cwd, step.compile, target);
      } else {
        await writeFile(target, step.text);
      }
    }

    const hashes = new Map();
    for (const step of plan.steps) {
      const path = step.to.join("/");
      if (versioned.test(path)) hashes.set(path, hash(await readFile(join(partial, ...step.to))));
    }
    for (const page of plan.pages) {
      const missing = new Set();
      const html = stamp(page.html, base, hashes, missing);
      for (const ref of missing) {
        const where = base === "/" ? "" : `, which is served from ${base}`;
        warnings.push(`${page.to.join("/")} refers to ${ref}, which isn't in the site${where}.`);
      }
      const target = join(partial, ...page.to);
      await mkdir(dirname(target), { recursive: true });
      await writeFile(target, html);
    }

    await rm(outDir, { recursive: true, force: true });
    await rename(partial, outDir);
  } catch (error) {
    await rm(partial, { recursive: true, force: true });
    throw error;
  }

  for (const warning of warnings) log.warn(`Warning: ${warning}`);
  const pages = plan.pages.map((page) => page.to.join("/"));
  const files = plan.steps.map((step) => step.to.join("/"));
  const count = (n, what) => `${n} ${what}${n === 1 ? "" : "s"}`;
  log.info(`Built ${count(pages.length, "page")} and ${count(files.length, "other file")} in ${relative(cwd, outDir)}`);
  return { pages, files: [...files, ...pages], warnings };
}

// Compile the site and run it, and return what it sends: its URL, its pages
// with their HTML, and its assets.
async function describe(elm, cwd, site, log) {
  const temp = await mkdtemp(join(tmpdir(), "jorn-build-"));
  try {
    const compiled = join(temp, "site.js");
    log.info(`Compiling ${site}`);
    await elmMake(elm, cwd, site, compiled);

    let app;
    try {
      // Elm's output puts `Elm` on whatever `this` is when it runs.
      const scope = {};
      new Function(await readFile(compiled, "utf8")).call(scope);
      app = findProgram(scope.Elm)?.init();
    } catch (error) {
      if (String(error?.message).includes("hints/3.md")) {
        throw new Error(
          `${site} has two ports with the same name, so it can't start. A site has a toJorn port of its own, so it can use your app's init and view but not its main or ports.`,
        );
      }
      throw new Error(`${site} failed as it started: ${error?.message ?? error}`);
    }
    const port = app?.ports?.toJorn;
    if (typeof port?.subscribe !== "function") {
      throw new Error(`${site} isn't a Jorn.Static site. Its main should be Static.site, given a port called toJorn.`);
    }
    const message = await new Promise((resolve) => {
      const timer = setTimeout(() => resolve(null), 5000);
      port.subscribe((value) => {
        clearTimeout(timer);
        resolve(value);
      });
    });
    if (typeof message?.error === "string") throw new Error(message.error);
    const description = message?.site;
    if (
      typeof description?.url !== "string" ||
      !Array.isArray(description.pages) ||
      !Array.isArray(description.assets)
    ) {
      throw new Error(`${site} didn't send a site. Its main should be Static.site.`);
    }
    return description;
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
}

// Check every path and source, and list what goes where, before anything is
// written: each step copies, compiles or writes one file, and each page is
// written last, once the files it refers to are there to hash.
async function planSite(description, cwd, outDir, out) {
  const files = new Map();
  const folders = new Map();
  // Two things in one place is a mistake, even when only the case of the
  // name differs, since some file systems don't tell those apart.
  function claim(to, what) {
    const path = to.join("/");
    const key = path.toLowerCase();
    const there = files.get(key) ?? folders.get(key);
    if (there) throw new Error(`${capitalize(what)} and ${there} both go to ${path}.`);
    for (let n = 1; n < to.length; n++) {
      const folder = to.slice(0, n).join("/");
      const file = files.get(folder.toLowerCase());
      if (file) throw new Error(`${capitalize(what)} goes in ${folder}, which is a file from ${file}.`);
      if (!folders.has(folder.toLowerCase())) folders.set(folder.toLowerCase(), what);
    }
    files.set(key, what);
  }

  const steps = [];
  for (const asset of description.assets) {
    if (typeof asset?.copy === "string") {
      const from = resolve(cwd, asset.copy);
      const info = await stat(from).catch(() => null);
      if (!info) throw new Error(`There's no ${asset.copy} to copy.`);
      if (outDir === from || inside(outDir, from)) throw new Error(`The site goes in ${out}, so ${asset.copy} can't be copied into it.`);
      if (inside(from, outDir)) throw new Error(`${asset.copy} is inside ${out}, which jorn build replaces.`);
      const to = sitePath(asset.to, `the copy of ${asset.copy}`);
      if (info.isDirectory()) {
        for (const file of await listFiles(from)) {
          const what = join(asset.copy, ...file);
          claim([...to, ...file], what);
          steps.push({ copy: join(from, ...file), to: [...to, ...file] });
        }
      } else {
        const target = asset.to.endsWith("/") ? [...to, basename(from)] : to;
        if (target.length === 0) throw new Error(`The copy of ${asset.copy} needs a file name, like "/${basename(from)}".`);
        claim(target, asset.copy);
        steps.push({ copy: from, to: target });
      }
    } else if (typeof asset?.compile === "string") {
      const to = sitePath(asset.to, `the compiled ${asset.compile}`);
      if (!to.at(-1)?.endsWith(".js")) throw new Error(`${asset.compile} compiles to JavaScript, so its path in the site should end in .js.`);
      if (!existsSync(resolve(cwd, asset.compile))) throw new Error(`There's no ${asset.compile} to compile.`);
      if (inside(resolve(cwd, asset.compile), outDir)) throw new Error(`${asset.compile} is inside ${out}, which jorn build replaces.`);
      claim(to, asset.compile);
      steps.push({ compile: asset.compile, to });
    } else if (typeof asset?.text === "string") {
      const to = sitePath(asset.to, `the file ${asset.to}`);
      if (to.length === 0 || asset.to.endsWith("/")) throw new Error(`The file ${asset.to} needs a file name, like "/robots.txt".`);
      claim(to, `the file ${asset.to}`);
      steps.push({ text: asset.text, to });
    } else {
      throw new Error(`The site has an asset jorn build doesn't know: ${JSON.stringify(asset)}`);
    }
  }
  claim(["jorn.js"], "Jorn's own client/jorn.js");
  steps.push({ copy: patcher, to: ["jorn.js"] });

  const pages = [];
  for (const page of description.pages) {
    const to = sitePath(page.path, `the page ${page.path}`);
    const file = to.at(-1)?.endsWith(".html") && !page.path.endsWith("/") ? to : [...to, "index.html"];
    claim(file, `the page ${page.path}`);
    pages.push({ html: String(page.html), to: file });
  }
  return { steps, pages };
}

// A path from the site's root, like "/posts/hello", as the names of the
// folders and file it's written to.
function sitePath(path, what) {
  if (typeof path !== "string" || !path.startsWith("/") || path.startsWith("//")) {
    throw new Error(`${capitalize(what)} needs a path from the site's root, which starts with one /, not ${JSON.stringify(path)}.`);
  }
  if (/[?#\\]/.test(path)) throw new Error(`${capitalize(what)} has a path with a query, a fragment or a backslash: ${path}`);
  const parts = path.slice(1).split("/");
  if (parts.at(-1) === "") parts.pop();
  return parts.map((part) => {
    let name = null;
    try {
      name = decodeURIComponent(part);
    } catch {
      // Not a name, so the check below says so.
    }
    if (name === null || name === "" || name === "." || name === ".." || /[/\\\0]/.test(name)) {
      throw new Error(`${capitalize(what)} has a path that would leave the site, or has an empty part: ${path}`);
    }
    return name;
  });
}

// The path the site is served from: "/" for a site at a domain's root, or
// the folder, like "/project/".
function basePath(url) {
  let path = "/";
  try {
    path = new URL(url).pathname;
  } catch {
    // Static.site checked it.
  }
  return path.endsWith("/") ? path : `${path}/`;
}

// Add `?v=` and a hash of the file to each URL in a page that refers to one
// of the site's scripts or stylesheets from the root: in `src` and `href`
// attributes, and in strings in inline scripts and styles, like an `import`.
// Text elsewhere on the page is left as it is. Jorn writes attribute values
// in double quotes and escapes `>` in them, so a tag ends at the first `>`.
function stamp(html, base, hashes, missing) {
  const version = (ref) => {
    if (!ref.startsWith("/") || ref.startsWith("//") || /[?#&]/.test(ref) || !versioned.test(ref)) return ref;
    let path = null;
    if (ref.startsWith(base)) {
      try {
        path = ref.slice(base.length).split("/").map(decodeURIComponent).join("/");
      } catch {
        // Not a path in the site.
      }
    }
    const hash = path === null ? undefined : hashes.get(path);
    if (hash === undefined) {
      missing.add(ref);
      return ref;
    }
    return `${ref}?v=${hash}`;
  };
  const inTag = (tag) => tag.replace(/(\s(?:src|href)=")([^"]*)"/g, (_, before, ref) => `${before}${version(ref)}"`);
  const inText = (text) => text.replace(/(["'`])(\/[^"'`\s]*)\1/g, (_, quote, ref) => `${quote}${version(ref)}${quote}`);
  return html.replace(/<(script|style)(?=[\s>])([^>]*)>([\s\S]*?)<\/\1>|<[a-zA-Z][^>]*>/g, (tag, raw, attributes, text) =>
    raw === undefined ? inTag(tag) : `<${raw}${inTag(attributes)}>${inText(text)}</${raw}>`,
  );
}

function hash(contents) {
  return createHash("sha256").update(contents).digest("hex").slice(0, 10);
}

// Every file in a folder, following links, as lists of names from it.
async function listFiles(folder, prefix = []) {
  const found = [];
  for (const name of (await readdir(folder)).sort()) {
    const info = await stat(join(folder, name));
    if (info.isDirectory()) found.push(...(await listFiles(join(folder, name), [...prefix, name])));
    else if (info.isFile()) found.push([...prefix, name]);
  }
  return found;
}

// `Elm.Site`, or `Elm.My.Site` for a module called My.Site.
function findProgram(scope) {
  if (!scope || typeof scope !== "object") return null;
  if (typeof scope.init === "function") return scope;
  for (const value of Object.values(scope)) {
    const program = findProgram(value);
    if (program) return program;
  }
  return null;
}

// The elm that npm installed here or in a folder above, like `npx elm`
// would find, or the one on the PATH.
function findElm(cwd) {
  for (let folder = cwd; ; folder = dirname(folder)) {
    const elm = join(folder, "node_modules", ".bin", "elm");
    if (existsSync(elm)) return elm;
    if (dirname(folder) === folder) return "elm";
  }
}

// elm make, showing its errors and not its progress.
function elmMake(elm, cwd, input, output) {
  return new Promise((resolve, reject) => {
    const child = spawn(elm, ["make", input, "--optimize", `--output=${output}`], {
      cwd,
      stdio: ["ignore", "ignore", "inherit"],
    });
    child.on("error", (error) =>
      reject(
        new Error(
          error.code === "ENOENT"
            ? `There's no ${elm} to compile with. Install Elm with npm install elm, or say where it is with --elm.`
            : `Couldn't run ${elm}: ${error.message}`,
        ),
      ),
    );
    child.on("close", (code) => (code === 0 ? resolve() : reject(new Error(`elm make ${input} failed.`))));
  });
}

function capitalize(text) {
  return text.charAt(0).toUpperCase() + text.slice(1);
}

// Whether `path` is somewhere inside `folder`, and not `folder` itself.
function inside(path, folder) {
  const rel = relative(folder, path);
  return rel !== "" && rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel);
}
