# Chat

A chat room, as a server component. Every page gets a session of its own, running `src/Main.elm` on the server, and sessions can't see each other. What makes it a room is a few lines of server code in [chat.mjs](chat.mjs): `attach` hands it each session's ports as the session starts, and it passes whatever one session says to all of them.

Build it, install the server's dependencies once, and serve the repository root:

```
elm make src/Main.elm --output=build/main.js
(cd ../../server && npm install)
node ../serve.mjs
```

Then open http://localhost:8000/examples/chat/ in two tabs.

## What it shows

- **The program's own ports.** `say` goes out when someone sends a message, and `hear` brings in every line for the room. The program doesn't know where they go or come from. They're ordinary Elm ports, declared next to `toJorn` and `fromJorn`.
- **`onSession`.** `chat.mjs` subscribes to each session's `say`, sends into every session's `hear`, and returns a function that `attach` calls when the session ends, which says who left.
- **Flags from the server.** The server picks each name and passes the recent lines, so a page that joins late sees what it missed, and nobody can speak as someone else.
- **A line comes back before it shows.** A message isn't added where it was typed: it goes out through `say` and comes back through `hear`, like everyone else's, so every page shows the same order.
- **A keyed log.** Each line has a number as its key, so dropping the oldest line moves nothing else.

CI builds the example and runs [server/test/chat.mjs](../../server/test/chat.mjs): three pages in jsdom on a real server, talking, leaving, and joining late.
