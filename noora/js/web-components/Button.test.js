// @vitest-environment happy-dom

import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { registerNooraButton } from "./Button.js";

beforeAll(() => {
  for (const property of [
    "ariaDescribedByElements",
    "ariaLabelledByElements",
  ]) {
    if (!(property in HTMLElement.prototype)) {
      Object.defineProperty(HTMLElement.prototype, property, {
        configurable: true,
        writable: true,
      });
    }
  }

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

  it("associates external accessible labels and descriptions with the native control", async () => {
    const label = document.createElement("span");
    const description = document.createElement("span");
    const button = document.createElement("noora-button");
    label.id = "button-label";
    description.id = "button-description";
    button.setAttribute("aria-labelledby", label.id);
    button.setAttribute("aria-describedby", description.id);
    document.body.append(label, description, button);
    await button.updateComplete;

    const control = button.shadowRoot.querySelector("button");

    expect(control.ariaLabelledByElements).toEqual([label]);
    expect(control.ariaDescribedByElements).toEqual([description]);
  });

  it("submits a parent form with its name and value", async () => {
    const form = document.createElement("form");
    const button = document.createElement("noora-button");
    const listener = vi.fn((event) => event.preventDefault());
    button.name = "intent";
    button.value = "create";
    const requestSubmit = vi.spyOn(form, "requestSubmit");
    form.addEventListener("submit", listener);
    form.append(button);
    document.body.append(form);
    await button.updateComplete;

    expect(button.type).toBe("submit");
    expect(button.nextElementSibling.form).toBe(form);

    button.click();
    await Promise.resolve();

    expect(requestSubmit).toHaveBeenCalledOnce();
    expect(listener).toHaveBeenCalledOnce();
    expect(listener.mock.calls[0][0].submitter.name).toBe("intent");
    expect(listener.mock.calls[0][0].submitter.value).toBe("create");
  });

  it("provides a native default submitter for implicit form submission", async () => {
    const form = document.createElement("form");
    const input = document.createElement("input");
    const button = document.createElement("noora-button");
    const listener = vi.fn((event) => event.preventDefault());
    button.name = "intent";
    button.value = "create";
    button.formAction = "/projects";
    button.formEnctype = "multipart/form-data";
    button.formMethod = "post";
    button.formNoValidate = true;
    button.formTarget = "_blank";
    form.addEventListener("submit", listener);
    form.append(input, button);
    document.body.append(form);
    await button.updateComplete;

    const submitter = button.nextElementSibling;

    expect(submitter).toBeInstanceOf(HTMLButtonElement);
    expect(submitter.hidden).toBe(true);
    expect(submitter.form).toBe(form);
    expect(submitter.name).toBe("intent");
    expect(submitter.value).toBe("create");
    expect(submitter.getAttribute("formaction")).toBe("/projects");
    expect(submitter.getAttribute("formenctype")).toBe("multipart/form-data");
    expect(submitter.getAttribute("formmethod")).toBe("post");
    expect(submitter.formNoValidate).toBe(true);
    expect(submitter.getAttribute("formtarget")).toBe("_blank");

    submitter.click();

    expect(listener).toHaveBeenCalledOnce();
    expect(listener.mock.calls[0][0].submitter).toBe(submitter);
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
