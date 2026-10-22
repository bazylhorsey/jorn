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

The container can already hold the app's HTML, as each page from `jorn build` does (see [cli/](../cli)). `start` mounts the app over it, and when the app's view at that address is the same, nothing changes on screen.

## Talking to a running app

The page talks to a running app the way it would to any Elm program: through the program's own ports. Any port it declares besides `toJorn` and `fromJorn` is in `app.ports`, as it would be from `Elm.Main.init`:

```elm
port notify : (Value -> msg) -> Sub msg

port saved : Value -> Cmd msg
```

```js
const app = start(Elm.Main, document.getElementById("app"));

app.ports.notify.send({ text: "New version available" }); // into the program
app.ports.saved.subscribe((draft) => localStorage.setItem("draft", JSON.stringify(draft))); // out of it
```

Elm leaves out ports the program never uses. After `shutdown`, the program ignores its ports.

When the program runs on a server, the page can't reach its ports. Server code can, with `attach`'s `onSession` (see [server/jorn.js](../server#talking-to-sessions)).

## URL routing

An app made with `Jorn.Navigation.application` owns the page's address. `start` and `stream` need nothing extra for it: the page tells the app where it is, and once the app says it routes, the page takes over clicks on links inside the container and the browser's back and forward buttons, and sets `document.title` from the view.

A click is left to the browser when a handler already prevented its default, when a modifier key or a button other than the main one was used, when the link has a `target` or `download` attribute, or when the link is inside a `<jorn-server-component>` in the app. Links outside the container aren't touched.

The app's address is always the browser's: `pushUrl` and the rest change the address, and the page reports where it landed. Routing needs an `http` or `https` address, so serve the page rather than opening it as a file.

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

A relative address is resolved against the page, and `http` becomes `ws`. `csrfToken` goes to the server's `authorize` check.

If the connection drops, the page reconnects, backing off up to five seconds between tries, and picks up its session where it left off: the server sends what it missed, or the whole view if that's too much. If a patch doesn't fit the page, because something else changed the DOM, the page asks for the whole view. Clicks and other events during a disconnect are lost, but anything typed stays in its field. If the page has to start a new session, for example because the server restarted, it sends its flags again. Pass `flags` as a function to send what's current rather than what was there when the page loaded. Style the waiting state with the container's `data-jorn-connection` attribute, which is `connecting`, `open`, `reconnecting` or `closed`:

```css
[data-jorn-connection="reconnecting"] { opacity: 0.5; pointer-events: none; }
``` The page only applies patches and sends events back: `update`, `view` and commands run on the server, and focus, scrolling and `Effect.client` run here.

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
| `start(program, container, { flags, effects, ports })` | Run a compiled Jorn program in `container`. Returns `{ ports, shutdown() }`, where `ports` are the program's own ports. |
| `stream(container, url, { flags, csrfToken, effects, heartbeat })` | Show a program running on a server in `container`, over a websocket. Sends the page's address when it connects. Returns `{ close() }`. |
| `defineServerComponent({ effects })` | Define `<jorn-server-component>`. Only the first call counts. |
| `connect(container, { send, decide, raw, effects })` | Take over `container`. Its only child is the root of your view from here on. `effects` maps names to the functions `Effect.client` can call. `decide`, for a program in the same page, answers handlers made with `Event.advanced` with `{ preventDefault, stopPropagation }`, before it returns. |
| `.mount(node)` | Render a whole tree, replacing whatever was there. |
| `.patch(patches)` | Apply patches strictly in order. Throws on a patch that doesn't fit the page, which means the page and the server have drifted apart. |
| `.run(instructions)` | Run patcher instructions from `Jorn.Effect` (focus, scroll, custom events, named effects), in order. Call it after the patches they came with. |
| `.nodeAt(path)` | The DOM node at a path, or `null`. |
| `.unmount()` | Empty the container. |

## Behavior worth knowing

- `preventDefault` and `stopPropagation` are applied synchronously when the event fires, from the options Elm sent ahead of time. A handler made with `Event.advanced` can add to them per event, but only in client mode, where `start` asks the program as the event fires. In server mode the answer would come too late, so only the options apply.
- `debounce` and `throttle` hold events back in the page, so dropped ones are never sent. An event that isn't held goes after the held ones that fired before it.
- Paths are worked out when an event fires, so they're correct for whatever is on screen.
- Events the browser fires because of a patch, like the `blur` Chrome sends when a patch removes the focused element, aren't reported. They aren't the user's doing.
- `value`, `checked` and `selected` attributes are mirrored onto the live properties, so updates still show after a user has typed or clicked. `value` is only written when it changed, so the caret stays put.
- Updates that arrive late, after the user has typed or clicked further, don't overwrite what's on screen: an update matching a value the user already reported is treated as an echo. Anything else, like clearing a field after a submit, is applied.

## Tests

`test/run.mjs` runs in jsdom: unit tests for live form state and events, then thousands of random view sequences generated in Elm, checking the DOM after every patch and routing every event back through the event router. `test/runtime.mjs` runs a small app through `Jorn.application` and `start`. `test/routing.mjs` clicks every kind of link in an app with URL routing and runs every navigation effect, in the page or, with `server`, on a server. See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to run them.
