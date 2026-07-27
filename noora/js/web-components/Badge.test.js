// @vitest-environment happy-dom

import { afterEach, beforeAll, describe, expect, it } from "vitest";
import { registerNooraBadge } from "./Badge.js";

beforeAll(() => {
  registerNooraBadge();
});

afterEach(() => {
  document.body.replaceChildren();
});

describe("NooraBadge", () => {
  it("renders the shared defaults and label", async () => {
    const badge = document.createElement("noora-badge");
    badge.label = "Available";
    document.body.append(badge);
    await badge.updateComplete;

    const container = badge.shadowRoot.querySelector('[part="badge"]');

    expect(container.dataset.style).toBe("fill");
    expect(container.dataset.color).toBe("neutral");
    expect(container.dataset.size).toBe("small");
    expect(container.textContent.trim()).toBe("Available");
  });

  it("updates its appearance, color, size, and disabled state", async () => {
    const badge = document.createElement("noora-badge");
    document.body.append(badge);
    await badge.updateComplete;

    badge.appearance = "light-fill";
    badge.color = "success";
    badge.size = "large";
    badge.disabled = true;
    await badge.updateComplete;

    const container = badge.shadowRoot.querySelector('[part="badge"]');

    expect(container.dataset.style).toBe("light-fill");
    expect(container.dataset.color).toBe("success");
    expect(container.dataset.size).toBe("large");
    expect(container.hasAttribute("data-disabled")).toBe(true);
  });

  it("falls back to contract defaults for unsupported values", async () => {
    const badge = document.createElement("noora-badge");
    badge.appearance = "unsupported";
    badge.color = "unsupported";
    badge.size = "unsupported";
    document.body.append(badge);
    await badge.updateComplete;

    const container = badge.shadowRoot.querySelector('[part="badge"]');

    expect(container.dataset.style).toBe("fill");
    expect(container.dataset.color).toBe("neutral");
    expect(container.dataset.size).toBe("small");
  });

  it("renders a generated dot when the icon slot is empty", async () => {
    const badge = document.createElement("noora-badge");
    badge.dot = true;
    document.body.append(badge);
    await badge.updateComplete;

    const container = badge.shadowRoot.querySelector('[part="badge"]');
    const icon = badge.shadowRoot.querySelector('[part="icon"]');

    expect(container.hasAttribute("data-dot")).toBe(true);
    expect(icon.querySelector("svg")).not.toBeNull();
  });

  it("gives a slotted icon precedence over the generated dot", async () => {
    const badge = document.createElement("noora-badge");
    const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    icon.slot = "icon";
    badge.dot = true;
    badge.append(icon, "Warning");
    document.body.append(badge);
    await badge.updateComplete;
    await badge.updateComplete;

    const container = badge.shadowRoot.querySelector('[part="badge"]');
    const iconSlot = badge.shadowRoot.querySelector('slot[name="icon"]');

    expect(iconSlot.assignedElements()).toEqual([icon]);
    expect(container.hasAttribute("data-icon")).toBe(true);
    expect(container.hasAttribute("data-dot")).toBe(false);
    expect(badge.shadowRoot.querySelector('[part="icon"] > svg')).toBeNull();
  });
});
