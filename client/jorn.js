// Jorn browser patcher.
//
// Applies Jorn's wire protocol (PROTOCOL.md) to the DOM and reports events
// back. No dependencies. The same file serves both modes:
//
//   - Server mode: patches arrive over a socket, events go back over it as
//     JSON. Only the event fields a handler asked for (`include`) are sent.
//   - Client mode: your Elm program runs in this page and talks to the
//     patcher through ports. Pass `raw: true` and handlers get the live event
//     object, so `include` isn't needed.
//
//   import { connect } from "./jorn.js";
//
//   const jorn = connect(document.getElementById("app"), {
//     send: (event) => socket.send(JSON.stringify(event)),
//   });
//   jorn.mount(tree);      // once
//   jorn.patch(patches);   // after every update, in order
//
// For an app built with Jorn.simple or Jorn.application, `start` does all of
// that for you when the program runs in the page, and `stream` does it when
// the program runs on a server (server/jorn.js). `defineServerComponent`
// does it for every <jorn-server-component> in the page.

const LIVE = {
  value: new Set(["input", "textarea", "select"]),
  checked: new Set(["input"]),
  selected: new Set(["option"]),
};

const XHTML = "http://www.w3.org/1999/xhtml";

/**
 * Take over `container` and return the patcher for it. The container's
 * contents belong to Jorn from here on: its only child is the root node.
 *
 * @param {Element} container
 * `effects` holds the functions Elm can call by name with `Effect.client`.
 *
 * @param {{ send: (event: { path: number[], name: string, event: unknown }) => void, raw?: boolean, effects?: Record<string, (payload: unknown, context: { container: Element }) => void> }} options
 */
export function connect(container, { send, raw = false, effects = {} } = {}) {
  if (!container || container.nodeType !== 1) {
    throw new TypeError("Jorn: connect needs a container element");
  }
  if (typeof send !== "function") {
    throw new TypeError("Jorn: connect needs a send function");
  }

  const doc = container.ownerDocument;
  const handlers = new WeakMap(); // element -> Map(event name -> options)
  const pristine = new Map(); // "namespace tag" -> untouched element, for property defaults
  const reported = new WeakMap(); // element -> { value: [...], checked: [...] } the user sent, not yet echoed
  const held = new WeakMap(); // element -> Map(event name -> debounce and throttle state)
  let echoed = new Map(); // element -> { name: value } echoes skipped in the current batch
  let changing = false; // true while mount, patch or unmount is changing the DOM

  // ---- Building nodes ------------------------------------------------------

  function create(node) {
    if (typeof node.text === "string") return doc.createTextNode(node.text);

    const el = node.namespace
      ? doc.createElementNS(node.namespace, node.tag)
      : doc.createElement(node.tag);
    for (const [name, value] of Object.entries(node.attrs)) el.setAttribute(name, value);
    // Children before live state and properties, so a <select> has its
    // options by the time its value is set.
    for (const child of node.children) el.appendChild(create(child));
    for (const name of Object.keys(LIVE)) if (Object.hasOwn(node.attrs, name)) syncLive(el, name);
    for (const [name, value] of Object.entries(node.props)) setProperty(el, name, value);
    for (const [name, options] of Object.entries(node.events)) setEvent(el, name, options);
    return el;
  }

  // `value`, `checked` and `selected` are sent as attributes so they show up
  // in server-rendered HTML. Once a user has typed or clicked, the attribute
  // no longer drives what's on screen, so mirror it onto the live property.
  function syncLive(el, name) {
    if (!isLive(el, name)) return;
    writeLive(el, name, name === "value" ? (el.getAttribute("value") ?? "") : el.hasAttribute(name));
  }

  function isLive(el, name) {
    return Object.hasOwn(LIVE, name) && el.namespaceURI === XHTML && LIVE[name].has(el.localName);
  }

  // Updates lag behind the user: by the time the update for "Ba" arrives
  // they may have typed "Baz". So remember what each element reported, and
  // treat an update matching one of those as an echo of the past rather than
  // an instruction. Anything else, like clearing a field, is applied.
  function writeLive(el, name, want) {
    // One change can arrive as two patches (an attribute and a property), so
    // an echo stays an echo for the rest of its batch.
    if (echoed.get(el)?.[name] === want) return;
    const pending = reported.get(el)?.[name];
    if (pending && pending.length) {
      const echo = pending.indexOf(want);
      if (echo !== -1) {
        pending.splice(0, echo + 1);
        echoed.set(el, { ...echoed.get(el), [name]: want });
        return;
      }
      pending.length = 0;
    }
    if (el[name] !== want) el[name] = want; // Leaves the caret alone when unchanged.
  }

  function remember(el) {
    for (const name of ["value", "checked"]) {
      if (!isLive(el, name)) continue;
      let byName = reported.get(el);
      if (!byName) reported.set(el, (byName = { value: [], checked: [] }));
      const pending = byName[name];
      if (pending[pending.length - 1] !== el[name]) pending.push(el[name]);
      if (pending.length > 64) pending.shift();
    }
  }

  function setProperty(el, name, value) {
    if (isPrototypeKey(name)) return;
    if (isLive(el, name)) writeLive(el, name, value);
    else el[name] = value;
  }

  // A removed property goes back to what a fresh element would have, unless
  // an attribute of the same name now says otherwise.
  function resetProperty(el, name) {
    if (isPrototypeKey(name)) return;
    const fresh = el.localName.includes("-") ? null : defaultsFor(el);
    if (fresh && name in fresh) {
      const value = el.hasAttribute(name)
        ? typeof fresh[name] === "boolean" ? true : el.getAttribute(name)
        : fresh[name];
      setProperty(el, name, value);
    } else {
      delete el[name];
      if (name in el) el[name] = undefined; // A setter on a custom element's prototype.
    }
  }

  function defaultsFor(el) {
    const key = `${el.namespaceURI} ${el.localName}`;
    let fresh = pristine.get(key);
    if (!fresh) {
      fresh = doc.createElementNS(el.namespaceURI, el.localName);
      pristine.set(key, fresh);
    }
    return fresh;
  }

  // ---- Events --------------------------------------------------------------

  function setEvent(el, name, options) {
    let byName = handlers.get(el);
    if (!byName) handlers.set(el, (byName = new Map()));
    if (!byName.has(name)) el.addEventListener(name, listen);
    byName.set(name, options);
  }

  function removeEvent(el, name) {
    const byName = handlers.get(el);
    if (byName && byName.delete(name)) el.removeEventListener(name, listen);
    held.get(el)?.get(name)?.cancel();
    held.get(el)?.delete(name);
  }

  function listen(event) {
    const el = event.currentTarget;
    const options = handlers.get(el)?.get(event.type);
    if (!options) return;
    // Decided here and now: a server can't answer in time.
    if (options.preventDefault) event.preventDefault();
    if (options.stopPropagation) event.stopPropagation();
    // Events the page fires because of our own DOM changes, like the blur
    // Chrome sends when a patch removes the focused element, aren't the
    // user's doing. Mid-patch, their path points into a half-updated tree.
    if (changing) return;
    const path = pathOf(el);
    if (!path) return;
    remember(el);
    const payload = raw ? event : pick(event, options.include);
    if (options.debounce > 0 || options.throttle > 0) {
      limited(el, event.type, options, payload);
    } else {
      flushHeld();
      send({ path, name: event.type, event: payload });
    }
  }

  // Debounce and throttle hold events back here, so dropped ones never leave
  // the page. What's held is the latest event's payload, picked when it
  // fired. Its path is worked out when it's sent, so it fits the tree on
  // screen by then, and an element that's gone by then sends nothing.
  function limited(el, name, { debounce = 0, throttle = 0 }, payload) {
    let byName = held.get(el);
    if (!byName) held.set(el, (byName = new Map()));
    let limit = byName.get(name);
    if (!limit) byName.set(name, (limit = new Limit(el, name)));

    if (debounce > 0) {
      // Send the last one once they stop. With throttle too, don't hold
      // them back longer than that.
      limit.hold(payload);
      clearTimeout(limit.debounce);
      limit.debounce = setTimeout(() => limit.flush(), debounce);
      if (throttle > 0 && !limit.throttle) limit.throttle = setTimeout(() => limit.flush(), throttle);
    } else if (limit.throttle) {
      // Throttle on its own, mid-interval: keep the latest.
      limit.hold(payload);
    } else {
      // The first goes now. The latest one held during the interval goes
      // when it ends, and starts the next one.
      flushHeld();
      report(el, name, payload);
      const interval = () => {
        limit.throttle = setTimeout(() => {
          limit.throttle = null;
          if (!limit.waiting) return;
          limit.flush();
          interval();
        }, throttle);
      };
      interval();
    }
  }

  // Held events, in the order they last fired. They go before any event
  // that fires after them, so a submit never overtakes the debounced typing
  // that came before it.
  const holding = new Set();

  class Limit {
    constructor(el, name) {
      this.el = el;
      this.name = name;
      this.pending = undefined;
      this.waiting = false;
      this.debounce = null;
      this.throttle = null;
    }

    hold(payload) {
      this.pending = payload;
      this.waiting = true;
      holding.delete(this);
      holding.add(this);
    }

    flush() {
      const { waiting, pending } = this;
      this.cancel();
      if (waiting) report(this.el, this.name, pending);
    }

    cancel() {
      clearTimeout(this.debounce);
      clearTimeout(this.throttle);
      this.debounce = this.throttle = null;
      this.waiting = false;
      this.pending = undefined;
      holding.delete(this);
    }
  }

  function flushHeld() {
    for (const limit of [...holding]) limit.flush();
  }

  function report(el, name, payload) {
    const path = pathOf(el);
    if (path) send({ path, name, event: payload });
  }

  // Paths are computed when the event fires, so they're always correct for
  // the tree on screen, whatever patches have moved things around.
  function pathOf(node) {
    const path = [];
    while (node !== container.firstChild) {
      const parent = node.parentNode;
      if (!parent || parent === container) return null;
      path.push(Array.prototype.indexOf.call(parent.childNodes, node));
      node = parent;
    }
    return path.reverse();
  }

  // ---- Patches -------------------------------------------------------------

  function resolve(path) {
    let node = container.firstChild;
    // `item` rather than indexing, so a step can only ever reach a child.
    for (const index of path) {
      node = node && node.nodeType === 1 && Number.isInteger(index) ? node.childNodes.item(index) : undefined;
    }
    if (!node) throw new Error(`Jorn: no node at path [${path}]`);
    return node;
  }

  function elementAt(path) {
    const node = resolve(path);
    if (node.nodeType !== 1) throw new Error(`Jorn: expected an element at path [${path}]`);
    return node;
  }

  function childAt(el, index, path) {
    const child = Number.isInteger(index) ? el.childNodes.item(index) : null;
    if (!child) throw new Error(`Jorn: no child ${index} at path [${path}]`);
    return child;
  }

  function applyPatch(patch) {
    switch (patch.op) {
      case "replace": {
        const old = resolve(patch.path);
        old.parentNode.replaceChild(create(patch.node), old);
        break;
      }
      case "set-text": {
        const node = resolve(patch.path);
        if (node.nodeType !== 3) throw new Error(`Jorn: expected text at path [${patch.path}]`);
        node.data = patch.text;
        break;
      }
      case "set-attr": {
        const el = elementAt(patch.path);
        el.setAttribute(patch.name, patch.value);
        syncLive(el, patch.name);
        break;
      }
      case "remove-attr": {
        const el = elementAt(patch.path);
        el.removeAttribute(patch.name);
        syncLive(el, patch.name);
        break;
      }
      case "set-prop":
        setProperty(elementAt(patch.path), patch.name, patch.value);
        break;
      case "remove-prop":
        resetProperty(elementAt(patch.path), patch.name);
        break;
      case "set-event":
        setEvent(elementAt(patch.path), patch.name, patch.options);
        break;
      case "remove-event":
        removeEvent(elementAt(patch.path), patch.name);
        break;
      case "append": {
        const el = elementAt(patch.path);
        const fragment = doc.createDocumentFragment();
        for (const node of patch.nodes) fragment.appendChild(create(node));
        el.appendChild(fragment);
        break;
      }
      case "truncate": {
        const el = elementAt(patch.path);
        while (el.childNodes.length > patch.length) el.removeChild(el.lastChild);
        break;
      }
      case "insert": {
        const el = elementAt(patch.path);
        if (patch.index < 0 || patch.index > el.childNodes.length) throw new Error(`Jorn: no index ${patch.index} at path [${patch.path}]`);
        el.insertBefore(create(patch.node), el.childNodes[patch.index] ?? null);
        break;
      }
      case "move": {
        const el = elementAt(patch.path);
        const child = childAt(el, patch.from, patch.path);
        // `to` counts siblings with the child already taken out.
        if (patch.to < 0 || patch.to >= el.childNodes.length) throw new Error(`Jorn: no index ${patch.to} at path [${patch.path}]`);
        const before = el.childNodes[patch.to < patch.from ? patch.to : patch.to + 1] ?? null;
        // moveBefore keeps focus, selection and running animations where
        // insertBefore would reset them. Older browsers fall back.
        if (typeof el.moveBefore === "function") el.moveBefore(child, before);
        else el.insertBefore(child, before);
        break;
      }
      case "remove": {
        const el = elementAt(patch.path);
        el.removeChild(childAt(el, patch.index, patch.path));
        break;
      }
      default:
        throw new Error(`Jorn: unknown patch op ${JSON.stringify(patch.op)}`);
    }
  }

  // ---- Instructions --------------------------------------------------------

  function byId(id) {
    const root = container.getRootNode();
    const found = typeof root.getElementById === "function" ? root.getElementById(id) : doc.getElementById(id);
    if (!found) console.warn(`Jorn: no element with id ${JSON.stringify(id)}`);
    return found;
  }

  function runInstruction(instruction) {
    switch (instruction.effect) {
      case "focus":
        byId(instruction.id)?.focus();
        break;
      case "blur":
        byId(instruction.id)?.blur();
        break;
      case "scroll-into-view":
        byId(instruction.id)?.scrollIntoView?.();
        break;
      case "event": {
        const CustomEvent = doc.defaultView.CustomEvent;
        container.dispatchEvent(new CustomEvent(instruction.name, { detail: instruction.detail, bubbles: true, composed: true }));
        break;
      }
      case "client": {
        const effect = Object.hasOwn(effects, instruction.name) ? effects[instruction.name] : undefined;
        if (typeof effect === "function") effect(instruction.payload, { container });
        else console.warn(`Jorn: no client effect called ${JSON.stringify(instruction.name)}`);
        break;
      }
      default:
        throw new Error(`Jorn: unknown effect ${JSON.stringify(instruction.effect)}`);
    }
  }

  return {
    /** Render a whole tree, replacing whatever the container held. */
    mount(node) {
      changing = true;
      try {
        container.replaceChildren(create(node));
      } finally {
        changing = false;
      }
    },

    /** Apply a list of patches, strictly in order. */
    patch(patches) {
      echoed = new Map();
      changing = true;
      try {
        for (const patch of patches) applyPatch(patch);
      } finally {
        changing = false;
        echoed = new Map();
      }
    },

    /** Run patcher instructions from Jorn.Effect, in order, after patching. */
    run(instructions) {
      for (const instruction of instructions) runInstruction(instruction);
    },

    /** The DOM node at a path, or `null`. Handy in tests. */
    nodeAt(path) {
      try {
        return resolve(path);
      } catch {
        return null;
      }
    },

    /** Empty the container and stop reporting its events. */
    unmount() {
      changing = true;
      try {
        container.replaceChildren();
      } finally {
        changing = false;
      }
    },
  };
}

/**
 * Start a compiled Jorn program (`Jorn.simple` or `Jorn.application`) in
 * `container`, in client mode: the program runs in this page.
 *
 *   import { start } from "./jorn.js";
 *
 *   const app = start(Elm.Main, document.getElementById("app"), {
 *     flags,                                   // whatever your init expects
 *     effects: { copy: (text) => ... },        // for Effect.client
 *   });
 *   app.shutdown();                            // stop and empty the container
 *
 * The program has to declare ports called `toJorn` and `fromJorn`. If yours
 * are named differently, pass `ports: { toJorn: "...", fromJorn: "..." }`.
 *
 * @param {{ init: (options: { flags?: unknown }) => { ports: Record<string, any> } }} program
 * @param {Element} container
 * @param {{ flags?: unknown, effects?: Record<string, Function>, ports?: { toJorn?: string, fromJorn?: string } }} options
 */
export function start(program, container, { flags, effects = {}, ports = {} } = {}) {
  const { toJorn = "toJorn", fromJorn = "fromJorn" } = ports;
  const app = program.init(flags === undefined ? {} : { flags });
  const out = app.ports?.[toJorn];
  const into = app.ports?.[fromJorn];
  if (!out?.subscribe || !into?.send) {
    throw new TypeError(`Jorn: start needs a program with ports called ${toJorn} and ${fromJorn}`);
  }

  const jorn = connect(container, { send: (event) => into.send({ event }), raw: true, effects });
  const view = container.ownerDocument.defaultView;
  // One render per animation frame, however many messages arrive before it.
  const nextFrame =
    typeof view?.requestAnimationFrame === "function"
      ? (callback) => view.requestAnimationFrame(callback)
      : (callback) => setTimeout(callback, 0);
  let running = true;

  function receive(message) {
    if (!running) return;
    draw(jorn, message, () => into.send({ painted: true }));
    if (message.frame) nextFrame(() => running && into.send({ frame: true }));
    if (message.error) console.warn(`Jorn: ${message.error}`);
  }
  out.subscribe(receive);

  return {
    /** Stop the program and empty the container. */
    shutdown() {
      if (!running) return;
      running = false;
      out.unsubscribe(receive);
      into.send({ shutdown: true });
      jorn.unmount();
    },
  };
}

/**
 * Show a Jorn program that runs on a server in `container`, in server mode:
 * the program runs in `server/jorn.js`, and this page applies its patches and
 * sends back events over a websocket.
 *
 *   import { stream } from "./jorn.js";
 *
 *   const app = stream(document.getElementById("app"), "/app", {
 *     flags,                                   // sent to the server, untrusted there
 *     effects: { copy: (text) => ... },        // for Effect.client
 *   });
 *   app.close();                               // disconnect and empty the container
 *
 * A relative `url` is resolved against the page's address, and `http` and
 * `https` become `ws` and `wss`.
 *
 * @param {Element} container
 * @param {string | URL} url
 * `csrfToken` goes to the server with `flags`, for its `authorize` check.
 *
 * @param {{ flags?: unknown, csrfToken?: string, effects?: Record<string, Function> }} options
 */
export function stream(container, url, { flags, csrfToken, effects = {} } = {}) {
  const view = container?.ownerDocument?.defaultView;
  const Socket = view?.WebSocket ?? globalThis.WebSocket;
  if (typeof Socket !== "function") {
    throw new TypeError("Jorn: stream needs a browser with WebSocket");
  }
  const address = new URL(url, view?.location?.href);
  if (address.protocol === "http:") address.protocol = "ws:";
  if (address.protocol === "https:") address.protocol = "wss:";

  const socket = new Socket(address.href);
  let running = true;
  const post = (message) => {
    if (running && socket.readyState === socket.OPEN) socket.send(JSON.stringify(message));
  };
  const jorn = connect(container, { send: (event) => post({ event }), effects });

  socket.addEventListener("open", () => post({ join: { protocol: 0, flags, csrfToken } }));
  socket.addEventListener("message", ({ data }) => {
    if (!running) return;
    let message;
    try {
      message = JSON.parse(data);
    } catch {
      console.warn("Jorn: the server sent something that isn't JSON");
      return;
    }
    draw(jorn, message, () => post({ painted: true }));
  });
  socket.addEventListener("close", ({ code, reason }) => {
    if (running && code !== 1000) console.warn(`Jorn: the server closed the connection (${code}${reason ? `: ${reason}` : ""})`);
  });

  return {
    /** Disconnect and empty the container. */
    close() {
      if (!running) return;
      running = false;
      socket.close(1000);
      jorn.unmount();
    },
  };
}

/**
 * Define `<jorn-server-component>`, the element `Jorn.ServerComponent.element`
 * makes, so that a page can hold server components:
 *
 *   <jorn-server-component route="/chat"></jorn-server-component>
 *
 * Each one streams the component at its `route` into itself while it's in
 * the document, sending its `flags` attribute (JSON) and `csrf-token`
 * attribute when it connects. Moving it keeps the connection. `effects` are
 * the functions every component's `Effect.client` can call.
 *
 * Changing `route`, `flags` or `csrf-token` reconnects, which starts a new
 * session. Only the first call defines the element, so call it before
 * anything else does if you have effects to give it.
 *
 * @param {{ effects?: Record<string, Function>, window?: Window }} options
 */
export function defineServerComponent({ effects = {}, window = globalThis } = {}) {
  const registry = window.customElements;
  if (!registry) throw new TypeError("Jorn: defineServerComponent needs a browser with custom elements");
  if (registry.get("jorn-server-component")) return;

  registry.define(
    "jorn-server-component",
    class extends window.HTMLElement {
      static observedAttributes = ["route", "flags", "csrf-token"];
      #app = null;

      connectedCallback() {
        if (!this.#app) this.#open();
      }

      // Moving an element without moveBefore removes it and adds it back
      // straight away, so only close if it's still gone after this task.
      disconnectedCallback() {
        queueMicrotask(() => {
          if (!this.isConnected) this.#close();
        });
      }

      attributeChangedCallback(name, before, after) {
        if (before !== after && this.#app) {
          this.#close();
          this.#open();
        }
      }

      #open() {
        const route = this.getAttribute("route");
        if (route === null) {
          console.warn("Jorn: a <jorn-server-component> needs a route");
          return;
        }
        let flags;
        const json = this.getAttribute("flags");
        if (json !== null) {
          try {
            flags = JSON.parse(json);
          } catch {
            console.warn("Jorn: a <jorn-server-component>'s flags aren't JSON");
          }
        }
        this.#app = stream(this, route, { flags, csrfToken: this.getAttribute("csrf-token") ?? undefined, effects });
      }

      #close() {
        this.#app?.close();
        this.#app = null;
      }
    },
  );
}

// What both modes do with a message from the program: mount it, or apply
// its patches and then its instructions, and say so if it asked.
function draw(jorn, message, painted) {
  if (message.mount) jorn.mount(message.mount);
  if (message.patches) {
    jorn.patch(message.patches);
    jorn.run(message.instructions ?? []);
    if (message.painted) painted();
  }
}

// Copy the requested dotted fields (like "target.value") off an event into
// plain JSON, keeping their nesting.
function pick(event, include) {
  const out = {};
  for (const dotted of include) {
    const keys = dotted.split(".");
    if (keys.some(isPrototypeKey)) continue;
    let value = event;
    for (const key of keys) {
      value = value == null ? undefined : value[key];
    }
    if (value === undefined || typeof value === "function") continue;

    let target = out;
    for (const key of keys.slice(0, -1)) {
      if (typeof target[key] !== "object" || target[key] === null) target[key] = {};
      target = target[key];
    }
    target[keys[keys.length - 1]] = toJson(value);
  }
  return out;
}

// Property names and event fields come off the wire. These would lead to an
// object's prototype instead of one of its own fields, so they're ignored.
function isPrototypeKey(key) {
  return key === "__proto__" || key === "constructor" || key === "prototype";
}

function toJson(value) {
  if (value === null || typeof value !== "object") return value;
  try {
    return JSON.parse(JSON.stringify(value));
  } catch {
    return null;
  }
}
