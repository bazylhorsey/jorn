# Contributing

Thanks for looking. Jorn is early, so issues that question the design are as welcome as pull requests.

## Setup

You need Node 22 or newer. Everything else comes from npm:

```
npm install --no-save elm@0.19.1-6 elm-test@0.19.1-revision15 elm-format@0.8.8
```

## Before you open a pull request

```
npx elm-format --validate src tests
npx elm-test
npx elm make --docs=docs.json
```

CI runs the same three, plus the browser patcher's, runtime's and server's tests and the todos example. If you touch `client/jorn.js`, `src/Jorn.elm` or an example, run those too:

```
(cd client/test/elm && ../../../node_modules/.bin/elm make src/ClientSpec.elm --optimize --output=build/spec.js)
(cd client/test/elm && ../../../node_modules/.bin/elm make src/RuntimeSpec.elm --output=build/runtime.js)
(cd client/test/elm && ../../../node_modules/.bin/elm make src/MemoSpec.elm --output=build/memo.js)
(cd examples/todos && ../../node_modules/.bin/elm make src/Main.elm --output=build/main.js)
(cd client/test && npm install && node run.mjs && node runtime.mjs && node memo.mjs && node example.mjs)
```

If you touch `server/` or `stream`, build `RuntimeSpec.elm` and the todos example as above, and the server's HTTP test app, then run the server's tests and the todos example in server mode:

```
(cd server/test/elm && ../../../node_modules/.bin/elm make src/HttpSpec.elm --optimize --output=build/http.js)
(cd server && npm install)
(cd server/test && npm install && node run.mjs && node reconnect.mjs && node http.mjs && node http-elm.mjs)
(cd client/test && node example.mjs server)
```

## How the code is laid out

- `src/Jorn/*.elm` is the public API. Every exposed function needs a doc comment.
- `src/Jorn/Internal/` is everything else. `Vdom` is the tree and its normalized form, `Patch` is the diff and the encoder.
- `tests/DiffTest.elm` has golden tests that pin the wire format byte for byte. If you change what goes over the wire, update [PROTOCOL.md](PROTOCOL.md) in the same pull request.
- `tests/Reference.elm` is an executable spec of the browser patcher: it applies patches to a tree in Elm, and the fuzz tests check that applying `diff a b` to `a` always gives `b`.
- `examples/` holds runnable examples. Each is an Elm application that pulls in `../../src`, written the way an app using Jorn would be. `client/test/example.mjs` uses the todos example in jsdom.
- `server/jorn.js` is the server runtime. `server/test/run.mjs` runs a session on its own, then pages in jsdom against a real server and real sockets. `server/test/reconnect.mjs` breaks those connections on purpose.
- `server/http.js` is the `XMLHttpRequest` that elm/http uses on the server. `server/test/http.mjs` uses it the way elm/http does, against a local HTTP server, and `server/test/http-elm.mjs` runs elm/http itself in a server component.
- `client/jorn.js` is the browser patcher. `client/test/run.mjs` checks it in jsdom: unit tests for live form state and events, then thousands of random view sequences generated in Elm, checking the DOM after every patch and routing every event back through `Jorn.Internal.Event`. `client/test/runtime.mjs` runs a small app through `Jorn.application` and `start`, checking batching and every kind of effect. `client/test/memo.mjs` counts how often the rows of a memoized list are built.

## Style

- Format with `elm-format`.
- Keep the package free of kernel code and ports. Anything that has to be JavaScript lives outside the Elm package, in `client/` or `server/`.
- Prefer plain names and short doc comments that say what a function does and anything surprising about it.
