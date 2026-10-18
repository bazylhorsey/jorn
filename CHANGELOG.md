# Changelog

## Unreleased

- Public modules reorganized around what things are instead of mirroring `elm/html` (#1). `Jorn.Html` is now `Jorn.Element`, its element helpers are in `Jorn.Element.Html`, `Jorn.Html.Attributes` is `Jorn.Attribute`, and `Jorn.Html.Events` is `Jorn.Event`.
- Renames: `node` to `element`, `nodeNS` to `namespaced`, the `Html` type to `Element`, and `classList` to `classes`.
- Event options are now attributes of the handler: `Event.preventDefault (onSubmit Submit)`. Options on one handler merge, and an option around anything that isn't a handler is ignored.
- Event routing moved from `Jorn.Event` to `Jorn.Internal.Event`. It becomes public with the server component API and the runtime.
- The restructure doesn't change the wire protocol. The golden tests in `tests/DiffTest.elm` still pass byte for byte.
- `Element.none` renders nothing, and `Element.fragment` groups siblings without a wrapper element (#2). Both are resolved before diffing, so the wire protocol is unchanged.
- `Element.advanced` builds an element with full control over its namespace, tag, and how its tags are written as HTML (`Normal`, `Void` or `SelfClosing`).
- `Jorn.Element.Keyed`: children matched by key instead of position (#10). Reordering, inserting or removing items moves the existing DOM nodes, so focus and typed input stay with the right item. Three new patch ops, `insert`, `move` and `remove`, documented in PROTOCOL.md. Unkeyed views produce exactly the same patches as before.

## v0.0 (2026-10-10)

First public release. The foundation layer.

- `Jorn.Html`, `Jorn.Html.Attributes`, `Jorn.Html.Events`: a virtual DOM that is ordinary Elm data, with the same shape as `elm/html`.
- `Jorn.Patch`: diff two views into an ordered list of patches and encode them, or a whole tree, as JSON.
- `Jorn.Event`: decode an event reported by the client and route it to the handler that produced it.
- `client/jorn.js`: the browser patcher. Applies patches to the DOM, keeps live form state in step, and reports events back, either as JSON for a server or as live events for Elm running in the page.
- Wire protocol version 0, specified in [PROTOCOL.md](PROTOCOL.md) and pinned by golden tests.
- [examples/counter](examples/counter): the full mount, event, diff loop, in a browser page and headless in Node.

Not yet on the Elm package registry. The registry requires a package's first published version to be 1.0.0, which is why `elm.json` already says `1.0.0`.
