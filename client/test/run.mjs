// Tests for client/jorn.js, in jsdom.
//
// 1. Unit tests for the parts random trees can't reach: live form state after
//    the user has typed or clicked, event payloads, propagation, raw mode.
// 2. Randomized cases: for view sequences A -> B -> C generated in Elm, mount
//    A, apply Jorn's patches for A->B and B->C, and check the DOM is exactly
//    what C describes: tags, namespaces, attributes, live properties, text.
//    Then fire every event on every element and check that exactly the
//    elements with a handler report it, with the right preventDefault, and
//    that the event router sends each report back to the handler on that element.
//
// Usage: node client/test/run.mjs [cases] [seed]
// Build first: cd client/test/elm && elm make src/ClientSpec.elm --optimize --output=build/spec.js

import { JSDOM } from "jsdom";
import { createRequire } from "node:module";
import { connect } from "../jorn.js";

const CASES = Number(process.argv[2] ?? 2000);
const SEED = Number(process.argv[3] ?? 42);
const XHTML = "http://www.w3.org/1999/xhtml";

const { window } = new JSDOM("<!doctype html><html><body></body></html>");
const { document } = window;

let failed = 0;
const failures = [];
function fail(what, detail = {}) {
  failed++;
  if (failures.length < 8) failures.push({ what, ...detail });
}
function check(condition, what, detail) {
  if (!condition) fail(what, detail);
}

function setup(raw = false) {
  const container = document.createElement("div");
  document.body.appendChild(container);
  const sent = [];
  const jorn = connect(container, { send: (e) => sent.push(e), raw });
  return { container, sent, jorn };
}

const el = (tag, { attrs = {}, props = {}, events = {}, namespace = "" } = {}, children = []) => ({
  tag,
  namespace,
  attrs,
  props,
  events,
  children,
});
const text = (t) => ({ text: t });
const opts = (o = {}) => ({ preventDefault: false, stopPropagation: false, include: [], ...o });

// ---- Unit tests --------------------------------------------------------------

function unit(name, body) {
  try {
    body();
  } catch (error) {
    fail(`unit: ${name} threw`, { error: String(error) });
  }
}

unit("mounts a tree", () => {
  const { container, jorn } = setup();
  jorn.mount(el("div", { attrs: { class: "app" } }, [text("hi"), el("span", {}, [text("x")])]));
  check(container.innerHTML === '<div class="app">hi<span>x</span></div>', "mount html", {
    got: container.innerHTML,
  });
});

unit("value attribute updates an input the user typed in", () => {
  const { container, jorn } = setup();
  jorn.mount(el("input", { attrs: { value: "a" } }));
  const input = container.firstChild;
  input.value = "typed";
  jorn.patch([{ op: "set-attr", path: [], name: "value", value: "b" }]);
  check(input.value === "b", "value synced after typing", { got: input.value });
  jorn.patch([{ op: "remove-attr", path: [], name: "value" }]);
  check(input.value === "", "value cleared on remove-attr", { got: input.value });
});

unit("checked attribute updates a box the user clicked", () => {
  const { container, jorn } = setup();
  jorn.mount(el("input", { attrs: { type: "checkbox", checked: "" } }));
  const box = container.firstChild;
  check(box.checked === true, "checked on mount");
  box.checked = false; // the user unticks it
  // checked True -> False, as the diff emits it
  jorn.patch([
    { op: "remove-attr", path: [], name: "checked" },
    { op: "set-prop", path: [], name: "checked", value: false },
  ]);
  check(box.checked === false, "unchecked");
  box.checked = true; // the user ticks it again
  // checked False -> True, as the diff emits it
  jorn.patch([
    { op: "set-attr", path: [], name: "checked", value: "" },
    { op: "remove-prop", path: [], name: "checked" },
  ]);
  check(box.checked === true, "checked again");
  box.checked = false;
  jorn.patch([
    { op: "remove-attr", path: [], name: "checked" },
    { op: "set-prop", path: [], name: "checked", value: false },
  ]);
  check(box.checked === false, "a dirty box is reset by the false property");
});

unit("disabled round trip keeps the attribute in step", () => {
  const { container, jorn } = setup();
  jorn.mount(el("button", { props: { disabled: false } }));
  const button = container.firstChild;
  jorn.patch([
    { op: "set-attr", path: [], name: "disabled", value: "" },
    { op: "remove-prop", path: [], name: "disabled" },
  ]);
  check(button.disabled === true && button.hasAttribute("disabled"), "disabled on");
});

unit("select value is set after its options exist", () => {
  const { container, jorn } = setup();
  jorn.mount(
    el("select", { attrs: { value: "b" } }, [
      el("option", { attrs: { value: "a" } }, [text("A")]),
      el("option", { attrs: { value: "b" } }, [text("B")]),
    ]),
  );
  check(container.firstChild.value === "b", "select value", { got: container.firstChild.value });
});

unit("li value attribute is left alone", () => {
  const { container, jorn } = setup();
  jorn.mount(el("ol", {}, [el("li", { attrs: { value: "v" } })]));
  check(container.innerHTML === '<ol><li value="v"></li></ol>', "li attribute kept", {
    got: container.innerHTML,
  });
});

unit("removing an expando property clears it", () => {
  const { container, jorn } = setup();
  jorn.mount(el("data-grid", { props: { rows: [1, 2] } }));
  check(JSON.stringify(container.firstChild.rows) === "[1,2]", "expando set");
  jorn.patch([{ op: "remove-prop", path: [], name: "rows" }]);
  check(container.firstChild.rows === undefined, "expando cleared");
});

unit("include serializes only the requested fields", () => {
  const { container, sent, jorn } = setup();
  jorn.mount(el("div", {}, [el("input", { events: { input: opts({ include: ["target.value", "target.missing.deep", "timeStamp"] }) } })]));
  const input = container.firstChild.firstChild;
  input.value = "hi";
  input.dispatchEvent(new window.Event("input", { bubbles: true }));
  check(sent.length === 1, "one event sent", { sent });
  const message = sent[0] ?? {};
  check(JSON.stringify(message.path) === "[0]" && message.name === "input", "path and name", { message });
  check(message.event?.target?.value === "hi" && Object.keys(message.event.target).length === 1, "target.value only", { message });
  check(typeof message.event?.timeStamp === "number", "top-level field");
  check(JSON.stringify(JSON.parse(JSON.stringify(message))) === JSON.stringify(message), "payload is plain JSON");
});

unit("raw mode hands over the live event", () => {
  const { container, sent, jorn } = setup(true);
  jorn.mount(el("button", { events: { click: opts() } }));
  const event = new window.Event("click");
  container.firstChild.dispatchEvent(event);
  check(sent[0]?.event === event, "raw event object");
});

unit("preventDefault and stopPropagation happen synchronously", () => {
  const { container, sent, jorn } = setup();
  jorn.mount(
    el("form", { events: { click: opts(), submit: opts({ preventDefault: true }) } }, [
      el("button", { events: { click: opts({ stopPropagation: true }) } }),
    ]),
  );
  const click = new window.Event("click", { bubbles: true, cancelable: true });
  container.firstChild.firstChild.dispatchEvent(click);
  check(sent.length === 1 && JSON.stringify(sent[0].path) === "[0]", "parent never saw the click", { sent });
  check(!click.defaultPrevented, "click not prevented");
  const submit = new window.Event("submit", { cancelable: true });
  container.firstChild.dispatchEvent(submit);
  check(submit.defaultPrevented, "submit prevented");
});

unit("set-event replaces options without a second listener", () => {
  const { container, sent, jorn } = setup();
  jorn.mount(el("a", { events: { click: opts() } }));
  jorn.patch([{ op: "set-event", path: [], name: "click", options: opts({ preventDefault: true }) }]);
  const click = new window.Event("click", { cancelable: true });
  container.firstChild.dispatchEvent(click);
  check(sent.length === 1, "one report per event", { count: sent.length });
  check(click.defaultPrevented, "new options apply");
  jorn.patch([{ op: "remove-event", path: [], name: "click" }]);
  container.firstChild.dispatchEvent(new window.Event("click"));
  check(sent.length === 1, "removed handler is silent");
});

unit("paths follow the tree after patches", () => {
  const { container, sent, jorn } = setup();
  jorn.mount(el("ul", {}, [el("li", {}, [text("a")])]));
  jorn.patch([
    { op: "append", path: [], nodes: [el("li", { events: { click: opts() } }, [text("b")])] },
    { op: "replace", path: [0], node: text("gone") },
  ]);
  check(container.innerHTML === "<ul>gone<li>b</li></ul>", "html", { got: container.innerHTML });
  container.firstChild.lastChild.dispatchEvent(new window.Event("click"));
  check(JSON.stringify(sent[0]?.path) === "[1]", "path of appended child", { sent });
  jorn.patch([{ op: "truncate", path: [], length: 1 }]);
  check(container.innerHTML === "<ul>gone</ul>", "truncate");
  jorn.patch([{ op: "replace", path: [], node: el("p", {}, [text("new root")]) }]);
  check(container.innerHTML === "<p>new root</p>", "replace root");
});

unit("keyed moves carry the DOM node and its live state", () => {
  const { container, sent, jorn } = setup();
  const item = (name) => el("input", { attrs: { name }, events: { input: opts({ include: ["target.value"] }) } });
  jorn.mount(el("ul", {}, [item("a"), item("b"), item("c")]));
  const [a, b, c] = container.firstChild.childNodes;
  a.value = "typed into a";
  jorn.patch([{ op: "move", path: [], from: 0, to: 2 }]);
  check([...container.firstChild.childNodes].map((n) => n.name).join() === "b,c,a", "move to the end", { got: container.innerHTML });
  check(container.firstChild.lastChild === a && a.value === "typed into a", "same node, same value");
  jorn.patch([{ op: "move", path: [], from: 2, to: 0 }]);
  check(container.firstChild.firstChild === a, "move to the front");
  jorn.patch([{ op: "move", path: [], from: 0, to: 1 }]);
  check([...container.firstChild.childNodes].map((n) => n.name).join() === "b,a,c", "move by one");
  jorn.patch([{ op: "remove", path: [], index: 0 }]);
  check(!b.isConnected && container.firstChild.firstChild === a, "remove");
  jorn.patch([{ op: "insert", path: [], index: 1, node: item("d") }]);
  check([...container.firstChild.childNodes].map((n) => n.name).join() === "a,d,c", "insert in the middle", { got: container.innerHTML });
  jorn.patch([{ op: "insert", path: [], index: 3, node: item("e") }]);
  check(container.firstChild.lastChild.name === "e", "insert at the end");
  c.dispatchEvent(new window.Event("input"));
  check(JSON.stringify(sent.at(-1)?.path) === "[2]", "a moved node reports its new path", { sent });
});

unit("default values start a control without controlling it", () => {
  const { container, jorn } = setup();
  jorn.mount(
    el("form", {}, [
      el("input", { props: { defaultValue: "a" } }),
      el("input", { attrs: { type: "checkbox" }, props: { defaultChecked: true } }),
    ]),
  );
  const [input, box] = container.firstChild.childNodes;
  check(input.value === "a" && box.checked === true, "initial values apply", { value: input.value, checked: box.checked });
  input.value = "typed";
  box.checked = false;
  jorn.patch([
    { op: "set-prop", path: [0], name: "defaultValue", value: "b" },
    { op: "set-prop", path: [1], name: "defaultChecked", value: false },
  ]);
  check(input.value === "typed", "typing survives a new defaultValue", { got: input.value });
  check(input.getAttribute("value") === "b", "defaultValue reflects into the attribute");
  check(box.checked === false && !box.hasAttribute("checked"), "defaultChecked reflects without touching the box");
  jorn.patch([{ op: "set-prop", path: [1], name: "defaultChecked", value: true }]);
  check(box.checked === false, "a clicked box keeps its state", { got: box.checked });
  jorn.patch([{ op: "remove-prop", path: [0], name: "defaultValue" }]);
  check(input.value === "typed", "removing defaultValue leaves typing alone", { got: input.value });
});

unit("selected follows the model, defaultSelected only starts it", () => {
  const { container, jorn } = setup();
  const option = (value, more = {}) => el("option", { attrs: { value, ...(more.attrs ?? {}) }, props: more.props ?? {} }, [text(value)]);
  jorn.mount(el("select", {}, [option("a"), option("b", { attrs: { selected: "" } }), option("c")]));
  const select = container.firstChild;
  check(select.value === "b", "selected attribute picks the option", { got: select.value });
  select.value = "a";
  jorn.patch([
    { op: "remove-attr", path: [1], name: "selected" },
    { op: "set-attr", path: [2], name: "selected", value: "" },
  ]);
  check(select.value === "c", "a new selected option applies even after the user chose", { got: select.value });
  jorn.mount(el("select", {}, [option("a"), option("b", { props: { defaultSelected: true } })]));
  const second = container.firstChild;
  check(second.value === "b", "defaultSelected starts the selection", { got: second.value });
  second.value = "a";
  jorn.patch([{ op: "set-prop", path: [1], name: "defaultSelected", value: false }]);
  check(second.value === "a" && !second.options[1].hasAttribute("selected"), "the user's choice stays", { got: second.value });
});

unit("keyboard events send their key in server mode", () => {
  const { container, sent, jorn } = setup();
  jorn.mount(el("input", { events: { keydown: opts({ include: ["key"] }) } }));
  container.firstChild.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter" }));
  check(JSON.stringify(sent[0]?.event) === '{"key":"Enter"}', "key is sent", { sent });
});

unit("patcher instructions run against the page", () => {
  const container = document.createElement("div");
  document.body.appendChild(container);
  const copied = [];
  const jorn = connect(container, { send: () => {}, effects: { copy: (payload, context) => copied.push([payload, context.container]) } });
  jorn.mount(el("div", {}, [el("input", { attrs: { id: "first" } }), el("input", { attrs: { id: "second" } })]));
  const [first, second] = container.firstChild.childNodes;
  let scrolled = null;
  second.scrollIntoView = () => (scrolled = second);
  const heard = [];
  document.body.addEventListener("saved", (event) => heard.push(event.detail));
  const warn = console.warn;
  const warnings = [];
  console.warn = (message) => warnings.push(message);
  try {
    jorn.run([
      { effect: "focus", id: "first" },
      { effect: "scroll-into-view", id: "second" },
      { effect: "event", name: "saved", detail: { id: 7 } },
      { effect: "client", name: "copy", payload: "link" },
      { effect: "focus", id: "missing" },
      { effect: "client", name: "toString", payload: null },
    ]);
  } finally {
    console.warn = warn;
  }
  check(document.activeElement === first, "focus");
  check(scrolled === second, "scroll into view");
  check(heard.length === 1 && heard[0].id === 7, "custom event bubbles out of the container", { heard });
  check(copied.length === 1 && copied[0][0] === "link" && copied[0][1] === container, "client effect gets its payload");
  check(warnings.length === 2, "missing ids and unregistered effects warn", { warnings });
  jorn.run([{ effect: "blur", id: "first" }]);
  check(document.activeElement !== first, "blur");
  let threw = false;
  try {
    jorn.run([{ effect: "explode" }]);
  } catch {
    threw = true;
  }
  check(threw, "unknown instruction throws");
});

unit("detached elements stay quiet", () => {
  const { container, sent, jorn } = setup();
  jorn.mount(el("div", {}, [el("button", { events: { click: opts() } })]));
  const button = container.firstChild.firstChild;
  jorn.patch([{ op: "truncate", path: [], length: 0 }]);
  button.dispatchEvent(new window.Event("click"));
  check(sent.length === 0, "no report from a removed element");
});

unit("events caused by a patch aren't reported", () => {
  // Chrome fires blur when a patch removes the focused element. jsdom doesn't,
  // so a custom element stands in: it blurs the input while it's being removed.
  let input;
  window.customElements.define(
    "jorn-test-probe",
    class extends window.HTMLElement {
      disconnectedCallback() {
        input.dispatchEvent(new window.Event("blur"));
      }
    },
  );
  const { container, sent, jorn } = setup();
  jorn.mount(el("div", {}, [el("input", { events: { blur: opts() } }), el("jorn-test-probe")]));
  input = container.firstChild.firstChild;
  jorn.patch([{ op: "truncate", path: [], length: 1 }]);
  check(sent.length === 0, "no report from an event fired mid-patch", { sent });
  input.dispatchEvent(new window.Event("blur"));
  check(sent.length === 1, "the same handler still reports afterwards", { sent });
});

unit("names that lead to a prototype are ignored", () => {
  const { container, sent, jorn } = setup();
  // Parsed, because a `__proto__` key in an object literal sets the prototype.
  const props = JSON.parse('{ "__proto__": { "polluted": true }, "constructor": 1, "title": "kept" }');
  const include = ["__proto__.NONE", "constructor.name", "type"];
  jorn.mount(el("div", { props, events: { click: opts({ include }) } }));
  const div = container.firstChild;
  const untouched = () => Object.getPrototypeOf(div) === window.HTMLDivElement.prototype && div.constructor === window.HTMLDivElement;
  check(untouched(), "mount leaves the element's prototype alone");
  check(div.title === "kept", "other properties still apply");
  jorn.patch([
    { op: "set-prop", path: [], name: "__proto__", value: { polluted: true } },
    { op: "remove-prop", path: [], name: "constructor" },
  ]);
  check(untouched(), "patches leave it alone too");
  div.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
  check(JSON.stringify(sent.map((e) => Object.keys(e.event))) === '[["type"]]', "event fields through a prototype are dropped", { sent });
  check({}.NONE === undefined && {}.polluted === undefined, "Object.prototype is untouched");
});

const rawEl = (tag, options, html) => {
  const { children, ...node } = el(tag, options);
  return { ...node, html };
};

unit("raw HTML is the element's content, replaced as a whole", () => {
  const { container, sent, jorn } = setup();
  jorn.mount(el("div", {}, [rawEl("article", { attrs: { class: "post" }, events: { click: opts() } }, "<p>a <b>b</b></p>")]));
  const article = container.firstChild.firstChild;
  check(article.innerHTML === "<p>a <b>b</b></p>" && article.className === "post", "mounted", { html: article.innerHTML });
  article.querySelector("b").dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
  check(sent.length === 1 && JSON.stringify(sent[0].path) === "[0]", "a click inside bubbles to the raw element's handler", { sent });
  jorn.patch([{ op: "set-html", path: [0], html: "<p>c</p>" }]);
  check(container.firstChild.firstChild === article && article.innerHTML === "<p>c</p>", "set-html replaces the content in place", { html: article.innerHTML });
  const throws = (patch) => {
    try {
      jorn.patch([patch]);
      return false;
    } catch {
      return true;
    }
  };
  check(throws({ op: "set-attr", path: [0, 0], name: "a", value: "b" }), "no path leads inside raw HTML");
  check(throws({ op: "append", path: [0], nodes: [text("x")] }), "raw HTML has no children to patch");
  check(throws({ op: "set-html", path: [], html: "x" }), "set-html on an ordinary element throws");
  check(article.innerHTML === "<p>c</p>", "and the refused patches changed nothing", { html: article.innerHTML });
});

unit("protocol violations throw", () => {
  const { jorn } = setup();
  jorn.mount(el("div", {}, [text("t")]));
  const throws = (patch) => {
    try {
      jorn.patch([patch]);
      return false;
    } catch {
      return true;
    }
  };
  check(throws({ op: "set-text", path: [5], text: "x" }), "missing path throws");
  check(throws({ op: "set-prop", path: ["__proto__"], name: "x", value: 1 }), "a path step that isn't an index throws");
  check(throws({ op: "set-attr", path: [0], name: "a", value: "b" }), "attr on text throws");
  check(throws({ op: "set-text", path: [], text: "x" }), "text on element throws");
  check(throws({ op: "explode", path: [] }), "unknown op throws");
  check(throws({ op: "insert", path: [], index: 2, node: text("x") }), "insert past the end throws");
  check(throws({ op: "move", path: [], from: 1, to: 0 }), "move of a missing child throws");
  check(throws({ op: "move", path: [], from: 0, to: 1 }), "move past the end throws");
  check(throws({ op: "remove", path: [], index: 1 }), "remove of a missing child throws");
});

unit("late updates don't overwrite newer typing", () => {
  const { container, sent, jorn } = setup();
  jorn.mount(el("input", { attrs: { value: "" }, events: { input: opts({ include: ["target.value"] }) } }));
  const input = container.firstChild;
  const type = (value) => {
    input.value = value;
    input.dispatchEvent(new window.Event("input"));
  };
  type("B");
  type("Ba");
  type("Baz");
  check(sent.length === 3, "three reports");
  jorn.patch([{ op: "set-attr", path: [], name: "value", value: "B" }]);
  check(input.value === "Baz", "echo of B ignored", { got: input.value });
  jorn.patch([{ op: "set-attr", path: [], name: "value", value: "Ba" }]);
  check(input.value === "Baz", "echo of Ba ignored", { got: input.value });
  type("Bazy");
  jorn.patch([{ op: "set-attr", path: [], name: "value", value: "Baz" }]);
  check(input.value === "Bazy", "echo of Baz ignored", { got: input.value });
  jorn.patch([{ op: "set-attr", path: [], name: "value", value: "Bazy" }]);
  check(input.value === "Bazy", "caught up", { got: input.value });
  jorn.patch([{ op: "set-attr", path: [], name: "value", value: "" }]);
  check(input.value === "", "a server-side clear applies", { got: input.value });
  type("x");
  jorn.patch([{ op: "set-attr", path: [], name: "value", value: "reset" }]);
  check(input.value === "reset", "a value the user never had applies", { got: input.value });
});

unit("late updates don't undo newer clicks", () => {
  const { container, jorn } = setup();
  jorn.mount(el("input", { attrs: { type: "checkbox" }, props: { checked: false }, events: { change: opts({ include: ["target.checked"] }) } }));
  const box = container.firstChild;
  const click = () => {
    box.checked = !box.checked;
    box.dispatchEvent(new window.Event("change"));
  };
  click(); // on
  click(); // off
  // the echo of "on" arrives as two patches
  jorn.patch([
    { op: "set-attr", path: [], name: "checked", value: "" },
    { op: "remove-prop", path: [], name: "checked" },
  ]);
  check(box.checked === false, "echo of on ignored", { got: box.checked });
  jorn.patch([
    { op: "remove-attr", path: [], name: "checked" },
    { op: "set-prop", path: [], name: "checked", value: false },
  ]);
  check(box.checked === false, "echo of off");
  jorn.patch([
    { op: "set-attr", path: [], name: "checked", value: "" },
    { op: "remove-prop", path: [], name: "checked" },
  ]);
  check(box.checked === true, "a server-side check applies");
});

// Debounce and throttle run on real timers, so these wait.
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function asyncUnit(name, body) {
  try {
    await body();
  } catch (error) {
    fail(`unit: ${name} threw`, { error: String(error) });
  }
}

function typeInto(input, value) {
  input.value = value;
  const event = new window.Event("input", { bubbles: true, cancelable: true });
  input.dispatchEvent(event);
  return event;
}

await asyncUnit("debounce sends only the last event, once they stop", async () => {
  const { container, sent, jorn } = setup();
  jorn.mount(el("div", {}, [el("input", { events: { input: opts({ include: ["target.value"], debounce: 40, preventDefault: true }) } })]));
  const input = container.firstChild.firstChild;
  const events = [];
  // Longer than the debounce in all, with no pause as long as it.
  for (const value of ["a", "ab", "abc", "abcd", "abcde", "abcdef", "abcdefg", "abcdefgh"]) {
    events.push(typeInto(input, value));
    await sleep(10);
  }
  check(sent.length === 0, "nothing sent while typing", { sent });
  check(events.every((event) => event.defaultPrevented), "preventDefault applies to every event, dropped ones too");
  await sleep(80);
  check(sent.length === 1 && sent[0].event.target.value === "abcdefgh", "the last one, once", { sent });
  check(JSON.stringify(sent[0]?.path) === "[0]", "with its path", { sent });
});

await asyncUnit("throttle sends the first now and the latest at the end of the interval", async () => {
  const { container, sent, jorn } = setup();
  jorn.mount(el("input", { events: { input: opts({ include: ["target.value"], throttle: 50 }) } }));
  const input = container.firstChild;
  typeInto(input, "1");
  check(sent.length === 1 && sent[0].event.target.value === "1", "the first goes straight away", { sent });
  typeInto(input, "2");
  typeInto(input, "3");
  check(sent.length === 1, "the rest wait", { sent });
  await sleep(80);
  check(sent.length === 2 && sent[1].event.target.value === "3", "the latest goes at the end of the interval", { sent });
  await sleep(80);
  check(sent.length === 2, "and nothing after that", { sent });
});

await asyncUnit("throttle caps how long debounce holds events back", async () => {
  const { container, sent, jorn } = setup();
  jorn.mount(el("input", { events: { input: opts({ include: ["target.value"], debounce: 30, throttle: 60 }) } }));
  const input = container.firstChild;
  let whileTyping = 0;
  for (let i = 1; i <= 15; i++) {
    whileTyping = sent.length;
    typeInto(input, String(i));
    await sleep(10);
  }
  check(whileTyping >= 1, "events go out while the typing never pauses", { sent });
  await sleep(80);
  check(sent.at(-1)?.event.target.value === "15", "and the last one goes once it does", { sent });
  check(sent.length < 15, "most are dropped", { sent });
});

await asyncUnit("late updates still count as echoes with debounced input", async () => {
  const { container, sent, jorn } = setup();
  jorn.mount(el("input", { attrs: { value: "" }, events: { input: opts({ include: ["target.value"], debounce: 20 }) } }));
  const input = container.firstChild;
  typeInto(input, "B");
  typeInto(input, "Ba");
  typeInto(input, "Baz");
  await sleep(50);
  check(sent.length === 1 && sent[0].event.target.value === "Baz", "one event", { sent });
  typeInto(input, "Bazy");
  jorn.patch([{ op: "set-attr", path: [], name: "value", value: "Baz" }]);
  check(input.value === "Bazy", "the update for Baz doesn't undo newer typing", { got: input.value });
  jorn.patch([{ op: "set-attr", path: [], name: "value", value: "" }]);
  check(input.value === "", "clearing the field still applies", { got: input.value });
});

await asyncUnit("an event goes after the held events that fired before it", async () => {
  const { container, sent, jorn } = setup();
  jorn.mount(
    el("form", { events: { submit: opts({ preventDefault: true }) } }, [
      el("input", { events: { input: opts({ include: ["target.value"], debounce: 1000 }) } }),
    ]),
  );
  const input = container.firstChild.firstChild;
  typeInto(input, "milk");
  container.firstChild.dispatchEvent(new window.Event("submit", { bubbles: true, cancelable: true }));
  check(sent.map((message) => message.name).join() === "input,submit", "the typing, then the submit", { sent });
  check(sent[0]?.event?.target?.value === "milk", "with the typed value", { sent });
  await sleep(20);
  check(sent.length === 2, "and the typing isn't sent again later", { sent });
});

await asyncUnit("held events are dropped when their handler or element goes", async () => {
  const { container, sent, jorn } = setup();
  const handler = { input: opts({ debounce: 20 }) };
  jorn.mount(el("div", {}, [el("input", { events: handler }), el("input", { events: handler })]));
  typeInto(container.firstChild.childNodes[0], "x");
  typeInto(container.firstChild.childNodes[1], "y");
  jorn.patch([
    { op: "remove-event", path: [0], name: "input" },
    { op: "truncate", path: [], length: 1 },
  ]);
  await sleep(50);
  check(sent.length === 0, "nothing sent", { sent });
});

const unitFailures = failed;

// ---- Randomized cases ---------------------------------------------------------

const require = createRequire(import.meta.url);
const { Elm } = require("./elm/build/spec.js");
const app = Elm.ClientSpec.init();
let reply;
app.ports.out.subscribe((value) => reply(value));
const ask = (port, payload) =>
  new Promise((resolve) => {
    reply = resolve;
    app.ports[port].send(payload);
  });

// What the DOM should look like, worked out from the node alone. Raw HTML is
// compared as the browser serializes it, which is what `want` is for.
function expected(node) {
  if (typeof node.text === "string") return { text: node.text };
  const content = typeof node.html === "string" ? { html: serialized(node.html) } : { children: node.children.map(expected) };
  const flag = (name) => (name in node.props ? node.props[name] : name in node.attrs);
  const props = {};
  if (!node.namespace && node.tag === "input") {
    props.checked = flag("checked");
    props.value = node.props.value ?? node.attrs.value ?? "";
  }
  if (!node.namespace && (node.tag === "input" || node.tag === "button")) props.disabled = flag("disabled");
  props.config = node.props.config;
  return {
    tag: node.tag,
    ns: node.namespace || XHTML,
    attrs: Object.entries(node.attrs).map(([k, v]) => `${k}=${v}`).sort(),
    props,
    ...content,
  };
}

function serialized(html) {
  const el = window.document.createElement("div");
  el.innerHTML = html;
  return el.innerHTML;
}

function actual(dom, want) {
  if (dom.nodeType === 3) return { text: dom.data };
  const content =
    want && "html" in want
      ? { html: dom.innerHTML }
      : { children: [...dom.childNodes].map((child, i) => actual(child, want?.children?.[i])) };
  const props = {};
  if (dom.namespaceURI === XHTML && dom.localName === "input") {
    props.checked = dom.checked;
    props.value = dom.value;
  }
  if (dom.namespaceURI === XHTML && (dom.localName === "input" || dom.localName === "button")) props.disabled = dom.disabled;
  props.config = dom.config;
  return {
    tag: dom.localName,
    ns: dom.namespaceURI,
    attrs: [...dom.attributes].map((a) => `${a.name}=${a.value}`).sort(),
    props,
    ...content,
  };
}

// Elements in document order, matching the labels Elm gave each handler.
// Nothing inside raw HTML is Jorn's, so neither list goes into it.
function elementsOf(node, out = []) {
  if (typeof node.text === "string") return out;
  out.push(node);
  for (const child of node.children ?? []) elementsOf(child, out);
  return out;
}

function domElementsOf(dom, node, out = []) {
  if (typeof node.text === "string") return out;
  out.push(dom);
  if (typeof node.html === "string") return out;
  node.children.forEach((child, i) => domElementsOf(dom.childNodes[i], child, out));
  return out;
}

// Nodes matched by the diff, by key or by position, must be the same DOM
// nodes afterwards: moved, never recreated.
let kept = 0;
function checkKept(jorn, pairs, before, step, caseId) {
  for (const [i, [from, to]] of pairs.entries()) {
    kept++;
    if (jorn.nodeAt(to) !== before[i]) fail(`${step} recreated a node it should have kept`, { caseId, from, to });
  }
}

const t0 = performance.now();
const cases = await ask("generate", { seed: SEED, count: CASES });
let patches = 0;
let events = 0;

for (let caseId = 0; caseId < cases.length; caseId++) {
  const c = cases[caseId];
  try {
    const { container, sent, jorn } = setup();
    jorn.mount(c.a);
    const keptAB = c.keepAB.map(([from]) => jorn.nodeAt(from));
    jorn.patch(c.ab);
    patches += c.ab.length;
    checkKept(jorn, c.keepAB, keptAB, "A->B", caseId);
    const wantB = JSON.stringify(expected(c.b));
    const afterB = JSON.stringify(actual(container.firstChild, expected(c.b)));
    if (afterB !== wantB) fail("A->B differs from B", { caseId, got: afterB, want: wantB, patches: c.ab });

    const keptBC = c.keepBC.map(([from]) => jorn.nodeAt(from));
    jorn.patch(c.bc);
    patches += c.bc.length;
    checkKept(jorn, c.keepBC, keptBC, "B->C", caseId);
    const wantC = JSON.stringify(expected(c.c));
    const afterC = JSON.stringify(actual(container.firstChild, expected(c.c)));
    if (afterC !== wantC) fail("B->C differs from C", { caseId, got: afterC, want: wantC, patches: c.bc });
    if (container.childNodes.length !== 1) fail("container holds more than the root", { caseId });

    if (afterC !== wantC) continue; // already reported above
    const nodes = elementsOf(c.c);
    const doms = domElementsOf(container.firstChild, c.c);

    for (const [position, dom] of doms.entries()) {
      for (const name of ["click", "input", "mouseover"]) {
        sent.length = 0;
        const event = new window.Event(name, { bubbles: false, cancelable: true });
        dom.dispatchEvent(event);
        events++;
        const options = nodes[position].events[name];
        if (!options) {
          if (sent.length) fail("stale handler reported an event", { caseId, position, name });
          continue;
        }
        if (sent.length !== 1) {
          fail("handler did not report exactly once", { caseId, position, name, count: sent.length });
          continue;
        }
        if (event.defaultPrevented !== options.preventDefault) {
          fail("preventDefault does not match the handler's options", { caseId, position, name });
        }
        const result = await ask("route", { caseId, message: sent[0] });
        if (result !== `ok:${position}`) fail("event routed wrongly", { caseId, name, message: sent[0], result });
      }
    }
    container.remove();
  } catch (error) {
    fail("patcher threw", { caseId, error: String(error) });
  }
}

const seconds = ((performance.now() - t0) / 1000).toFixed(1);
console.log(`unit tests: ${unitFailures ? `${unitFailures} problems` : "passed"}`);
console.log(`${cases.length} random cases, ${patches} patches applied, ${kept} nodes checked for keeping, ${events} events fired, seed ${SEED}, ${seconds}s`);
if (failed) {
  console.log(`FAILED: ${failed} problems`);
  for (const f of failures) console.log(JSON.stringify(f, null, 2).slice(0, 3000));
  process.exit(1);
}
console.log("PASSED: the patcher turns every A into C exactly, and every event routes home.");
