# Todos

A todo list, written the way a Jorn app is meant to be: an ordinary Elm program on `Jorn.application`, started in the page with `start` from [client/jorn.js](../../client/jorn.js). It keeps the list in localStorage, so it's still there when you come back.

Build it, serve the repository root, and open http://localhost:8000/examples/todos/:

```
elm make src/Main.elm --output=build/main.js
node ../serve.mjs
```

The same program also runs on the server. Install the server's dependencies once with `(cd ../../server && npm install)`, start `serve.mjs` again, and open http://localhost:8000/examples/todos/server.html. `src/Main.elm` doesn't change: `server.html` calls `stream` instead of `start`, `update` and `view` run in Node, and focus and saving still happen in the page.

## What it shows

- **The wiring.** Two port declarations at the top of `src/Main.elm`, and one `start` call in `index.html`. That's all of it.
- **Flags and a client effect.** The page passes the saved list in as flags. Whenever the list changes, `update` returns `Effect.client "save"`, which calls the `save` function the page registered.
- **Focus as an effect.** Edit returns `Effect.focus`, which runs right after the patch that creates the edit field.
- **Keyed children.** The list is a `Keyed.ul`, so filtering and deleting add and remove items around the others instead of rewriting every item after the change.
- **Forms and the keyboard.** `onSubmit` (which keeps the page from reloading), `onInput`, `onCheck`, `onBlur`, and `onKeydown` to cancel an edit with Escape.
- **SVG.** The progress ring is drawn with `Jorn.Element.Svg`.
- **ARIA.** The ring is a `progressbar` with its values, the filter buttons say which one is pressed, and the count is a live region.
- **`Element.none`** for parts that come and go, like the footer and the Clear completed button.

CI builds the example and uses it in jsdom with [client/test/example.mjs](../../client/test/example.mjs): adding, ticking, editing, filtering and deleting, once in the page and once on a server.
