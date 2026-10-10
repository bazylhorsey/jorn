# Roadmap

Where Jorn is, feature by feature. The [README](README.md#roadmap) has the stage-level view.

Statuses: **done** is available today. **partial** is available with a stated difference. **todo** is not started.

## Views

| Feature | Status | Notes |
|---|---|---|
| Elements with any tag (`node`) and namespaced elements (`nodeNS`) | done | SVG and MathML work today through `nodeNS`. |
| Text nodes | done | |
| `Html.map` | partial | Eager: walks the subtree. A lazy map needs kernel code, which a pure package can't use. |
| HTML element helpers | partial | 20 of about 115 standard elements have helpers (`div`, `span`, `p`, `h1` to `h3`, `a`, `button`, `input`, `label`, `form`, `ul`, `ol`, `li`, `section`, `main_`, `header`, `footer`, `nav`). The rest work through `node`. |
| SVG element helpers | todo | |
| MathML element helpers | todo | |
| `none` and fragments | todo | |
| Keyed children | todo | Needed for efficient reordering of lists. |
| Memoized subtrees | todo | |
| Raw HTML | todo | |
| Render to an HTML string | todo | Needed for server-side rendering. |

## Attributes

| Feature | Status | Notes |
|---|---|---|
| Any attribute (`attribute`) and any property (`property`) | done | |
| `class` and `classList` | done | Multiple `class` attributes on one element accumulate. |
| `id`, `href`, `type_`, `name`, `placeholder`, `for` | done | |
| `value`, `checked`, `disabled` | done | Encoded so server-rendered HTML and the live DOM agree. |
| Global attributes (`style`, `title`, `hidden`, `tabindex`, `lang`, `data-*`, ...) | todo | All work today through `attribute`. |
| Form, media, link, and table attributes | todo | |
| ARIA attributes and `role` | todo | |

## Events

| Feature | Status | Notes |
|---|---|---|
| `on` and `custom` | done | Options are static, so the client can decide `preventDefault` instantly without a round trip. |
| `onClick`, `onInput`, `onCheck`, `onSubmit` | done | |
| `preventDefault` and `stopPropagation` | done | Static, through `custom`. Deciding per event is todo. |
| Mouse, keyboard, focus, blur, and change helpers | todo | All work today through `on`. |
| Debounce and throttle | todo | |
| Emitting custom events from a component | todo | |

## Wire protocol and routing

| Feature | Status | Notes |
|---|---|---|
| Mount (encode a whole tree) | done | `Jorn.Patch.encodeHtml` |
| Diff and patch encoding | done | `Jorn.Patch`, specified in [PROTOCOL.md](PROTOCOL.md) |
| Event decoding and routing | done | `Jorn.Event` |

## Runtime

| Feature | Status | Notes |
|---|---|---|
| App runtime (`init`, `update`, `view` programs) | todo | |
| Effects (`Effect.none`, `batch`, `map`, ...) | todo | |
| Browser patcher (small JavaScript) | done | [client/jorn.js](client/jorn.js). Checked against [tests/Reference.elm](tests/Reference.elm)'s semantics with randomized diffs in `client/test/`. |
| Server runtime over a websocket (Node, Bun, Deno) | todo | |
| Components as custom elements (attributes, properties, slots, form association) | todo | |
| Generated encoders for shared client/server types | todo | |
| Session snapshots and typed migrations across deploys | todo | |
| Server-side rendering and hydration | todo | |

## Testing utilities

| Feature | Status | Notes |
|---|---|---|
| Query a view (find by tag, class, id, text, ...) | todo | |
| Simulate an app (send messages and events, inspect model and view) | todo | |

## Performance

The goal is for Jorn to be as fast as Elm allows. The diff already skips attribute work entirely for elements with no attributes, which is most of them. Keyed children and memoized subtrees are the next big wins.
