// @vitest-environment happy-dom

import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import publishedContracts from "./contracts.json";
import { registerRemainingNooraComponents } from "./Remaining.js";

const remainingContracts = publishedContracts.filter(
  (contract) =>
    contract.tagName !== "noora-badge" && contract.tagName !== "noora-button",
);

beforeAll(() => {
  registerRemainingNooraComponents();
});

afterEach(() => {
  document.body.replaceChildren();
});

describe("remaining Noora web components", () => {
  it("registers every published contract", () => {
    for (const contract of remainingContracts) {
      expect(customElements.get(contract.tagName)).toBeDefined();
    }
  });

  it("passes chart dimensions from the host to the drawing surface", () => {
    const chart = customElements.get("noora-chart");
    const styles = chart.elementStyles.map((style) => style.cssText).join("\n");

    expect(styles).toContain("height: var(--noora-chart-height, 180px)");
    expect(styles).toContain('[part="container"]');
    expect(styles).toContain("height: 100%");
  });

  it("upgrades and renders every non-canvas component", async () => {
    for (const contract of remainingContracts) {
      if (contract.tagName === "noora-chart") continue;

      const element = document.createElement(contract.tagName);
      document.body.append(element);
      await element.updateComplete;

      expect(element.shadowRoot, contract.tagName).not.toBeNull();
      element.remove();
    }
  });

  it("renders and dismisses a semantic alert", async () => {
    const alert = document.createElement("noora-alert");
    const listener = vi.fn();
    alert.status = "success";
    alert.title = "Project created";
    alert.dismissible = true;
    alert.addEventListener("noora-dismiss", listener);
    document.body.append(alert);
    await alert.updateComplete;

    const container = alert.shadowRoot.querySelector('[part="alert"]');

    expect(container.dataset.status).toBe("success");
    expect(container.getAttribute("role")).toBe("status");
    expect(container.textContent).toContain("Project created");

    container.querySelector('[data-part="dismiss-icon"]').click();

    expect(alert.hidden).toBe(true);
    expect(listener).toHaveBeenCalledOnce();
  });

  it("falls back to initials when an avatar image fails", async () => {
    const avatar = document.createElement("noora-avatar");
    avatar.name = "Ada Lovelace";
    avatar.imageHref = "/missing.png";
    document.body.append(avatar);
    await avatar.updateComplete;

    avatar.shadowRoot.querySelector("img").dispatchEvent(new Event("error"));
    await avatar.updateComplete;

    expect(
      avatar.shadowRoot.querySelector('[part="initials"]').textContent,
    ).toBe("AL");
  });

  it("renders full-width primary banners without an empty icon", async () => {
    const banner = document.createElement("noora-banner");
    banner.status = "primary";
    banner.title = "Title only banner";
    document.body.append(banner);
    await banner.updateComplete;

    expect(
      banner.shadowRoot.querySelector('[data-part="background"]'),
    ).not.toBeNull();
    expect(banner.shadowRoot.querySelector('[data-part="icon"]')).toBeNull();
    expect(
      banner.constructor.elementStyles.some((style) =>
        style.cssText.includes("flex: 1 0 100%"),
      ),
    ).toBe(true);
  });

  it("keeps line dividers at the full width of their parent", async () => {
    const lineDivider = document.createElement("noora-line-divider");
    lineDivider.text = "OR";
    document.body.append(lineDivider);
    await lineDivider.updateComplete;

    const styles = lineDivider.constructor.elementStyles
      .map((style) => style.cssText)
      .join("\n");

    expect(styles).toContain("width: 100%");
    expect(
      lineDivider.shadowRoot.querySelector('[part="divider"]').textContent,
    ).toContain("OR");
  });

  it("matches LiveView progress values while clamping only the filled track", async () => {
    const progressBar = document.createElement("noora-progress-bar");
    progressBar.title = "Exceeded goal:";
    progressBar.value = 120;
    progressBar.max = 100;
    document.body.append(progressBar);
    await progressBar.updateComplete;

    expect(
      progressBar.shadowRoot.querySelector('[data-part="value"]').textContent,
    ).toBe("120");
    expect(
      progressBar.shadowRoot.querySelector('[data-part="max-value"]')
        .textContent,
    ).toBe("100");
    expect(
      progressBar.shadowRoot.querySelector('[data-part="value-bar"]').style
        .width,
    ).toBe("100%");
  });

  it("renders button group items with LiveView-equivalent structure", async () => {
    const buttonGroup = document.createElement("noora-button-group");
    const listener = vi.fn();
    buttonGroup.items = [
      { label: "Previous", iconLeft: "chevron_left", value: "previous" },
      { label: "Disabled", disabled: true },
      {
        icon: "chevron_right",
        iconOnly: true,
        ariaLabel: "Next",
        value: "next",
      },
    ];
    buttonGroup.addEventListener("noora-select", listener);
    document.body.append(buttonGroup);
    await buttonGroup.updateComplete;

    const items = buttonGroup.shadowRoot.querySelectorAll('[part="item"]');
    expect(items).toHaveLength(3);
    expect(items[0].classList).toContain("noora-button-group-item");
    expect(items[0].querySelector("svg")).not.toBeNull();
    expect(items[1].disabled).toBe(true);
    expect(items[2].hasAttribute("data-icon-only")).toBe(true);
    expect(items[2].getAttribute("aria-label")).toBe("Next");

    items[2].click();

    expect(listener).toHaveBeenCalledOnce();
    expect(listener.mock.calls[0][0].detail.value).toBe("next");
  });

  it("renders declarative button group items inside the styled surface", async () => {
    const buttonGroup = document.createElement("noora-button-group");
    const internalEventListener = vi.fn();
    buttonGroup.size = "small";
    buttonGroup.innerHTML = `
      <noora-button-group-item value="first">First</noora-button-group-item>
      <noora-button-group-item value="second" selected>Second</noora-button-group-item>
      <noora-button-group-item icon="chevron_right" icon-only aria-label="Next"></noora-button-group-item>
    `;
    document.body.addEventListener(
      "noora-configuration-change",
      internalEventListener,
    );
    document.body.append(buttonGroup);
    await Promise.all(
      [...buttonGroup.children].map((child) => child.updateComplete),
    );
    await buttonGroup.updateComplete;

    const group = buttonGroup.shadowRoot.querySelector('[part="group"]');
    const items = buttonGroup.shadowRoot.querySelectorAll('[part="item"]');

    expect(group.dataset.size).toBe("small");
    expect(items).toHaveLength(3);
    expect(items[0].textContent).toContain("First");
    expect(items[1].hasAttribute("data-selected")).toBe(true);
    expect(items[2].hasAttribute("data-icon-only")).toBe(true);
    expect(internalEventListener).not.toHaveBeenCalled();

    const styles = buttonGroup.constructor.elementStyles
      .map((style) => style.cssText)
      .join("\n");
    expect(styles).toContain('[data-size="small"] .noora-button-group-item');
    expect(styles).toContain('[data-size="medium"] .noora-button-group-item');
    expect(styles).toContain('[data-size="large"] .noora-button-group-item');
  });

  it("renders card content as one body or multiple independent sections", async () => {
    const simpleCard = document.createElement("noora-card");
    const paragraph = document.createElement("p");
    paragraph.textContent = "Overview";
    simpleCard.append(paragraph);
    document.body.append(simpleCard);
    await simpleCard.updateComplete;

    expect(simpleCard.shadowRoot.querySelector('[part="body"]')).not.toBeNull();

    const sectionedCard = document.createElement("noora-card");
    for (const title of ["Source Files", "Test Files", "Documentation"]) {
      const section = document.createElement("section");
      section.slot = "section";
      section.textContent = title;
      sectionedCard.append(section);
    }
    document.body.append(sectionedCard);
    await sectionedCard.updateComplete;

    expect(sectionedCard.shadowRoot.querySelector('[part="body"]')).toBeNull();
    expect(
      sectionedCard.shadowRoot
        .querySelector('slot[name="section"]')
        .assignedElements(),
    ).toHaveLength(3);
  });

  it("keeps a checkbox property and native control in sync", async () => {
    const checkbox = document.createElement("noora-checkbox");
    const input = vi.fn();
    const change = vi.fn();
    checkbox.label = "Analytics";
    checkbox.addEventListener("input", input);
    checkbox.addEventListener("change", change);
    document.body.append(checkbox);
    await checkbox.updateComplete;

    const control = checkbox.control;
    control.click();
    await checkbox.updateComplete;

    expect(checkbox.checked).toBe(true);
    expect(control.checked).toBe(true);
    expect(input).toHaveBeenCalledOnce();
    expect(change).toHaveBeenCalledOnce();
  });

  it("propagates disabled fieldset state to every form control", async () => {
    const controls = [
      ["noora-checkbox", "input"],
      ["noora-toggle", "input"],
      ["noora-text-input", "input"],
      ["noora-text-area", "textarea"],
      ["noora-digit-input", '[data-part="input"]'],
      ["noora-select", '[data-part="trigger"]'],
      ["noora-date-picker", '[data-part="trigger"]'],
    ];

    for (const [tagName, selector] of controls) {
      const element = document.createElement(tagName);
      document.body.append(element);
      await element.updateComplete;

      element.formDisabledCallback(true);
      await element.updateComplete;

      expect(element.shadowRoot.querySelector(selector).disabled, tagName).toBe(
        true,
      );

      element.remove();
    }
  });

  it("updates a text input from its native control", async () => {
    const textInput = document.createElement("noora-text-input");
    const input = vi.fn();
    const change = vi.fn();
    textInput.type = "email";
    textInput.label = "Email";
    textInput.hint = "Use a work address.";
    textInput.addEventListener("input", input);
    textInput.addEventListener("change", change);
    document.body.append(textInput);
    await textInput.updateComplete;

    textInput.control.value = "hello@tuist.dev";
    textInput.control.dispatchEvent(new InputEvent("input", { bubbles: true }));
    textInput.control.dispatchEvent(new Event("change", { bubbles: true }));
    await textInput.updateComplete;

    expect(textInput.value).toBe("hello@tuist.dev");
    expect(textInput.control.type).toBe("email");
    expect(textInput.shadowRoot.querySelector("label").htmlFor).toBe(
      textInput.control.id,
    );
    expect(textInput.control.getAttribute("aria-describedby")).toBe(
      textInput.shadowRoot.querySelector(".noora-hint-text").id,
    );
    expect(input).toHaveBeenCalledOnce();
    expect(change).toHaveBeenCalledOnce();
  });

  it("restores a text input's initial value on form reset", async () => {
    const textInput = document.createElement("noora-text-input");
    textInput.setAttribute("value", "hello@tuist.dev");
    document.body.append(textInput);
    await textInput.updateComplete;

    textInput.value = "changed@tuist.dev";
    await textInput.updateComplete;
    textInput.formResetCallback();
    await textInput.updateComplete;

    expect(textInput.value).toBe("hello@tuist.dev");
    expect(textInput.control.value).toBe("hello@tuist.dev");
  });

  it("associates text area labels with their native controls", async () => {
    const textArea = document.createElement("noora-text-area");
    textArea.label = "Description";
    textArea.error = "Description is required.";
    document.body.append(textArea);
    await textArea.updateComplete;

    expect(textArea.shadowRoot.querySelector("label").htmlFor).toBe(
      textArea.control.id,
    );
    expect(textArea.control.getAttribute("aria-invalid")).toBe("true");
    expect(textArea.control.getAttribute("aria-describedby")).toBe(
      textArea.shadowRoot.querySelector(".noora-hint-text").id,
    );
  });

  it("matches LiveView text input spacing without empty adornments", async () => {
    const textInput = document.createElement("noora-text-input");
    textInput.placeholder = "Username";
    document.body.append(textInput);
    await textInput.updateComplete;

    const styles = textInput.constructor.elementStyles
      .map((style) => style.cssText)
      .join("\n");

    expect(
      textInput.shadowRoot.querySelector('[data-part="prefix"]'),
    ).toBeNull();
    expect(
      textInput.shadowRoot.querySelector('[data-part="suffix"]'),
    ).toBeNull();
    expect(styles).toContain("padding: 0");
    expect(styles).toContain("margin: 0");
    expect(styles).toContain("min-width: 0");

    textInput.type = "password";
    await textInput.updateComplete;

    expect(
      textInput.shadowRoot.querySelector('[data-part="prefix"]'),
    ).not.toBeNull();
    expect(
      textInput.shadowRoot.querySelector('[data-part="suffix"]'),
    ).not.toBeNull();
  });

  it("only reflects active digit input states", async () => {
    const digitInput = document.createElement("noora-digit-input");
    document.body.append(digitInput);
    await digitInput.updateComplete;

    expect(
      digitInput.shadowRoot
        .querySelector('[data-part="input"]')
        .hasAttribute("data-error"),
    ).toBe(false);

    digitInput.error = true;
    digitInput.disabled = true;
    await digitInput.updateComplete;

    const inputs = digitInput.shadowRoot.querySelectorAll(
      '[data-part="input"]',
    );
    expect(inputs).toHaveLength(6);
    for (const input of inputs) {
      expect(input.hasAttribute("data-error")).toBe(true);
      expect(input.hasAttribute("data-disabled")).toBe(true);
      expect(input.disabled).toBe(true);
    }
  });

  it("emits standard and component-specific digit input events", async () => {
    const digitInput = document.createElement("noora-digit-input");
    const input = vi.fn();
    const change = vi.fn();
    const complete = vi.fn();
    digitInput.characters = 2;
    digitInput.addEventListener("input", input);
    digitInput.addEventListener("change", change);
    digitInput.addEventListener("noora-complete", complete);
    document.body.append(digitInput);
    await digitInput.updateComplete;

    const controls = digitInput.shadowRoot.querySelectorAll('[part="input"]');
    controls[0].value = "1";
    controls[0].dispatchEvent(new InputEvent("input", { bubbles: true }));
    controls[1].value = "2";
    controls[1].dispatchEvent(new InputEvent("input", { bubbles: true }));
    await digitInput.updateComplete;

    expect(digitInput.value).toBe("12");
    expect(input).toHaveBeenCalledTimes(2);
    expect(change).toHaveBeenCalledOnce();
    expect(complete.mock.calls[0][0].detail.value).toBe("12");
  });

  it("emits dropdown selections and closes the menu", async () => {
    const dropdown = document.createElement("noora-dropdown");
    const listener = vi.fn();
    dropdown.items = [{ label: "Edit", value: "edit" }];
    dropdown.open = true;
    dropdown.addEventListener("noora-select", listener);
    document.body.append(dropdown);
    await dropdown.updateComplete;

    expect(
      dropdown.shadowRoot.querySelector('[part="content"]').dataset.state,
    ).toBe("open");
    expect(
      dropdown.shadowRoot.querySelector('[data-part="indicator"]').dataset
        .state,
    ).toBe("open");

    dropdown.shadowRoot.querySelector('[data-part="item"]').click();
    await dropdown.updateComplete;

    expect(listener).toHaveBeenCalledOnce();
    expect(listener.mock.calls[0][0].detail.value).toBe("edit");
    expect(dropdown.open).toBe(false);
  });

  it("renders and selects declarative dropdown items", async () => {
    const dropdown = document.createElement("noora-dropdown");
    const listener = vi.fn();
    dropdown.label = "Options";
    dropdown.open = true;
    dropdown.innerHTML = `
      <noora-dropdown-item value="edit" icon="edit">Edit</noora-dropdown-item>
      <noora-dropdown-item value="duplicate" right-icon="chevron_right">Duplicate</noora-dropdown-item>
    `;
    dropdown.addEventListener("noora-select", listener);
    document.body.append(dropdown);
    await Promise.all(
      [...dropdown.children].map((child) => child.updateComplete),
    );
    await dropdown.updateComplete;

    const items = dropdown.shadowRoot.querySelectorAll('[data-part="item"]');
    expect(items).toHaveLength(2);
    expect(dropdown.shadowRoot.querySelector('[data-part="items"]').role).toBe(
      "menu",
    );
    expect(items[0].role).toBe("menuitem");
    expect(
      dropdown.shadowRoot.querySelector(
        '[data-part="trigger"] [data-part="icon"]',
      ),
    ).toBeNull();
    expect(
      dropdown.shadowRoot.querySelector(
        '[data-part="content"] > [data-part="search"]',
      ),
    ).toBeNull();
    expect(items[0].textContent).toContain("Edit");
    expect(items[1].querySelector('[data-part="right-icon"]')).not.toBeNull();

    items[0].focus();
    items[0].dispatchEvent(
      new KeyboardEvent("keydown", {
        bubbles: true,
        composed: true,
        key: "ArrowDown",
      }),
    );
    expect(dropdown.shadowRoot.activeElement).toBe(items[1]);
    items[1].dispatchEvent(
      new KeyboardEvent("keydown", {
        bubbles: true,
        composed: true,
        key: "Home",
      }),
    );
    expect(dropdown.shadowRoot.activeElement).toBe(items[0]);
    items[0].dispatchEvent(
      new KeyboardEvent("keydown", {
        bubbles: true,
        composed: true,
        key: "Enter",
      }),
    );
    await dropdown.updateComplete;

    expect(listener.mock.calls[0][0].detail.value).toBe("edit");
    expect(dropdown.open).toBe(false);
  });

  it("only reserves dropdown regions when their slots have content", async () => {
    const dropdown = document.createElement("noora-dropdown");
    dropdown.label = "Dropdown";
    document.body.append(dropdown);
    await dropdown.updateComplete;

    expect(
      dropdown.shadowRoot.querySelector(
        '[data-part="trigger"] [data-part="icon"]',
      ),
    ).toBeNull();
    expect(
      dropdown.shadowRoot.querySelector(
        '[data-part="content"] > [data-part="search"]',
      ),
    ).toBeNull();

    const icon = document.createElement("noora-icon");
    icon.slot = "icon";
    icon.name = "category";
    const search = document.createElement("input");
    search.slot = "search";
    dropdown.append(icon, search);
    await new Promise((resolve) => setTimeout(resolve, 0));
    await dropdown.updateComplete;

    expect(
      dropdown.shadowRoot.querySelector(
        '[data-part="trigger"] [data-part="icon"]',
      ),
    ).not.toBeNull();
    expect(
      dropdown.shadowRoot.querySelector(
        '[data-part="content"] > [data-part="search"]',
      ),
    ).not.toBeNull();
  });

  it("matches breadcrumb triggers and selected menu items", async () => {
    const breadcrumbs = document.createElement("noora-breadcrumbs");
    const listener = vi.fn();
    breadcrumbs.items = [
      {
        label: "Company",
        showAvatar: true,
        avatarColor: "green",
      },
      {
        label: "Products",
        badgeLabel: "Xcode",
        badgeColor: "focus",
        items: [
          { label: "Electronics", value: "electronics" },
          {
            label: "Phones",
            value: "phones",
            selected: true,
            badgeLabel: "Xcode",
            badgeColor: "focus",
          },
        ],
      },
      { label: "iPhone 15" },
    ];
    breadcrumbs.addEventListener("noora-select", listener);
    document.body.append(breadcrumbs);
    await breadcrumbs.updateComplete;

    const avatar = breadcrumbs.shadowRoot.querySelector("noora-avatar");
    await avatar.updateComplete;
    expect(
      avatar.shadowRoot.querySelector('[part="avatar"]').dataset.color,
    ).toBe("green");
    expect(
      breadcrumbs.shadowRoot.querySelectorAll('[data-part="slash"]'),
    ).toHaveLength(2);
    expect(
      breadcrumbs.shadowRoot.querySelectorAll('[data-part="arrow"]'),
    ).toHaveLength(2);

    const trigger = breadcrumbs.shadowRoot.querySelector(
      '[data-part="trigger"]',
    );
    expect(trigger.parentElement.dataset.part).toBe("menu-anchor");
    const selector = trigger.querySelector("noora-icon");
    expect(selector.name).toBe("selector");
    expect(selector.activeName).toBe("selector_2");
    expect(selector.size).toBe(16);

    trigger.click();
    await breadcrumbs.updateComplete;
    expect(trigger.dataset.state).toBe("open");

    const selectedItem = breadcrumbs.shadowRoot.querySelector(
      '[data-part="item"][data-selected]',
    );
    expect(
      selectedItem
        .querySelector('[data-part="right-icon"] noora-badge')
        .getAttribute("label"),
    ).toBe("Xcode");
    expect(selectedItem.querySelector('[data-part="check"]')).not.toBeNull();
    expect(selectedItem.querySelector('[data-part="checkbox"]')).toBeNull();
    expect(
      breadcrumbs.shadowRoot.querySelector('[data-value="electronics"]')
        .tagName,
    ).toBe("SPAN");

    breadcrumbs.shadowRoot.querySelector('[data-value="electronics"]').click();
    await breadcrumbs.updateComplete;

    expect(listener.mock.calls[0][0].detail.value).toBe("electronics");
    expect(
      breadcrumbs.shadowRoot.querySelector('[data-part="trigger"]').dataset
        .state,
    ).toBe("closed");
  });

  it("opens and closes a modal through its interactive controls", async () => {
    const modal = document.createElement("noora-modal");
    const trigger = document.createElement("button");
    const openChanges = vi.fn();
    const dismiss = vi.fn();
    trigger.slot = "trigger";
    trigger.textContent = "Open modal";
    modal.title = "Edit profile";
    modal.description = "This is hidden";
    modal.headerType = "warning";
    modal.headerSize = "small";
    modal.append(trigger, document.createElement("p"));
    modal.addEventListener("noora-open-change", openChanges);
    modal.addEventListener("noora-dismiss", dismiss);
    document.body.append(modal);
    await modal.updateComplete;

    expect(modal.open).toBe(false);
    expect(
      modal.shadowRoot
        .querySelector('[data-part="positioner"]')
        .hasAttribute("hidden"),
    ).toBe(true);
    expect(
      modal.shadowRoot
        .querySelector('[data-part="content"]')
        .hasAttribute("data-state"),
    ).toBe(false);

    modal.shadowRoot.querySelector('[data-part="trigger"]').click();
    await modal.updateComplete;

    expect(modal.open).toBe(true);
    expect(modal.hasAttribute("open")).toBe(false);
    expect(
      modal.shadowRoot
        .querySelector('[data-part="positioner"]')
        .hasAttribute("hidden"),
    ).toBe(false);
    expect(
      modal.shadowRoot.querySelector('[data-part="content"]').tagName,
    ).toBe("DIV");
    expect(
      modal.shadowRoot.querySelector('[data-part="header"]').dataset.type,
    ).toBe("warning");
    expect(
      modal.shadowRoot.querySelector('[data-part="header"]').dataset.size,
    ).toBe("small");
    expect(
      modal.shadowRoot.querySelector('[data-part="description"]'),
    ).toBeNull();
    expect(modal.shadowRoot.querySelector('[data-part="footer"]').hidden).toBe(
      true,
    );

    modal.shadowRoot.querySelector('[data-part="close-trigger"]').click();
    await modal.updateComplete;

    expect(modal.open).toBe(false);
    expect(
      modal.shadowRoot
        .querySelector('[data-part="content"]')
        .hasAttribute("data-state"),
    ).toBe(false);
    expect(openChanges).toHaveBeenCalledTimes(2);
    expect(dismiss.mock.calls[0][0].detail.reason).toBe("close-button");
  });

  it("groups modal footer actions like the LiveView component", async () => {
    const modal = document.createElement("noora-modal");
    for (const label of ["Cancel", "Confirm"]) {
      const action = document.createElement("button");
      action.slot = "footer";
      action.textContent = label;
      if (label === "Cancel") action.dataset.action = "close";
      modal.append(action);
    }
    document.body.append(modal);
    await modal.updateComplete;

    const footer = modal.shadowRoot.querySelector('[data-part="footer"]');
    const actions = footer.querySelector('[data-part="actions"]');

    expect(footer.hidden).toBe(false);
    expect(
      actions.querySelector('slot[name="footer"]').assignedElements(),
    ).toHaveLength(2);

    modal.setOpen(true);
    await modal.updateComplete;
    modal.querySelector('[data-action="close"]').click();
    await modal.updateComplete;

    expect(modal.open).toBe(false);
  });

  it("toggles popovers and date pickers from their triggers", async () => {
    const popover = document.createElement("noora-popover");
    const popoverTrigger = document.createElement("button");
    popoverTrigger.slot = "trigger";
    popoverTrigger.textContent = "Open popover";
    popover.append(popoverTrigger);
    document.body.append(popover);
    await popover.updateComplete;

    expect(popover.open).toBe(false);
    expect(popover.hasAttribute("open")).toBe(false);
    expect(
      popover.shadowRoot
        .querySelector('[data-part="positioner"]')
        .hasAttribute("hidden"),
    ).toBe(true);

    popover.shadowRoot.querySelector('[data-part="trigger"]').click();
    await popover.updateComplete;
    expect(popover.open).toBe(true);
    expect(popover.hasAttribute("open")).toBe(false);
    expect(
      popover.shadowRoot.querySelector(".noora-popover").dataset
        .positioningPlacement,
    ).toBe("bottom");
    expect(
      popover.shadowRoot.querySelector('[data-part="content"]').dataset.state,
    ).toBe("open");

    popover.shadowRoot.querySelector('[data-part="trigger"]').click();
    await popover.updateComplete;
    expect(popover.open).toBe(false);
    expect(
      popover.shadowRoot
        .querySelector('[data-part="positioner"]')
        .hasAttribute("hidden"),
    ).toBe(true);

    const datePicker = document.createElement("noora-date-picker");
    document.body.append(datePicker);
    await datePicker.updateComplete;

    datePicker.shadowRoot.querySelector('[part="trigger"]').click();
    await datePicker.updateComplete;
    expect(datePicker.open).toBe(true);
  });

  it("renders the LiveView calendar structure and applies a pending preset", async () => {
    const datePicker = document.createElement("noora-date-picker");
    const periodChange = vi.fn();
    datePicker.open = true;
    datePicker.selectedPreset = "7d";
    datePicker.addEventListener("noora-period-change", periodChange);
    datePicker.innerHTML = `
      <noora-date-picker-preset value="7d" start="2026-07-21" end="2026-07-27">
        Last 7 days
      </noora-date-picker-preset>
      <noora-date-picker-preset value="30d" start="2026-06-28" end="2026-07-27">
        Last 30 days
      </noora-date-picker-preset>
    `;
    document.body.append(datePicker);
    await Promise.all(
      [...datePicker.children].map((child) => child.updateComplete),
    );
    await datePicker.updateComplete;
    await new Promise((resolve) => setTimeout(resolve, 0));

    const months = datePicker.shadowRoot.querySelectorAll(
      '[data-part="month"]',
    );
    const inputs = datePicker.shadowRoot.querySelectorAll(
      '[data-part="date-input"]',
    );

    expect(months).toHaveLength(2);
    expect(
      months[0].querySelector('[data-part="view-trigger"]').textContent,
    ).toBe("June 2026");
    expect(
      months[1].querySelector('[data-part="view-trigger"]').textContent,
    ).toBe("July 2026");
    expect([...inputs].map((input) => input.value)).toEqual([
      "21",
      "07",
      "2026",
      "27",
      "07",
      "2026",
    ]);

    const presets = datePicker.shadowRoot.querySelectorAll(
      '[data-part="presets"][data-device="desktop"] button',
    );
    presets[1].click();
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(datePicker.start).toBeUndefined();
    expect(datePicker.end).toBeUndefined();

    datePicker.shadowRoot.querySelector('[data-action="apply"]').click();
    await datePicker.updateComplete;

    expect(datePicker.start).toBe("2026-06-28");
    expect(datePicker.end).toBe("2026-07-27");
    expect(datePicker.selectedPreset).toBe("30d");
    expect(periodChange).toHaveBeenCalledOnce();
    expect(periodChange.mock.calls[0][0].detail).toEqual({
      start: "2026-06-28",
      end: "2026-07-27",
      preset: "30d",
    });
  });

  it("submits the selected date range with the configured name", async () => {
    const originalAttachInternals = Object.getOwnPropertyDescriptor(
      HTMLElement.prototype,
      "attachInternals",
    );
    const setFormValue = vi.fn();
    Object.defineProperty(HTMLElement.prototype, "attachInternals", {
      configurable: true,
      value: () => ({ form: null, setFormValue }),
    });

    try {
      const datePicker = document.createElement("noora-date-picker");
      datePicker.name = "range";
      datePicker.start = "2026-07-21";
      datePicker.end = "2026-07-27";
      document.body.append(datePicker);
      await datePicker.updateComplete;

      const data = setFormValue.mock.calls.at(-1)[0];

      expect(data.get("range[start]")).toBe("2026-07-21");
      expect(data.get("range[end]")).toBe("2026-07-27");
    } finally {
      if (originalAttachInternals) {
        Object.defineProperty(
          HTMLElement.prototype,
          "attachInternals",
          originalAttachInternals,
        );
      } else {
        delete HTMLElement.prototype.attachInternals;
      }
    }
  });

  it("reacts to the parent state for paired icon transitions", async () => {
    const trigger = document.createElement("button");
    const icon = document.createElement("noora-icon");
    trigger.dataset.state = "closed";
    icon.name = "menu";
    icon.activeName = "close";
    trigger.append(icon);
    document.body.append(trigger);
    await icon.updateComplete;

    expect(
      icon.shadowRoot.querySelector('[part="icon"]').getAttribute("style"),
    ).toContain("var(--noora-icon-size, 24px)");
    expect(icon.shadowRoot.querySelector('[part="icon"]').dataset.active).toBe(
      "false",
    );

    trigger.dataset.state = "open";
    await Promise.resolve();
    await icon.updateComplete;

    expect(icon.shadowRoot.querySelector('[part="icon"]').dataset.active).toBe(
      "true",
    );
  });

  it("keeps structured inputs property-only", () => {
    for (const contract of remainingContracts) {
      for (const property of contract.properties ?? []) {
        const element = document.createElement(contract.tagName);
        const attributeName = property.name.replace(
          /[A-Z]/g,
          (letter) => `-${letter.toLowerCase()}`,
        );
        const value = Array.isArray(property.default)
          ? [{ sentinel: true }]
          : { sentinel: true };

        element.setAttribute(attributeName, JSON.stringify(value));

        expect(
          element[property.name],
          `${contract.tagName}.${property.name}`,
        ).toEqual(property.default);

        element[property.name] = value;

        expect(
          element[property.name],
          `${contract.tagName}.${property.name}`,
        ).toEqual(value);
      }
    }
  });

  it("emits page changes from pagination controls", async () => {
    const pagination = document.createElement("noora-pagination-group");
    const listener = vi.fn();
    pagination.currentPage = 2;
    pagination.numberOfPages = 10;
    pagination.addEventListener("noora-page-change", listener);
    document.body.append(pagination);
    await pagination.updateComplete;

    pagination.shadowRoot.querySelector('[part="next"]').click();
    await pagination.updateComplete;

    expect(pagination.currentPage).toBe(3);
    expect(listener.mock.calls[0][0].detail.page).toBe(3);
  });

  it("renders structured table data", async () => {
    const table = document.createElement("noora-table");
    table.columns = [
      { key: "name", label: "Name" },
      { key: "duration", label: "Duration (desc)", sortOrder: "desc" },
    ];
    table.rows = [{ id: "tuist", name: "Tuist" }];
    table.selectable = true;
    document.body.append(table);
    await table.updateComplete;

    expect(table.shadowRoot.querySelector("th").textContent).toContain("Name");
    expect(table.shadowRoot.querySelector("td").textContent).toContain("Tuist");
    expect(
      table.shadowRoot.querySelector(
        "td > [data-part='cell'][data-type='text']",
      ).textContent,
    ).toContain("Tuist");
    expect(
      table.shadowRoot.querySelector("th [data-part='icon']").dataset.state,
    ).toBe("desc");
    expect(
      table.shadowRoot.querySelector("td").hasAttribute("data-selectable"),
    ).toBe(true);
    expect(
      table.constructor.elementStyles.map((style) => style.cssText).join("\n"),
    ).toContain("width: 100%");
  });

  it("renders declarative children across collection components", async () => {
    const breadcrumbs = document.createElement("noora-breadcrumbs");
    breadcrumbs.innerHTML = `
      <noora-breadcrumb-item icon="smart_home">Home</noora-breadcrumb-item>
      <noora-breadcrumb-item label="Products">
        <noora-dropdown-item value="phones" selected>Phones</noora-dropdown-item>
      </noora-breadcrumb-item>
      <noora-breadcrumb-item>iPhone 15</noora-breadcrumb-item>
    `;

    const select = document.createElement("noora-select");
    select.label = "Country";
    select.innerHTML = `
      <option value="es">Spain</option>
      <option value="de">Germany</option>
    `;

    const datePicker = document.createElement("noora-date-picker");
    datePicker.open = true;
    datePicker.innerHTML = `
      <noora-date-picker-preset value="7d" start="2026-07-21" end="2026-07-27">
        Last 7 days
      </noora-date-picker-preset>
    `;

    const filter = document.createElement("noora-filter");
    filter.innerHTML = `
      <noora-filter-definition name="status" label="Status">
        <noora-filter-option value="active">Active</noora-filter-option>
      </noora-filter-definition>
      <noora-filter-value name="status" label="Status" value="active" display-value="Active"></noora-filter-value>
    `;

    const tabs = document.createElement("noora-tab-menu");
    tabs.value = "overview";
    tabs.innerHTML = `
      <noora-tab-item value="overview" icon="category">Overview</noora-tab-item>
      <noora-tab-item value="settings">Settings</noora-tab-item>
    `;

    const sidebar = document.createElement("noora-sidebar");
    sidebar.innerHTML = `
      <noora-sidebar-item href="/" icon="dashboard" selected>Dashboard</noora-sidebar-item>
      <noora-sidebar-group label="Projects" default-open>
        <noora-sidebar-item href="/projects/tuist">Tuist</noora-sidebar-item>
      </noora-sidebar-group>
    `;

    const table = document.createElement("noora-table");
    const rowSelect = vi.fn();
    table.selectable = true;
    table.addEventListener("noora-row-select", rowSelect);
    table.innerHTML = `
      <noora-table-column name="project">Project</noora-table-column>
      <noora-table-row row-key="tuist">
        <noora-table-cell column="project">Tuist</noora-table-cell>
      </noora-table-row>
    `;

    document.body.append(
      breadcrumbs,
      select,
      datePicker,
      filter,
      tabs,
      sidebar,
      table,
    );
    await Promise.all(
      [...document.querySelectorAll("*")]
        .filter((element) => element.updateComplete)
        .map((element) => element.updateComplete),
    );
    await Promise.all(
      [breadcrumbs, select, datePicker, filter, tabs, sidebar, table].map(
        (element) => element.updateComplete,
      ),
    );

    expect(
      breadcrumbs.shadowRoot.querySelectorAll(".noora-breadcrumb"),
    ).toHaveLength(3);
    expect(select.shadowRoot.querySelectorAll("option")).toHaveLength(3);
    expect(
      datePicker.shadowRoot.querySelector('[data-part="presets"]').textContent,
    ).toContain("Last 7 days");
    expect(
      filter.shadowRoot.querySelector('[data-part="active-filters"]')
        .textContent,
    ).toContain("Status");
    expect(tabs.shadowRoot.querySelectorAll('[part="item"]')).toHaveLength(2);
    expect(
      sidebar.shadowRoot.querySelector('[data-part="group"]'),
    ).not.toBeNull();
    expect(table.shadowRoot.querySelector("th").textContent).toContain(
      "Project",
    );
    expect(table.shadowRoot.querySelector("td").textContent).toContain("Tuist");

    datePicker.shadowRoot.querySelector('[data-part="presets"] button').click();
    await new Promise((resolve) => setTimeout(resolve, 0));
    datePicker.shadowRoot.querySelector('[data-action="apply"]').click();
    tabs.shadowRoot.querySelectorAll('[part="item"]')[1].click();
    sidebar.shadowRoot.querySelector('[data-part="group-label"]').click();
    table.shadowRoot.querySelector('[part="row"]').click();
    await Promise.all(
      [datePicker, tabs, sidebar, table].map(
        (element) => element.updateComplete,
      ),
    );

    expect(datePicker.start).toBe("2026-07-21");
    expect(datePicker.end).toBe("2026-07-27");
    expect(tabs.value).toBe("settings");
    expect(
      sidebar.shadowRoot.querySelector('[data-part="group"] > div').hidden,
    ).toBe(true);
    expect(rowSelect.mock.calls[0][0].detail.row.project).toBe("Tuist");
  });

  it("renders and operates a Select like its LiveView counterpart", async () => {
    const select = document.createElement("noora-select");
    const input = vi.fn();
    const change = vi.fn();
    const selection = vi.fn();
    select.label = "Country";
    select.name = "country";
    select.value = "de";
    select.hint = "Used for regional settings.";
    select.innerHTML = `
      <option value="es">Spain</option>
      <option value="de" data-icon="category">Germany</option>
      <option value="fr">France</option>
    `;
    select.addEventListener("input", input);
    select.addEventListener("change", change);
    select.addEventListener("noora-select", selection);
    document.body.append(select);
    await select.updateComplete;

    const trigger = select.shadowRoot.querySelector('[part="select"]');

    expect(trigger.tagName).toBe("BUTTON");
    expect(trigger.textContent).toContain("Germany");
    expect(trigger.querySelector('[data-part="icon"] svg')).not.toBeNull();
    expect(select.control.dataset.part).toBe("hidden-select");
    expect(select.control.value).toBe("de");
    expect(
      select.shadowRoot.querySelector('[part="hint"]').textContent,
    ).toContain("Used for regional settings.");
    expect(trigger.getAttribute("aria-describedby")).toBe(
      select.shadowRoot.querySelector('[part="hint"]').id,
    );

    trigger.click();
    await select.updateComplete;

    expect(select.open).toBe(true);
    expect(
      select.shadowRoot.querySelector('[part="content"]').dataset.state,
    ).toBe("open");
    expect(select.shadowRoot.querySelectorAll('[part="item"]')).toHaveLength(3);

    const options = select.shadowRoot.querySelectorAll('[part="item"]');
    expect(select.shadowRoot.querySelector('[data-part="items"]').role).toBe(
      "listbox",
    );
    expect(options[1].role).toBe("option");
    expect(options[1].getAttribute("aria-selected")).toBe("true");
    expect(select.shadowRoot.activeElement).toBe(options[1]);
    options[1].dispatchEvent(
      new KeyboardEvent("keydown", {
        bubbles: true,
        composed: true,
        key: "ArrowDown",
      }),
    );
    expect(select.shadowRoot.activeElement).toBe(options[2]);
    options[2].dispatchEvent(
      new KeyboardEvent("keydown", {
        bubbles: true,
        composed: true,
        key: "Enter",
      }),
    );
    await select.updateComplete;

    expect(select.value).toBe("fr");
    expect(select.control.value).toBe("fr");
    expect(
      select.shadowRoot.querySelector('[part="select"]').textContent,
    ).toContain("France");
    expect(select.open).toBe(false);
    expect(input).toHaveBeenCalledOnce();
    expect(change).toHaveBeenCalledOnce();
    expect(selection.mock.calls[0][0].detail.value).toBe("fr");
  });

  it("renders Tab Menu items without browser-default control styling", async () => {
    const tabs = document.createElement("noora-tab-menu");
    const change = vi.fn();
    tabs.value = "general";
    tabs.innerHTML = `
      <noora-tab-item value="general" icon="category">General</noora-tab-item>
      <noora-tab-item value="settings">Settings</noora-tab-item>
    `;
    tabs.addEventListener("noora-tab-change", change);
    document.body.append(tabs);
    await Promise.all([...tabs.children].map((child) => child.updateComplete));
    await tabs.updateComplete;

    const items = tabs.shadowRoot.querySelectorAll('[part="item"]');
    const styles = tabs.constructor.elementStyles
      .map((style) => style.cssText)
      .join("\n");

    expect(items).toHaveLength(2);
    expect(items[0].hasAttribute("data-selected")).toBe(true);
    expect(styles).toContain(".noora-tab-menu-horizontal-item");
    expect(styles).toContain("appearance: none");
    expect(styles).toContain("background: transparent");

    items[1].click();
    await tabs.updateComplete;

    expect(tabs.value).toBe("settings");
    expect(change.mock.calls[0][0].detail.value).toBe("settings");

    tabs.orientation = "vertical";
    await tabs.updateComplete;

    expect(tabs.shadowRoot.querySelector('[part="menu"]').classList).toContain(
      "noora-tab-menu-vertical-list",
    );
  });

  it("matches the structured LiveView filter and supports its interactions", async () => {
    const filter = document.createElement("noora-filter");
    const change = vi.fn();
    filter.addEventListener("noora-filter-change", change);
    filter.innerHTML = `
      <noora-filter-definition name="status" label="Status" type="option">
        <noora-filter-option value="active">Active</noora-filter-option>
        <noora-filter-option value="paused">Paused</noora-filter-option>
      </noora-filter-definition>
      <noora-filter-definition name="name" label="Name" type="text"></noora-filter-definition>
      <noora-filter-value name="status" operator="==" value="active"></noora-filter-value>
    `;
    document.body.append(filter);
    await filter.updateComplete;

    const activeFilter = filter.shadowRoot.querySelector(
      '[part="active-filter"]',
    );
    expect(activeFilter.textContent).toContain("Status");
    expect(activeFilter.textContent).toContain("is");
    expect(activeFilter.textContent).toContain("Active");
    expect(filter.shadowRoot.querySelector("select")).toBeNull();

    activeFilter
      .querySelector('[data-control="operator"] [data-part="trigger"]')
      .click();
    await filter.updateComplete;
    activeFilter
      .querySelectorAll('[data-control="operator"] .noora-dropdown-item')[1]
      .click();
    await filter.updateComplete;

    expect(change).toHaveBeenLastCalledWith(
      expect.objectContaining({
        detail: expect.objectContaining({
          filters: [
            expect.objectContaining({
              id: "status",
              operator: "!=",
              value: "active",
            }),
          ],
        }),
      }),
    );

    const updatedFilter = filter.shadowRoot.querySelector(
      '[part="active-filter"]',
    );
    updatedFilter
      .querySelector('[data-control="value"] [data-part="trigger"]')
      .click();
    await filter.updateComplete;
    updatedFilter
      .querySelectorAll('[data-control="value"] .noora-dropdown-item')[1]
      .click();
    await filter.updateComplete;

    expect(filter.filters[0]).toEqual(
      expect.objectContaining({
        displayValue: "Paused",
        value: "paused",
      }),
    );

    const add = filter.shadowRoot.querySelector("noora-dropdown");
    await add.updateComplete;
    add.shadowRoot.querySelector('[part="trigger"]').click();
    await add.updateComplete;
    add.shadowRoot.querySelector(".noora-dropdown-item").click();
    await filter.updateComplete;

    expect(filter.filters).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: "name", type: "text" }),
      ]),
    );

    filter.shadowRoot
      .querySelector('[part="active-filter"] [data-part="delete-icon"]')
      .click();
    await filter.updateComplete;

    expect(filter.filters).toHaveLength(1);
    expect(filter.filters[0].id).toBe("name");
  });

  it("renders the selected status badge indicator", async () => {
    const badge = document.createElement("noora-status-badge");
    badge.status = "warning";
    badge.type = "dot";
    badge.label = "Pending";
    document.body.append(badge);
    await badge.updateComplete;

    const container = badge.shadowRoot.querySelector('[part="badge"]');

    expect(container.dataset.status).toBe("warning");
    expect(container.textContent).toContain("Pending");
    expect(badge.shadowRoot.querySelector('[part="icon"] svg')).not.toBeNull();
  });

  it("formats absolute and relative times", async () => {
    const time = document.createElement("noora-time");
    time.datetime = new Date(Date.now() - 60_000).toISOString();
    document.body.append(time);
    await time.updateComplete;

    const absolute = time.shadowRoot.querySelector("time").textContent;
    time.relative = true;
    await time.updateComplete;

    expect(absolute.length).toBeGreaterThan(0);
    expect(time.shadowRoot.querySelector("time").textContent).toContain(
      "minute",
    );
    expect(
      time.shadowRoot.querySelector('[data-part="trigger"]'),
    ).not.toBeNull();
    expect(time.shadowRoot.querySelector("noora-tooltip").title).toBe(absolute);
  });
});
