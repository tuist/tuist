import { LitElement, css, html, unsafeCSS } from "lit";
import { ifDefined } from "lit/directives/if-defined.js";
import badgeStyles from "../../css/badge.css";
import badgeContract from "../../components/badge.json";
import {
  contractAttribute,
  contractProperties,
  initializeContractDefaults,
  resolveContractValue,
} from "./Contract.js";

const appearanceAttribute = contractAttribute(badgeContract, "appearance");
const colorAttribute = contractAttribute(badgeContract, "color");
const sizeAttribute = contractAttribute(badgeContract, "size");

export class NooraBadge extends LitElement {
  static properties = {
    ...contractProperties(badgeContract),
    _hasIcon: { state: true },
  };

  static styles = [
    unsafeCSS(badgeStyles),
    css`
      slot[name="icon"]::slotted(svg) {
        width: 100%;
        height: 100%;
        pointer-events: none;
      }
    `,
  ];

  constructor() {
    super();
    initializeContractDefaults(this, badgeContract);
    this._hasIcon = false;
  }

  updated() {
    this.#synchronizeIconState(
      this.renderRoot.querySelector('slot[name="icon"]'),
    );
  }

  render() {
    const showDot = this.dot && !this._hasIcon;
    const showIcon = this._hasIcon || showDot;

    return html`
      <span
        class=${badgeContract.className}
        part="badge"
        data-style=${this.#appearance()}
        data-color=${this.#color()}
        data-size=${this.#size()}
        ?data-disabled=${this.disabled}
        ?data-dot=${showDot}
        ?data-icon=${this._hasIcon}
        ?data-icon-only=${this.iconOnly}
        aria-label=${ifDefined(this._ariaLabel)}
      >
        <span data-part="icon" part="icon" ?hidden=${!showIcon}>
          <slot name="icon" @slotchange=${this.#handleIconSlotChange}></slot>
          ${showDot ? this.#dot() : null}
        </span>
        <span data-part="label" part="label" ?hidden=${this.iconOnly}>
          <slot>${this.label}</slot>
        </span>
      </span>
    `;
  }

  #appearance() {
    return resolveContractValue(this.appearance, appearanceAttribute);
  }

  #color() {
    return resolveContractValue(this.color, colorAttribute);
  }

  #dot() {
    if (this.#size() === "small") {
      return html`
        <svg
          aria-hidden="true"
          width="12"
          height="12"
          viewBox="0 0 12 12"
          fill="none"
        >
          <rect x="4" y="4" width="4" height="4" rx="1" fill="#FDFDFD"></rect>
        </svg>
      `;
    }

    return html`
      <svg
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
      </svg>
    `;
  }

  #handleIconSlotChange(event) {
    this.#synchronizeIconState(event.currentTarget);
  }

  #size() {
    return resolveContractValue(this.size, sizeAttribute);
  }

  #synchronizeIconState(slot) {
    const hasIcon = slot.assignedElements({ flatten: true }).length > 0;
    if (hasIcon !== this._hasIcon) {
      this._hasIcon = hasIcon;
    }
  }
}

export function registerNooraBadge() {
  if (!customElements.get(badgeContract.tagName)) {
    customElements.define(badgeContract.tagName, NooraBadge);
  }
}
