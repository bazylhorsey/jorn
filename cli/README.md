# cli/jorn.mjs

The `jorn` command. For now it does one thing: build a static site. It runs a site written with `Jorn.Static`, an Elm program that lists pages and files, and writes the site to a folder that any static host serves as it is, like GitHub Pages.

## Building a site

Run it in the folder with your app's `elm.json`:

```
node path/to/jorn/cli/jorn.mjs build
```

Or install the command once with `npm install --save-dev path/to/jorn/cli`, and run `npx jorn build`.

```
jorn build [site] [--out folder] [--elm command]
```

- `site` is the site's Elm file: `src/Site.elm` if you leave it out.
- `--out` is where the site goes: `build` if you leave it out. It has to be a folder inside this one, since each build replaces it.
- `--elm` is the `elm` to compile with. By default it's the one npm installed here or in a folder above, or else the one on your PATH.

It compiles the site with `elm make --optimize` and runs it in Node. The site sends every page, already rendered to HTML, and its assets. Then `jorn build`:

1. Checks every path before it writes anything. Two things can't go in one place, even when only the case of their names differs, since some file systems don't tell those apart. Nothing can go outside the site, and nothing it reads can be inside the folder it replaces.
2. Copies and compiles the assets, writes each `Static.file`, and copies `client/jorn.js` to `/jorn.js`, from the same checkout as the command, so the page and your Elm code always match.
3. Writes each page: `"/"` to `index.html`, `"/about/"` or `"/about"` to `about/index.html`, and `"/404.html"` to `404.html`.
4. Adds `?v=` and a hash of the file's contents to every URL in a page that refers to one of the site's scripts or stylesheets (`.js`, `.mjs` or `.css`) from the root. That covers `src` and `href` attributes, and strings in inline scripts and styles, like the `"/jorn.js"` in `import { start } from "/jorn.js"`. A returning visitor never gets new HTML with an old script. Fonts and images keep their URLs, so a preload and the stylesheet that uses the font still agree. A page that refers to a script or stylesheet the site doesn't have gets a warning.

The site is put together next to the output folder, and replaces it only once it's whole, so a build that fails leaves the last one as it was.

To look at it, serve the folder with any static file server, such as `python3 -m http.server --directory build 8080`.

## A site in a folder

For a site served from a folder of its domain, like a GitHub project page at `https://you.github.io/project/`, give `Static.site` that URL. Pages and assets still have paths from the site's root, like `"/about/"`, and each page gets its whole URL. The URLs in your pages need the folder in front, like `"/project/main.js"`, and that's where `jorn build` looks for the files to hash.

## From code

`build` in [build.mjs](build.mjs) does the same thing, for scripts and tests:

```js
import { build } from "./jorn/cli/build.mjs";

const { pages, files, warnings } = await build({ site: "src/Site.elm", out: "build" });
```

It takes `cwd` and `log` too, and throws an `Error` whose message says what went wrong.

## Tests

[test/build.mjs](test/build.mjs) builds small sites in a project of their own: every kind of page path and asset, hashes, a site in a folder, and the mistakes `jorn build` has to stop at without touching the last build. CI runs it, and builds [examples/site](../examples/site), which [client/test/site.mjs](../client/test/site.mjs) opens in jsdom.
