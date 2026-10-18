# client/jorn.js

The browser side of Jorn. It applies [Jorn's wire protocol](../PROTOCOL.md) to the DOM and reports events back. One small ES module, no dependencies.

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

- **Server mode** (the default). Events are reduced to plain JSON holding only the fields each handler asked for with `include`, so they can go over a socket.
- **Client mode**, `connect(container, { send, raw: true })`. Your Elm program runs in the same page, so `event` is the live event object and decoders can read anything on it. See [examples/counter](../examples/counter).

## API

| | |
|---|---|
| `connect(container, { send, raw, effects })` | Take over `container`. Its only child is the root of your view from here on. `effects` maps names to the functions `Effect.client` can call. |
| `.mount(node)` | Render a whole tree, replacing whatever was there. |
| `.patch(patches)` | Apply patches strictly in order. Throws on a patch that doesn't fit the page, which means the page and the server have drifted apart. |
| `.run(instructions)` | Run patcher instructions from `Jorn.Effect` (focus, scroll, custom events, named effects), in order. Call it after the patches they came with. |
| `.nodeAt(path)` | The DOM node at a path, or `null`. |
| `.unmount()` | Empty the container. |

## Behavior worth knowing

- `preventDefault` and `stopPropagation` are applied synchronously when the event fires, from the options Elm sent ahead of time.
- Paths are worked out when an event fires, so they're correct for whatever is on screen.
- `value`, `checked` and `selected` attributes are mirrored onto the live properties, so updates still show after a user has typed or clicked. `value` is only written when it changed, so the caret stays put.
- Updates that arrive late, after the user has typed or clicked further, don't overwrite what's on screen: an update matching a value the user already reported is treated as an echo. Anything else, like clearing a field after a submit, is applied.

## Tests

`test/run.mjs` runs in jsdom: unit tests for live form state and events, then thousands of random view sequences generated in Elm, checking the DOM after every patch and routing every event back through the event router. See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to run it.
