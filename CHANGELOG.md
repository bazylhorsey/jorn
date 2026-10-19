# Changelog

## Unreleased

- Server mode (#19). `server/jorn.js` runs a `Jorn.simple` or `Jorn.application` program on Node, one instance per connected page, and `stream` in `client/jorn.js` shows it in the page over a websocket. The program doesn't change: commands run on the server, and patcher instructions and `Effect.client` run in the page. `attach` serves a program on a path of an HTTP server, only to pages from the same origin unless you list others, and `session` runs one instance for hosts that move the messages themselves. The socket messages are specified in PROTOCOL.md.
- `Jorn.ServerComponent` (#20). `element` puts a server component in a page as a `<jorn-server-component>`, with its `route`, `flags` and `csrfToken`, and `script` loads the client for pages that don't have it. `defineServerComponent` in `client/jorn.js` defines the element: it connects while it's in the document and keeps its connection when moved. A component talks to the page around it with `Effect.event`, which bubbles out of the element. `decodeEvent` turns an event from the page into a message, for hosts that do their own routing. `attach` takes an `authorize` function, which gets the page's CSRF token.
- `examples/serve.mjs` also runs the todos app on the server, at `examples/todos/server.html`. CI runs the todos checks in both modes.
- The patcher ignores property names and event fields that lead to a prototype (`__proto__`, `constructor`, `prototype`). Setting `__proto__` on an element used to replace its prototype and break the page. A path step that isn't a child index is now a protocol error.
- CI runs with a read-only token.

## v0.1 (2026-10-18)

Client apps: the full HTML and SVG vocabulary, attributes and ARIA, keyed lists, fragments, effects, and an app runtime.

- Public modules reorganized around what things are instead of mirroring `elm/html` (#1). `Jorn.Html` is now `Jorn.Element`, its element helpers are in `Jorn.Element.Html`, `Jorn.Html.Attributes` is `Jorn.Attribute`, and `Jorn.Html.Events` is `Jorn.Event`.
- Renames: `node` to `element`, `nodeNS` to `namespaced`, the `Html` type to `Element`, and `classList` to `classes`.
- Event options are now attributes of the handler: `Event.preventDefault (onSubmit Submit)`. Options on one handler merge, and an option around anything that isn't a handler is ignored.
- Event routing moved from `Jorn.Event` to `Jorn.Internal.Event`. It becomes public with the server component API.
- The restructure doesn't change the wire protocol. The golden tests in `tests/DiffTest.elm` still pass byte for byte.
- `Element.none` renders nothing, and `Element.fragment` groups siblings without a wrapper element (#2). Both are resolved before diffing, so the wire protocol is unchanged.
- `Element.advanced` builds an element with full control over its namespace, tag, and how its tags are written as HTML (`Normal`, `Void` or `SelfClosing`).
- `Jorn.Element.Keyed`: children matched by key instead of position (#10). Reordering, inserting or removing items moves the existing DOM nodes, so focus and typed input stay with the right item. Three new patch ops, `insert`, `move` and `remove`, documented in PROTOCOL.md. Unkeyed views produce exactly the same patches as before.
- `Jorn.Element.Html` has a function for every standard HTML element (#3), 114 in all. Void elements take only attributes, so `Html.input [ ... ] []` is now `Html.input [ ... ]`. `Html.svg` and `Html.math` start their own namespaces.
- `Jorn.Element.Svg` has a function for every SVG element, in the SVG namespace (#13).
- Global attributes in `Jorn.Attribute` (#4): `none`, `style`, `styles`, `title`, `lang`, `dir`, `data`, `tabindex`, `hidden`, `inert`, and the editing, popover, command and microdata attributes. Several `style` attributes on one element now accumulate into one, the way `class` does, including ones set with `attribute "style"`.
- Element attributes in `Jorn.Attribute` for links, resources, media, forms, meta, templates, tables and dates (#5). Boolean ones reset the DOM property by its own spelling (`readonly` resets `readOnly`). `selected` keeps an option's live selection in step like `checked` does, and `defaultValue`, `defaultChecked` and `defaultSelected` start a control without controlling it.
- `role`, a generic `aria`, and one function per ARIA attribute in `Jorn.Attribute` (#6). They all take a `String`, since ARIA values are tokens like `"mixed"` or `"page"`.
- Event helpers for mouse, keyboard, focus, blur and change (#7), and a `key` decoder. Each helper includes exactly the event fields it decodes, so server mode sends only those.
- `Jorn.Effect` (#17): effects as values. `none`, `batch`, `map`, `fromCmd` for ordinary Elm commands, `focus`, `blur` and `scrollIntoView`, `beforePaint` and `afterPaint`, `event` to dispatch a DOM event from the app's container, and `client` to call a JavaScript function the page registered. The patcher instructions are specified in PROTOCOL.md.
- `Jorn.simple` and `Jorn.application` run an app in the page (#16): mount, route events, update, diff and patch, with one render per animation frame. Your app declares two ports and `start` from `client/jorn.js` does the rest. `connect` is still there for hosting a program yourself.
- The patcher no longer reports events the browser fires because of a patch, like the `blur` Chrome sends when a patch removes the focused element. They used to reach the app with a path into the updated view.
- `examples/todos` replaces `examples/counter` (#18): a complete app on `Jorn.application` showing keyed lists, forms, effects, SVG and ARIA. CI builds it and uses it in jsdom.

## v0.0 (2026-10-10)

First public release. The foundation layer.

- `Jorn.Html`, `Jorn.Html.Attributes`, `Jorn.Html.Events`: a virtual DOM that is ordinary Elm data, with the same shape as `elm/html`.
- `Jorn.Patch`: diff two views into an ordered list of patches and encode them, or a whole tree, as JSON.
- `Jorn.Event`: decode an event reported by the client and route it to the handler that produced it.
- `client/jorn.js`: the browser patcher. Applies patches to the DOM, keeps live form state in step, and reports events back, either as JSON for a server or as live events for Elm running in the page.
- Wire protocol version 0, specified in [PROTOCOL.md](PROTOCOL.md) and pinned by golden tests.
- [examples/counter](examples/counter): the full mount, event, diff loop, in a browser page and headless in Node.

Not yet on the Elm package registry. The registry requires a package's first published version to be 1.0.0, which is why `elm.json` already says `1.0.0`.
