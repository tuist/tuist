import * as echarts from "echarts";
import { css, html, nothing, unsafeCSS } from "lit";
import { ifDefined } from "lit/directives/if-defined.js";
import { live } from "lit/directives/live.js";
import { getNooraChartTheme, prepareChartOptions } from "../Chart.js";
import { DateInputHandler } from "../DatePicker/DateInputHandler.js";
import { toISODateString } from "../DatePicker/dateUtils.js";
import { DatePicker as DatePickerController } from "../DatePicker/index.js";
import alertStyles from "../../css/alert.css";
import avatarStyles from "../../css/avatar.css";
import badgeStyles from "../../css/badge.css";
import bannerStyles from "../../css/banner.css";
import breadcrumbsStyles from "../../css/breadcrumbs.css";
import buttonStyles from "../../css/button.css";
import buttonDropdownStyles from "../../css/button_dropdown.css";
import buttonGroupStyles from "../../css/button_group.css";
import cardStyles from "../../css/card.css";
import chartStyles from "../../css/chart.css";
import checkboxStyles from "../../css/checkbox.css";
import checkboxControlStyles from "../../css/checkbox_control.css";
import datePickerStyles from "../../css/date_picker.css";
import dismissIconStyles from "../../css/dismiss_icon.css";
import dropdownStyles from "../../css/dropdown.css";
import filterStyles from "../../css/filter.css";
import hintTextStyles from "../../css/hint_text.css";
import iconStyles from "../../css/icon.css";
import labelStyles from "../../css/label.css";
import lineDividerStyles from "../../css/line_divider.css";
import modalStyles from "../../css/modal.css";
import paginationStyles from "../../css/pagination_group.css";
import popoverStyles from "../../css/popover.css";
import progressBarStyles from "../../css/progress_bar.css";
import selectStyles from "../../css/select.css";
import shortcutKeyStyles from "../../css/shortcut_key.css";
import sidebarStyles from "../../css/sidebar.css";
import tabMenuStyles from "../../css/tab_menu.css";
import tableStyles from "../../css/table.css";
import tagStyles from "../../css/tag.css";
import textAreaStyles from "../../css/text_area.css";
import textDividerStyles from "../../css/text_divider.css";
import textInputStyles from "../../css/text_input.css";
import timeStyles from "../../css/time.css";
import toggleStyles from "../../css/toggle.css";
import tooltipStyles from "../../css/tooltip.css";
import {
  contractAttribute,
  contractByTag,
  resolveContractValue,
} from "./Contract.js";
import { NooraElement, nooraIcon, registerNooraElement } from "./Component.js";
import publishedContracts from "./contracts.json";

const contract = (tagName) => contractByTag(publishedContracts, tagName);
const validated = (element, name) => {
  const attribute = contractAttribute(element.constructor.contract, name);
  return resolveContractValue(element[attribute.property], attribute);
};
const hostDisplay = css`
  :host {
    display: block;
  }
`;
const inlineHostDisplay = css`
  :host {
    display: inline-block;
  }
`;
const anchoredPopupPositioning = css`
  [data-part="positioner"] {
    position: absolute;
    top: calc(100% + var(--noora-spacing-2));
    left: 0;
    z-index: var(--noora-z-index-10);
    box-sizing: border-box;
    width: 100%;
  }
`;
const visuallyHidden = css`
  .visually-hidden {
    position: absolute;
    clip: rect(0 0 0 0);
    clip-path: inset(50%);
    width: 1px;
    height: 1px;
    overflow: hidden;
    white-space: nowrap;
  }
`;
let nextGeneratedId = 0;

function generatedId(prefix) {
  nextGeneratedId += 1;
  return `noora-${prefix}-${nextGeneratedId}`;
}

function statusIcon(status) {
  if (status === "success") return nooraIcon("circle_check");
  if (status === "warning") return nooraIcon("alert_triangle");
  return nooraIcon("alert_circle");
}

function statusBadgeIcon(status) {
  if (status === "success") return nooraIcon("circle_check");
  if (status === "warning") return nooraIcon("alert_hexagon");
  if (status === "attention") return nooraIcon("alert_triangle");
  if (status === "disabled") return nooraIcon("cancel");
  if (status === "in_progress") return nooraIcon("circle_dashed");
  return nooraIcon("alert_circle");
}

function normalizedIconName(name) {
  return name?.replaceAll("-", "_");
}

function directText(element) {
  return [...element.childNodes]
    .filter((node) => node.nodeType === Node.TEXT_NODE)
    .map((node) => node.textContent)
    .join(" ")
    .trim();
}

function compactRecord(record) {
  return Object.fromEntries(
    Object.entries(record).filter(([, value]) => value !== undefined),
  );
}

function childConfigurations(element, tagName, fallback = []) {
  const children = [...element.children].filter(
    (child) => child.localName === tagName,
  );
  if (children.length === 0) return fallback;

  return children
    .map((child) => child.configuration)
    .filter((configuration) => configuration !== undefined);
}

class NooraConfigurationElement extends NooraElement {
  static styles = css`
    :host {
      display: none !important;
    }
  `;

  connectedCallback() {
    super.connectedCallback();
    queueMicrotask(() => this.#notifyParent());
  }

  updated() {
    this.#notifyParent();
  }

  render() {
    return html`<slot @slotchange=${this.#notifyParent}></slot>`;
  }

  #notifyParent = () => {
    this.emit("noora-configuration-change");
  };
}

export class NooraDropdownItem extends NooraConfigurationElement {
  static contract = contract("noora-dropdown-item");

  get configuration() {
    const showAvatar =
      this.avatar || this.avatarName || this.avatarImageHref !== undefined;
    const showBadge = this.badgeLabel !== undefined;

    return compactRecord({
      label: this.label || directText(this),
      value: this.value,
      icon: this.icon,
      rightIcon: this.rightIcon,
      size: this.size,
      href: this.href,
      secondaryText: this.secondaryText,
      description: this.description,
      disabled: this.disabled || undefined,
      checked: this.checkable ? this.checked : undefined,
      selected: this.selected || undefined,
      avatar: showAvatar
        ? compactRecord({
            name: this.avatarName,
            color: this.avatarColor,
            imageHref: this.avatarImageHref,
          })
        : undefined,
      badge: showBadge
        ? compactRecord({
            label: this.badgeLabel,
            color: this.badgeColor,
          })
        : undefined,
    });
  }
}

export class NooraBreadcrumbItem extends NooraConfigurationElement {
  static contract = contract("noora-breadcrumb-item");

  get configuration() {
    const showAvatar =
      this.avatar || this.avatarName || this.avatarImageHref !== undefined;

    return compactRecord({
      label: this.label || directText(this),
      href: this.href,
      icon: this.icon,
      avatar: showAvatar
        ? compactRecord({
            name: this.avatarName,
            color: this.avatarColor,
            imageHref: this.avatarImageHref,
          })
        : undefined,
      badge: this.badgeLabel
        ? compactRecord({
            label: this.badgeLabel,
            color: this.badgeColor,
          })
        : undefined,
      items: childConfigurations(this, "noora-dropdown-item"),
    });
  }
}

export class NooraDatePickerPreset extends NooraConfigurationElement {
  static contract = contract("noora-date-picker-preset");

  get configuration() {
    return {
      id: this.value,
      label: this.label || directText(this),
      start: this.start,
      end: this.end,
    };
  }
}

export class NooraButtonGroupItem extends NooraConfigurationElement {
  static contract = contract("noora-button-group-item");

  get configuration() {
    return compactRecord({
      label: this.label || directText(this),
      value: this.value,
      href: this.href,
      icon: this.icon,
      iconLeft: this.iconLeft,
      iconRight: this.iconRight,
      iconOnly: this.iconOnly || undefined,
      ariaLabel: this.ariaLabel,
      disabled: this.disabled || undefined,
      selected: this.selected || undefined,
    });
  }
}

export class NooraChartGrid extends NooraConfigurationElement {
  static contract = contract("noora-chart-grid");

  get configuration() {
    return compactRecord({
      containLabel: this.containLabel || undefined,
      height: this.height,
      width: this.width,
    });
  }
}

export class NooraChartCategory extends NooraConfigurationElement {
  static contract = contract("noora-chart-category");

  get configuration() {
    return this.value || directText(this);
  }
}

export class NooraChartAxis extends NooraConfigurationElement {
  static contract = contract("noora-chart-axis");

  get configuration() {
    const categories = childConfigurations(this, "noora-chart-category");
    const hasAxisLabel =
      this.labelFormat !== undefined ||
      this.labelSize !== undefined ||
      this.labelMargin !== undefined;

    return {
      dimension: this.dimension,
      options: compactRecord({
        type: this.type,
        data: categories.length > 0 ? categories : undefined,
        min: this.min,
        max: this.max,
        show: this.axisHidden ? false : undefined,
        boundaryGap: this.noBoundaryGap ? false : undefined,
        axisLabel: hasAxisLabel
          ? compactRecord({
              formatter: this.labelFormat,
              fontSize: this.labelSize,
              margin: this.labelMargin,
            })
          : undefined,
        axisLine: this.hideLine ? { show: false } : undefined,
        axisTick: this.hideTicks ? { show: false } : undefined,
        splitLine: this.dashedGrid
          ? { lineStyle: { type: "dashed" } }
          : undefined,
      }),
    };
  }
}

export class NooraChartPoint extends NooraConfigurationElement {
  static contract = contract("noora-chart-point");

  get configuration() {
    if (this.color === undefined && this.url === undefined) return this.value;

    return compactRecord({
      value: this.value,
      itemStyle: this.color ? { color: this.color } : undefined,
      url: this.url,
    });
  }
}

export class NooraChartSeries extends NooraConfigurationElement {
  static contract = contract("noora-chart-series");

  get configuration() {
    const points = childConfigurations(this, "noora-chart-point");

    return compactRecord({
      name: this.name,
      type: this.type,
      symbol: this.symbol,
      barWidth: this.barWidth,
      barGap: this.barGap,
      itemStyle:
        this.borderRadius !== undefined
          ? { borderRadius: this.borderRadius }
          : undefined,
      data: points,
    });
  }
}

export class NooraFilterOption extends NooraConfigurationElement {
  static contract = contract("noora-filter-option");

  get configuration() {
    return {
      label: this.label || directText(this),
      value: this.value,
    };
  }
}

export class NooraFilterDefinition extends NooraConfigurationElement {
  static contract = contract("noora-filter-definition");

  get configuration() {
    return compactRecord({
      id: this.name,
      label: this.label,
      type: this.type,
      operator: this.operator,
      default: this.defaultValue,
      searchable: this.searchable || undefined,
      options: childConfigurations(this, "noora-filter-option"),
    });
  }
}

export class NooraFilterValue extends NooraConfigurationElement {
  static contract = contract("noora-filter-value");

  get configuration() {
    return compactRecord({
      id: this.name,
      label: this.label,
      type: this.type,
      operator: this.operator,
      value: this.value,
      displayValue: this.displayValue,
    });
  }
}

export class NooraTabItem extends NooraConfigurationElement {
  static contract = contract("noora-tab-item");

  get configuration() {
    return compactRecord({
      label: this.label || directText(this),
      value: this.value,
      icon: this.icon,
      rightIcon: this.rightIcon,
      href: this.href,
      disabled: this.disabled || undefined,
    });
  }
}

export class NooraSidebarItem extends NooraConfigurationElement {
  static contract = contract("noora-sidebar-item");

  get configuration() {
    return compactRecord({
      label: this.label || directText(this),
      icon: this.icon,
      href: this.href,
      selected: this.selected || undefined,
    });
  }
}

export class NooraSidebarGroup extends NooraConfigurationElement {
  static contract = contract("noora-sidebar-group");

  get configuration() {
    return {
      label: this.label,
      collapsible: !this.fixed,
      defaultOpen: this.defaultOpen,
      items: childConfigurations(this, "noora-sidebar-item"),
    };
  }
}

export class NooraTableColumn extends NooraConfigurationElement {
  static contract = contract("noora-table-column");

  get configuration() {
    return compactRecord({
      key: this.name,
      label: this.label || directText(this),
      icon: this.icon,
      sortOrder: this.sortOrder,
      format: this.format,
    });
  }
}

export class NooraTableCell extends NooraConfigurationElement {
  static contract = contract("noora-table-cell");

  get configuration() {
    return {
      column: this.column,
      value: this.value ?? directText(this),
    };
  }
}

export class NooraTableRow extends NooraConfigurationElement {
  static contract = contract("noora-table-row");

  get configuration() {
    const cells = childConfigurations(this, "noora-table-cell");
    return {
      id: this.rowKey,
      ...Object.fromEntries(cells.map((cell) => [cell.column, cell.value])),
    };
  }
}

function menuItemTemplate(
  item,
  onSelect,
  { role = "menuitem", selected = item.selected } = {},
) {
  const ariaSelected =
    role === "option" ? String(Boolean(selected)) : undefined;
  const body = html`
    ${item.avatar || item.showAvatar
      ? html`<noora-avatar
          size="2xsmall"
          name=${item.avatar?.name ?? item.label ?? ""}
          color=${item.avatar?.color ?? item.avatarColor ?? "pink"}
          image-href=${ifDefined(item.avatar?.imageHref)}
        ></noora-avatar>`
      : item.checked === undefined
        ? item.icon
          ? html`<div data-part="left-icon">
              ${nooraIcon(normalizedIconName(item.icon))}
            </div>`
          : nothing
        : html`<div data-part="checkbox">
            <span
              class="noora-checkbox-control"
              data-state=${item.checked ? "checked" : "unchecked"}
            >
              <span data-part="check">${nooraIcon("check")}</span>
            </span>
          </div>`}
    <div data-part="content">
      <div data-part="body">
        <span data-part="label">${item.label ?? item.value}</span>
        ${item.secondaryText
          ? html`<span data-part="secondary-text"
              >(${item.secondaryText})</span
            >`
          : nothing}
        ${item.description
          ? html`<span data-part="description">${item.description}</span>`
          : nothing}
      </div>
    </div>
    ${item.rightIcon
      ? html`<div data-part="right-icon">
          ${nooraIcon(normalizedIconName(item.rightIcon))}
        </div>`
      : nothing}
    ${item.badge || item.badgeLabel
      ? html`<noora-badge
          appearance="light-fill"
          color=${item.badge?.color ?? item.badgeColor ?? "neutral"}
          label=${item.badge?.label ?? item.badgeLabel}
        ></noora-badge>`
      : nothing}
  `;

  if (item.href) {
    return html`
      <a
        class="noora-dropdown-item"
        part="item"
        data-part="item"
        data-size=${item.size ?? "small"}
        data-value=${item.value ?? item.label}
        role=${role}
        tabindex="-1"
        aria-disabled=${item.disabled ? "true" : "false"}
        aria-selected=${ifDefined(ariaSelected)}
        href=${item.href}
        @click=${(event) => {
          if (item.disabled) {
            event.preventDefault();
            return;
          }
          onSelect(item);
        }}
      >
        ${body}
      </a>
    `;
  }

  return html`
    <button
      class="noora-dropdown-item"
      part="item"
      data-part="item"
      data-size=${item.size ?? "small"}
      data-value=${item.value ?? item.label}
      type="button"
      role=${role}
      tabindex="-1"
      aria-selected=${ifDefined(ariaSelected)}
      ?disabled=${item.disabled}
      @click=${() => onSelect(item)}
    >
      ${body}
    </button>
  `;
}

function popupItemElements(container) {
  if (!container) return [];
  return [...container.querySelectorAll('[data-part="item"]')].filter(
    (item) =>
      !item.hasAttribute("disabled") &&
      item.getAttribute("aria-disabled") !== "true",
  );
}

function focusPopupItem(container, index = 0) {
  const items = popupItemElements(container);
  if (items.length === 0) return;
  items[Math.max(0, Math.min(index, items.length - 1))].focus();
}

function handlePopupItemKeydown(event) {
  const items = popupItemElements(event.currentTarget);
  if (items.length === 0) return;

  const currentItem = event.target.closest?.('[data-part="item"]');
  const currentIndex = items.indexOf(currentItem);
  let nextIndex;

  if (event.key === "ArrowDown") {
    nextIndex = currentIndex < 0 ? 0 : (currentIndex + 1) % items.length;
  } else if (event.key === "ArrowUp") {
    nextIndex =
      currentIndex < 0
        ? items.length - 1
        : (currentIndex - 1 + items.length) % items.length;
  } else if (event.key === "Home") {
    nextIndex = 0;
  } else if (event.key === "End") {
    nextIndex = items.length - 1;
  } else if (
    (event.key === "Enter" || event.key === " ") &&
    currentIndex >= 0
  ) {
    event.preventDefault();
    currentItem.click();
    return;
  } else {
    return;
  }

  event.preventDefault();
  items[nextIndex].focus();
}

function breadcrumbMenuItemTemplate(item, onSelect) {
  const showAvatar = (item.avatar || item.showAvatar) && !item.icon;
  const showRightContent =
    item.badge || item.badgeLabel || item.selected === true;
  const body = html`
    ${showAvatar
      ? html`<noora-avatar
          data-part="avatar"
          size="2xsmall"
          name=${item.avatar?.name ?? item.label ?? ""}
          color=${item.avatar?.color ?? item.avatarColor ?? "pink"}
          image-href=${ifDefined(item.avatar?.imageHref)}
        ></noora-avatar>`
      : item.icon
        ? html`<div data-part="left-icon">
            ${nooraIcon(normalizedIconName(item.icon))}
          </div>`
        : nothing}
    <div data-part="content">
      <div data-part="body">
        <span data-part="label">${item.label ?? item.value}</span>
      </div>
    </div>
    ${showRightContent
      ? html`<div data-part="right-icon">
          ${item.badge || item.badgeLabel
            ? html`<noora-badge
                appearance="light-fill"
                size="small"
                color=${item.badge?.color ?? item.badgeColor ?? "neutral"}
                label=${item.badge?.label ?? item.badgeLabel}
              ></noora-badge>`
            : nothing}
          <div data-part="check">${nooraIcon("check")}</div>
        </div>`
      : nothing}
  `;

  if (item.href) {
    return html`
      <a
        class="noora-dropdown-item"
        part="item"
        data-part="item"
        data-size="small"
        data-value=${item.value ?? item.label}
        ?data-selected=${item.selected}
        role="menuitem"
        tabindex="-1"
        href=${item.href}
        @click=${() => onSelect(item)}
      >
        ${body}
      </a>
    `;
  }

  return html`
    <span
      class="noora-dropdown-item"
      part="item"
      data-part="item"
      data-size="small"
      data-value=${item.value ?? item.label}
      ?data-selected=${item.selected}
      role="menuitem"
      tabindex="-1"
      aria-disabled=${item.disabled ? "true" : "false"}
      @click=${() => {
        if (!item.disabled) onSelect(item);
      }}
    >
      ${body}
    </span>
  `;
}

class NooraFormElement extends NooraElement {
  static formAssociated = true;
  static shadowRootOptions = {
    ...NooraElement.shadowRootOptions,
    delegatesFocus: true,
  };

  #formDisabled = false;
  #internals;

  constructor() {
    super();
    this.#internals = this.attachInternals?.();
  }

  get form() {
    return this.#internals?.form ?? null;
  }

  get formControlDisabled() {
    return this.disabled || this.#formDisabled;
  }

  formDisabledCallback(disabled) {
    this.#formDisabled = disabled;
    this.requestUpdate();
  }

  setFormValue(value) {
    this.#internals?.setFormValue(value);
  }

  setValidity(flags = {}, message = "", anchor) {
    this.#internals?.setValidity(flags, message, anchor);
  }
}

function forwardFormEvent(element, event) {
  event.stopPropagation();
  const options = { bubbles: true, composed: true };
  const forwardedEvent =
    event.type === "input"
      ? new InputEvent("input", {
          ...options,
          data: event.data,
          inputType: event.inputType,
        })
      : new Event(event.type, options);
  element.dispatchEvent(forwardedEvent);
}

class NooraPopupElement extends NooraElement {
  #handleDocumentClick = (event) => {
    if (
      this.open &&
      this.closeOnInteractOutside &&
      !event.composedPath().includes(this)
    ) {
      this.dismiss("outside");
    }
  };

  #handleDocumentKeydown = (event) => {
    if (this.open && this.closeOnEscape && event.key === "Escape") {
      this.dismiss("escape");
    }
  };

  connectedCallback() {
    super.connectedCallback();
    document.addEventListener("click", this.#handleDocumentClick);
    document.addEventListener("keydown", this.#handleDocumentKeydown);
  }

  disconnectedCallback() {
    document.removeEventListener("click", this.#handleDocumentClick);
    document.removeEventListener("keydown", this.#handleDocumentKeydown);
    super.disconnectedCallback();
  }

  setOpen(open) {
    if (this.open === open) return;
    this.open = open;
    this.emit("noora-open-change", { open });
  }

  dismiss(_reason) {
    this.setOpen(false);
    queueMicrotask(() =>
      this.renderRoot?.querySelector('[data-part="trigger"]')?.focus?.(),
    );
  }

  toggleOpen() {
    if (!this.disabled) this.setOpen(!this.open);
  }
}

export class NooraAlert extends NooraElement {
  static contract = contract("noora-alert");
  static styles = [unsafeCSS(alertStyles), hostDisplay];

  render() {
    const size = validated(this, "size");
    const status = validated(this, "status");
    const description = html`<slot>${this.description}</slot>`;

    return html`
      <div
        class=${this.constructor.contract.className}
        part="alert"
        data-type=${validated(this, "type")}
        data-status=${status}
        data-size=${size}
        role=${status === "error" ? "alert" : "status"}
      >
        ${this.showIcon
          ? html`<div data-part="icon">${statusIcon(status)}</div>`
          : nothing}
        ${size === "large"
          ? html`
              <div data-part="column">
                <span data-part="title" part="title">${this.title}</span>
                <div data-part="description" part="description">
                  ${description}
                </div>
                <div data-part="actions" part="actions">
                  <slot name="action"></slot>
                </div>
              </div>
            `
          : html`
              <span data-part="title" part="title">${this.title}</span>
              <div data-part="actions" part="actions">
                <slot name="action"></slot>
              </div>
            `}
        ${this.dismissible
          ? html`<button
              class="noora-dismiss-icon"
              data-part="dismiss-icon"
              data-size=${size === "small" ? "small" : "large"}
              type="button"
              aria-label="Dismiss"
              @click=${this.#dismiss}
            >
              ${nooraIcon("close")}
            </button>`
          : nothing}
      </div>
    `;
  }

  #dismiss() {
    this.hidden = true;
    this.emit("noora-dismiss");
  }
}

export class NooraAvatar extends NooraElement {
  static contract = contract("noora-avatar");
  static styles = [unsafeCSS(avatarStyles), inlineHostDisplay];

  #imageFailed = false;

  willUpdate(changedProperties) {
    if (changedProperties.has("imageHref")) this.#imageFailed = false;
  }

  render() {
    const showImage = this.imageHref && !this.#imageFailed;
    const fallback = validated(this, "fallback");
    const initials = this.name
      .split(/[\s,_-]+/)
      .filter(Boolean)
      .slice(0, this.size === "2xsmall" ? 1 : 2)
      .map((part) => part[0]?.toUpperCase())
      .join("");

    return html`
      <div
        class=${this.constructor.contract.className}
        part="avatar"
        data-scope="avatar"
        data-size=${validated(this, "size")}
        data-color=${validated(this, "color")}
        role="img"
        aria-label=${this.name}
      >
        ${showImage
          ? html`<img
              part="image"
              data-part="image"
              src=${this.imageHref}
              decoding=${validated(this, "image-decoding")}
              loading=${ifDefined(this.imageLoading)}
              @load=${() =>
                this.emit("noora-status-change", { status: "loaded" })}
              @error=${this.#handleImageError}
            />`
          : nothing}
        ${!showImage && fallback === "placeholder"
          ? html`<span data-part="fallback">${nooraIcon("photo")}</span>`
          : nothing}
        ${!showImage && fallback === "initials"
          ? html`<span part="initials" data-part="initials">${initials}</span>`
          : nothing}
      </div>
    `;
  }

  #handleImageError() {
    this.#imageFailed = true;
    this.requestUpdate();
    this.emit("noora-status-change", { status: "error" });
  }
}

export class NooraBanner extends NooraElement {
  static contract = contract("noora-banner");
  static styles = [
    unsafeCSS(bannerStyles),
    unsafeCSS(dismissIconStyles),
    hostDisplay,
    css`
      :host {
        box-sizing: border-box;
        flex: 1 0 100%;
        min-width: 0;
      }
    `,
  ];

  render() {
    const status = validated(this, "status");
    const hasCustomIcon = this.querySelector('[slot="icon"]') !== null;

    return html`
      <div
        class=${this.constructor.contract.className}
        part="banner"
        data-status=${status}
        role=${status === "error" ? "alert" : "status"}
      >
        ${status === "primary"
          ? html`<svg
              data-part="background"
              aria-hidden="true"
              viewBox="0 0 1440 44"
              preserveAspectRatio="xMidYMid slice"
            >
              <defs>
                <pattern
                  id="noora-banner-grid"
                  width="10"
                  height="10"
                  patternUnits="userSpaceOnUse"
                >
                  <path
                    d="M 10 0 L 0 0 0 10"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="0.5"
                    opacity="0.15"
                  ></path>
                </pattern>
                <radialGradient id="noora-banner-fade">
                  <stop offset="0" stop-color="white"></stop>
                  <stop offset="1" stop-color="black"></stop>
                </radialGradient>
                <mask id="noora-banner-mask">
                  <rect
                    width="100%"
                    height="100%"
                    fill="url(#noora-banner-fade)"
                  ></rect>
                </mask>
              </defs>
              <rect
                width="100%"
                height="100%"
                fill="url(#noora-banner-grid)"
                mask="url(#noora-banner-mask)"
              ></rect>
            </svg>`
          : nothing}
        ${status === "primary"
          ? hasCustomIcon
            ? html`<div data-part="icon"><slot name="icon"></slot></div>`
            : nothing
          : html`<div data-part="icon">${statusIcon(status)}</div>`}
        <span data-part="title" part="title">${this.title}</span>
        ${this.description
          ? html`
              <span data-part="dot">•</span>
              <span data-part="description" part="description"
                >${this.description}</span
              >
            `
          : nothing}
        ${this.dismissible
          ? html`<div data-part="dismiss-icon">
              <button
                class="noora-dismiss-icon"
                type="button"
                aria-label="Dismiss"
                @click=${this.#dismiss}
              >
                ${nooraIcon("close")}
              </button>
            </div>`
          : nothing}
      </div>
    `;
  }

  #dismiss() {
    this.hidden = true;
    this.emit("noora-dismiss");
  }
}

export class NooraStatusBadge extends NooraElement {
  static contract = contract("noora-status-badge");
  static styles = [unsafeCSS(badgeStyles), inlineHostDisplay];

  render() {
    const status = validated(this, "status");

    return html`
      <span
        class=${this.constructor.contract.className}
        part="badge"
        data-status=${status}
      >
        <span data-part="icon" part="icon">
          ${validated(this, "type") === "dot"
            ? html`<svg
                aria-hidden="true"
                width="16"
                height="16"
                viewBox="0 0 16 16"
                fill="none"
              >
                <rect
                  x="5"
                  y="5"
                  width="6"
                  height="6"
                  rx="1.33333"
                  fill="currentColor"
                ></rect>
              </svg>`
            : statusBadgeIcon(status)}
        </span>
        <span data-part="label" part="label"><slot>${this.label}</slot></span>
      </span>
    `;
  }
}

export class NooraHintText extends NooraElement {
  static contract = contract("noora-hint-text");
  static styles = [unsafeCSS(hintTextStyles), inlineHostDisplay];

  render() {
    return html`
      <div
        class=${this.constructor.contract.className}
        part="hint"
        data-variant=${validated(this, "variant")}
      >
        ${nooraIcon("alert_circle")}<span>${this.label}</span>
      </div>
    `;
  }
}

export class NooraIcon extends NooraElement {
  static contract = contract("noora-icon");
  static styles = [
    unsafeCSS(iconStyles),
    css`
      :host {
        display: inline-flex;
        line-height: 0;
      }
      [part="icon"] {
        position: relative;
        display: inline-flex;
      }
      [data-part="icon-layer"] {
        position: absolute;
        inset: 0;
        display: inline-flex;
        transition:
          opacity 160ms ease,
          transform 160ms ease;
      }
      [data-part="icon-layer"][data-layer="inactive"] {
        position: relative;
      }
      [data-active="false"] [data-layer="active"],
      [data-active="true"] [data-layer="inactive"] {
        opacity: 0;
        transform: rotate(-90deg) scale(0.8);
      }
      [data-active="false"] [data-layer="inactive"],
      [data-active="true"] [data-layer="active"] {
        opacity: 1;
        transform: rotate(0deg) scale(1);
      }
      svg {
        display: block;
        width: 100%;
        height: 100%;
      }
    `,
  ];

  #active = false;
  #stateObserver;

  connectedCallback() {
    super.connectedCallback();
    this.#observeParentState();
  }

  disconnectedCallback() {
    this.#stateObserver?.disconnect();
    super.disconnectedCallback();
  }

  render() {
    const icon = nooraIcon(normalizedIconName(this.name));
    return html`<span
      part="icon"
      role=${this.label ? "img" : nothing}
      aria-label=${ifDefined(this.label)}
      aria-hidden=${this.label ? nothing : "true"}
      data-active=${this.#active}
      data-transition=${validated(this, "transition")}
      style=${`width: var(--noora-icon-size, ${this.size}px); height: var(--noora-icon-size, ${this.size}px)`}
      >${this.activeName
        ? html`<span data-part="icon-layer" data-layer="inactive">${icon}</span>
            <span data-part="icon-layer" data-layer="active"
              >${nooraIcon(normalizedIconName(this.activeName))}</span
            >`
        : icon}</span
    >`;
  }

  #observeParentState() {
    this.#stateObserver?.disconnect();
    const parent = this.parentElement;
    if (!parent || !this.activeName) return;

    const updateState = () => {
      const active = parent.dataset.state === "open";
      if (active !== this.#active) {
        this.#active = active;
        this.requestUpdate();
      }
    };
    updateState();
    this.#stateObserver = new MutationObserver(updateState);
    this.#stateObserver.observe(parent, {
      attributes: true,
      attributeFilter: ["data-state"],
    });
  }
}

export class NooraLabel extends NooraElement {
  static contract = contract("noora-label");
  static styles = [unsafeCSS(labelStyles), inlineHostDisplay];

  render() {
    return html`
      <div
        class=${this.constructor.contract.className}
        ?disabled=${this.disabled}
      >
        <label part="label" for=${ifDefined(this.htmlFor)}>${this.label}</label>
        ${this.required
          ? html`<span data-part="required-indicator" aria-hidden="true"
              >*</span
            >`
          : nothing}
        ${this.sublabel
          ? html`<span data-part="sublabel" part="sublabel"
              >${this.sublabel}</span
            >`
          : nothing}
      </div>
    `;
  }
}

export class NooraLineDivider extends NooraElement {
  static contract = contract("noora-line-divider");
  static styles = [
    unsafeCSS(lineDividerStyles),
    hostDisplay,
    css`
      :host {
        width: 100%;
        min-width: 0;
      }
    `,
  ];

  render() {
    return html`
      <div class=${this.constructor.contract.className} part="divider">
        ${this.text
          ? html`<span data-part="text" part="text">${this.text}</span>`
          : nothing}
      </div>
    `;
  }
}

export class NooraTextDivider extends NooraElement {
  static contract = contract("noora-text-divider");
  static styles = [unsafeCSS(textDividerStyles), inlineHostDisplay];

  render() {
    return html`<span
      class=${this.constructor.contract.className}
      part="divider"
      >${this.text}</span
    >`;
  }
}

export class NooraShortcutKey extends NooraElement {
  static contract = contract("noora-shortcut-key");
  static styles = [unsafeCSS(shortcutKeyStyles), inlineHostDisplay];

  render() {
    return html`<kbd
      class=${this.constructor.contract.className}
      data-size=${validated(this, "size")}
      part="key"
      ><slot></slot
    ></kbd>`;
  }
}

export class NooraProgressBar extends NooraElement {
  static contract = contract("noora-progress-bar");
  static styles = [unsafeCSS(progressBarStyles), hostDisplay];

  render() {
    const max = Math.max(0, Number(this.max));
    const value = Math.max(0, Number(this.value));
    const percent = max === 0 ? 0 : Math.min((value / max) * 100, 100);

    return html`
      <div
        class=${this.constructor.contract.className}
        part="progress"
        role="progressbar"
        aria-valuemin="0"
        aria-valuemax=${max}
        aria-valuenow=${value}
      >
        ${this.title
          ? html`<div data-part="header">
              <span data-part="title">${this.title}</span>
              <span data-part="value">${value}</span>
              <span data-part="max-value">${max}</span>
            </div>`
          : nothing}
        <div data-part="progress-bar" part="track">
          <div data-part="max-bar"></div>
          <div
            data-part="value-bar"
            part="value"
            style=${`width: ${percent}%`}
          ></div>
        </div>
        <slot name="description"></slot>
      </div>
    `;
  }
}

export class NooraTime extends NooraElement {
  static contract = contract("noora-time");
  static styles = [unsafeCSS(timeStyles), inlineHostDisplay];

  render() {
    const date = new Date(this.datetime);
    if (Number.isNaN(date.valueOf())) return nothing;

    const absolute = new Intl.DateTimeFormat(undefined, {
      dateStyle: "long",
      ...(this.showTime ? { timeStyle: "medium" } : {}),
    }).format(date);
    const display = this.relative ? this.#relativeLabel(date) : absolute;

    return html`
      <div class=${this.constructor.contract.className}>
        ${this.relative
          ? html`
              <noora-tooltip title=${absolute}>
                <span slot="trigger" data-part="trigger">
                  <time part="time" datetime=${date.toISOString()}
                    >${display}</time
                  >
                </span>
              </noora-tooltip>
            `
          : html`<time part="time" datetime=${date.toISOString()}
              >${display}</time
            >`}
      </div>
    `;
  }

  #relativeLabel(date) {
    const seconds = Math.round((date.valueOf() - Date.now()) / 1000);
    const formatter = new Intl.RelativeTimeFormat(undefined, {
      numeric: "auto",
    });
    const units = [
      ["year", 31_536_000],
      ["month", 2_592_000],
      ["week", 604_800],
      ["day", 86_400],
      ["hour", 3_600],
      ["minute", 60],
      ["second", 1],
    ];
    const [unit, divisor] =
      units.find(([, candidate]) => Math.abs(seconds) >= candidate) ??
      units.at(-1);
    return formatter.format(Math.round(seconds / divisor), unit);
  }
}

export class NooraDismissIcon extends NooraElement {
  static contract = contract("noora-dismiss-icon");
  static styles = [unsafeCSS(dismissIconStyles), inlineHostDisplay];

  focus(options) {
    this.renderRoot?.querySelector("button")?.focus(options);
  }

  render() {
    return html`
      <button
        class=${this.constructor.contract.className}
        part="button"
        type="button"
        data-size=${validated(this, "size")}
        ?disabled=${this.disabled}
        aria-label=${this.label}
        @click=${() => this.emit("noora-dismiss")}
      >
        ${nooraIcon("close")}
      </button>
    `;
  }
}

export class NooraTag extends NooraElement {
  static contract = contract("noora-tag");
  static styles = [
    unsafeCSS(tagStyles),
    unsafeCSS(dismissIconStyles),
    inlineHostDisplay,
  ];

  render() {
    return html`
      <div
        class=${this.constructor.contract.className}
        part="tag"
        ?data-disabled=${this.disabled}
        aria-disabled=${this.disabled}
      >
        ${this.icon
          ? html`<div data-part="icon">
              <slot name="icon"
                >${nooraIcon(normalizedIconName(this.icon))}</slot
              >
            </div>`
          : html`<slot name="icon"></slot>`}
        <span data-part="label" part="label">${this.label}</span>
        ${this.dismissible
          ? html`<button
              class="noora-dismiss-icon"
              part="dismiss"
              data-part="dismiss-icon"
              data-size="small"
              type="button"
              ?disabled=${this.disabled}
              aria-label="Dismiss"
              @click=${this.#dismiss}
            >
              ${nooraIcon("close")}
            </button>`
          : nothing}
      </div>
    `;
  }

  #dismiss() {
    this.emit("noora-dismiss", { value: this.dismissValue });
  }
}

export class NooraCheckbox extends NooraFormElement {
  static contract = contract("noora-checkbox");
  static styles = [
    unsafeCSS(checkboxStyles),
    unsafeCSS(checkboxControlStyles),
    inlineHostDisplay,
    visuallyHidden,
  ];

  get control() {
    return this.renderRoot?.querySelector("input") ?? null;
  }

  formResetCallback() {
    this.checked = false;
    this.indeterminate = false;
  }

  updated() {
    const control = this.control;
    if (!control) return;
    control.indeterminate = this.indeterminate;
    this.setFormValue(this.checked ? this.value : null);
    this.setValidity(
      this.required && !this.checked ? { valueMissing: true } : {},
      this.required && !this.checked ? "Please select this option." : "",
      control,
    );
  }

  render() {
    const disabled = this.formControlDisabled;
    const state = this.indeterminate
      ? "indeterminate"
      : this.checked
        ? "checked"
        : "unchecked";

    return html`
      <div
        class=${this.constructor.contract.className}
        ?data-indeterminate=${this.indeterminate}
        ?data-disabled=${disabled}
      >
        <label data-part="root" part="root" ?data-disabled=${disabled}>
          <input
            class="visually-hidden"
            data-peer
            data-part="hidden-input"
            type="checkbox"
            name=${this.name}
            value=${this.value}
            .checked=${live(this.checked)}
            ?required=${this.required}
            ?disabled=${disabled}
            @input=${this.#handleInput}
            @change=${this.#handleChange}
          />
          <div
            class="noora-checkbox-control"
            data-part="control"
            part="control"
            data-state=${state}
            ?data-disabled=${disabled}
          >
            <div data-part="check">${nooraIcon("check")}</div>
            <div data-part="minus">${nooraIcon("minus")}</div>
          </div>
          <div>
            <span data-part="label" part="label">${this.label}</span>
            ${this.description
              ? html`<span data-part="description">${this.description}</span>`
              : nothing}
          </div>
        </label>
      </div>
    `;
  }

  #handleInput(event) {
    this.checked = event.currentTarget.checked;
    this.indeterminate = false;
    forwardFormEvent(this, event);
  }

  #handleChange(event) {
    forwardFormEvent(this, event);
  }
}

export class NooraToggle extends NooraFormElement {
  static contract = contract("noora-toggle");
  static styles = [unsafeCSS(toggleStyles), inlineHostDisplay, visuallyHidden];

  get control() {
    return this.renderRoot?.querySelector("input") ?? null;
  }

  formResetCallback() {
    this.checked = false;
  }

  updated() {
    this.setFormValue(this.checked ? this.value : null);
  }

  render() {
    const disabled = this.formControlDisabled;
    const state = this.checked ? "checked" : "unchecked";

    return html`
      <div
        class=${this.constructor.contract.className}
        ?data-checked=${this.checked}
        ?data-disabled=${disabled}
      >
        <label data-part="root" part="root" ?data-disabled=${disabled}>
          <input
            class="visually-hidden"
            data-peer
            data-part="hidden-input"
            type="checkbox"
            role="switch"
            name=${this.name}
            value=${this.value}
            .checked=${live(this.checked)}
            ?disabled=${disabled}
            @input=${this.#handleInput}
            @change=${this.#handleChange}
          />
          <div
            class="noora-toggle-control"
            data-state=${state}
            data-part="control"
            part="control"
            ?data-disabled=${disabled}
          >
            <div data-part="track">
              <div data-part="thumb"></div>
            </div>
          </div>
          ${this.label
            ? html`<div>
                <span data-part="label" part="label">${this.label}</span>
                ${this.description
                  ? html`<span data-part="description"
                      >${this.description}</span
                    >`
                  : nothing}
              </div>`
            : nothing}
        </label>
      </div>
    `;
  }

  #handleInput(event) {
    this.checked = event.currentTarget.checked;
    forwardFormEvent(this, event);
  }

  #handleChange(event) {
    forwardFormEvent(this, event);
  }
}

function labelTemplate(element, controlId) {
  if (!element.label) return nothing;

  return html`
    <div
      class="noora-label"
      data-part="label"
      ?disabled=${element.formControlDisabled ?? element.disabled}
    >
      <label for=${controlId}>${element.label}</label>
      ${element.required && element.showRequired
        ? html`<span data-part="required-indicator" aria-hidden="true">*</span>`
        : nothing}
      ${element.sublabel
        ? html`<span data-part="sublabel">${element.sublabel}</span>`
        : nothing}
    </div>
  `;
}

function hintTemplate(element, hintId) {
  const message = element.error ?? element.hint;
  if (!message) return nothing;
  const variant = element.error ? "destructive" : element.hintVariant;

  return html`
    <div id=${hintId} class="noora-hint-text" data-variant=${variant}>
      ${nooraIcon("alert_circle")}<span>${message}</span>
    </div>
  `;
}

export class NooraTextInput extends NooraFormElement {
  static contract = contract("noora-text-input");
  static styles = [
    unsafeCSS(textInputStyles),
    unsafeCSS(labelStyles),
    unsafeCSS(hintTextStyles),
    hostDisplay,
    css`
      input {
        box-sizing: border-box;
        margin: 0;
        padding: 0;
        min-width: 0;
      }
    `,
  ];

  #passwordVisible = false;
  #defaultValue = "";
  #hasDefaultValue = false;
  #controlId = generatedId("text-input");
  #hintId = generatedId("text-input-hint");

  connectedCallback() {
    super.connectedCallback();
    if (!this.#hasDefaultValue) {
      this.#defaultValue = this.value;
      this.#hasDefaultValue = true;
    }
  }

  get control() {
    return this.renderRoot?.querySelector("input") ?? null;
  }

  formResetCallback() {
    this.value = this.#defaultValue;
  }

  updated() {
    this.setFormValue(this.value);
    const control = this.control;
    if (!control) return;
    this.setValidity(
      control.validity.valid ? {} : { customError: true },
      control.validationMessage,
      control,
    );
  }

  focus(options) {
    this.control?.focus(options);
  }

  render() {
    const disabled = this.formControlDisabled;
    const semanticType = validated(this, "type");
    const nativeType =
      semanticType === "email"
        ? "email"
        : semanticType === "card_number"
          ? "tel"
          : semanticType === "password"
            ? this.#passwordVisible
              ? "text"
              : "password"
            : semanticType === "search"
              ? "search"
              : this.inputType;
    const iconName = {
      email: "mail",
      card_number: "credit_card",
      search: "search",
      password: "lock_password",
    }[semanticType];
    const hasCustomPrefix = this.querySelector('[slot="prefix"]') !== null;
    const hasCustomSuffix = this.querySelector('[slot="suffix"]') !== null;
    const showPrefix = Boolean(iconName) || hasCustomPrefix;
    const showSuffix =
      hasCustomSuffix ||
      ["card_number", "search", "password"].includes(semanticType);

    return html`
      <div class=${this.constructor.contract.className}>
        ${labelTemplate(this, this.#controlId)}
        <div
          data-part="wrapper"
          part="wrapper"
          data-type=${semanticType}
          ?data-error=${Boolean(this.error)}
          @click=${() => this.control?.focus()}
        >
          ${showPrefix
            ? html`<span data-part="prefix">
                <slot name="prefix"
                  >${iconName ? nooraIcon(iconName) : nothing}</slot
                >
              </span>`
            : nothing}
          <input
            id=${this.#controlId}
            part="input"
            name=${this.name}
            type=${nativeType}
            aria-describedby=${ifDefined(
              this.error || this.hint ? this.#hintId : undefined,
            )}
            aria-invalid=${ifDefined(this.error ? "true" : undefined)}
            .value=${live(this.value)}
            placeholder=${ifDefined(
              this.placeholder ??
                (semanticType === "password"
                  ? "• • • • • • • • • •"
                  : undefined),
            )}
            min=${ifDefined(this.min)}
            max=${ifDefined(this.max)}
            step=${ifDefined(this.step)}
            ?required=${this.required}
            ?disabled=${disabled}
            @input=${this.#handleInput}
            @change=${this.#handleChange}
          />
          ${showSuffix
            ? html`<span data-part="suffix" data-type=${semanticType}>
                <slot name="suffix">
                  ${semanticType === "password"
                    ? html`<button
                        type="button"
                        tabindex="-1"
                        ?disabled=${disabled}
                        aria-label=${this.#passwordVisible
                          ? "Hide password"
                          : "Show password"}
                        @click=${this.#togglePassword}
                      >
                        ${nooraIcon(this.#passwordVisible ? "eye_off" : "eye")}
                      </button>`
                    : semanticType === "search"
                      ? html`<kbd
                          class="noora-shortcut-key"
                          data-size="small"
                          aria-hidden="true"
                          >⌘K</kbd
                        >`
                      : semanticType === "card_number"
                        ? nooraIcon("custom_input_credit_card")
                        : nothing}
                </slot>
              </span>`
            : nothing}
        </div>
        ${hintTemplate(this, this.#hintId)}
      </div>
    `;
  }

  #handleInput(event) {
    this.value = event.currentTarget.value;
    forwardFormEvent(this, event);
  }

  #handleChange(event) {
    forwardFormEvent(this, event);
  }

  #togglePassword(event) {
    event.stopPropagation();
    this.#passwordVisible = !this.#passwordVisible;
    this.requestUpdate();
    queueMicrotask(() => this.control?.focus());
  }
}

export class NooraTextArea extends NooraFormElement {
  static contract = contract("noora-text-area");
  static styles = [
    unsafeCSS(textAreaStyles),
    unsafeCSS(labelStyles),
    unsafeCSS(hintTextStyles),
    hostDisplay,
  ];
  #controlId = generatedId("text-area");
  #hintId = generatedId("text-area-hint");

  get control() {
    return this.renderRoot?.querySelector("textarea") ?? null;
  }

  formResetCallback() {
    this.value = "";
  }

  updated() {
    this.setFormValue(this.value);
    const control = this.control;
    if (!control) return;
    this.setValidity(
      control.validity.valid ? {} : { customError: true },
      control.validationMessage,
      control,
    );
  }

  focus(options) {
    this.control?.focus(options);
  }

  render() {
    const disabled = this.formControlDisabled;
    return html`
      <div
        class=${this.constructor.contract.className}
        ?data-error=${Boolean(this.error)}
        ?disabled=${disabled}
      >
        ${labelTemplate(this, this.#controlId)}
        <div data-part="wrapper" @click=${() => this.control?.focus()}>
          <textarea
            id=${this.#controlId}
            part="textarea"
            name=${this.name}
            aria-describedby=${ifDefined(
              this.error || this.hint ? this.#hintId : undefined,
            )}
            aria-invalid=${ifDefined(this.error ? "true" : undefined)}
            rows=${this.rows}
            maxlength=${this.maxLength}
            placeholder=${ifDefined(this.placeholder)}
            style=${`resize: ${disabled ? "none" : validated(this, "resize")}`}
            .value=${live(this.value)}
            ?required=${this.required}
            ?disabled=${disabled}
            @input=${this.#handleInput}
            @change=${this.#handleChange}
          ></textarea>
          ${this.showCharacterCount
            ? html`<span data-part="character-count" part="character-count"
                >${this.value.length}/${this.maxLength}</span
              >`
            : nothing}
        </div>
        ${hintTemplate(this, this.#hintId)}
      </div>
    `;
  }

  #handleInput(event) {
    this.value = event.currentTarget.value;
    forwardFormEvent(this, event);
  }

  #handleChange(event) {
    forwardFormEvent(this, event);
  }
}

export class NooraDigitInput extends NooraFormElement {
  static contract = contract("noora-digit-input");
  static styles = [unsafeCSS(textInputStyles), hostDisplay];

  formResetCallback() {
    this.value = "";
  }

  updated() {
    this.setFormValue(this.value);
  }

  render() {
    const disabled = this.formControlDisabled;
    const length = Math.max(1, Math.min(32, this.characters));
    const values = Array.from(
      { length },
      (_, index) => this.value[index] ?? "",
    );
    const type = validated(this, "type");

    return html`
      <div
        class=${this.constructor.contract.className}
        data-type=${type}
        ?data-disabled=${disabled}
      >
        <div data-part="root" part="root">
          ${values.map(
            (value, index) => html`
              <input
                part="input"
                data-part="input"
                data-index=${index}
                ?data-error=${this.error}
                ?data-disabled=${disabled}
                type="text"
                inputmode=${type === "numeric" ? "numeric" : "text"}
                autocomplete=${this.oneTimeCode && index === 0
                  ? "one-time-code"
                  : "off"}
                maxlength="1"
                .value=${live(value)}
                placeholder=${this.placeholder}
                ?disabled=${disabled}
                @input=${(event) => this.#handleInput(event, index)}
                @keydown=${(event) => this.#handleKeydown(event, index)}
                @paste=${this.#handlePaste}
              />
            `,
          )}
        </div>
        <input
          class="visually-hidden"
          type="hidden"
          name=${this.name}
          .value=${this.value}
        />
      </div>
    `;
  }

  #accepts(value) {
    const type = validated(this, "type");
    if (type === "numeric") return /^\d*$/.test(value);
    if (type === "alphabetic") return /^[a-z]*$/i.test(value);
    return /^[a-z0-9]*$/i.test(value);
  }

  #handleInput(event, index) {
    event.stopPropagation();
    const input = event.currentTarget;
    const character = input.value.slice(-1);
    if (!this.#accepts(character)) {
      input.value = "";
      this.emit("noora-invalid", { value: character });
      return;
    }

    const values = [...this.value.padEnd(this.characters, " ")];
    values[index] = character || " ";
    this.value = values.join("").trimEnd();
    this.emit("noora-input", { value: this.value });
    this.dispatchEvent(
      new InputEvent("input", { bubbles: true, composed: true }),
    );

    if (character) {
      const next = input.nextElementSibling;
      next?.focus();
    }
    if (this.value.length === this.characters) {
      this.emit("noora-complete", { value: this.value });
      this.dispatchEvent(
        new Event("change", { bubbles: true, composed: true }),
      );
    }
  }

  #handleKeydown(event, index) {
    if (event.key !== "Backspace" || event.currentTarget.value) return;
    const previous = event.currentTarget.previousElementSibling;
    previous?.focus();
    if (index > 0) {
      const values = [...this.value];
      values[index - 1] = "";
      this.value = values.join("");
    }
  }

  #handlePaste = (event) => {
    event.preventDefault();
    const value = event.clipboardData.getData("text").slice(0, this.characters);
    if (!this.#accepts(value)) {
      this.emit("noora-invalid", { value });
      return;
    }
    this.value = value;
    this.emit("noora-input", { value });
    this.dispatchEvent(
      new InputEvent("input", { bubbles: true, composed: true }),
    );
    if (value.length === this.characters) {
      this.emit("noora-complete", { value });
      this.dispatchEvent(
        new Event("change", { bubbles: true, composed: true }),
      );
    }
  };
}

export class NooraSelect extends NooraFormElement {
  static contract = contract("noora-select");
  static styles = [
    unsafeCSS(dropdownStyles),
    unsafeCSS(selectStyles),
    unsafeCSS(hintTextStyles),
    hostDisplay,
    anchoredPopupPositioning,
  ];

  get control() {
    return this.renderRoot?.querySelector("select") ?? null;
  }

  #listboxId = generatedId("select-listbox");
  #hintId = generatedId("select-hint");
  #contentObserver;
  #handleDocumentClick = (event) => {
    if (this.open && !event.composedPath().includes(this)) {
      this.#setOpen(false);
    }
  };
  #handleDocumentKeydown = (event) => {
    if (this.open && event.key === "Escape") {
      this.#setOpen(false);
      this.renderRoot?.querySelector('[data-part="trigger"]')?.focus();
    }
  };

  connectedCallback() {
    super.connectedCallback();
    this.#contentObserver = new MutationObserver(() => this.requestUpdate());
    this.#contentObserver.observe(this, {
      attributes: true,
      childList: true,
      characterData: true,
      subtree: true,
    });
    document.addEventListener("click", this.#handleDocumentClick);
    document.addEventListener("keydown", this.#handleDocumentKeydown);
  }

  disconnectedCallback() {
    this.#contentObserver?.disconnect();
    document.removeEventListener("click", this.#handleDocumentClick);
    document.removeEventListener("keydown", this.#handleDocumentKeydown);
    super.disconnectedCallback();
  }

  formResetCallback() {
    this.value = "";
    this.#setOpen(false);
  }

  formDisabledCallback(disabled) {
    super.formDisabledCallback(disabled);
    if (disabled) this.#setOpen(false);
  }

  updated() {
    this.setFormValue(this.value);
    if (this.control) this.control.value = this.value;
    this.setValidity(
      this.required && !this.value ? { valueMissing: true } : {},
      this.required && !this.value ? "Please select an option." : "",
      this.renderRoot?.querySelector('[data-part="trigger"]'),
    );
  }

  render() {
    const disabled = this.formControlDisabled;
    const options = this.#options();
    const selected = options.find((option) => option.value === this.value);

    return html`
      <div class=${this.constructor.contract.className}>
        <select
          data-part="hidden-select"
          name=${this.name}
          tabindex="-1"
          aria-hidden="true"
          .value=${live(this.value)}
          ?disabled=${disabled}
          ?required=${this.required}
        >
          <option value=""></option>
          ${options.map(
            (option) => html`
              <option
                value=${option.value}
                ?disabled=${option.disabled}
                ?selected=${option.value === this.value}
              >
                ${option.label}
              </option>
            `,
          )}
        </select>
        <button
          data-part="trigger"
          part="select"
          type="button"
          ?disabled=${disabled}
          data-state=${this.open ? "open" : "closed"}
          aria-haspopup="listbox"
          aria-expanded=${this.open}
          aria-controls=${this.#listboxId}
          aria-describedby=${ifDefined(this.hint ? this.#hintId : undefined)}
          aria-invalid=${ifDefined(
            this.required && !this.value ? "true" : undefined,
          )}
          @click=${() => this.#setOpen(!this.open)}
          @keydown=${this.#handleTriggerKeydown}
        >
          <div data-part="label-wrapper">
            ${selected?.icon
              ? html`<div data-part="icon">
                  ${nooraIcon(normalizedIconName(selected.icon))}
                </div>`
              : nothing}
            <span data-part="label">${selected?.label ?? this.label}</span>
          </div>
          <div
            data-part="indicator"
            data-state=${this.open ? "open" : "closed"}
          >
            <div data-part="indicator-down">${nooraIcon("chevron_down")}</div>
            <div data-part="indicator-up">${nooraIcon("chevron_up")}</div>
          </div>
        </button>
        <div data-part="positioner" ?hidden=${!this.open}>
          <div
            class="noora-dropdown-content"
            data-part="content"
            part="content"
            data-state=${this.open ? "open" : "closed"}
          >
            <div
              id=${this.#listboxId}
              data-part="items"
              part="items"
              role="listbox"
              @keydown=${handlePopupItemKeydown}
            >
              ${options.map((option) =>
                menuItemTemplate(
                  option,
                  (selectedOption) => this.#selectOption(selectedOption),
                  {
                    role: "option",
                    selected: option.value === this.value,
                  },
                ),
              )}
            </div>
          </div>
        </div>
        ${this.hint
          ? html`<span id=${this.#hintId} data-part="hint" part="hint">
              ${nooraIcon("info_circle")}<span>${this.hint}</span>
            </span>`
          : nothing}
      </div>
    `;
  }

  #options() {
    const options = [...this.children].filter(
      (child) => child.localName === "option",
    );
    if (options.length === 0) return this.options;

    return options.map((option) => ({
      label: option.label || option.textContent.trim(),
      value: option.value,
      icon: option.dataset.icon,
      disabled: option.disabled,
    }));
  }

  #setOpen(open) {
    if ((open && this.formControlDisabled) || this.open === open) return;
    this.open = open;
    this.emit("noora-open-change", { open });
    if (open) {
      const selectedIndex = Math.max(
        0,
        this.#options().findIndex((option) => option.value === this.value),
      );
      this.updateComplete.then(() =>
        focusPopupItem(
          this.renderRoot.querySelector('[data-part="items"]'),
          selectedIndex,
        ),
      );
    } else {
      queueMicrotask(() =>
        this.renderRoot?.querySelector('[data-part="trigger"]')?.focus(),
      );
    }
  }

  #handleTriggerKeydown = (event) => {
    if (!["ArrowDown", "ArrowUp"].includes(event.key)) return;
    event.preventDefault();
    this.#setOpen(true);
    this.updateComplete.then(() => {
      const items = this.renderRoot.querySelector('[data-part="items"]');
      focusPopupItem(
        items,
        event.key === "ArrowUp" ? popupItemElements(items).length - 1 : 0,
      );
    });
  };

  #selectOption(option) {
    if (option.disabled) return;
    this.value = String(option.value ?? "");
    this.#setOpen(false);
    this.dispatchEvent(
      new InputEvent("input", { bubbles: true, composed: true }),
    );
    this.dispatchEvent(new Event("change", { bubbles: true, composed: true }));
    this.emit("noora-select", { item: option, value: this.value });
  }
}

function datePickerMonthTemplate(index, desktopOnly = false, disabled = false) {
  return html`
    <div
      data-part="month"
      part="month"
      data-index=${index}
      ?data-desktop-only=${desktopOnly}
    >
      <div data-part="view-control">
        <button
          type="button"
          data-part="prev-trigger"
          aria-label="Previous month"
          ?disabled=${disabled}
        >
          ${nooraIcon("chevron_left")}
        </button>
        <span data-part="view-trigger"></span>
        <button
          type="button"
          data-part="next-trigger"
          aria-label="Next month"
          ?disabled=${disabled}
        >
          ${nooraIcon("chevron_right")}
        </button>
      </div>
      <table data-part="table">
        <thead data-part="table-head">
          <tr data-part="table-row">
            ${Array.from(
              { length: 7 },
              () => html`<th data-part="table-header"></th>`,
            )}
          </tr>
        </thead>
        <tbody data-part="table-body">
          ${Array.from(
            { length: 6 },
            () => html`
              <tr data-part="table-row">
                ${Array.from(
                  { length: 7 },
                  () => html`
                    <td data-part="day-table-cell">
                      <button
                        type="button"
                        data-part="table-cell-trigger"
                        ?disabled=${disabled}
                      ></button>
                    </td>
                  `,
                )}
              </tr>
            `,
          )}
        </tbody>
      </table>
    </div>
  `;
}

function datePickerInputTemplate(type, disabled) {
  return html`
    <div data-part="date-display" data-type=${type} data-format="dmy">
      <input
        type="text"
        data-part="date-input"
        data-field="day"
        placeholder="DD"
        maxlength="2"
        ?disabled=${disabled}
      />
      <span data-part="date-separator">•</span>
      <input
        type="text"
        data-part="date-input"
        data-field="month"
        placeholder="MM"
        maxlength="2"
        ?disabled=${disabled}
      />
      <span data-part="date-separator">•</span>
      <input
        type="text"
        data-part="date-input"
        data-field="year"
        placeholder="YYYY"
        maxlength="4"
        ?disabled=${disabled}
      />
    </div>
  `;
}

let datePickerId = 0;

export class NooraDatePicker extends NooraPopupElement {
  static formAssociated = true;
  static contract = contract("noora-date-picker");
  static styles = [
    unsafeCSS(datePickerStyles),
    unsafeCSS(lineDividerStyles),
    unsafeCSS(buttonStyles),
    hostDisplay,
    css`
      slot[name="actions"] {
        display: contents;
      }
    `,
  ];

  closeOnInteractOutside = true;
  closeOnEscape = true;

  #controller = null;
  #controllerId = `noora-date-picker-${(datePickerId += 1)}`;
  #defaultEnd;
  #defaultSelectedPreset;
  #defaultStart;
  #formDisabled = false;
  #hasDefaultRange = false;
  #internals;

  constructor() {
    super();
    this.#internals = this.attachInternals?.();
  }

  connectedCallback() {
    super.connectedCallback();
    if (!this.#hasDefaultRange) {
      this.#defaultStart = this.start;
      this.#defaultEnd = this.end;
      this.#defaultSelectedPreset = this.selectedPreset;
      this.#hasDefaultRange = true;
    }
  }

  get form() {
    return this.#internals?.form ?? null;
  }

  get formControlDisabled() {
    return this.disabled || this.#formDisabled;
  }

  formDisabledCallback(disabled) {
    this.#formDisabled = disabled;
    if (disabled) this.open = false;
    this.requestUpdate();
  }

  formResetCallback() {
    this.start = this.#defaultStart;
    this.end = this.#defaultEnd;
    this.selectedPreset = this.#defaultSelectedPreset;
    this.open = false;
  }

  disconnectedCallback() {
    this.#controller?.destroy();
    this.#controller = null;
    super.disconnectedCallback();
  }

  updated(changedProperties) {
    this.#syncFormValue();

    if (!this.#controller) {
      this.#initializeController();
      return;
    }

    if (changedProperties.size === 1 && changedProperties.has("open")) {
      if (this.#controller.api.open !== this.open) {
        this.#controller.api.setOpen(this.open);
      }
      return;
    }

    this.#initializeController();
  }

  render() {
    const disabled = this.formControlDisabled;
    const presets = this.#presets();
    const selectedPreset = presets.find(
      (preset) => preset.id === this.selectedPreset,
    );
    const triggerLabel =
      selectedPreset?.label ??
      (this.start && this.end ? `${this.start} – ${this.end}` : this.label);

    return html`
      <div
        id=${this.id || this.#controllerId}
        class=${this.constructor.contract.className}
        data-open=${this.open ? "true" : "false"}
        data-start-of-week=${this.startOfWeek}
        data-min=${ifDefined(this.min)}
        data-max=${ifDefined(this.max)}
        data-selected-preset=${ifDefined(this.selectedPreset)}
        data-period-start=${ifDefined(this.start)}
        data-period-end=${ifDefined(this.end)}
        data-on-period-change="noora-period-change"
        data-on-cancel="noora-date-picker-cancel"
        ?data-disabled=${disabled}
      >
        <div data-part="control">
          <button
            data-part="trigger"
            part="trigger"
            type="button"
            ?disabled=${disabled}
          >
            <div data-part="trigger-icon">${nooraIcon("calendar_week")}</div>
            <span data-part="trigger-label">${triggerLabel}</span>
          </button>
        </div>

        <div data-part="positioner">
          <div data-part="content" part="content">
            <div data-part="presets" data-device="desktop">
              ${presets.map(
                (preset) => html`
                  <button
                    type="button"
                    data-part="preset-item"
                    data-preset-id=${preset.id}
                    ?data-selected=${this.selectedPreset === preset.id}
                    ?disabled=${disabled}
                  >
                    ${preset.label}
                  </button>
                `,
              )}
            </div>

            <div data-part="presets" data-device="mobile">
              ${presets.map(
                (preset) => html`
                  <button
                    type="button"
                    data-part="preset-item"
                    data-preset-id=${preset.id}
                    ?data-selected=${this.selectedPreset === preset.id}
                    ?disabled=${disabled}
                  >
                    ${preset.label}
                  </button>
                `,
              )}
            </div>

            <div data-part="calendar" part="calendar">
              <div data-part="months">
                ${datePickerMonthTemplate(0, false, disabled)}
                ${datePickerMonthTemplate(1, true, disabled)}
              </div>

              <div class="noora-line-divider"></div>

              <div data-part="footer">
                <div data-part="range-display">
                  ${datePickerInputTemplate("start", disabled)}
                  <div data-part="arrow">
                    ${nooraIcon("arrow_narrow_right")}
                  </div>
                  ${datePickerInputTemplate("end", disabled)}
                </div>
                <div data-part="actions" @click=${this.#handleAction}>
                  <slot name="actions">
                    <button
                      class="noora-button"
                      data-variant="secondary"
                      data-size="medium"
                      data-action="cancel"
                      type="button"
                      ?disabled=${disabled}
                    >
                      Cancel
                    </button>
                    <button
                      class="noora-button"
                      data-variant="primary"
                      data-size="medium"
                      data-action="apply"
                      type="button"
                      ?disabled=${disabled}
                    >
                      Apply
                    </button>
                  </slot>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    `;
  }

  #presets() {
    return childConfigurations(this, "noora-date-picker-preset", this.presets);
  }

  #initializeController() {
    this.#controller?.destroy();

    const root = this.renderRoot?.querySelector(".noora-date-picker");
    if (!root) return;

    const presets = this.#presets();
    const selectedPreset = presets.find(
      (preset) => preset.id === this.selectedPreset,
    );
    const controller = new DatePickerController(root, {
      id: root.id,
      getRootNode: () => root.getRootNode(),
      startOfWeek: this.startOfWeek,
      disabled: this.formControlDisabled,
      presets,
      selectedPreset: this.selectedPreset,
      periodStart: this.start ?? selectedPreset?.start,
      periodEnd: this.end ?? selectedPreset?.end,
      min: this.min,
      max: this.max,
      onOpenChange: ({ open }) => this.#handleOpenChange(open),
    });
    controller.pushEvent = (event, payload) =>
      this.#handleControllerEvent(event, payload);
    controller.init();
    controller.dateInputHandler = new DateInputHandler(root, {
      onDateChange: (parsed, type) =>
        controller.handleDateInputChange(parsed, type),
      getCurrentValue: () => controller.api.value,
      minDate: controller.minDate,
      maxDate: controller.maxDate,
    });
    controller.renderRangeDisplay();
    this.#controller = controller;
  }

  #handleOpenChange(open) {
    if (open && this.formControlDisabled) return;
    if (this.open === open) return;
    this.open = open;
    this.emit("noora-open-change", { open });
  }

  #handleControllerEvent(event, payload) {
    if (event === "noora-period-change") {
      this.start = toISODateString(new Date(payload.value.start));
      this.end = toISODateString(new Date(payload.value.end));
      this.selectedPreset = payload.preset;
      this.#syncFormValue();
      this.emit("noora-period-change", {
        start: this.start,
        end: this.end,
        preset: this.selectedPreset,
      });
    } else if (event === "noora-date-picker-cancel") {
      this.emit("noora-cancel");
    }
  }

  #handleAction = (event) => {
    if (this.formControlDisabled) return;

    const path = event.composedPath();
    const control =
      path.find(
        (element) => element instanceof HTMLElement && element.dataset.action,
      ) ?? path.find((element) => element instanceof HTMLButtonElement);
    if (!control) return;

    const action =
      control.dataset.action ?? control.textContent.trim().toLowerCase();
    if (action === "cancel") {
      this.#controller?.handleCancel();
    } else if (action === "apply") {
      this.#controller?.handleApply();
    }
  };

  #syncFormValue() {
    if (!this.name) {
      this.#internals?.setFormValue(null);
      return;
    }

    const selectedPreset = this.#presets().find(
      (preset) => preset.id === this.selectedPreset,
    );
    const value = new FormData();
    value.append(
      `${this.name}[start]`,
      this.start ?? selectedPreset?.start ?? "",
    );
    value.append(`${this.name}[end]`, this.end ?? selectedPreset?.end ?? "");
    this.#internals?.setFormValue(value);
  }
}

export class NooraFilter extends NooraElement {
  static contract = contract("noora-filter");
  static styles = [
    unsafeCSS(filterStyles),
    unsafeCSS(dropdownStyles),
    unsafeCSS(buttonStyles),
    unsafeCSS(textInputStyles),
    hostDisplay,
    css`
      .noora-filter-root,
      [data-part="active-filters"] {
        display: flex;
        flex-wrap: wrap;
        gap: var(--noora-spacing-3);
      }

      .noora-filter {
        position: relative;
      }

      .noora-filter > [data-part="dropdown"],
      .noora-filter > [data-part="popover"] {
        position: relative;
      }

      .noora-filter [data-part="trigger"] {
        border: 0;
        background: transparent;
        padding: 0;
        color: inherit;
        font: inherit;
      }

      .noora-filter [data-part="positioner"] {
        position: absolute;
        top: calc(100% + var(--noora-spacing-2));
        left: 0;
        z-index: var(--noora-z-index-10);
        min-width: max-content;
      }

      .noora-filter [data-control="value"] [data-part="positioner"] {
        right: 0;
        left: auto;
      }

      .noora-filter [data-part="content"] {
        min-width: 160px;
      }

      .noora-filter [data-part="popover"] [data-part="positioner"] {
        right: 0;
        left: auto;
      }

      .noora-filter [data-part="popover"] [data-part="content"] {
        min-width: 300px;
      }

      .noora-filter [data-part="popover"] [data-part="actions"] {
        display: flex;
        justify-content: flex-end;
        gap: var(--noora-spacing-3);
      }

      .noora-filter [data-part="search-input"] {
        box-sizing: border-box;
      }

      .noora-filter button:disabled {
        cursor: not-allowed;
      }

      .noora-filter-root > noora-dropdown {
        flex: none;
      }

      [hidden] {
        display: none !important;
      }

      .noora-filter [data-part="plain-input"] {
        display: flex;
        align-items: center;
        box-shadow: var(--noora-border-light-default);
        border-radius: var(--noora-radius-3);
        background: var(--noora-surface-background-primary);
        padding: var(--noora-spacing-3) var(--noora-spacing-4);
      }

      .noora-filter [data-part="plain-input"] input {
        flex-grow: 1;
        outline: none;
        border: 0;
        background: transparent;
        color: var(--noora-surface-label-primary);
        font: var(--noora-font-body-medium);
      }
    `,
  ];

  #filtersManaged = false;
  #openControl;
  #draftValues = new Map();
  #searchQueries = new Map();

  #handleDocumentClick = (event) => {
    if (this.#openControl && !event.composedPath().includes(this)) {
      this.#openControl = undefined;
      this.requestUpdate();
    }
  };

  #handleDocumentKeydown = (event) => {
    if (this.#openControl && event.key === "Escape") {
      this.#openControl = undefined;
      this.requestUpdate();
    }
  };

  connectedCallback() {
    super.connectedCallback();
    document.addEventListener("click", this.#handleDocumentClick);
    document.addEventListener("keydown", this.#handleDocumentKeydown);
  }

  disconnectedCallback() {
    document.removeEventListener("click", this.#handleDocumentClick);
    document.removeEventListener("keydown", this.#handleDocumentKeydown);
    super.disconnectedCallback();
  }

  render() {
    const definitions = this.#availableFilters();
    const filters = this.#filters();
    const activeIds = new Set(filters.map((filter) => filter.id));
    const availableFilters = definitions.filter(
      (filter) => !activeIds.has(filter.id),
    );

    return html`
      <div class="noora-filter-root" part="filter">
        <div data-part="active-filters" part="active-filters">
          ${filters.map((filter) => this.#activeFilter(filter))}
          ${availableFilters.length > 0
            ? html`
                <noora-dropdown
                  part="add"
                  label=${this.label}
                  ?disabled=${this.disabled}
                  .items=${availableFilters.map((filter) => ({
                    label: filter.label ?? filter.id,
                    value: filter.id,
                    size: "small",
                  }))}
                  @noora-select=${this.#add}
                >
                  <noora-icon slot="icon" name="filter"></noora-icon>
                </noora-dropdown>
              `
            : nothing}
        </div>
      </div>
    `;
  }

  #activeFilter(filter) {
    const operators = this.#operators(filter.type);

    return html`
      <div
        id=${filter.id}
        class=${this.constructor.contract.className}
        part="active-filter"
      >
        <span data-part="label">${filter.label ?? filter.id}</span>
        ${operators.length > 1
          ? this.#dropdown(
              filter,
              "operator",
              this.#operatorText(filter.operator),
              operators.map((operator) => ({
                value: operator,
                label: this.#operatorText(operator),
              })),
            )
          : html`<span data-part="label"
              >${this.#operatorText(filter.operator)}</span
            >`}
        ${filter.type === "option"
          ? this.#dropdown(
              filter,
              "value",
              filter.displayValue ?? this.#displayValue(filter),
              filter.options ?? [],
              true,
            )
          : this.#valuePopover(filter)}
        <button
          data-part="delete-icon"
          type="button"
          aria-label=${`Remove ${filter.label ?? filter.id} filter`}
          ?disabled=${this.disabled}
          @click=${() => this.#remove(filter.id)}
        >
          ${nooraIcon("trash")}
        </button>
      </div>
    `;
  }

  #dropdown(filter, kind, label, items, badge = false) {
    const key = `${filter.id}:${kind}`;
    const open = this.#openControl === key;
    const query = this.#searchQueries.get(key)?.toLowerCase() ?? "";
    const visibleItems =
      kind === "value" && filter.searchable && query
        ? items.filter((item) =>
            String(item.label ?? item.value)
              .toLowerCase()
              .includes(query),
          )
        : items;

    return html`
      <div data-part="dropdown" data-control=${kind}>
        <button
          data-part="trigger"
          type="button"
          aria-haspopup="menu"
          aria-expanded=${open}
          aria-controls=${`filter-menu-${key}`}
          ?disabled=${this.disabled}
          @click=${(event) => this.#toggleControl(event, key)}
          @keydown=${(event) => this.#handleControlKeydown(event, key)}
        >
          ${badge
            ? label
              ? html`<span data-part="badge">${label}</span>`
              : html`<span data-part="placeholder">Enter value</span>`
            : html`<span data-part="label">${label}</span>`}
          <div data-part="indicator" data-state=${open ? "open" : "closed"}>
            <div data-part="indicator-down">${nooraIcon("chevron_down")}</div>
            <div data-part="indicator-up">${nooraIcon("chevron_up")}</div>
          </div>
        </button>
        <div data-part="positioner" ?hidden=${!open}>
          <div
            class="noora-dropdown-content"
            data-part="content"
            data-state=${open ? "open" : "closed"}
          >
            ${kind === "value" && filter.searchable
              ? html`
                  <div data-part="search">
                    <input
                      data-part="search-input"
                      type="search"
                      placeholder="Search..."
                      .value=${this.#searchQueries.get(key) ?? ""}
                      @input=${(event) => {
                        this.#searchQueries.set(key, event.currentTarget.value);
                        this.requestUpdate();
                      }}
                    />
                  </div>
                `
              : nothing}
            <div
              id=${`filter-menu-${key}`}
              data-part="items"
              role="menu"
              @keydown=${handlePopupItemKeydown}
            >
              ${visibleItems.map((item) =>
                menuItemTemplate(
                  {
                    label: item.label ?? item.value,
                    value: item.value,
                    size: "small",
                  },
                  (selected) => this.#select(filter.id, kind, selected),
                ),
              )}
              ${visibleItems.length === 0
                ? html`<span data-part="search-empty">No results</span>`
                : nothing}
            </div>
          </div>
        </div>
      </div>
    `;
  }

  #valuePopover(filter) {
    const key = `${filter.id}:value`;
    const open = this.#openControl === key;
    const type =
      filter.type === "number" || filter.type === "percentage"
        ? "number"
        : "text";

    return html`
      <div data-part="popover">
        <button
          data-part="trigger"
          type="button"
          aria-expanded=${open}
          ?disabled=${this.disabled}
          @click=${(event) => this.#toggleValuePopover(event, filter)}
        >
          ${filter.value !== undefined &&
          filter.value !== null &&
          filter.value !== ""
            ? html`<span data-part="badge">${filter.value}</span>`
            : html`<span data-part="placeholder">Enter value</span>`}
          <div data-part="indicator">${nooraIcon("chevron_down")}</div>
        </button>
        <div data-part="positioner" ?hidden=${!open}>
          <div data-part="content" data-state=${open ? "open" : "closed"}>
            <span>Filter by ${filter.label ?? filter.id}</span>
            <div data-part="plain-input">
              <input
                type=${type}
                min=${ifDefined(
                  filter.type === "number" || filter.type === "percentage"
                    ? 0
                    : undefined,
                )}
                max=${ifDefined(filter.type === "percentage" ? 100 : undefined)}
                step=${ifDefined(
                  filter.type === "percentage"
                    ? 0.1
                    : filter.type === "number"
                      ? 1
                      : undefined,
                )}
                .value=${this.#draftValues.get(filter.id) ??
                String(filter.value ?? "")}
                @input=${(event) =>
                  this.#draftValues.set(filter.id, event.currentTarget.value)}
                @keydown=${(event) => {
                  if (event.key === "Enter") this.#applyDraft(filter.id);
                }}
              />
            </div>
            <div data-part="actions">
              <button
                class="noora-button"
                data-variant="secondary"
                data-size="medium"
                type="button"
                @click=${() => this.#closeControl()}
              >
                <span>Cancel</span>
              </button>
              <button
                class="noora-button"
                data-variant="primary"
                data-size="medium"
                type="button"
                @click=${() => this.#applyDraft(filter.id)}
              >
                <span>Apply</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    `;
  }

  #add = (event) => {
    const definition = this.#availableFilters().find(
      (filter) => filter.id === event.detail.value,
    );
    if (!definition) return;

    const value =
      definition.default ??
      definition.options?.[0]?.value ??
      definition.options?.[0] ??
      "";
    const option = definition.options?.find(
      (candidate) => candidate.value === value,
    );
    this.filters = [
      ...this.#filters(),
      {
        ...definition,
        operator:
          definition.operator ?? this.#operators(definition.type)[0] ?? "==",
        value,
        displayValue: option?.label,
      },
    ];
    this.#filtersManaged = true;
    this.#emitChange();
  };

  #remove(id) {
    this.filters = this.#filters().filter((filter) => filter.id !== id);
    this.#filtersManaged = true;
    this.#openControl = undefined;
    this.#emitChange();
  }

  #select(id, kind, item) {
    const filters = this.#filters().map((filter) => {
      if (filter.id !== id) return filter;
      if (kind === "operator") return { ...filter, operator: item.value };

      return {
        ...filter,
        value: item.value,
        displayValue: item.label,
      };
    });
    this.filters = filters;
    this.#filtersManaged = true;
    this.#openControl = undefined;
    this.#searchQueries.delete(`${id}:${kind}`);
    this.#emitChange();
  }

  #applyDraft(id) {
    const value = this.#draftValues.get(id) ?? "";
    this.filters = this.#filters().map((filter) =>
      filter.id === id ? { ...filter, value, displayValue: value } : filter,
    );
    this.#filtersManaged = true;
    this.#draftValues.delete(id);
    this.#openControl = undefined;
    this.#emitChange();
  }

  #toggleControl(event, key) {
    event.stopPropagation();
    this.#openControl = this.#openControl === key ? undefined : key;
    this.requestUpdate();
    if (this.#openControl === key) {
      this.updateComplete.then(() =>
        focusPopupItem(this.renderRoot.getElementById(`filter-menu-${key}`), 0),
      );
    }
  }

  #handleControlKeydown(event, key) {
    if (!["ArrowDown", "ArrowUp"].includes(event.key)) return;
    event.preventDefault();
    this.#openControl = key;
    this.requestUpdate();
    this.updateComplete.then(() => {
      const items = this.renderRoot.getElementById(`filter-menu-${key}`);
      focusPopupItem(
        items,
        event.key === "ArrowUp" ? popupItemElements(items).length - 1 : 0,
      );
    });
  }

  #toggleValuePopover(event, filter) {
    const key = `${filter.id}:value`;
    if (this.#openControl !== key) {
      this.#draftValues.set(filter.id, String(filter.value ?? ""));
    }
    this.#toggleControl(event, key);
  }

  #closeControl() {
    this.#openControl = undefined;
    this.requestUpdate();
  }

  #emitChange() {
    this.emit("noora-filter-change", { filters: this.filters });
  }

  #availableFilters() {
    return childConfigurations(
      this,
      "noora-filter-definition",
      this.availableFilters,
    );
  }

  #filters() {
    const rawFilters = this.#filtersManaged
      ? this.filters
      : childConfigurations(this, "noora-filter-value", this.filters);
    const definitions = this.#availableFilters();

    return rawFilters.map((filter) => {
      const definition = definitions.find(
        (candidate) => candidate.id === filter.id,
      );
      const type = filter.type ?? definition?.type ?? "option";
      const options = filter.options ?? definition?.options ?? [];
      const value = filter.value ?? definition?.default ?? "";
      const option = options.find((candidate) => candidate.value === value);

      return {
        ...definition,
        ...filter,
        label: filter.label ?? definition?.label ?? filter.id,
        type,
        operator:
          filter.operator ??
          definition?.operator ??
          this.#operators(type)[0] ??
          "==",
        options,
        searchable: filter.searchable ?? definition?.searchable ?? false,
        value,
        displayValue: filter.displayValue ?? option?.label,
      };
    });
  }

  #operators(type) {
    if (type === "text") return ["==", "=~", "!=~"];
    if (type === "number" || type === "percentage") {
      return ["==", "<", ">", "<=", ">="];
    }
    if (type === "list") return ["=~", "!=~"];
    return ["==", "!="];
  }

  #operatorText(operator) {
    return (
      {
        "==": "is",
        "!=": "is not",
        "=~": "contains",
        "!=~": "does not contain",
        "<": "less than",
        ">": "greater than",
        "<=": "less than or equal to",
        ">=": "greater than or equal to",
      }[operator] ?? operator
    );
  }

  #displayValue(filter) {
    return (
      filter.options?.find((option) => option.value === filter.value)?.label ??
      filter.value
    );
  }
}

export class NooraButtonGroup extends NooraElement {
  static contract = contract("noora-button-group");
  static styles = [
    unsafeCSS(buttonGroupStyles),
    inlineHostDisplay,
    css`
      :host {
        --noora-icon-size: var(--noora-icon-size-medium);
      }
      :host([size="small"]) {
        --noora-icon-size: var(--noora-icon-size-small);
      }
      :host([size="large"]) {
        --noora-icon-size: var(--noora-icon-size-large);
      }
      [data-size="small"] .noora-button-group-item {
        padding: var(--noora-spacing-3) var(--noora-spacing-4);
        font: var(--noora-font-weight-medium) var(--noora-font-body-xsmall);
      }
      [data-size="medium"] .noora-button-group-item {
        padding: var(--noora-spacing-2);
        font: var(--noora-font-weight-medium) var(--noora-font-body-small);
      }
      [data-size="large"] .noora-button-group-item {
        padding: var(--noora-spacing-2) var(--noora-spacing-4);
        font: var(--noora-font-weight-medium) var(--noora-font-body-medium);
      }
      .noora-button-group-item svg {
        width: var(--noora-icon-size);
        height: var(--noora-icon-size);
      }
    `,
  ];

  render() {
    const items = childConfigurations(
      this,
      "noora-button-group-item",
      this.items,
    );

    return html`
      <div
        class=${this.constructor.contract.className}
        part="group"
        data-size=${validated(this, "size")}
      >
        ${items.map((item, index) => this.#item(item, index))}
      </div>
    `;
  }

  #item(item, index) {
    const content = item.iconOnly
      ? nooraIcon(
          normalizedIconName(item.icon ?? item.iconLeft ?? item.iconRight),
        )
      : html`
          ${item.iconLeft
            ? nooraIcon(normalizedIconName(item.iconLeft))
            : nothing}
          <span data-part="label">${item.label}</span>
          ${item.iconRight
            ? nooraIcon(normalizedIconName(item.iconRight))
            : nothing}
        `;
    const select = () =>
      this.emit("noora-select", {
        item,
        index,
        value: item.value ?? item.label,
      });

    if (item.href && !item.disabled) {
      return html`
        <a
          class="noora-button-group-item"
          part="item"
          href=${item.href}
          ?data-icon-only=${item.iconOnly}
          ?data-selected=${item.selected}
          aria-label=${ifDefined(item.ariaLabel)}
          @click=${select}
        >
          ${content}
        </a>
      `;
    }

    return html`
      <button
        class="noora-button-group-item"
        part="item"
        type="button"
        ?data-icon-only=${item.iconOnly}
        ?data-selected=${item.selected}
        ?disabled=${item.disabled}
        aria-label=${ifDefined(item.ariaLabel)}
        @click=${select}
      >
        ${content}
      </button>
    `;
  }
}

export class NooraCard extends NooraElement {
  static contract = contract("noora-card");
  static styles = [
    unsafeCSS(cardStyles),
    hostDisplay,
    css`
      slot[name="section"] {
        display: contents;
      }
      slot[name="section"]::slotted(*) {
        display: flex;
        position: relative;
        flex-direction: column;
        gap: var(--noora-spacing-5);
        box-sizing: border-box;
        box-shadow: var(--noora-border-light-default);
        border-radius: var(--noora-radius-4);
        background: var(--noora-surface-background-primary);
        padding: var(--noora-spacing-7);
        color: var(--noora-surface-label-primary);
      }
    `,
  ];

  #contentObserver;

  connectedCallback() {
    super.connectedCallback();
    this.#contentObserver = new MutationObserver(() => this.requestUpdate());
    this.#contentObserver.observe(this, { childList: true });
  }

  disconnectedCallback() {
    this.#contentObserver?.disconnect();
    super.disconnectedCallback();
  }

  render() {
    return html`
      <section class=${this.constructor.contract.className} part="card">
        <header data-part="header" part="header">
          <div data-part="icon-with-title">
            <div data-part="icon">
              <slot name="icon"
                >${this.icon
                  ? nooraIcon(normalizedIconName(this.icon))
                  : nothing}</slot
              >
            </div>
            <span data-part="title">${this.title}</span>
          </div>
          <div data-part="actions"><slot name="actions"></slot></div>
        </header>
        <slot name="section"></slot>
        ${this.#hasDefaultContent()
          ? html`<div class="noora-card__section" part="body">
              <slot></slot>
            </div>`
          : nothing}
      </section>
    `;
  }

  #hasDefaultContent() {
    return [...this.childNodes].some((node) => {
      if (node.nodeType === Node.TEXT_NODE) {
        return node.textContent.trim() !== "";
      }
      return node.nodeType === Node.ELEMENT_NODE && !node.hasAttribute("slot");
    });
  }
}

export class NooraChart extends NooraElement {
  static contract = contract("noora-chart");
  static styles = [
    unsafeCSS(chartStyles),
    hostDisplay,
    css`
      :host {
        height: var(--noora-chart-height, 180px);
        min-width: 0;
      }
      [part="container"] {
        width: 100%;
        height: 100%;
      }
      [data-part="chart"] {
        width: 100%;
        height: 100%;
      }
    `,
  ];

  chart = null;
  #resizeObserver;
  #colorSchemeListener = () => {
    this.chart?.dispose();
    this.chart = null;
    this.requestUpdate();
  };

  connectedCallback() {
    super.connectedCallback();
    this.#resizeObserver = new ResizeObserver(() => this.chart?.resize());
    this.#resizeObserver.observe(this);
    window.addEventListener(
      "changed-preferred-theme",
      this.#colorSchemeListener,
    );
  }

  disconnectedCallback() {
    this.#resizeObserver?.disconnect();
    window.removeEventListener(
      "changed-preferred-theme",
      this.#colorSchemeListener,
    );
    this.chart?.dispose();
    this.chart = null;
    super.disconnectedCallback();
  }

  updated(changedProperties) {
    if (changedProperties.has("renderer") && this.chart) {
      this.chart.dispose();
      this.chart = null;
    }
    this.#renderChart();
  }

  render() {
    return html`
      <figure class=${this.constructor.contract.className} part="container">
        <div
          data-part="chart"
          part="chart"
          role="img"
          aria-label=${ifDefined(this._ariaLabel)}
        ></div>
      </figure>
    `;
  }

  #renderChart() {
    const container = this.renderRoot?.querySelector('[data-part="chart"]');
    if (!container) return;

    const options = prepareChartOptions(this.#configuration(), this);
    const theme = getNooraChartTheme(options);
    if (this.chart) options.color = theme.color;
    if (!this.chart) {
      echarts.registerTheme("noora", theme);
      this.chart = echarts.init(container, "noora", {
        renderer: validated(this, "renderer"),
      });
      this.chart.on("click", (parameters) => {
        const item = parameters.data;
        const shouldNavigate = this.emit(
          "noora-chart-select",
          { item, parameters },
          { cancelable: true },
        );
        if (shouldNavigate && item?.url) window.location.assign(item.url);
      });
    }
    this.chart.setOption(options, { notMerge: true });
  }

  #configuration() {
    const childNames = new Set([
      "noora-chart-grid",
      "noora-chart-axis",
      "noora-chart-series",
    ]);
    const hasDeclarativeConfiguration = [...this.children].some((child) =>
      childNames.has(child.localName),
    );
    if (!hasDeclarativeConfiguration) return this.options;

    const grid = childConfigurations(this, "noora-chart-grid")[0];
    const axes = childConfigurations(this, "noora-chart-axis");
    const series = childConfigurations(this, "noora-chart-series");
    const axisOptions = (dimension) => {
      const options = axes.find(
        (axis) => axis.dimension === dimension,
      )?.options;
      if (!options) return undefined;

      return {
        ...options,
        axisLabel: {
          fontSize: 10,
          ...options.axisLabel,
        },
        splitLine: options.splitLine ?? {
          lineStyle: { type: "dashed" },
        },
        axisLine: options.axisLine ?? { show: false },
        axisTick: options.axisTick ?? { show: false },
      };
    };

    return {
      colors: [
        "var:noora-chart-primary",
        "var:noora-chart-secondary",
        "var:noora-chart-tertiary",
        "var:noora-chart-quaternary",
      ],
      series: series.map((item) => ({
        label: { show: false },
        name: "",
        stack: null,
        ...item,
      })),
      yAxis: axisOptions("y"),
      xAxis: axisOptions("x"),
      tooltip: {
        show: !this.hideTooltip,
        trigger: this.tooltipTrigger,
      },
      grid: {
        containLabel: true,
        ...grid,
      },
      legend: this.hideLegend ? { show: false } : { left: "center", top: "0" },
      textStyle: {
        fontFamily: "Geist Mono",
      },
    };
  }
}

function paginationItems(currentPage, numberOfPages) {
  const siblingCount = 1;
  const totalPageNumbers = Math.min(2 * siblingCount + 5, numberOfPages);
  const leftSibling = Math.max(currentPage - siblingCount, 1);
  const rightSibling = Math.min(currentPage + siblingCount, numberOfPages);
  const showLeft = leftSibling > 2;
  const showRight = rightSibling < numberOfPages - 1;
  const itemCount = totalPageNumbers - 2;

  if (!showLeft && showRight) {
    return [
      ...Array.from({ length: itemCount }, (_, index) => index + 1),
      "ellipsis",
      numberOfPages,
    ];
  }
  if (showLeft && !showRight) {
    return [
      1,
      "ellipsis",
      ...Array.from(
        { length: itemCount },
        (_, index) => numberOfPages - itemCount + index + 1,
      ),
    ];
  }
  if (showLeft && showRight) {
    return [
      1,
      "ellipsis",
      ...Array.from(
        { length: rightSibling - leftSibling + 1 },
        (_, index) => leftSibling + index,
      ),
      "ellipsis",
      numberOfPages,
    ];
  }
  return Array.from({ length: numberOfPages }, (_, index) => index + 1);
}

export class NooraPaginationGroup extends NooraElement {
  static contract = contract("noora-pagination-group");
  static styles = [
    unsafeCSS(paginationStyles),
    unsafeCSS(buttonStyles),
    inlineHostDisplay,
  ];

  render() {
    const pageCount = Number.isFinite(this.numberOfPages)
      ? Math.max(1, Math.trunc(this.numberOfPages))
      : 1;
    const requestedPage = Number.isFinite(this.currentPage)
      ? Math.trunc(this.currentPage)
      : 1;
    const currentPage = Math.max(1, Math.min(requestedPage, pageCount));
    const pages = paginationItems(currentPage, pageCount);

    return html`
      <nav
        class=${this.constructor.contract.className}
        part="pagination"
        aria-label="Pagination"
      >
        ${this.#control(
          currentPage - 1,
          "Previous page",
          "previous",
          currentPage === 1,
          "chevron_left",
        )}
        ${pages.map((page) =>
          page === "ellipsis"
            ? html`<span data-part="ellipsis" aria-hidden="true">...</span>`
            : html`<a
                part="page"
                data-part="page-button"
                ?data-selected=${currentPage === page}
                aria-current=${currentPage === page ? "page" : nothing}
                href=${this.#href(page)}
                @click=${(event) => this.#select(event, page)}
              >
                <span data-part="label">${page}</span>
              </a>`,
        )}
        ${this.#control(
          currentPage + 1,
          "Next page",
          "next",
          currentPage === pageCount,
          "chevron_right",
        )}
      </nav>
    `;
  }

  #control(page, label, part, disabled, icon) {
    return html`<button
      class="noora-neutral-button"
      part=${part}
      data-size="large"
      type="button"
      ?disabled=${disabled}
      aria-label=${label}
      @click=${(event) => this.#select(event, page)}
    >
      ${nooraIcon(icon)}
    </button>`;
  }

  #href(page) {
    return this.hrefTemplate?.replaceAll("{page}", String(page)) ?? "#";
  }

  #select(event, page) {
    if (!this.hrefTemplate) event.preventDefault();
    this.currentPage = page;
    this.emit("noora-page-change", { page });
  }
}

export class NooraTable extends NooraElement {
  static contract = contract("noora-table");
  static styles = [
    unsafeCSS(tableStyles),
    hostDisplay,
    css`
      :host {
        width: 100%;
      }
    `,
  ];

  render() {
    const columns = childConfigurations(
      this,
      "noora-table-column",
      this.columns,
    );
    const rows = childConfigurations(this, "noora-table-row", this.rows);

    return html`
      <div class=${this.constructor.contract.className}>
        <div data-part="scroll-container">
          <table part="table">
            <thead>
              <tr>
                ${columns.map(
                  (column) =>
                    html`<th>
                      <span>${column.label ?? column.key}</span>
                      ${column.icon
                        ? html`<span data-part="icon"
                            >${nooraIcon(normalizedIconName(column.icon))}</span
                          >`
                        : nothing}
                      ${column.sortOrder
                        ? html`<span
                            data-part="icon"
                            data-state=${column.sortOrder}
                          >
                            ${nooraIcon(
                              column.sortOrder === "asc"
                                ? "square_rounded_arrow_up"
                                : "square_rounded_arrow_down",
                            )}
                          </span>`
                        : nothing}
                    </th>`,
                )}
              </tr>
            </thead>
            <tbody>
              ${rows.map(
                (row, index) => html`
                  <tr
                    part="row"
                    data-row-key=${row[this.rowKey] ?? index}
                    ?data-selectable=${this.selectable}
                    tabindex=${this.selectable ? "0" : nothing}
                    @click=${() => this.#selectRow(row, index)}
                    @keydown=${(event) =>
                      this.#handleRowKeydown(event, row, index)}
                  >
                    ${columns.map(
                      (column) =>
                        html`<td
                          part="cell"
                          ?data-selectable=${this.selectable}
                        >
                          ${this.#cellValue(row[column.key], column)}
                        </td>`,
                    )}
                  </tr>
                `,
              )}
              ${rows.length === 0
                ? html`<tr>
                    <td colspan=${Math.max(1, columns.length)}>
                      <slot name="empty">${this.emptyTitle}</slot>
                    </td>
                  </tr>`
                : nothing}
            </tbody>
          </table>
        </div>
      </div>
    `;
  }

  #cellValue(value, column) {
    let formattedValue = value;
    if (column.format === "date" && value) {
      formattedValue = new Intl.DateTimeFormat().format(new Date(value));
    }
    if (column.format === "number" && value !== undefined) {
      formattedValue = new Intl.NumberFormat().format(value);
    }
    if (value === null || value === undefined) formattedValue = "";
    if (typeof formattedValue === "object") {
      formattedValue = JSON.stringify(formattedValue);
    }

    return html`
      <div data-part="cell" data-type="text">
        <span data-part="label">${String(formattedValue)}</span>
      </div>
    `;
  }

  #handleRowKeydown(event, row, index) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.#selectRow(row, index);
    }
  }

  #selectRow(row, index) {
    if (this.selectable) this.emit("noora-row-select", { row, index });
  }
}

class NooraCompactButton extends NooraElement {
  focus(options) {
    this.renderRoot?.querySelector("a, button")?.focus(options);
  }

  click() {
    this.renderRoot?.querySelector("a, button")?.click();
  }
}

const compactButtonIconStyles = css`
  :host {
    --noora-icon-size: var(--noora-icon-size-large);
  }
  :host([size="small"]) {
    --noora-icon-size: var(--noora-icon-size-small);
  }
  :host([size="medium"]) {
    --noora-icon-size: var(--noora-icon-size-medium);
  }
`;

export class NooraNeutralButton extends NooraCompactButton {
  static contract = contract("noora-neutral-button");
  static styles = [
    unsafeCSS(buttonStyles),
    inlineHostDisplay,
    compactButtonIconStyles,
  ];

  render() {
    const content = this.label
      ? html`
          <slot name="icon-left"></slot>
          <span data-part="label">${this.label}</span>
          <slot name="icon-right"></slot>
        `
      : html`<slot></slot>`;
    if (this.href && !this.disabled) {
      return html`<a
        class=${this.constructor.contract.className}
        part="control"
        data-size=${validated(this, "size")}
        ?data-with-label=${Boolean(this.label)}
        href=${this.href}
        aria-label=${ifDefined(this._ariaLabel)}
        >${content}</a
      >`;
    }

    return html`<button
      class=${this.constructor.contract.className}
      part="control"
      data-size=${validated(this, "size")}
      ?data-with-label=${Boolean(this.label)}
      type="button"
      ?disabled=${this.disabled}
      aria-label=${ifDefined(this._ariaLabel)}
    >
      ${content}
    </button>`;
  }
}

export class NooraLinkButton extends NooraCompactButton {
  static contract = contract("noora-link-button");
  static styles = [
    unsafeCSS(buttonStyles),
    inlineHostDisplay,
    compactButtonIconStyles,
  ];

  render() {
    const content = html`
      <slot name="icon-left"></slot>
      <span>${this.label}</span>
      <slot name="icon-right"></slot>
    `;

    if (this.href && !this.disabled) {
      return html`<a
        class=${this.constructor.contract.className}
        part="control"
        data-variant=${validated(this, "variant")}
        data-size=${validated(this, "size")}
        ?data-underline=${this.underline}
        href=${this.href}
        >${content}</a
      >`;
    }

    return html`<button
      class=${this.constructor.contract.className}
      part="control"
      data-variant=${validated(this, "variant")}
      data-size=${validated(this, "size")}
      ?data-underline=${this.underline}
      type="button"
      ?disabled=${this.disabled}
    >
      ${content}
    </button>`;
  }
}

class NooraMenuElement extends NooraPopupElement {
  closeOnInteractOutside = true;
  closeOnEscape = true;
  menuId = generatedId("menu");
  #contentObserver;

  connectedCallback() {
    super.connectedCallback();
    this.#contentObserver = new MutationObserver(() => this.requestUpdate());
    this.#contentObserver.observe(this, {
      childList: true,
      attributes: true,
      attributeFilter: ["slot"],
    });
  }

  disconnectedCallback() {
    this.#contentObserver?.disconnect();
    super.disconnectedCallback();
  }

  selectItem(item) {
    this.emit("noora-select", {
      item,
      value: item.value ?? item.label,
    });
    if (!this.keepOpen && this.closeOnSelect !== false) this.setOpen(false);
  }

  setOpen(open) {
    const changed = this.open !== open;
    super.setOpen(open);
    if (changed && open) {
      this.updateComplete.then(() =>
        focusPopupItem(this.renderRoot.querySelector('[data-part="items"]'), 0),
      );
    } else if (changed) {
      queueMicrotask(() =>
        this.renderRoot?.querySelector('[data-part="trigger"]')?.focus(),
      );
    }
  }

  handleTriggerKeydown(event) {
    if (!["ArrowDown", "ArrowUp"].includes(event.key)) return;
    event.preventDefault();
    this.setOpen(true);
    this.updateComplete.then(() => {
      const items = this.renderRoot.querySelector('[data-part="items"]');
      focusPopupItem(
        items,
        event.key === "ArrowUp" ? popupItemElements(items).length - 1 : 0,
      );
    });
  }
}

export class NooraDropdown extends NooraMenuElement {
  static contract = contract("noora-dropdown");
  static styles = [
    unsafeCSS(dropdownStyles),
    unsafeCSS(checkboxControlStyles),
    hostDisplay,
    anchoredPopupPositioning,
  ];

  render() {
    const items = childConfigurations(this, "noora-dropdown-item", this.items);
    const hasIcon = this.querySelector('[slot="icon"]') !== null;
    const hasSearch = this.querySelector('[slot="search"]') !== null;

    return html`
      <div
        class=${this.constructor.contract.className}
        data-size=${validated(this, "size")}
      >
        <button
          data-part="trigger"
          part="trigger"
          type="button"
          ?data-icon-only=${this.iconOnly}
          ?disabled=${this.disabled}
          data-state=${this.open ? "open" : "closed"}
          aria-label=${ifDefined(
            this.iconOnly
              ? this.getAttribute("aria-label") || this.label
              : undefined,
          )}
          aria-haspopup="menu"
          aria-expanded=${this.open}
          aria-controls=${this.menuId}
          @click=${() => this.toggleOpen()}
          @keydown=${this.handleTriggerKeydown}
        >
          ${this.iconOnly
            ? html`<div data-part="icon"><slot name="icon"></slot></div>`
            : html`
                <div data-part="label-wrapper">
                  ${hasIcon
                    ? html`<div data-part="icon">
                        <slot name="icon"></slot>
                      </div>`
                    : nothing}
                  ${this.secondaryText
                    ? html`<span data-part="secondary-text"
                        >${this.secondaryText}</span
                      >`
                    : nothing}
                  <span data-part="label">${this.label}</span>
                </div>
                <div
                  data-part="indicator"
                  data-state=${this.open ? "open" : "closed"}
                >
                  <div data-part="indicator-down">
                    ${nooraIcon("chevron_down")}
                  </div>
                  <div data-part="indicator-up">${nooraIcon("chevron_up")}</div>
                </div>
              `}
        </button>
        <div data-part="positioner" ?hidden=${!this.open}>
          <div
            class="noora-dropdown-content"
            data-part="content"
            part="content"
            data-state=${this.open ? "open" : "closed"}
          >
            ${hasSearch
              ? html`<div data-part="search">
                  <slot name="search"></slot>
                </div>`
              : nothing}
            <div
              id=${this.menuId}
              data-part="items"
              part="items"
              role="menu"
              @keydown=${handlePopupItemKeydown}
            >
              ${items.map((item) =>
                menuItemTemplate(item, (selected) => this.selectItem(selected)),
              )}
              <slot></slot>
            </div>
          </div>
        </div>
        ${this.hint
          ? html`<span data-part="hint">
              ${nooraIcon("info_circle")}<span>${this.hint}</span>
            </span>`
          : nothing}
      </div>
    `;
  }
}

export class NooraInlineDropdown extends NooraMenuElement {
  static contract = contract("noora-inline-dropdown");
  static styles = [
    unsafeCSS(dropdownStyles),
    unsafeCSS(checkboxControlStyles),
    inlineHostDisplay,
    anchoredPopupPositioning,
    css`
      .noora-inline-dropdown {
        position: relative;
      }
    `,
  ];

  render() {
    const items = childConfigurations(this, "noora-dropdown-item", this.items);
    const hasIcon = this.querySelector('[slot="icon"]') !== null;

    return html`
      <div
        class=${this.constructor.contract.className}
        data-size=${validated(this, "size")}
      >
        <button
          data-part="trigger"
          part="trigger"
          type="button"
          data-state=${this.open ? "open" : "closed"}
          ?disabled=${this.disabled}
          aria-haspopup="menu"
          aria-expanded=${this.open}
          aria-controls=${this.menuId}
          @click=${() => this.toggleOpen()}
          @keydown=${this.handleTriggerKeydown}
        >
          ${hasIcon
            ? html`<div data-part="icon"><slot name="icon"></slot></div>`
            : nothing}
          <span data-part="label">${this.label}</span>
          <div
            data-part="indicator"
            data-state=${this.open ? "open" : "closed"}
          >
            <div data-part="indicator-down">${nooraIcon("chevron_down")}</div>
            <div data-part="indicator-up">${nooraIcon("chevron_up")}</div>
          </div>
        </button>
        <div data-part="positioner" ?hidden=${!this.open}>
          <div
            class="noora-dropdown-content"
            data-part="content"
            part="content"
            data-state=${this.open ? "open" : "closed"}
          >
            <div
              id=${this.menuId}
              data-part="items"
              role="menu"
              @keydown=${handlePopupItemKeydown}
            >
              ${items.map((item) =>
                menuItemTemplate(item, (selected) => this.selectItem(selected)),
              )}
              <slot></slot>
            </div>
          </div>
        </div>
      </div>
    `;
  }
}

export class NooraButtonDropdown extends NooraMenuElement {
  static contract = contract("noora-button-dropdown");
  static styles = [
    unsafeCSS(buttonDropdownStyles),
    unsafeCSS(dropdownStyles),
    unsafeCSS(checkboxControlStyles),
    inlineHostDisplay,
    compactButtonIconStyles,
  ];

  render() {
    const items = childConfigurations(this, "noora-dropdown-item", this.items);

    return html`
      <div
        class=${this.constructor.contract.className}
        data-size=${validated(this, "size")}
        data-align=${validated(this, "align")}
      >
        <button
          data-part="main-button"
          part="main-button"
          type="button"
          ?disabled=${this.disabled}
          @click=${() => this.emit("noora-action")}
        >
          <div data-part="icon-left"><slot name="icon-left"></slot></div>
          <span data-part="label">${this.label}</span>
          <div data-part="icon-right"><slot name="icon-right"></slot></div>
        </button>
        <button
          data-part="trigger"
          part="trigger"
          type="button"
          data-state=${this.open ? "open" : "closed"}
          ?disabled=${this.disabled}
          aria-label=${`${this.label} menu`}
          aria-haspopup="menu"
          aria-expanded=${this.open}
          aria-controls=${this.menuId}
          @click=${() => this.toggleOpen()}
          @keydown=${this.handleTriggerKeydown}
        >
          <div data-part="indicator">${nooraIcon("chevron_down")}</div>
        </button>
        <div data-part="positioner" ?hidden=${!this.open}>
          <div
            class="noora-dropdown-content"
            data-part="content"
            part="content"
            data-state=${this.open ? "open" : "closed"}
          >
            <div
              id=${this.menuId}
              data-part="items"
              role="menu"
              @keydown=${handlePopupItemKeydown}
            >
              ${items.map((item) =>
                menuItemTemplate(item, (selected) => this.selectItem(selected)),
              )}
              <slot></slot>
            </div>
          </div>
        </div>
      </div>
    `;
  }
}

export class NooraBreadcrumbs extends NooraElement {
  static contract = contract("noora-breadcrumbs");
  static styles = [
    unsafeCSS(breadcrumbsStyles),
    unsafeCSS(dropdownStyles),
    unsafeCSS(avatarStyles),
    unsafeCSS(buttonStyles),
    hostDisplay,
    css`
      [data-part="menu-anchor"] {
        display: inline-flex;
        position: relative;
      }
      [data-part="positioner"] {
        position: absolute;
        top: calc(100% + var(--noora-spacing-4));
        left: 0;
      }
    `,
  ];

  #openIndex = -1;
  #handleDocumentClick = (event) => {
    if (this.#openIndex >= 0 && !event.composedPath().includes(this)) {
      this.#closeMenu();
    }
  };
  #handleDocumentKeydown = (event) => {
    if (this.#openIndex >= 0 && event.key === "Escape") {
      this.#closeMenu();
    }
  };

  connectedCallback() {
    super.connectedCallback();
    document.addEventListener("click", this.#handleDocumentClick);
    document.addEventListener("keydown", this.#handleDocumentKeydown);
  }

  disconnectedCallback() {
    document.removeEventListener("click", this.#handleDocumentClick);
    document.removeEventListener("keydown", this.#handleDocumentKeydown);
    super.disconnectedCallback();
  }

  render() {
    const styleVariant = validated(this, "style-variant");
    const items = childConfigurations(
      this,
      "noora-breadcrumb-item",
      this.items,
    );

    return html`
      <nav
        class=${this.constructor.contract.className}
        part="breadcrumbs"
        data-style=${styleVariant}
        aria-label="Breadcrumb"
      >
        ${items.map(
          (item, index) => html`
            ${this.#breadcrumb(item, index)}
            ${index < items.length - 1
              ? html`
                  <div data-part="slash" aria-hidden="true">
                    ${nooraIcon("slash")}
                  </div>
                  <div data-part="arrow" aria-hidden="true">
                    ${nooraIcon("chevron_right")}
                  </div>
                `
              : nothing}
          `,
        )}
        <slot></slot>
      </nav>
    `;
  }

  #breadcrumb(item, index) {
    const content = html`
      ${item.avatar || item.showAvatar
        ? html`<noora-avatar
            data-part="avatar"
            size="2xsmall"
            name=${item.avatar?.name ?? item.label ?? ""}
            color=${item.avatar?.color ?? item.avatarColor ?? "pink"}
            image-href=${ifDefined(item.avatar?.imageHref)}
          ></noora-avatar>`
        : item.icon
          ? html`<div data-part="icon">
              ${nooraIcon(normalizedIconName(item.icon))}
            </div>`
          : nothing}
      <span data-part="label">${item.label}</span>
      ${item.badge || item.badgeLabel
        ? html`<noora-badge
            appearance="light-fill"
            size="small"
            color=${item.badge?.color ?? item.badgeColor ?? "neutral"}
            label=${item.badge?.label ?? item.badgeLabel}
          ></noora-badge>`
        : nothing}
    `;

    return html`
      <div class="noora-breadcrumb">
        <a data-part="link" href=${ifDefined(item.href)}>${content}</a>
        ${item.items?.length
          ? html`
              <div data-part="menu-anchor">
                <button
                  data-part="trigger"
                  data-state=${this.#openIndex === index ? "open" : "closed"}
                  type="button"
                  aria-label=${`Choose ${item.label}`}
                  aria-haspopup="menu"
                  aria-expanded=${this.#openIndex === index}
                  aria-controls=${`breadcrumb-menu-${index}`}
                  @click=${() => this.#toggleMenu(index)}
                >
                  <noora-icon
                    name="selector"
                    active-name="selector_2"
                    transition="morph"
                    size="16"
                  ></noora-icon>
                </button>
                <div data-part="positioner">
                  <div class="noora-dropdown-content" data-part="content">
                    <div
                      id=${`breadcrumb-menu-${index}`}
                      data-part="items"
                      role="menu"
                      @keydown=${handlePopupItemKeydown}
                    >
                      ${item.items.map((candidate) =>
                        breadcrumbMenuItemTemplate(candidate, (selected) =>
                          this.#selectItem(index, selected),
                        ),
                      )}
                    </div>
                  </div>
                </div>
              </div>
            `
          : nothing}
      </div>
    `;
  }

  #toggleMenu(index) {
    this.#openIndex = this.#openIndex === index ? -1 : index;
    this.requestUpdate();
    this.emit("noora-open-change", {
      open: this.#openIndex >= 0,
      index: this.#openIndex,
    });
    if (this.#openIndex >= 0) {
      this.updateComplete.then(() =>
        focusPopupItem(
          this.renderRoot.querySelector(`#breadcrumb-menu-${this.#openIndex}`),
        ),
      );
    }
  }

  #selectItem(index, item) {
    this.#closeMenu();
    this.emit("noora-select", { index, item, value: item.value ?? item.label });
  }

  #closeMenu() {
    if (this.#openIndex < 0) return;
    this.#openIndex = -1;
    this.requestUpdate();
    this.emit("noora-open-change", { open: false, index: -1 });
  }
}

export class NooraTabMenu extends NooraElement {
  static contract = contract("noora-tab-menu");
  static styles = [
    unsafeCSS(tabMenuStyles),
    hostDisplay,
    css`
      button.noora-tab-menu-horizontal-item,
      button.noora-tab-menu-vertical {
        appearance: none;
        border: 0;
        background: transparent;
        font: inherit;
      }
      button.noora-tab-menu-horizontal-item {
        padding: 0;
      }
      button.noora-tab-menu-vertical {
        text-align: left;
      }
    `,
  ];

  render() {
    const vertical = validated(this, "orientation") === "vertical";
    const items = childConfigurations(this, "noora-tab-item", this.items);
    const className = vertical
      ? "noora-tab-menu-vertical-list"
      : "noora-tab-menu-horizontal";

    return html`
      <div
        class=${className}
        part="menu"
        role="tablist"
        aria-orientation=${vertical ? "vertical" : "horizontal"}
      >
        ${items.map((item) => {
          const selected = this.value === (item.value ?? item.label);
          const itemClass = vertical
            ? "noora-tab-menu-vertical"
            : "noora-tab-menu-horizontal-item";
          const content = html`
            ${item.icon
              ? html`<span data-part="icon-left"
                  >${nooraIcon(normalizedIconName(item.icon))}</span
                >`
              : nothing}
            <span data-part="label">${item.label}</span>
            ${item.rightIcon
              ? html`<span data-part="icon-right"
                  >${nooraIcon(normalizedIconName(item.rightIcon))}</span
                >`
              : nothing}
          `;

          return item.href
            ? html`<a
                class=${itemClass}
                part="item"
                role="tab"
                aria-selected=${selected}
                aria-disabled=${item.disabled ? "true" : nothing}
                ?data-selected=${selected}
                href=${item.href}
                @click=${(event) => {
                  if (item.disabled) event.preventDefault();
                  else this.#select(item);
                }}
                >${content}</a
              >`
            : html`<button
                class=${itemClass}
                part="item"
                role="tab"
                aria-selected=${selected}
                ?data-selected=${selected}
                type="button"
                ?disabled=${item.disabled}
                @click=${() => this.#select(item)}
              >
                ${content}
              </button>`;
        })}
        <slot></slot>
      </div>
    `;
  }

  #select(item) {
    this.value = item.value ?? item.label;
    this.emit("noora-tab-change", { value: this.value, item });
  }
}

export class NooraSidebar extends NooraElement {
  static contract = contract("noora-sidebar");
  static styles = [
    unsafeCSS(sidebarStyles),
    unsafeCSS(tabMenuStyles),
    hostDisplay,
    css`
      :host {
        height: 100%;
      }
      .noora-sidebar {
        display: block;
        height: 100%;
      }
      button[data-part="group-label"] {
        border: 0;
        background: transparent;
        width: 100%;
        text-align: left;
      }
    `,
  ];

  #openGroups = new Set();
  #initializedGroups = new Set();

  render() {
    const items = [...this.children]
      .filter((child) =>
        ["noora-sidebar-group", "noora-sidebar-item"].includes(child.localName),
      )
      .map((child) => child.configuration)
      .filter((configuration) => configuration !== undefined);
    const navigationItems = items.length ? items : this.items;
    for (const item of navigationItems) {
      if (!item.items || this.#initializedGroups.has(item.label)) continue;
      this.#initializedGroups.add(item.label);
      if (item.defaultOpen) this.#openGroups.add(item.label);
    }

    return html`
      <nav
        class=${this.constructor.contract.className}
        part="sidebar"
        aria-label=${this.label}
      >
        <div data-part="viewport" part="viewport">
          ${navigationItems.map((item) =>
            item.items ? this.#group(item) : this.#item(item),
          )}
          <slot></slot>
        </div>
      </nav>
    `;
  }

  #group(group) {
    const open =
      this.#openGroups.has(group.label) || group.collapsible === false;
    return html`
      <div data-part="group">
        <button
          data-part="group-label"
          type="button"
          aria-expanded=${open}
          ?disabled=${group.collapsible === false}
          @click=${() => this.#toggleGroup(group)}
        >
          ${group.label}
        </button>
        <div ?hidden=${!open}>
          ${group.items.map((item) => this.#item(item))}
        </div>
      </div>
    `;
  }

  #item(item) {
    return html`<a
      data-part="item"
      href=${item.href ?? "#"}
      ?data-selected=${item.selected}
      aria-current=${item.selected ? "page" : nothing}
    >
      <span class="noora-tab-menu-vertical">
        ${item.icon
          ? html`<span data-part="icon-left"
              >${nooraIcon(normalizedIconName(item.icon))}</span
            >`
          : nothing}
        <span data-part="label">${item.label}</span>
      </span>
    </a>`;
  }

  #toggleGroup(group) {
    if (group.collapsible === false) return;
    if (this.#openGroups.has(group.label)) {
      this.#openGroups.delete(group.label);
    } else {
      this.#openGroups.add(group.label);
    }
    this.requestUpdate();
  }
}

export class NooraPopover extends NooraPopupElement {
  static contract = contract("noora-popover");
  static styles = [
    unsafeCSS(popoverStyles),
    inlineHostDisplay,
    css`
      :host {
        position: relative;
      }

      [data-part="positioner"] {
        position: absolute;
      }

      [data-part="content"] {
        width: max-content;
        max-width: min(320px, calc(100dvw - 32px));
        overflow-wrap: anywhere;
      }

      .noora-popover[data-positioning-placement^="bottom"]
        > [data-part="positioner"] {
        top: calc(100% + var(--noora-spacing-2));
      }

      .noora-popover[data-positioning-placement^="top"]
        > [data-part="positioner"] {
        bottom: calc(100% + var(--noora-spacing-2));
      }

      .noora-popover[data-positioning-placement$="-start"]
        > [data-part="positioner"] {
        left: 0;
      }

      .noora-popover[data-positioning-placement$="-end"]
        > [data-part="positioner"] {
        right: 0;
      }

      .noora-popover[data-positioning-placement="top"]
        > [data-part="positioner"],
      .noora-popover[data-positioning-placement="bottom"]
        > [data-part="positioner"] {
        left: 50%;
        transform: translateX(-50%);
      }
    `,
  ];

  disabled = false;

  render() {
    return html`
      <div
        class=${this.constructor.contract.className}
        data-positioning-placement=${validated(this, "placement")}
      >
        <div
          data-part="trigger"
          part="trigger"
          data-state=${this.open ? "open" : "closed"}
          aria-expanded=${this.open}
          @click=${() => this.toggleOpen()}
        >
          <slot name="trigger"></slot>
        </div>
        <div data-part="positioner" ?hidden=${!this.open}>
          <div
            data-part="content"
            part="content"
            role="dialog"
            tabindex="-1"
            aria-modal=${this.modal}
            data-state=${this.open ? "open" : "closed"}
            data-placement=${validated(this, "placement")}
          >
            <slot></slot>
          </div>
        </div>
      </div>
    `;
  }

  updated(changedProperties) {
    if (changedProperties.has("open") && this.open && this.autoFocus) {
      queueMicrotask(() => {
        const focusable = this.querySelector(
          "button, [href], input, select, textarea, [tabindex]:not([tabindex='-1'])",
        );
        focusable?.focus();
      });
    }
  }
}

export class NooraTooltip extends NooraPopupElement {
  static contract = contract("noora-tooltip");
  static styles = [
    unsafeCSS(tooltipStyles),
    inlineHostDisplay,
    css`
      :host {
        position: relative;
      }
      [data-part="positioner"] {
        position: absolute;
        top: 100%;
        left: 0;
        padding-top: var(--noora-spacing-2);
      }
    `,
  ];

  closeOnInteractOutside = false;
  closeOnEscape = true;
  #openTimer;
  #closeTimer;

  disconnectedCallback() {
    clearTimeout(this.#openTimer);
    clearTimeout(this.#closeTimer);
    super.disconnectedCallback();
  }

  render() {
    const size = validated(this, "size");

    return html`
      <div class=${this.constructor.contract.className}>
        <div
          data-part="trigger"
          part="trigger"
          data-state=${this.open ? "open" : "closed"}
          @pointerenter=${this.#scheduleOpen}
          @pointerleave=${this.#scheduleClose}
          @focusin=${this.#scheduleOpen}
          @focusout=${this.#scheduleClose}
        >
          <slot name="trigger"></slot>
        </div>
        <div
          data-part="positioner"
          ?hidden=${!this.open}
          @pointerenter=${this.#cancelClose}
          @pointerleave=${this.#scheduleClose}
        >
          <div
            data-part="content"
            data-size=${size}
            part="content"
            role="tooltip"
          >
            ${size === "large"
              ? html`
                  <div data-part="icon"><slot name="icon"></slot></div>
                  <div data-part="body">
                    <span data-part="title">${this.title}</span>
                    <span data-part="description">${this.description}</span>
                  </div>
                `
              : this.title}
          </div>
        </div>
      </div>
    `;
  }

  #scheduleOpen = () => {
    if (this.disabled) return;
    clearTimeout(this.#closeTimer);
    this.#openTimer = setTimeout(() => this.setOpen(true), 250);
  };

  #scheduleClose = () => {
    clearTimeout(this.#openTimer);
    this.#closeTimer = setTimeout(() => this.setOpen(false), 150);
  };

  #cancelClose = () => clearTimeout(this.#closeTimer);
}

export class NooraModal extends NooraPopupElement {
  static contract = contract("noora-modal");
  static styles = [
    unsafeCSS(modalStyles),
    unsafeCSS(dismissIconStyles),
    hostDisplay,
    css`
      :host {
        display: contents;
      }
      [data-part="content"] {
        width: min(560px, calc(100dvw - 32px));
        max-height: calc(100dvh - 32px);
        overflow: auto;
      }
    `,
  ];

  disabled = false;
  #previouslyFocused;
  #handleFooterClick = (event) => {
    const closeAction = event
      .composedPath()
      .some(
        (element) =>
          element?.slot === "footer" && element?.dataset?.action === "close",
      );
    if (closeAction) this.dismiss("action");
  };

  connectedCallback() {
    super.connectedCallback();
    this.addEventListener("click", this.#handleFooterClick);
  }

  render() {
    const headerType = validated(this, "header-type");
    const headerSize = validated(this, "header-size");
    const headerIcon = {
      success: "circle_check",
      warning: "alert_triangle",
      info: "alert_circle",
      error: "alert_circle",
    }[headerType];
    const hasFooter = this.querySelector('[slot="footer"]') !== null;

    return html`
      <div class=${this.constructor.contract.className}>
        <div
          data-part="trigger"
          @click=${() => this.setOpen(true)}
          aria-haspopup="dialog"
        >
          <slot name="trigger"></slot>
        </div>
        <div
          data-part="backdrop"
          part="backdrop"
          data-state=${this.open ? "open" : nothing}
          ?hidden=${!this.open}
          @click=${this.#handleBackdrop}
        ></div>
        <div data-part="positioner" ?hidden=${!this.open}>
          <div
            data-part="content"
            part="content"
            data-state=${this.open ? "open" : nothing}
            role="dialog"
            aria-modal="true"
            aria-label=${ifDefined(this.title)}
          >
            ${this.title
              ? html`<header
                  data-part="header"
                  part="header"
                  data-type=${headerType}
                  data-size=${headerSize}
                >
                  ${headerType !== "default"
                    ? html`<div data-part="icon">
                        <slot name="header-icon"
                          >${headerIcon ? nooraIcon(headerIcon) : nothing}</slot
                        >
                      </div>`
                    : nothing}
                  <div data-part="header-content">
                    <div data-part="row">
                      <span data-part="title">${this.title}</span>
                      <button
                        class="noora-dismiss-icon"
                        data-part="close-trigger"
                        type="button"
                        aria-label="Dismiss"
                        @click=${() => this.dismiss("close-button")}
                      >
                        ${nooraIcon("close")}
                      </button>
                    </div>
                    ${headerSize === "large" && this.description
                      ? html`<div data-part="description">
                          ${this.description}
                        </div>`
                      : nothing}
                  </div>
                  <slot name="header-button"></slot>
                </header>`
              : nothing}
            <div data-part="body" part="body"><slot></slot></div>
            <footer data-part="footer" part="footer" ?hidden=${!hasFooter}>
              <div></div>
              <div data-part="actions">
                <slot
                  name="footer"
                  @slotchange=${() => this.requestUpdate()}
                ></slot>
              </div>
            </footer>
          </div>
        </div>
      </div>
    `;
  }

  updated(changedProperties) {
    if (!changedProperties.has("open")) return;
    if (this.open) {
      this.#previouslyFocused = document.activeElement;
      document.documentElement.style.overflow = "hidden";
      queueMicrotask(() => {
        this.renderRoot
          ?.querySelector(
            '[data-part="content"] button, [data-part="content"] [href], [data-part="content"] input, [data-part="content"] select, [data-part="content"] textarea',
          )
          ?.focus();
      });
    } else {
      document.documentElement.style.removeProperty("overflow");
      this.#previouslyFocused?.focus?.();
    }
  }

  disconnectedCallback() {
    this.removeEventListener("click", this.#handleFooterClick);
    document.documentElement.style.removeProperty("overflow");
    super.disconnectedCallback();
  }

  #handleBackdrop() {
    if (this.closeOnInteractOutside) this.dismiss("outside");
  }

  dismiss(reason) {
    if (!this.open) return;
    super.dismiss(reason);
    this.emit("noora-dismiss", { reason });
  }
}

export function registerNooraAlert() {
  registerNooraElement(NooraAlert.contract, NooraAlert);
}
export function registerNooraAvatar() {
  registerNooraElement(NooraAvatar.contract, NooraAvatar);
}
export function registerNooraBanner() {
  registerNooraElement(NooraBanner.contract, NooraBanner);
}
export function registerNooraBreadcrumbItem() {
  registerNooraElement(NooraBreadcrumbItem.contract, NooraBreadcrumbItem);
}
export function registerNooraBreadcrumbs() {
  registerNooraElement(NooraBreadcrumbs.contract, NooraBreadcrumbs);
}
export function registerNooraButtonDropdown() {
  registerNooraElement(NooraButtonDropdown.contract, NooraButtonDropdown);
}
export function registerNooraButtonGroup() {
  registerNooraElement(NooraButtonGroup.contract, NooraButtonGroup);
}
export function registerNooraButtonGroupItem() {
  registerNooraElement(NooraButtonGroupItem.contract, NooraButtonGroupItem);
}
export function registerNooraCard() {
  registerNooraElement(NooraCard.contract, NooraCard);
}
export function registerNooraChart() {
  registerNooraElement(NooraChart.contract, NooraChart);
}
export function registerNooraChartAxis() {
  registerNooraElement(NooraChartAxis.contract, NooraChartAxis);
}
export function registerNooraChartCategory() {
  registerNooraElement(NooraChartCategory.contract, NooraChartCategory);
}
export function registerNooraChartGrid() {
  registerNooraElement(NooraChartGrid.contract, NooraChartGrid);
}
export function registerNooraChartPoint() {
  registerNooraElement(NooraChartPoint.contract, NooraChartPoint);
}
export function registerNooraChartSeries() {
  registerNooraElement(NooraChartSeries.contract, NooraChartSeries);
}
export function registerNooraCheckbox() {
  registerNooraElement(NooraCheckbox.contract, NooraCheckbox);
}
export function registerNooraDatePicker() {
  registerNooraElement(NooraDatePicker.contract, NooraDatePicker);
}
export function registerNooraDatePickerPreset() {
  registerNooraElement(NooraDatePickerPreset.contract, NooraDatePickerPreset);
}
export function registerNooraDigitInput() {
  registerNooraElement(NooraDigitInput.contract, NooraDigitInput);
}
export function registerNooraDismissIcon() {
  registerNooraElement(NooraDismissIcon.contract, NooraDismissIcon);
}
export function registerNooraDropdown() {
  registerNooraElement(NooraDropdown.contract, NooraDropdown);
}
export function registerNooraDropdownItem() {
  registerNooraElement(NooraDropdownItem.contract, NooraDropdownItem);
}
export function registerNooraInlineDropdown() {
  registerNooraElement(NooraInlineDropdown.contract, NooraInlineDropdown);
}
export function registerNooraFilter() {
  registerNooraElement(NooraFilter.contract, NooraFilter);
}
export function registerNooraFilterDefinition() {
  registerNooraElement(NooraFilterDefinition.contract, NooraFilterDefinition);
}
export function registerNooraFilterOption() {
  registerNooraElement(NooraFilterOption.contract, NooraFilterOption);
}
export function registerNooraFilterValue() {
  registerNooraElement(NooraFilterValue.contract, NooraFilterValue);
}
export function registerNooraHintText() {
  registerNooraElement(NooraHintText.contract, NooraHintText);
}
export function registerNooraIcon() {
  registerNooraElement(NooraIcon.contract, NooraIcon);
}
export function registerNooraLabel() {
  registerNooraElement(NooraLabel.contract, NooraLabel);
}
export function registerNooraLineDivider() {
  registerNooraElement(NooraLineDivider.contract, NooraLineDivider);
}
export function registerNooraLinkButton() {
  registerNooraElement(NooraLinkButton.contract, NooraLinkButton);
}
export function registerNooraModal() {
  registerNooraElement(NooraModal.contract, NooraModal);
}
export function registerNooraNeutralButton() {
  registerNooraElement(NooraNeutralButton.contract, NooraNeutralButton);
}
export function registerNooraPaginationGroup() {
  registerNooraElement(NooraPaginationGroup.contract, NooraPaginationGroup);
}
export function registerNooraPopover() {
  registerNooraElement(NooraPopover.contract, NooraPopover);
}
export function registerNooraProgressBar() {
  registerNooraElement(NooraProgressBar.contract, NooraProgressBar);
}
export function registerNooraSelect() {
  registerNooraElement(NooraSelect.contract, NooraSelect);
}
export function registerNooraShortcutKey() {
  registerNooraElement(NooraShortcutKey.contract, NooraShortcutKey);
}
export function registerNooraSidebar() {
  registerNooraElement(NooraSidebar.contract, NooraSidebar);
}
export function registerNooraSidebarGroup() {
  registerNooraElement(NooraSidebarGroup.contract, NooraSidebarGroup);
}
export function registerNooraSidebarItem() {
  registerNooraElement(NooraSidebarItem.contract, NooraSidebarItem);
}
export function registerNooraStatusBadge() {
  registerNooraElement(NooraStatusBadge.contract, NooraStatusBadge);
}
export function registerNooraTable() {
  registerNooraElement(NooraTable.contract, NooraTable);
}
export function registerNooraTableCell() {
  registerNooraElement(NooraTableCell.contract, NooraTableCell);
}
export function registerNooraTableColumn() {
  registerNooraElement(NooraTableColumn.contract, NooraTableColumn);
}
export function registerNooraTableRow() {
  registerNooraElement(NooraTableRow.contract, NooraTableRow);
}
export function registerNooraTabMenu() {
  registerNooraElement(NooraTabMenu.contract, NooraTabMenu);
}
export function registerNooraTabItem() {
  registerNooraElement(NooraTabItem.contract, NooraTabItem);
}
export function registerNooraTag() {
  registerNooraElement(NooraTag.contract, NooraTag);
}
export function registerNooraTextArea() {
  registerNooraElement(NooraTextArea.contract, NooraTextArea);
}
export function registerNooraTextDivider() {
  registerNooraElement(NooraTextDivider.contract, NooraTextDivider);
}
export function registerNooraTextInput() {
  registerNooraElement(NooraTextInput.contract, NooraTextInput);
}
export function registerNooraTime() {
  registerNooraElement(NooraTime.contract, NooraTime);
}
export function registerNooraToggle() {
  registerNooraElement(NooraToggle.contract, NooraToggle);
}
export function registerNooraTooltip() {
  registerNooraElement(NooraTooltip.contract, NooraTooltip);
}

export function registerRemainingNooraComponents() {
  for (const [componentContract, elementClass] of [
    [NooraAlert.contract, NooraAlert],
    [NooraAvatar.contract, NooraAvatar],
    [NooraBanner.contract, NooraBanner],
    [NooraBreadcrumbItem.contract, NooraBreadcrumbItem],
    [NooraBreadcrumbs.contract, NooraBreadcrumbs],
    [NooraButtonDropdown.contract, NooraButtonDropdown],
    [NooraButtonGroup.contract, NooraButtonGroup],
    [NooraButtonGroupItem.contract, NooraButtonGroupItem],
    [NooraCard.contract, NooraCard],
    [NooraChart.contract, NooraChart],
    [NooraChartAxis.contract, NooraChartAxis],
    [NooraChartCategory.contract, NooraChartCategory],
    [NooraChartGrid.contract, NooraChartGrid],
    [NooraChartPoint.contract, NooraChartPoint],
    [NooraChartSeries.contract, NooraChartSeries],
    [NooraCheckbox.contract, NooraCheckbox],
    [NooraDatePicker.contract, NooraDatePicker],
    [NooraDatePickerPreset.contract, NooraDatePickerPreset],
    [NooraDigitInput.contract, NooraDigitInput],
    [NooraDismissIcon.contract, NooraDismissIcon],
    [NooraDropdown.contract, NooraDropdown],
    [NooraDropdownItem.contract, NooraDropdownItem],
    [NooraInlineDropdown.contract, NooraInlineDropdown],
    [NooraFilter.contract, NooraFilter],
    [NooraFilterDefinition.contract, NooraFilterDefinition],
    [NooraFilterOption.contract, NooraFilterOption],
    [NooraFilterValue.contract, NooraFilterValue],
    [NooraHintText.contract, NooraHintText],
    [NooraIcon.contract, NooraIcon],
    [NooraLabel.contract, NooraLabel],
    [NooraLineDivider.contract, NooraLineDivider],
    [NooraLinkButton.contract, NooraLinkButton],
    [NooraModal.contract, NooraModal],
    [NooraNeutralButton.contract, NooraNeutralButton],
    [NooraPaginationGroup.contract, NooraPaginationGroup],
    [NooraPopover.contract, NooraPopover],
    [NooraProgressBar.contract, NooraProgressBar],
    [NooraSelect.contract, NooraSelect],
    [NooraShortcutKey.contract, NooraShortcutKey],
    [NooraSidebar.contract, NooraSidebar],
    [NooraSidebarGroup.contract, NooraSidebarGroup],
    [NooraSidebarItem.contract, NooraSidebarItem],
    [NooraStatusBadge.contract, NooraStatusBadge],
    [NooraTable.contract, NooraTable],
    [NooraTableCell.contract, NooraTableCell],
    [NooraTableColumn.contract, NooraTableColumn],
    [NooraTableRow.contract, NooraTableRow],
    [NooraTabItem.contract, NooraTabItem],
    [NooraTabMenu.contract, NooraTabMenu],
    [NooraTag.contract, NooraTag],
    [NooraTextArea.contract, NooraTextArea],
    [NooraTextDivider.contract, NooraTextDivider],
    [NooraTextInput.contract, NooraTextInput],
    [NooraTime.contract, NooraTime],
    [NooraToggle.contract, NooraToggle],
    [NooraTooltip.contract, NooraTooltip],
  ]) {
    registerNooraElement(componentContract, elementClass);
  }
}
