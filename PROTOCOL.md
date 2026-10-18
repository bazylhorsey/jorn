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

`namespace` is `""` for HTML. `attrs` are strings set with `setAttribute`. `props` are JSON values assigned to the DOM object. `events` tell the client which listeners to install and how; the handlers themselves never leave Elm.

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

**Live state.** `value` on `input`, `textarea` and `select`, `checked` on `input`, and `selected` on `option` are sent as attributes, so they appear in server-rendered HTML. Once a user has typed or clicked, the attribute no longer controls what's on screen, so after setting or removing one of these attributes the client copies it onto the live property. `value` is only written when it differs, which leaves the caret where it is.

**Late updates.** Updates lag behind the user: the update for "Ba" can arrive after they've typed "Baz". So the client remembers the `value` and `checked` state each element had when it reported an event, and an update matching one of those is treated as an echo of the past and not written. An update to anything else, such as clearing a field, is applied. Within one patch message, an echo stays an echo, since one change can arrive as both an attribute and a property patch.

**Resetting a property.** If the element's tag has the property natively, it goes back to its value on a freshly created element of that tag, unless an attribute of the same name is present, in which case it follows the attribute (`true` for boolean properties). Any other property is deleted.

## Events, client to Elm

```json
{ "path": [1, 0], "name": "input", "event": { "target": { "value": "hi" } } }
```

The client applies `preventDefault` and `stopPropagation` synchronously from the listener's options, then builds `event` from the dotted paths in `include`. When Elm runs in the same page (client mode), the client can pass the live event object instead, and `include` doesn't matter. Routing an incoming event to the handler that produced it lives in `Jorn.Internal.Event` for now, and becomes public with the runtime.

## Semantics worth knowing

Within one element, the last attribute, property, or handler with a given name wins, except `class` and `style`, which accumulate: classes joined with spaces like `elm/html`, and style declarations joined with semicolons. The client only ever sees the joined attribute.

Changing only a handler's message (same event name and options) produces no patch. Decoders stay in Elm and routing always uses the current tree.

`Element.map` is eager: it walks the subtree and wraps every decoder. `elm/html` makes it lazy with kernel code, which a pure package can't do.

