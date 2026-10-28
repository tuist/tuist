import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("./code-group.js", import.meta.url), "utf8")
  .replace(/^import .*$/gm, "")
  .replace("export { CodeGroup, setupCodeGroups };", "globalThis.setupCodeGroups = setupCodeGroups;");

class Element {
  constructor(attributes = {}, text = "") {
    this.attributes = { ...attributes };
    this.textContent = text;
    this.listeners = {};
    this.dataset = {};
    this.style = {};
    this.offsetLeft = this.offsetTop = this.offsetWidth = this.offsetHeight = 0;
  }
  getAttribute(name) {
    return name in this.attributes ? this.attributes[name] : null;
  }
  setAttribute(name, value) {
    this.attributes[name] = String(value);
  }
  removeAttribute(name) {
    delete this.attributes[name];
  }
  addEventListener(type, listener) {
    (this.listeners[type] ||= []).push(listener);
  }
  click() {
    (this.listeners.click || []).forEach((listener) => listener());
  }
  prepend() {}
  querySelector() {
    return null;
  }
}

function group(labels) {
  const tabs = labels.map(
    (label, index) =>
      new Element(
        { "data-part": "tab", "data-index": `${index}`, ...(index === 0 && { "data-selected": "true" }) },
        label,
      ),
  );
  const panels = labels.map(
    (_, index) =>
      new Element({ "data-part": "panel", "data-index": `${index}`, ...(index > 0 && { "data-hidden": "true" }) }),
  );
  const tabsContainer = new Element({ "data-part": "tabs" });
  const element = new Element({ class: "code-group" });
  element.querySelectorAll = (selector) => (selector === '[data-part="tab"]' ? tabs : panels);
  element.querySelector = (selector) => (selector === '[data-part="tabs"]' ? tabsContainer : null);
  element.selected = () => tabs.find((tab) => tab.getAttribute("data-selected") === "true").textContent;
  element.visible = () =>
    panels
      .filter((panel) => panel.getAttribute("data-hidden") !== "true")
      .map((panel) => panel.getAttribute("data-index"));
  element.tab = (label) => tabs.find((tab) => tab.textContent === label);
  return element;
}

function page(groups, stored = {}, { blocked = false } = {}) {
  const storage = {
    values: { ...stored },
    getItem(key) {
      if (blocked) throw new Error("blocked");
      return key in this.values ? this.values[key] : null;
    },
    setItem(key, value) {
      if (blocked) throw new Error("blocked");
      this.values[key] = value;
    },
  };
  const document = {
    querySelectorAll: (selector) => (selector === ".code-group" ? groups : []),
    createElement: () => new Element(),
  };
  const context = {
    window: { localStorage: storage },
    document,
    ResizeObserver: class {
      observe() {}
    },
    requestAnimationFrame: () => {},
    console,
  };
  runInNewContext(source, context);
  const setup = () => context.setupCodeGroups({ querySelectorAll: () => groups });
  setup();
  storage.setup = setup;
  return storage;
}

const providers = ["GitHub Actions", "Buildkite", "GitLab CI"];

test("selecting a tab selects the same label in every group on the page", () => {
  const first = group(providers);
  const second = group(providers);
  const other = group(["Mise", "Homebrew"]);
  page([first, second, other]);

  first.tab("Buildkite").click();

  assert.equal(first.selected(), "Buildkite");
  assert.equal(second.selected(), "Buildkite");
  assert.deepEqual(second.visible(), ["1"]);
  assert.equal(other.selected(), "Mise");
});

test("the selected label carries over to later pages", () => {
  const first = group(providers);
  const storage = page([first]);
  first.tab("GitLab CI").click();

  const later = group(providers);
  const unrelated = group(["Mise", "Homebrew"]);
  page([later, unrelated], storage.values);

  assert.equal(later.selected(), "GitLab CI");
  assert.deepEqual(later.visible(), ["2"]);
  assert.equal(unrelated.selected(), "Mise");
});

test("groups still switch together when storage is blocked", () => {
  const first = group(providers);
  const second = group(providers);
  page([first, second], {}, { blocked: true });

  first.tab("Buildkite").click();

  assert.equal(second.selected(), "Buildkite");
});

test("a LiveView patch that restores the rendered selection is undone on the next pass", () => {
  const first = group(providers);
  const storage = page([first]);
  first.tab("GitLab CI").click();

  first.tab("GitLab CI").removeAttribute("data-selected");
  first.tab("GitHub Actions").setAttribute("data-selected", "true");
  storage.setup();

  assert.equal(first.selected(), "GitLab CI");
});
