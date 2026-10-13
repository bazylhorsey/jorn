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

CI runs the same three, plus the browser patcher's tests and the counter example. If you touch `client/jorn.js`, run its tests too:

```
(cd client/test/elm && ../../../node_modules/.bin/elm make src/ClientSpec.elm --optimize --output=build/spec.js)
(cd client/test && npm install && node run.mjs)
```

## How the code is laid out

- `src/Jorn/*.elm` is the public API. Every exposed function needs a doc comment.
- `src/Jorn/Internal/` is everything else. `Vdom` is the tree and its normalized form, `Patch` is the diff and the encoder.
- `tests/DiffTest.elm` has golden tests that pin the wire format byte for byte. If you change what goes over the wire, update [PROTOCOL.md](PROTOCOL.md) in the same pull request.
- `tests/Reference.elm` is an executable spec of the browser patcher: it applies patches to a tree in Elm, and the fuzz tests check that applying `diff a b` to `a` always gives `b`.
- `examples/` holds runnable examples. Each is an Elm application that pulls in `../../src`.
- `client/jorn.js` is the browser patcher. `client/test/run.mjs` checks it in jsdom: unit tests for live form state and events, then thousands of random view sequences generated in Elm, checking the DOM after every patch and routing every event back through `Jorn.Internal.Event`.

## Style

- Format with `elm-format`.
- Keep the package free of kernel code and ports. Anything that has to be JavaScript lives outside the Elm package.
- Prefer plain names and short doc comments that say what a function does and anything surprising about it.
