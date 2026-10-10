# Counter

One Elm program, run two ways. It never touches the DOM: it sends the initial tree and then patches out of a port, and takes events in through another.

Build it first, from this folder:

```
elm make src/Main.elm --output=build/main.js
```

**In a browser.** `index.html` loads the program and [client/jorn.js](../../client/jorn.js), which applies the patches to the page. From the repository root:

```
node examples/serve.mjs
```

Then open http://localhost:8000/examples/counter/.

**Headless, like a server component.** `run.mjs` plays the part of the browser: it prints what Jorn sends and fires a few events back.

```
node run.mjs
```

`src/Main.elm` is split in two. The top half is an ordinary Elm Architecture component. The bottom half is the glue a Jorn runtime will eventually provide for you: mount, route each incoming event to its handler, update, diff, send patches.
