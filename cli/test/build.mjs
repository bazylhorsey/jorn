// Tests for `jorn build` (cli/build.mjs), with small sites in a project of
// their own in a temporary folder: where each kind of path and asset goes,
// the hashes in pages' URLs, a site served from a folder, replacing the last
// build, and every mistake it should stop at without touching the last build.
//
// Usage: node cli/test/build.mjs
// Needs elm, from `npm install elm` at the repository's root or on the PATH.

import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "../build.mjs";

const jorn = fileURLToPath(new URL("../../", import.meta.url));
const installed = join(jorn, "node_modules", ".bin", "elm");
const elm = existsSync(installed) ? installed : "elm";

let failed = 0;
function check(condition, what, detail = {}) {
  if (!condition) {
    failed++;
    console.log(`FAILED: ${what}`, JSON.stringify(detail));
  }
}

const project = await mkdtemp(join(tmpdir(), "jorn-build-test-"));
const out = join(project, "build");
const read = (path) => readFileSync(join(out, path), "utf8");
const version = (path) => createHash("sha256").update(readFileSync(join(out, path))).digest("hex").slice(0, 10);

async function file(path, contents) {
  await mkdir(dirname(join(project, path)), { recursive: true });
  await writeFile(join(project, path), contents);
}

await file(
  "elm.json",
  JSON.stringify({
    type: "application",
    "source-directories": ["src", join(jorn, "src")],
    "elm-version": "0.19.1",
    dependencies: { direct: { "elm/core": "1.0.5", "elm/json": "1.1.3", "elm/url": "1.0.0" }, indirect: {} },
    "test-dependencies": { direct: {}, indirect: {} },
  }),
);
await file("assets/style.css", "body { color: red; }\n");
await file("assets/img/logo.svg", "<svg></svg>\n");
await file("single.txt", "one file\n");
await file("clash/index.html", "<p>not a page</p>\n");

// An app with URL routing. Its `record` has its ports in it, which a site
// can't use.
await file(
  "src/App.elm",
  String.raw`port module App exposing (main, record)

import Jorn
import Jorn.Effect as Effect
import Jorn.Navigation as Navigation
import Json.Encode exposing (Value)


port toJorn : Value -> Cmd msg


port fromJorn : (Value -> msg) -> Sub msg


record =
    { init = \_ _ _ -> ( (), Effect.none )
    , update = \_ model -> ( model, Effect.none )
    , view = \_ -> { title = "App", body = [] }
    , subscriptions = \_ -> Sub.none
    , onUrlRequest = \_ -> ()
    , onUrlChange = \_ -> ()
    , ports = { toJorn = toJorn, fromJorn = fromJorn }
    }


main : Jorn.Program () () ()
main =
    Navigation.application record
`,
);

// A site served from a folder of its domain, with every kind of page path
// and asset.
await file(
  "src/Good.elm",
  String.raw`port module Good exposing (main)

import Jorn.Attribute as Attr
import Jorn.Element as Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Static as Static
import Json.Encode exposing (Value)
import Url exposing (Url)


port toJorn : Value -> Cmd msg


main : Static.Program
main =
    Static.site toJorn
        { url = "https://you.github.io/project/"
        , pages =
            [ Static.page "/" home
            , Static.page "/a/b" show
            , Static.page "/x.html" show
            , Static.page "/caf%C3%A9/" show
            ]
        , assets =
            [ Static.copy "assets" "/"
            , Static.copy "single.txt" "/docs/"
            , Static.copy "single.txt" "/renamed.txt"
            , Static.compile "src/App.elm" "/app.js"
            , Static.file "/robots.txt" "User-agent: *\nAllow: /\n"
            ]
        }


home : Url -> Element msg
home _ =
    Html.html []
        [ Html.head []
            [ Html.link [ Attr.rel "stylesheet", Attr.href "/project/style.css" ]
            , Html.link [ Attr.rel "stylesheet", Attr.href "/style.css" ]
            ]
        , Html.body []
            [ Html.p [] [ Element.text "\"/project/app.js\"" ]
            , Html.script [ Attr.src "/project/app.js" ] []
            , Html.script [ Attr.src "/project/missing.js" ] []
            , Html.script [ Attr.type_ "module" ] [ Element.text "import '/project/app.js'; const logo = \"/project/img/logo.svg\";" ]
            , Html.a [ Attr.href "https://example.com/project/app.js" ] [ Element.text "elsewhere" ]
            ]
        ]


show : Url -> Element msg
show url =
    Html.html [] [ Html.body [] [ Html.p [] [ Element.text (Url.toString url) ] ] ]
`,
);

const result = await build({ cwd: project, site: "src/Good.elm", elm, log: { info() {}, warn() {} } });

const files = [
  "index.html",
  "a/b/index.html",
  "x.html",
  "café/index.html",
  "style.css",
  "img/logo.svg",
  "docs/single.txt",
  "renamed.txt",
  "app.js",
  "robots.txt",
  "jorn.js",
];
for (const path of files) check(existsSync(join(out, path)), `the site has ${path}`);
check(
  JSON.stringify([...result.files].sort()) === JSON.stringify([...files].sort()),
  "build lists every file it wrote",
  { files: result.files },
);
check(
  JSON.stringify(result.pages) === JSON.stringify(["index.html", "a/b/index.html", "x.html", "café/index.html"]),
  "build lists the pages",
  { pages: result.pages },
);
check(read("img/logo.svg") === "<svg></svg>\n", "a folder's files are copied with their folders");
check(read("docs/single.txt") === "one file\n", "a file copied to a folder keeps its name");
check(read("robots.txt") === "User-agent: *\nAllow: /\n", "a file's text is written as it is");
check(read("jorn.js") === readFileSync(join(jorn, "client/jorn.js"), "utf8"), "jorn.js is client/jorn.js");

check(read("a/b/index.html").includes("<p>https://you.github.io/project/a/b</p>"), "a page gets its URL, in the site's folder", {
  html: read("a/b/index.html"),
});
check(read("x.html").includes("<p>https://you.github.io/project/x.html</p>"), "a page ending in .html is that file");
check(read("café/index.html").includes("<p>https://you.github.io/project/caf%C3%A9/</p>"), "an escaped path is written to the file it names");

const home = read("index.html");
for (const [ref, what] of [
  [`href="/project/style.css?v=${version("style.css")}"`, "a stylesheet's URL gets its hash"],
  [`src="/project/app.js?v=${version("app.js")}"`, "a script's URL gets its hash"],
  [`import '/project/app.js?v=${version("app.js")}'`, "so does a string in an inline script"],
  [`"/project/img/logo.svg"`, "an image keeps its URL"],
  [`<p>"/project/app.js"</p>`, "text outside scripts is left alone"],
  [`href="https://example.com/project/app.js"`, "another site's URL is left alone"],
  [`src="/project/missing.js"`, "a script the site doesn't have is left alone"],
  [`href="/style.css"`, "a URL outside the site's folder is left alone"],
]) {
  check(home.includes(ref), what, { ref, home });
}
check(
  result.warnings.some((warning) => warning.includes("/project/missing.js")),
  "a script the site doesn't have is a warning",
  { warnings: result.warnings },
);
check(
  result.warnings.some((warning) => warning.includes("/style.css,") && warning.includes("served from /project/")),
  "so is a stylesheet outside the site's folder",
  { warnings: result.warnings },
);

// A new build replaces the last one.
await writeFile(join(out, "stale.txt"), "from before\n");
await build({ cwd: project, site: "src/Good.elm", elm, log: { info() {}, warn() {} } });
check(!existsSync(join(out, "stale.txt")), "a build replaces what was there");

// Sites with mistakes. Each one has to fail with a message that says what's
// wrong, leave the last build as it was, and leave nothing else behind.
function site(name, { url = "https://example.com", pages = `[ Static.page "/" empty ]`, assets = "[]", extra = "" } = {}) {
  return String.raw`port module ${name} exposing (main)

import App
import Jorn.Element exposing (Element)
import Jorn.Element.Html as Html
import Jorn.Static as Static
import Json.Encode exposing (Value)
import Url exposing (Url)


port toJorn : Value -> Cmd msg


main : Static.Program
main =
    Static.site toJorn { url = ${JSON.stringify(url)}, pages = ${pages}, assets = ${assets} }


empty : Url -> Element msg
empty _ =
    Html.html [] []
${extra}`;
}

const mistakes = [
  {
    name: "Twice",
    source: site("Twice", { pages: `[ Static.page "/about" empty, Static.page "/About/" empty ]` }),
    message: /The page \/About\/ and the page \/about both go to About\/index\.html/,
  },
  {
    name: "Escape",
    source: site("Escape", { pages: `[ Static.page "/a/../../x" empty ]` }),
    message: /The page \/a\/\.\.\/\.\.\/x has a path that would leave the site/,
  },
  {
    name: "Empty",
    source: site("Empty", { assets: `[ Static.file "/a//b" "x" ]` }),
    message: /The file \/a\/\/b has a path that would leave the site, or has an empty part/,
  },
  {
    name: "Clash",
    source: site("Clash", { assets: `[ Static.copy "clash" "/" ]` }),
    message: /The page \/ and clash\/index\.html both go to index\.html/,
  },
  {
    name: "Patcher",
    source: site("Patcher", { assets: `[ Static.file "/jorn.js" "x" ]` }),
    message: /Jorn's own client\/jorn\.js and the file \/jorn\.js both go to jorn\.js/,
  },
  {
    name: "FileAndFolder",
    source: site("FileAndFolder", { pages: `[ Static.page "/a" empty ]`, assets: `[ Static.file "/a" "x" ]` }),
    message: /The page \/a goes in a, which is a file from the file \/a/,
  },
  {
    name: "BadUrl",
    source: site("BadUrl", { url: "example.com" }),
    message: /The site's url, example\.com, isn't a URL/,
  },
  {
    name: "Relative",
    source: site("Relative", { pages: `[ Static.page "about" empty ]` }),
    message: /The page about needs a path from the site's root/,
  },
  {
    name: "Unrooted",
    source: site("Unrooted", { assets: `[ Static.file "robots.txt" "x" ]` }),
    message: /The file robots\.txt needs a path from the site's root/,
  },
  {
    name: "Query",
    source: site("Query", { assets: `[ Static.file "/a?b" "x" ]` }),
    message: /has a path with a query/,
  },
  {
    name: "NoSource",
    source: site("NoSource", { assets: `[ Static.copy "nope" "/" ]` }),
    message: /There's no nope to copy/,
  },
  {
    name: "NotJs",
    source: site("NotJs", { assets: `[ Static.compile "src/App.elm" "/app.txt" ]` }),
    message: /its path in the site should end in \.js/,
  },
  {
    name: "Everything",
    source: site("Everything", { assets: `[ Static.copy "." "/" ]` }),
    message: /The site goes in build, so \. can't be copied into it/,
  },
  {
    name: "Ports",
    source: site("Ports", {
      pages: `[ Static.page "/" app ]`,
      extra: String.raw`

app : Url -> Element ()
app url =
    (Static.view App.record () url).body
`,
    }),
    message: /two ports with the same name/,
  },
  {
    name: "NotSite",
    source: String.raw`port module NotSite exposing (main)

import Json.Encode exposing (Value)


port toJorn : Value -> Cmd msg


main : Program () () Never
main =
    Platform.worker { init = \_ -> ( (), toJorn Json.Encode.null ), update = \_ m -> ( m, Cmd.none ), subscriptions = \_ -> Sub.none }
`,
    message: /src\/NotSite\.elm didn't send a site/,
  },
  {
    name: "NoPort",
    source: String.raw`module NoPort exposing (main)


main : Program () () Never
main =
    Platform.worker { init = \_ -> ( (), Cmd.none ), update = \_ m -> ( m, Cmd.none ), subscriptions = \_ -> Sub.none }
`,
    message: /src\/NoPort\.elm isn't a Jorn\.Static site/,
  },
  {
    name: "Broken",
    source: site("Broken", { pages: "[ Static.page ]" }),
    message: /elm make src\/Broken\.elm failed/,
    note: "(An Elm error about Broken.elm is expected here.)",
  },
  {
    name: "BrokenApp",
    source: site("BrokenApp", { assets: `[ Static.compile "src/Broken.elm" "/app.js" ]` }),
    message: /elm make src\/Broken\.elm failed/,
    note: "(And the same one again, as the site compiles it.)",
  },
];

for (const mistake of mistakes) await file(`src/${mistake.name}.elm`, mistake.source);
const built = read("index.html");

async function fails(what, options, message) {
  try {
    await build({ cwd: project, elm, log: { info() {}, warn() {} }, ...options });
    check(false, `${what} fails`);
  } catch (error) {
    check(message.test(error.message), `${what} fails, saying so`, { message: error.message });
  }
  check(existsSync(join(out, "index.html")) && read("index.html") === built, `${what} leaves the last build as it was`);
  const left = (await readdir(project)).filter((name) => name.startsWith("."));
  check(left.length === 0, `${what} leaves nothing behind`, { left });
}

for (const mistake of mistakes) {
  if (mistake.note) console.log(mistake.note);
  await fails(mistake.name, { site: `src/${mistake.name}.elm` }, mistake.message);
}
await fails("A missing site", { site: "src/Nope.elm" }, /There's no site at src\/Nope\.elm/);
await fails("Building into the project itself", { site: "src/Good.elm", out: "." }, /has to go in a folder inside this one/);
await fails("Building outside the project", { site: "src/Good.elm", out: "../elsewhere" }, /has to go in a folder inside this one/);
await fails("Building over the site's source", { site: "src/Good.elm", out: "src" }, /src\/Good\.elm is inside src/);
await fails("Building with no elm", { site: "src/Good.elm", elm: join(project, "no-elm") }, /There's no .*no-elm to compile with/);

await rm(project, { recursive: true, force: true });

if (failed > 0) {
  console.log(`${failed} check(s) failed`);
  process.exit(1);
}
console.log(`jorn build writes every kind of page and asset, and stops at ${mistakes.length + 5} kinds of mistake.`);
