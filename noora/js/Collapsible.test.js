// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import Collapsible from "./Collapsible.js";

const mounted = [];

// Mirrors what `Noora.Sidebar.sidebar_group/1` and `sidebar_item/1` render:
// Phoenix renders `data-selected={true}` as a bare attribute and omits it when
// false.
function sidebarGroup({
  headerSelected = false,
  itemSelected = false,
  content = "",
} = {}) {
  return `
    <div data-part="root">
      <div class="noora-tab-menu-vertical" data-part="header" ${headerSelected ? "data-selected" : ""}>
        <a data-part="link" href="/tests">Tests</a>
        <button type="button" data-part="trigger"></button>
      </div>
      <div data-part="content">
        <a data-part="item" href="/tests/test-runs">
          <div class="noora-tab-menu-vertical" ${itemSelected ? "data-selected" : ""}>Test Runs</div>
        </a>
        ${content}
      </div>
    </div>`;
}

// The current page of a `Noora.PaginationGroup`, which pages inside
// collapsibles such as the bundle page's duplicate files.
const pagination = `
  <div class="noora-pagination-group">
    <a data-part="page-button" href="?page=1" data-selected>1</a>
    <a data-part="page-button" href="?page=2">2</a>
  </div>`;

function mount({ html, open = false, persistKey = "sidebar-tests" }) {
  const el = document.createElement("div");
  el.id = "collapsible";
  if (persistKey) el.dataset.persistKey = persistKey;
  el.dataset.open = String(open);
  el.innerHTML = html;
  document.body.appendChild(el);
  const pushed = [];
  const hook = Object.assign(
    { el, pushEvent: (...args) => pushed.push(args) },
    Collapsible,
  );
  hook.mounted();
  mounted.push(hook);
  return { hook, pushed };
}

const stored = () => sessionStorage.getItem("noora-collapsible:sidebar-tests");
const nextFrames = () =>
  new Promise((resolve) =>
    requestAnimationFrame(() => requestAnimationFrame(resolve)),
  );

describe("Collapsible", () => {
  beforeEach(() => sessionStorage.clear());

  afterEach(() => {
    mounted.splice(0).forEach((hook) => hook.beforeDestroy());
    document.body.innerHTML = "";
  });

  it("seeds storage with the server's state when nothing is remembered", () => {
    const { hook } = mount({ html: sidebarGroup(), open: true });

    expect(hook.collapsible.api.open).toBe(true);
    expect(stored()).toBe("true");
  });

  it("keeps a group remembered as closed closed when the page is outside it", () => {
    sessionStorage.setItem("noora-collapsible:sidebar-tests", "false");

    const { hook } = mount({ html: sidebarGroup(), open: true });

    expect(hook.collapsible.api.open).toBe(false);
    expect(stored()).toBe("false");
  });

  it("opens a group remembered as closed when the current page is one of its items", () => {
    sessionStorage.setItem("noora-collapsible:sidebar-tests", "false");

    const { hook } = mount({
      html: sidebarGroup({ itemSelected: true }),
      open: true,
    });

    expect(hook.collapsible.api.open).toBe(true);
    expect(stored()).toBe("true");
  });

  it("opens a group remembered as closed when the current page is its label", () => {
    sessionStorage.setItem("noora-collapsible:sidebar-tests", "false");

    const { hook } = mount({
      html: sidebarGroup({ headerSelected: true }),
      open: true,
    });

    expect(hook.collapsible.api.open).toBe(true);
    expect(stored()).toBe("true");
  });

  it("still animates open after a label click lands on the group's page", async () => {
    sessionStorage.setItem("noora-collapsible:sidebar-tests", "true");
    sessionStorage.setItem("noora-collapsible-anim:sidebar-tests", "1");

    const { hook } = mount({
      html: sidebarGroup({ headerSelected: true }),
      open: true,
    });

    expect(hook.collapsible.api.open).toBe(false);
    await nextFrames();
    expect(hook.collapsible.api.open).toBe(true);
    expect(
      sessionStorage.getItem("noora-collapsible-anim:sidebar-tests"),
    ).toBeNull();
  });

  it("ignores selected controls in a sidebar group's content that are not its items", () => {
    sessionStorage.setItem("noora-collapsible:sidebar-tests", "false");

    const { hook } = mount({
      html: sidebarGroup({ content: pagination }),
      open: true,
    });

    expect(hook.collapsible.api.open).toBe(false);
  });

  it("keeps a closed collapsible without persistence closed when it holds the current page of a pagination", () => {
    const { hook, pushed } = mount({
      persistKey: null,
      html: `
        <div data-part="root">
          <div data-part="trigger">Remove duplicate files</div>
          <div data-part="content">${pagination}</div>
        </div>`,
    });

    expect(hook.collapsible.api.open).toBe(false);
    expect(pushed).toEqual([]);
  });
});
