// Plays the part of the browser: prints what Jorn sends, and fires a few
// events back at it.
//
//   elm make src/Main.elm --output=build/main.js
//   node run.mjs

import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { Elm } = require("./build/main.js");

const app = Elm.Main.init();
const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

app.ports.toClient.subscribe((message) => {
  console.log("server -> client", JSON.stringify(message));
});

async function fire(event) {
  await tick();
  console.log("\nclient -> server", JSON.stringify(event));
  app.ports.fromClient.send(event);
}

await fire({ path: [4], name: "click", event: {} });
await fire({ path: [4], name: "click", event: {} });
await fire({ path: [1], name: "input", event: { target: { value: "Jorn" } } });
await fire({ path: [3], name: "click", event: {} });
await tick();
