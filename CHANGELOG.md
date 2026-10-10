# Changelog

## v0.0 (2026-10-10)

First public release. The foundation layer.

- `Jorn.Html`, `Jorn.Html.Attributes`, `Jorn.Html.Events`: a virtual DOM that is ordinary Elm data, with the same shape as `elm/html`.
- `Jorn.Patch`: diff two views into an ordered list of patches and encode them, or a whole tree, as JSON.
- `Jorn.Event`: decode an event reported by the client and route it to the handler that produced it.
- `client/jorn.js`: the browser patcher. Applies patches to the DOM, keeps live form state in step, and reports events back, either as JSON for a server or as live events for Elm running in the page.
- Wire protocol version 0, specified in [PROTOCOL.md](PROTOCOL.md) and pinned by golden tests.
- [examples/counter](examples/counter): the full mount, event, diff loop, in a browser page and headless in Node.

Not yet on the Elm package registry. The registry requires a package's first published version to be 1.0.0, which is why `elm.json` already says `1.0.0`.
