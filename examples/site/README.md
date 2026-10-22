# Site

A small blog, built as a static site. `src/Main.elm` is an ordinary app with URL routing, made with `Jorn.Navigation`. `src/Site.elm` describes the site with `Jorn.Static`: a page for each of the app's routes, holding the app's view at that address, and the files that go with them. `jorn build` writes it all to `build/`, ready for any static host.

Build it in this folder and serve the result:

```
node ../../cli/jorn.mjs build
python3 -m http.server --directory build 8080
```

Then open http://localhost:8080/.

## What it shows

- **One app, two ways.** `Main.elm` doesn't know about the build. `start` runs it like any other app, and `Site.elm` builds each page from its `init` and `view`.
- **Pages from a list.** The posts are values in `Posts.elm`, `Route.all` lists every route, and `Site.elm` makes a page for each one, and a sitemap with `Static.file`.
- **The same view, twice.** A page's HTML is the app's view at the page's address, so when the app starts there, it mounts the same view over it and nothing moves. Jorn doesn't adopt existing HTML yet, so for now the app replaces the page's HTML with the same thing as it starts.
- **What search engines read.** Every page is whole HTML, with its own title, description, canonical link and Open Graph tags, made from its route in `Site.elm`. Posts say what they are in JSON-LD, the 404 page says `noindex`, and `sitemap.xml` lists every route.
- **Paths that end in `/`.** A static host serves `about/index.html` at `/about/`, so that's the route's address, and the app's links and the sitemap never go through a redirect.
- **A 404 page.** `404.html` is the app at an address it doesn't have a route for. GitHub Pages and most static hosts serve it for any missing page, and the app starts there and shows Not found too.
- **Hashed URLs.** Every page refers to `main.js`, `style.css` and `jorn.js` with `?v=` and a hash of their contents, including the `import` in the inline script.
- **Links that stay in the app.** Once the app is running, a link pushes the address and scrolls to the top instead of loading a page. Before then, or without JavaScript, it loads that page's HTML.

CI builds the site with `jorn build` and checks it with [client/test/site.mjs](../../client/test/site.mjs): the files, hashes and tags for search engines, each page in jsdom mounting without a change, and then the links, the back button and the filter.
