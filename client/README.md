# client/jorn.js

The browser side of Jorn. It applies [Jorn's wire protocol](../PROTOCOL.md) to the DOM and reports events back. One small ES module, no dependencies.

## Starting an app

For an app built with `Jorn.simple` or `Jorn.application`, `start` is all the page needs:

```js
import { start } from "./jorn.js";

const app = start(Elm.Main, document.getElementById("app"), {
  flags: { user: "Ada" },                             // what your init expects
  effects: { copy: (text) => navigator.clipboard.writeText(text) }, // for Effect.client
});

app.shutdown(); // stop the program and empty the container
```

The program has to declare two ports, `toJorn` and `fromJorn` (see the `Jorn` module). If yours have other names, pass `ports: { toJorn: "...", fromJorn: "..." }`.

## Showing an app that runs on a server

When the same program runs on a server with [server/jorn.js](../server), `stream` connects the page to it:

```js
import { stream } from "./jorn.js";

const app = stream(document.getElementById("app"), "/app", {
  flags: { theme: "dark" },                           // sent to the server, which decides whether to use them
  csrfToken,                                          // optional, for the server's authorize check
  effects: { copy: (text) => navigator.clipboard.writeText(text) }, // Effect.client still runs here
});

app.close(); // disconnect and empty the container
```

A relative address is resolved against the page, and `http` becomes `ws`. `csrfToken` goes to the server's `authorize` check. The page only applies patches and sends events back: `update`, `view` and commands run on the server, and focus, scrolling and `Effect.client` run here.

## Server components as elements

`defineServerComponent` defines `<jorn-server-component>`, the element `Jorn.ServerComponent.element` makes. Each one streams the component at its `route` into itself while it's in the document:

```html
<jorn-server-component route="/chat" flags='{"room":"elm"}'></jorn-server-component>

<script type="module">
  import { defineServerComponent } from "./jorn.js";

  defineServerComponent({ effects: { copy: (text) => navigator.clipboard.writeText(text) } });
</script>
```

It disconnects when it's removed, and moving it, for example in a keyed list, keeps the connection. Changing its `route`, `flags` or `csrf-token` reconnects. Events from `Effect.event` bubble out of it, so the page or an enclosing Jorn app can listen for them.

## Hosting a program yourself

`connect` is the lower level: it applies what you give it and reports events, and you move the messages. `start` and `stream` are built on it.

```js
import { connect } from "./jorn.js";

const jorn = connect(document.getElementById("app"), {
  send: (event) => socket.send(JSON.stringify(event)),
});

jorn.mount(tree);    // once, with the output of Jorn.Patch.encodeHtml
jorn.patch(patches); // after every update, with the output of Jorn.Patch.encode
```

`send` receives `{ path, name, event }`, the message the client event decoder reads.

## Two modes

- **Server mode** (the default). Events are reduced to plain JSON holding only the fields each handler asked for with `include`, so they can go over a socket. `stream` uses this mode.
- **Client mode**, `connect(container, { send, raw: true })`. Your Elm program runs in the same page, so `event` is the live event object and decoders can read anything on it. `start` uses this mode.

## API

| | |
|---|---|
| `start(program, container, { flags, effects, ports })` | Run a compiled Jorn program in `container`. Returns `{ shutdown() }`. |
| `stream(container, url, { flags, csrfToken, effects })` | Show a program running on a server in `container`, over a websocket. Returns `{ close() }`. |
| `defineServerComponent({ effects })` | Define `<jorn-server-component>`. Only the first call counts. |
| `connect(container, { send, raw, effects })` | Take over `container`. Its only child is the root of your view from here on. `effects` maps names to the functions `Effect.client` can call. |
| `.mount(node)` | Render a whole tree, replacing whatever was there. |
| `.patch(patches)` | Apply patches strictly in order. Throws on a patch that doesn't fit the page, which means the page and the server have drifted apart. |
| `.run(instructions)` | Run patcher instructions from `Jorn.Effect` (focus, scroll, custom events, named effects), in order. Call it after the patches they came with. |
| `.nodeAt(path)` | The DOM node at a path, or `null`. |
| `.unmount()` | Empty the container. |

## Behavior worth knowing

- `preventDefault` and `stopPropagation` are applied synchronously when the event fires, from the options Elm sent ahead of time.
- Paths are worked out when an event fires, so they're correct for whatever is on screen.
- Events the browser fires because of a patch, like the `blur` Chrome sends when a patch removes the focused element, aren't reported. They aren't the user's doing.
- `value`, `checked` and `selected` attributes are mirrored onto the live properties, so updates still show after a user has typed or clicked. `value` is only written when it changed, so the caret stays put.
- Updates that arrive late, after the user has typed or clicked further, don't overwrite what's on screen: an update matching a value the user already reported is treated as an echo. Anything else, like clearing a field after a submit, is applied.

## Tests

`test/run.mjs` runs in jsdom: unit tests for live form state and events, then thousands of random view sequences generated in Elm, checking the DOM after every patch and routing every event back through the event router. `test/runtime.mjs` runs a small app through `Jorn.application` and `start`. See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to run them.
