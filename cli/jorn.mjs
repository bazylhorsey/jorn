#!/usr/bin/env node
// The jorn command. For now it has one job, building a static site:
//
//   node jorn/cli/jorn.mjs build [site] [--out folder] [--elm command]
//
// See README.md here, and Jorn.Static for the site itself.

import { parseArgs } from "node:util";
import { build } from "./build.mjs";

const usage = `Usage: jorn build [site] [--out folder] [--elm command]

Builds the static site that site, a Jorn.Static program, describes, into a
folder any static host can serve as it is. Run it in the folder with your
app's elm.json.

  site            the site's Elm file (src/Site.elm if you leave it out)
  --out folder    where the site goes, replacing what's there (build)
  --elm command   the elm to compile with (the one npm installed, or elm)
`;

async function main() {
  let parsed;
  try {
    parsed = parseArgs({
      allowPositionals: true,
      options: { out: { type: "string" }, elm: { type: "string" }, help: { type: "boolean", short: "h" } },
    });
  } catch (error) {
    return fail(`${error.message}\n\n${usage}`);
  }
  const { values, positionals } = parsed;
  if (values.help) return process.stdout.write(usage);
  const [command, site, ...extra] = positionals;
  if (command !== "build" || extra.length > 0) return fail(usage);

  try {
    await build({ site, out: values.out, elm: values.elm });
  } catch (error) {
    fail(error.message);
  }
}

// Exit once the message is out, even if something the site started is still
// running.
function fail(message) {
  process.stderr.write(`${message}\n`, () => process.exit(1));
}

await main();
