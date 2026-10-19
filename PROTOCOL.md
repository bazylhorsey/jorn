# Jorn wire protocol (version 0)

Everything on the wire is JSON. The format is pinned by the golden tests in `tests/DiffTest.elm`, and `tests/Reference.elm` is an executable spec of the client patcher. [`client/jorn.js`](client/jorn.js) is the browser implementation, tested against random diffs in `client/test/`.

## Paths

A path is a list of child indices from the root. The root is `[]`. `[1, 0]` is the first child of the root's second child. Text nodes count as children.

## Fragments

Fragments and keys never appear on the wire. Before diffing or encoding, a fragment's children are spliced into its parent's child list, at any depth, and `none` (the empty fragment) disappears. Paths count the spliced children.

A view's root is always a single node. A fragment at the root becomes an empty text node if it has no children, its child if it has one, and otherwise a `jorn-fragment` element with `style="display: contents"` holding the children.

## Nodes

```json
{ "text": "hello" }

{ "tag": "input", "namespace": "",
  "attrs":  { "class": "field" },
  "props":  { "value": "hi" },
  "events": { "input": { "preventDefault": false, "stopPropagation": false, "include": ["target.value"] } },
  "children": [] }
```

`namespace` is `""` for HTML. `attrs` are strings set with `setAttribute`. `props` are JSON values assigned to the DOM object; the client ignores the names `__proto__`, `constructor` and `prototype`, so a property can't change what kind of object an element is. `events` tell the client which listeners to install and how; the handlers themselves never leave Elm. An event's options can also have `debounce` and `throttle`, in milliseconds, which are left out when they're not used (below).

## Patches

A patch message is a JSON array of patches. **Apply them strictly in order.** The diff guarantees every path is valid at the moment its patch is applied.

| `op` | Fields | Client behavior |
|---|---|---|
| `replace` | `node` | Replace the node at `path` |
| `set-text` | `text` | Set the text node's content |
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

**Debounce and throttle.** They run in the client, after `preventDefault` and `stopPropagation`, which still apply to every event. With `debounce`, the client holds the latest event back until none has fired for that long, then sends it. With `throttle`, it sends the first event straight away and holds the latest of the rest until the interval ends, which starts the next interval. With both, `throttle` caps how long `debounce` holds an event. A held event's fields are copied when it fires and its path is worked out when it's sent, and it's dropped if its element or handler is gone by then. Any event the client sends goes after the held events that fired before it, so a submit never overtakes debounced typing.

## Client mode runtime

A `Jorn.simple` or `Jorn.application` program running in the page talks to `start` in `client/jorn.js` through its two ports. Apps never see these messages. They're listed here for anyone hosting a program some other way.

Program to page, on `toJorn`:

| Message | Page behavior |
|---|---|
| `{ "mount": node }` | Render the first view |
| `{ "frame": true }` | Send `{ "frame": true }` back on the next animation frame |
| `{ "patches": [...], "instructions": [...], "painted": bool }` | Apply the patches, then run the instructions. If `painted` is `true`, send `{ "painted": true }` back once both are done |
| `{ "error": "..." }` | Log it. The program got an event or message it couldn't read |

Page to program, on `fromJorn`:

| Message | Program behavior |
|---|---|
| `{ "event": { "path", "name", "event" } }` | Route the event to its handler and run `update` |
| `{ "frame": true }` | Run `beforePaint` messages, diff once, and send the patches and instructions |
| `{ "painted": true }` | Run `afterPaint` messages |
| `{ "shutdown": true }` | Stop, and ignore everything after |

The program asks for a frame only when something changed, and every message that arrives before the frame is handled before its one diff, so a burst of events costs one render.

## Server mode

The same program can run on a server instead, in `server/jorn.js`, with `stream` from `client/jorn.js` on the page, or a `<jorn-server-component>` element, which calls `stream` for itself. The program's messages are the ones above. The server answers `frame` itself, at most once every 16 ms, and logs `error`, so neither goes over the wire. Everything else travels as one JSON text message per websocket message.

Page to server:

| Message | Server behavior |
|---|---|
| `{ "join": { "protocol": 0, "flags": ..., "csrfToken": "..." } }` | Must be first. Start a session for this page. `flags` and `csrfToken` are optional, and the server decides what to do with them |
| `{ "event": { "path", "name", "event" } }` | Pass it to the program. `event` holds only the fields in the handler's `include` |
| `{ "painted": true }` | Pass it to the program |

Anything else from the page is ignored. Server to page:

| Message | Page behavior |
|---|---|
| `{ "mount": node }` | Render the first view |
| `{ "patches": [...], "instructions": [...], "painted": bool }` | As in client mode: apply, run, and send `{ "painted": true }` back if asked |

The server closes the socket with 1002 if the first message isn't a `join` for a protocol it speaks, 1007 if a message isn't JSON, 1008 if it won't let the page in, and 1011 if the session can't start. Closing the socket ends the session.

## Semantics worth knowing

Within one element, the last attribute, property, or handler with a given name wins, except `class` and `style`, which accumulate: classes joined with spaces like `elm/html`, and style declarations joined with semicolons. The client only ever sees the joined attribute.

Changing only a handler's message (same event name and options) produces no patch. Decoders stay in Elm and routing always uses the current tree.

`Element.map` is eager: it walks the subtree and wraps every decoder. `elm/html` makes it lazy with kernel code, which a pure package can't do.

