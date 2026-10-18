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

unit("detached elements stay quiet", () => {
  const { container, sent, jorn } = setup();
  jorn.mount(el("div", {}, [el("button", { events: { click: opts() } })]));
  const button = container.firstChild.firstChild;
  jorn.patch([{ op: "truncate", path: [], length: 0 }]);
  button.dispatchEvent(new window.Event("click"));
  check(sent.length === 0, "no report from a removed element");
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

// What the DOM should look like, worked out from the node alone.
function expected(node) {
  if (typeof node.text === "string") return { text: node.text };
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
    children: node.children.map(expected),
  };
}

function actual(dom) {
  if (dom.nodeType === 3) return { text: dom.data };
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
    children: [...dom.childNodes].map(actual),
  };
}

// Elements in document order, matching the labels Elm gave each handler.
function elementsOf(node, out = []) {
  if (typeof node.text === "string") return out;
  out.push(node);
  for (const child of node.children) elementsOf(child, out);
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
    const afterB = JSON.stringify(actual(container.firstChild));
    const wantB = JSON.stringify(expected(c.b));
    if (afterB !== wantB) fail("A->B differs from B", { caseId, got: afterB, want: wantB, patches: c.ab });

    const keptBC = c.keepBC.map(([from]) => jorn.nodeAt(from));
    jorn.patch(c.bc);
    patches += c.bc.length;
    checkKept(jorn, c.keepBC, keptBC, "B->C", caseId);
    const afterC = JSON.stringify(actual(container.firstChild));
    const wantC = JSON.stringify(expected(c.c));
    if (afterC !== wantC) fail("B->C differs from C", { caseId, got: afterC, want: wantC, patches: c.bc });
    if (container.childNodes.length !== 1) fail("container holds more than the root", { caseId });

    const doms = [...container.querySelectorAll("*")];
    const nodes = elementsOf(c.c);
    if (doms.length !== nodes.length) continue; // already reported above

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
