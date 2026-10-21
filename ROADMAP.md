# Roadmap

Where Jorn is, feature by feature. The [README](README.md#roadmap) has the version-level view.

Statuses: **done** is available today. **partial** is available with a stated difference. **todo** is not started.

## Views

| Feature | Status | Notes |
|---|---|---|
| Elements with any tag (`element`) and namespaced elements (`namespaced`) | done | SVG and MathML work today through `namespaced`. |
| Text nodes | done | |
| `Element.map` | partial | Eager: walks the subtree. A lazy map needs kernel code, which a pure package can't use. |
| HTML element helpers | done | All standard elements in `Jorn.Element.Html`. Void elements (`br`, `img`, `input`, ...) take only attributes. |
| SVG element helpers | done | `Jorn.Element.Svg`. Attributes go through `Attribute.attribute`. |
| MathML element helpers | done | `Jorn.Element.MathMl`, the elements of MathML Core. Attributes go through `Attribute.attribute`. |
| `none`, `fragment` and `advanced` | done | Fragments are spliced into their parent before diffing, so they never appear on the wire. |
| Keyed children | done | `Jorn.Element.Keyed`. Moves DOM nodes instead of rewriting them, with the fewest moves the order allows. |
| Memoized subtrees | todo | |
| Raw HTML | done | `Element.unsafeRawHtml`, for content like rendered Markdown. The HTML isn't escaped, and its content is replaced as a whole when it changes. |
| Render to an HTML string | done | `Element.toString`, `toDocumentString` and `toReadableString`. Matches what the browser's `innerHTML` gives for the mounted view, checked against jsdom on random views. The base for server-side rendering. |

## Attributes

| Feature | Status | Notes |
|---|---|---|
| Any attribute (`attribute`) and any property (`property`) | done | |
| `class` and `classes` | done | Multiple `class` attributes on one element accumulate, and so do `style` attributes. |
| `id`, `href`, `type_`, `name`, `placeholder`, `for` | done | |
| `value`, `checked`, `disabled` | done | Encoded so server-rendered HTML and the live DOM agree. |
| Global attributes (`style`, `title`, `hidden`, `tabindex`, `lang`, `data-*`, ...) | done | `style` declarations accumulate into one attribute, like `class`. `Attribute.none` for conditionals. |
| Form, media, link, and table attributes | done | Plus `defaultValue`, `defaultChecked` and `defaultSelected` for controls you don't keep in step with your model. |
| ARIA attributes and `role` | done | One function per ARIA attribute, all taking a `String`, plus `aria` for any other. |

## Events

| Feature | Status | Notes |
|---|---|---|
| `on` and `custom` | done | Options are static, so the client can decide `preventDefault` instantly without a round trip. |
| `onClick`, `onInput`, `onCheck`, `onSubmit` | done | |
| Submitting a form with its fields | done | `Event.onSubmitFields`, and `Event.formFields` for other handlers. The page collects the fields, so it works the same in server mode. File inputs are left out. |
| `preventDefault` and `stopPropagation` | done | Static, through `custom`, or decided per event with `advanced` in client mode. In server mode the answer would arrive too late, so only the static options apply. |
| Mouse, keyboard, focus, blur, and change helpers | done | Keyboard helpers include `key`, so server components get it. |
| Debounce and throttle | done | `Event.debounce` and `Event.throttle`. They run in the page, so dropped events never reach a server. |
| Emitting custom events from a component | todo | |

## Wire protocol and routing

| Feature | Status | Notes |
|---|---|---|
| Mount (encode a whole tree) | done | `Jorn.Patch.encodeHtml` |
| Diff and patch encoding | done | `Jorn.Patch`, specified in [PROTOCOL.md](PROTOCOL.md) |
| Event decoding and routing | done | Built into the runtime, in both modes, and public as `Jorn.ServerComponent.decodeEvent` for hosts that route events themselves. |

## Runtime

| Feature | Status | Notes |
|---|---|---|
| App runtime (`init`, `update`, `view` programs) | done | `Jorn.simple` and `Jorn.application`, started in the page with `start` from `client/jorn.js`. One diff per animation frame, however many messages arrive. |
| Effects (`Effect.none`, `batch`, `map`, ...) | done | `Jorn.Effect`: Elm commands, focus and scrolling, paint timing, custom events and named client effects. Contexts come with #28. |
| Browser patcher (small JavaScript) | done | [client/jorn.js](client/jorn.js). Checked against [tests/Reference.elm](tests/Reference.elm)'s semantics with randomized diffs in `client/test/`. |
| Server components in a page (`Jorn.ServerComponent.element`, `<jorn-server-component>`) | done | Connects while it's in the document, and keeps the connection when it moves. |
| Server runtime over a websocket (Node, Bun, Deno) | partial | Node, in [server/jorn.js](server/jorn.js), with `stream` in the page. Pages reconnect to their sessions and catch up, heartbeats and limits keep the server healthy, and elm/http works on the server. Bun and Deno come after 1.0, with #23. |
| Components as custom elements (attributes, properties, slots, form association) | todo | |
| Server-side rendering and hydration | todo | |
| Server components over server-sent events or polling | todo | For hosts and proxies that don't allow websockets. |
| URL routing | todo | Jorn programs run on `Platform.worker`, which has no `Browser.Navigation`. |
| Messaging a running app from JavaScript | todo | Through the program's own ports. |

## Tooling and testing

| Feature | Status | Notes |
|---|---|---|
| Query a view (find by tag, class, id, text, ...) | todo | |
| Simulate an app (send messages and events, inspect model and view) | todo | |
| Dev server and build command | todo | |
| JavaScript written in TypeScript, with built files on each release | todo | |

## After 1.0

The full feature set comes first. These build on it, and start once 1.0 is out.

| Feature | Status | Notes |
|---|---|---|
| Generated encoders for types shared by the browser and the server | todo | For apps running in the browser that talk to a server. Server components don't need them: only events and patches cross the network. |
| Keeping sessions across a deploy | todo | Reattach each page to its session when the new version starts. |
| Session snapshots and typed migrations across deploys | todo | |
| REST endpoints written in Elm | todo | |
| Bun and Deno | todo | |

## Performance

The goal is for Jorn to be as fast as Elm allows. The diff already skips attribute work entirely for elements with no attributes, which is most of them, and keyed children turn reorders into a handful of moves. Memoized subtrees are the next big win.
