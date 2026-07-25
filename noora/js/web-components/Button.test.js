// @vitest-environment happy-dom

import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { registerNooraButton } from "./Button.js";

beforeAll(() => {
  registerNooraButton();
});

afterEach(() => {
  document.body.replaceChildren();
});

describe("NooraButton", () => {
  it("renders the shared defaults and label", async () => {
    const button = document.createElement("noora-button");
    button.label = "Create project";
    document.body.append(button);
    await button.updateComplete;

    const control = button.shadowRoot.querySelector("button");

    expect(control.dataset.variant).toBe("primary");
    expect(control.dataset.size).toBe("large");
    expect(control.textContent.trim()).toBe("Create project");
  });

  it("projects icons and a text label into the native control", async () => {
    const button = document.createElement("noora-button");
    const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    icon.slot = "icon-left";
    button.append(icon, "Previous");
    document.body.append(button);
    await button.updateComplete;

    const control = button.shadowRoot.querySelector("button");
    const iconSlot = control.querySelector('slot[name="icon-left"]');
    const labelSlot = control.querySelector("span slot");

    expect(iconSlot.assignedElements()).toEqual([icon]);
    expect(
      labelSlot
        .assignedNodes()
        .map((node) => node.textContent)
        .join(""),
    ).toBe("Previous");
  });

  it("updates variants, sizes, and disabled state", async () => {
    const button = document.createElement("noora-button");
    document.body.append(button);
    await button.updateComplete;

    button.variant = "destructive";
    button.size = "small";
    button.disabled = true;
    await button.updateComplete;

    const control = button.shadowRoot.querySelector("button");

    expect(control.dataset.variant).toBe("destructive");
    expect(control.dataset.size).toBe("small");
    expect(control.disabled).toBe(true);
  });

  it("falls back to the shared contract for unsupported presentation values", async () => {
    const button = document.createElement("noora-button");
    button.setAttribute("variant", "unsupported");
    button.setAttribute("size", "unsupported");
    document.body.append(button);
    await button.updateComplete;

    const control = button.shadowRoot.querySelector("button");

    expect(control.dataset.variant).toBe("primary");
    expect(control.dataset.size).toBe("large");
  });

  it("renders links unless the component is disabled", async () => {
    const button = document.createElement("noora-button");
    button.href = "/projects";
    document.body.append(button);
    await button.updateComplete;

    expect(button.shadowRoot.querySelector("a").getAttribute("href")).toBe(
      "/projects",
    );

    button.disabled = true;
    await button.updateComplete;

    expect(button.shadowRoot.querySelector("a")).toBeNull();
    expect(button.shadowRoot.querySelector("button").disabled).toBe(true);
  });

  it("forwards programmatic clicks through the native control", async () => {
    const button = document.createElement("noora-button");
    const listener = vi.fn();
    button.addEventListener("click", listener);
    document.body.append(button);
    await button.updateComplete;

    button.click();

    expect(listener).toHaveBeenCalledOnce();
    expect(listener.mock.calls[0][0].composed).toBe(true);
  });

  it("submits a parent form with its name and value", async () => {
    const form = document.createElement("form");
    const button = document.createElement("noora-button");
    const listener = vi.fn((event) => event.preventDefault());
    button.name = "intent";
    button.value = "create";
    form.addEventListener("submit", listener);
    form.append(button);
    document.body.append(form);
    await button.updateComplete;

    button.click();
    await Promise.resolve();

    expect(listener).toHaveBeenCalledOnce();
    expect(listener.mock.calls[0][0].submitter.name).toBe("intent");
    expect(listener.mock.calls[0][0].submitter.value).toBe("create");
  });

  it("does not submit when the click is prevented", async () => {
    const form = document.createElement("form");
    const button = document.createElement("noora-button");
    const listener = vi.fn();
    button.addEventListener("click", (event) => event.preventDefault());
    form.addEventListener("submit", listener);
    form.append(button);
    document.body.append(form);
    await button.updateComplete;

    button.click();
    await Promise.resolve();

    expect(listener).not.toHaveBeenCalled();
  });
});
