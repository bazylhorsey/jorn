# Jorn wire protocol (version 0)

Everything on the wire is JSON. The format is pinned by the golden tests in `tests/DiffTest.elm`, and `tests/Reference.elm` is an executable spec of the client patcher. [`client/jorn.js`](client/jorn.js) is the browser implementation, tested against random diffs in `client/test/`.

## Paths

A path is a list of child indices from the root. The root is `[]`. `[1, 0]` is the first child of the root's second child. Text nodes count as children.

## Fragments and memos

Fragments, keys and memos never appear on the wire. Before diffing or encoding, a fragment's children are spliced into its parent's child list, at any depth, and `none` (the empty fragment) disappears. Paths count the spliced children.

A view's root is always a single node. A fragment at the root becomes an empty text node if it has no children, its child if it has one, and otherwise a `jorn-fragment` element with `style="display: contents"` holding the children.

A memo (`Element.memo`) is encoded as the node it builds, which is always a single node, rooted like a whole view. A memo whose dependencies didn't change gives no patches.

## Nodes

```json
{ "text": "hello" }

{ "tag": "input", "namespace": "",
  "attrs":  { "class": "field" },
  "props":  { "value": "hi" },
  "events": { "input": { "preventDefault": false, "stopPropagation": false, "include": ["target.value"] } },
  "children": [] }
```

An element made with `Element.unsafeRawHtml` has `html` in place of `children`:

```json
{ "tag": "article", "namespace": "", "attrs": {}, "props": {}, "events": {},
  "html": "<p>Rendered <em>Markdown</em></p>" }
```

The client sets `html` as the element's `innerHTML`, without checking it. Its content is opaque: no path ever leads inside it, and patches that would change its children are protocol errors. Listeners are only installed on nodes from the wire, so events from inside the content reach Elm only through handlers on the raw element or its ancestors, with their paths.

`namespace` is `""` for HTML. `attrs` are strings set with `setAttribute`. `props` are JSON values assigned to the DOM object; the client ignores the names `__proto__`, `constructor` and `prototype`, so a property can't change what kind of object an element is. `events` tell the client which listeners to install and how; the handlers themselves never leave Elm. An event's options can also have `debounce` and `throttle`, in milliseconds, and `"advanced": true`, all of which are left out when they're not used (below).

## Patches

A patch message is a JSON array of patches. **Apply them strictly in order.** The diff guarantees every path is valid at the moment its patch is applied.

| `op` | Fields | Client behavior |
|---|---|---|
| `replace` | `node` | Replace the node at `path` |
| `set-text` | `text` | Set the text node's content |
| `set-html` | `html` | Replace a raw element's content, as its `innerHTML` |
| `set-attr` | `name`, `value` | `setAttribute`, then sync live state (below) |
| `remove-attr` | `name` | `removeAttribute`, then sync live state (below) |
| `set-prop` | `name`, `value` | Assign the property |
| `remove-prop` | `name` | Reset the property (below) |
| `set-event` | `name`, `options` | Install or replace the listener with these options |
| `remove-event` | `name` | Remove the listener |
| `append` | `nodes` | Append children to the element at `path` |
| `truncate` | `length` | Remove children from index `length` onward |
| `insert` | `index`, `node` | Insert a child so it ends up at `index` (`index` equal to the child count appends) |
| `move` | `from`, `to` | Move the child at `from` so it ends up at `to`, counting with it taken out. The DOM node moves, it isn't recreated |
| `remove` | `index` | Remove the child at `index` |

**Keyed children.** `insert`, `move` and `remove` come from keyed children, which are matched by key rather than position. For one parent, the diff sends its `remove` patches first (highest index first), then its `move` and `insert` patches, each index valid at the moment it's applied, and only then patches aimed at the children themselves, at their final positions. Keys stay in Elm: they never appear on the wire.

**Live state.** `value` on `input`, `textarea` and `select`, `checked` on `input`, and `selected` on `option` are sent as attributes, so they appear in server-rendered HTML. Once a user has typed or clicked, the attribute no longer controls what's on screen, so after setting or removing one of these attributes the client copies it onto the live property. `value` is only written when it differs, which leaves the caret where it is. The `defaultValue`, `defaultChecked` and `defaultSelected` properties are ordinary properties: the browser reflects them into the attribute, and the client never copies them onto the live state, so they start a control without controlling it.

**Late updates.** Updates lag behind the user: the update for "Ba" can arrive after they've typed "Baz". So the client remembers the `value` and `checked` state each element had when it reported an event, and an update matching one of those is treated as an echo of the past and not written. An update to anything else, such as clearing a field, is applied. Within one patch message, an echo stays an echo, since one change can arrive as both an attribute and a property patch.

**Resetting a property.** If the element's tag has the property natively, it goes back to its value on a freshly created element of that tag, unless an attribute of the same name is present, in which case it follows the attribute (`true` for boolean properties). Any other property is deleted.

## Patcher instructions

Effects that have to touch the DOM travel as instructions, applied in order right after the patches they arrive with, so they can refer to elements those patches created. Elements are found by `id`, within the root node of the container (its document or shadow root).

| `effect` | Fields | Client behavior |
|---|---|---|
| `focus` | `id` | `focus()` the element |
| `blur` | `id` | `blur()` the element |
| `scroll-into-view` | `id` | `scrollIntoView()` the element |
| `event` | `name`, `detail` | Dispatch a `CustomEvent` from the container that bubbles and is composed |
| `client` | `name`, `payload` | Call the function the page registered under `name`, with `payload` |

An `id` that matches nothing, or a `client` name nobody registered, is reported with a console warning and skipped.

## Events, client to Elm

```json
{ "path": [1, 0], "name": "input", "event": { "target": { "value": "hi" } } }
```

The client applies `preventDefault` and `stopPropagation` synchronously from the listener's options, then builds `event` from the dotted paths in `include`, skipping any path that goes through `__proto__`, `constructor` or `prototype`. When Elm runs in the same page (client mode), the client can pass the live event object instead, and `include` doesn't matter. Events the browser fires as a result of applying patches, like the `blur` some browsers send when a patch removes the focused element, are not reported. In client mode, `Jorn.application` routes each event to the handler that produced it. Hosts that route events themselves can use `Jorn.ServerComponent.decodeEvent`.

**Form fields.** `formFields` in `include` isn't a field of the event: the client builds it. It finds the form, which is the event's target or the form the target belongs to, and sends the fields that form would submit as a list of `[name, value]` pairs, in order, with the button that submitted it last. Fields that are disabled, unchecked or have no name are left out, the way the browser leaves them out of a submission, and so are file inputs, since their contents can't be sent as text. An event with no form gets an empty list. In client mode the client adds `formFields` to the live event object, so the same decoder works in both modes.

```json
{ "path": [], "name": "submit", "event": { "formFields": [["email", "a@b.c"], ["plan", "pro"]] } }
```

**Deciding per event.** A handler made with `Event.advanced` has `"advanced": true` in its options: its decoder decides, for each event, whether to call `preventDefault` and `stopPropagation`, on top of what the options say. The browser needs to know before the listener returns, so the client can only ask when the program runs in the same page. In client mode it asks right after the static options, before the event is sent or held (see the client mode runtime, below), and applies a yes at once. If the handler's decoder fails, the answer is no. In server mode the answer would arrive after the browser has acted on the event, so the client doesn't ask: only the static options apply, and the event is sent as usual. A server never sees the question.

**Debounce and throttle.** They run in the client, after `preventDefault` and `stopPropagation`, which still apply to every event. With `debounce`, the client holds the latest event back until none has fired for that long, then sends it. With `throttle`, it sends the first event straight away and holds the latest of the rest until the interval ends, which starts the next interval. With both, `throttle` caps how long `debounce` holds an event. A held event's fields are copied when it fires and its path is worked out when it's sent, and it's dropped if its element or handler is gone by then. Any event the client sends goes after the held events that fired before it, so a submit never overtakes debounced typing.

## Client mode runtime

A `Jorn.simple`, `Jorn.application` or `Jorn.Navigation.application` program running in the page talks to `start` in `client/jorn.js` through its two ports. Apps never see these messages. They're listed here for anyone hosting a program some other way.

Program to page, on `toJorn`:

| Message | Page behavior |
|---|---|
| `{ "mount": node }` | Render the first view |
| `{ "frame": true }` | Send `{ "frame": true }` back on the next animation frame |
| `{ "patches": [...], "instructions": [...], "painted": bool }` | Apply the patches, then run the instructions. If `painted` is `true`, send `{ "painted": true }` back once both are done |
| `{ "mount": node, "painted": bool }` | The answer to `remount`. Render the view, and send `{ "painted": true }` back if `painted` is `true` |
| `{ "navigate": instruction }` | Change the address (see [URL routing](#url-routing)) |
| `{ "error": "..." }` | Log it. The program got an event or message it couldn't read |

A program with URL routing adds `"routing": true` to every `mount`, and `"title": "..."` to a `mount` and to any `patches` message whose view changed the title. The page sets `document.title` to it.

Page to program, on `fromJorn`:

| Message | Program behavior |
|---|---|
| `{ "url": "..." }` | Sent once when the page starts the program, and again whenever the address changes. A program with URL routing starts with the first, and gets `onUrlChange` for the rest. Others ignore it |
| `{ "event": { "path", "name", "event" } }` | Route the event to its handler and run `update` |
| `{ "decide": { "path", "name", "event" }, "reply": object }` | Run the handler's decoder, but not `update`, and answer through `reply` before `send` returns (below) |
| `{ "link": "..." }` | Someone clicked a link (see [URL routing](#url-routing)) |
| `{ "frame": true }` | Run `beforePaint` messages, diff once, and send the patches and instructions |
| `{ "painted": true }` | Run `afterPaint` messages |
| `{ "remount": true }` | Send the whole view again, as `mount` |
| `{ "shutdown": true }` | Stop, and ignore everything after |

The program asks for a frame only when something changed, and every message that arrives before the frame is handled before its one diff, so a burst of events costs one render.

**Answering `decide`.** The answer to an advanced handler's question can't go back as a message on `toJorn`: after each batch of commands, Elm's ports wait for the event loop to come round before handing over the next, and the browser's listener can't wait. A port's `send` runs `update` before it returns, though, so the program answers by reading `reply`, an object the page makes with a getter for each field: reading `reply.preventDefault` means prevent the default, and reading `reply.stopPropagation` means stop propagation. It reads neither for no. The event itself follows as an ordinary `event`, right away or once debounce and throttle let it go.

## URL routing

A program made with `Jorn.Navigation.application` owns the page's address. The page is where the address lives, so the program learns it from the page and asks the page to change it:

- The page sends `{ "url": location.href }` when it starts the program. The program runs `init` with that URL, so it sends nothing before then. An address that isn't `http` or `https` can't be read as a URL, and the program reports an `error` and doesn't start.
- Once a `mount` says `"routing": true`, the page takes over clicks on links (`a` elements with an `href`) inside the container, and listens for `popstate`. It leaves a click alone if a handler already called `preventDefault`, a modifier key or a button other than the main one was used, the link has a `target` or `download` attribute, or the link is inside a `<jorn-server-component>` within the container. For the rest it calls `preventDefault` and sends `{ "link": href }`, with `href` resolved against the page. The program compares it with the current address and gives the app `Internal` with the URL if the protocol, host and port match, and `External` with the string otherwise.
- `navigate` instructions go out as soon as `update` returns them, not with the next frame's patches, and the page reports the address it ends up at with `{ "url": ... }`. So the URL the app sees is always the browser's.

| `navigate` | Page behavior |
|---|---|
| `{ "push": url }` | `history.pushState`, then report the address |
| `{ "replace": url }` | `history.replaceState`, then report the address |
| `{ "go": n }` | `history.go(n)`. The `popstate` that follows reports the address |
| `{ "load": url }` | `location.assign(url)`, leaving the app |
| `{ "reload": skipCache }` | `location.reload()` |

A navigation the browser refuses, such as pushing an address on another site, is reported with a console warning.

## Server mode

The same program can run on a server instead, in `server/jorn.js`, with `stream` from `client/jorn.js` on the page, or a `<jorn-server-component>` element, which calls `stream` for itself. The program's messages are the ones above. The server answers `frame` itself, at most once every 16 ms, and logs `error`, so neither goes over the wire. Everything else travels as one JSON text message per websocket message.

Page to server:

| Message | Server behavior |
|---|---|
| `{ "join": { "protocol": 0, "flags": ..., "csrfToken": "...", "session": "...", "seen": n, "url": "..." } }` | Must be first. Start a session for this page, or resume the one named by `session`. Everything but `protocol` is optional, and the server decides what to do with `flags` and `csrfToken`. `url` is the page's address: a new session's program gets it as its first `url`, and a resumed one gets it if it differs from the last address the page reported, since the page may have moved while it was away |
| `{ "event": { "path", "name", "event" } }` | Pass it to the program. `event` holds only the fields in the handler's `include` |
| `{ "painted": true }` | Pass it to the program |
| `{ "remount": true }` | The page couldn't apply a patch. Pass it to the program, which sends the whole view again |
| `{ "url": "..." }`, `{ "link": "..." }` | Pass it to the program (see [URL routing](#url-routing)) |
| `{ "ping": true }` | Answer `{ "pong": true }` |

Anything else from the page is ignored. Server to page, each with a `seq` that counts up from 1 within a session (`pong` has none):

| Message | Page behavior |
|---|---|
| `{ "seq": 1, "session": "..." }` | First in every new session. Keep the id, to resume with it |
| `{ "seq": n, "mount": node, "painted": bool }` | Render the whole view, replacing what's there. If `painted` is `true`, send `{ "painted": true }` back |
| `{ "seq": n, "patches": [...], "instructions": [...], "painted": bool }` | As in client mode: apply, run, and send `{ "painted": true }` back if asked |
| `{ "seq": n, "navigate": instruction }` | As in client mode: change the address, and report it |
| `{ "pong": true }` | Nothing. It only shows the server is there |

`mount` and `patches` carry `routing` and `title` as in client mode.

The program sends `mount` with `painted` when it answers `remount`, so `afterPaint` messages waiting on patches the page never applied still run.

**Reconnecting.** When a socket drops without a close from either side on purpose, the session waits for its page for a while (30 seconds by default). A page that reconnects sends a `join` with its `session` and `seen`, the last `seq` it applied. If the server still has every message after `seen`, it sends them again, in order. If not, it sends the whole view. If the session is gone, the page gets a new one, with a new `session` message and a fresh mount, so it never keeps showing a view nobody is updating. Events the user causes while the page is disconnected are lost. A page that closes its socket with 1000 or 1001 ends its session straight away.

**Heartbeats.** The server pings every socket (with websocket ping frames, every 30 seconds by default) and drops one that hasn't answered the last ping. The page sends `{ "ping": true }` when it hasn't heard from the server for a while, and reconnects if no answer comes.

The server closes the socket with 1002 if the first message isn't a `join` for a protocol it speaks, 1007 if a message isn't JSON, 1008 if it won't let the page in or the page sends too many messages, 1013 if it's running as many sessions as it allows, and 1011 if the session can't start. A page doesn't reconnect after 1002, 1007 or 1008.

## Semantics worth knowing

Within one element, the last attribute, property, or handler with a given name wins, except `class` and `style`, which accumulate: classes joined with spaces like `elm/html`, and style declarations joined with semicolons. The client only ever sees the joined attribute.

Changing only a handler's message (same event name and options) produces no patch. Decoders stay in Elm and routing always uses the current tree. A memo whose dependencies didn't change is kept as it was built, handlers included, so events inside it are routed through those.

`Element.map` is eager: it walks the subtree and wraps every decoder. `elm/html` makes it lazy with kernel code, which a pure package can't do. It doesn't walk into a memo, which maps what it builds when it builds it.

