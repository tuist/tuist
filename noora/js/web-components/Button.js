import { LitElement, css, html, unsafeCSS } from "lit";
import { ifDefined } from "lit/directives/if-defined.js";
import buttonStyles from "../../css/button.css";
import buttonContract from "../../components/button.json";
import {
  contractAttribute,
  contractProperties,
  initializeContractDefaults,
  resolveContractValue,
} from "./Contract.js";

const sizeAttribute = contractAttribute(buttonContract, "size");
const typeAttribute = contractAttribute(buttonContract, "type");
const variantAttribute = contractAttribute(buttonContract, "variant");

export class NooraButton extends LitElement {
  static formAssociated = true;
  static shadowRootOptions = {
    ...LitElement.shadowRootOptions,
    delegatesFocus: true,
  };

  static properties = contractProperties(buttonContract);

  static styles = [
    unsafeCSS(buttonStyles),
    css`
      slot::slotted(svg) {
        width: var(--noora-button-icon-size);
        height: var(--noora-button-icon-size);
        pointer-events: none;
      }
    `,
  ];

  #formDisabled = false;
  #internals;
  #restoreFocus = false;
  #submitProxy;

  constructor() {
    super();

    this.#internals = this.attachInternals?.();
    initializeContractDefaults(this, buttonContract);
  }

  connectedCallback() {
    super.connectedCallback();
    this.#syncAccessibilityReferences();
    this.#syncSubmitProxy();
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    queueMicrotask(() => {
      if (!this.isConnected) this.#submitProxy?.remove();
    });
  }

  get form() {
    return (
      this.#internals?.form ?? this.#formFromAttribute() ?? this.closest("form")
    );
  }

  get control() {
    return this.renderRoot?.querySelector('[part="control"]') ?? null;
  }

  click() {
    this.control?.click();
  }

  focus(options) {
    this.control?.focus(options);
  }

  formDisabledCallback(disabled) {
    this.#formDisabled = disabled;
    if (this.#submitProxy) this.#submitProxy.disabled = this.#isDisabled();
    this.requestUpdate();
  }

  willUpdate() {
    this.#restoreFocus = this.control === this.renderRoot?.activeElement;
  }

  updated() {
    if (this.#restoreFocus) this.control?.focus();
    this.#syncAccessibilityReferences();
    this.#syncSubmitProxy();
  }

  render() {
    const content = this.iconOnly
      ? html`<slot></slot>`
      : html`
          <slot name="icon-left"></slot>
          <span><slot>${this.label}</slot></span>
          <slot name="icon-right"></slot>
        `;

    if (this.href && !this.#isDisabled()) {
      return html`
        <a
          class=${buttonContract.className}
          part="control"
          href=${this.href}
          data-variant=${this.#variant()}
          data-size=${this.#size()}
          ?data-icon-only=${this.iconOnly}
          aria-describedby=${ifDefined(this._ariaDescribedBy)}
          aria-label=${ifDefined(this._ariaLabel)}
          aria-labelledby=${ifDefined(this._ariaLabelledBy)}
          download=${ifDefined(this.download)}
          rel=${ifDefined(this.rel)}
          target=${ifDefined(this.target)}
          title=${ifDefined(this._title)}
        >
          ${content}
        </a>
      `;
    }

    return html`
      <button
        class=${buttonContract.className}
        part="control"
        type=${this.#type()}
        name=${this.name}
        value=${this.value}
        data-variant=${this.#variant()}
        data-size=${this.#size()}
        ?data-icon-only=${this.iconOnly}
        ?autofocus=${this.autofocus}
        ?disabled=${this.#isDisabled()}
        aria-describedby=${ifDefined(this._ariaDescribedBy)}
        aria-label=${ifDefined(this._ariaLabel)}
        aria-labelledby=${ifDefined(this._ariaLabelledBy)}
        form=${ifDefined(this.formId)}
        formaction=${ifDefined(this.formAction)}
        formenctype=${ifDefined(this.formEnctype)}
        formmethod=${ifDefined(this.formMethod)}
        ?formnovalidate=${this.formNoValidate}
        formtarget=${ifDefined(this.formTarget)}
        title=${ifDefined(this._title)}
        @click=${this.#handleButtonActivation}
      >
        ${content}
      </button>
    `;
  }

  #handleButtonActivation(event) {
    if (this.#isDisabled() || this.#type() === "button") return;

    queueMicrotask(() => {
      if (event.defaultPrevented) return;

      const form = this.form;
      if (!form) return;

      if (this.#type() === "reset") {
        form.reset();
        return;
      }

      this.#syncSubmitProxy();
      this.#submitProxy?.form?.requestSubmit(this.#submitProxy);
    });
  }

  #syncAccessibilityReferences() {
    const control = this.control;
    const root = this.getRootNode();

    if (!control || !("getElementById" in root)) return;

    for (const [property, value] of [
      ["ariaDescribedByElements", this._ariaDescribedBy],
      ["ariaLabelledByElements", this._ariaLabelledBy],
    ]) {
      if (!(property in control)) continue;

      control[property] =
        value
          ?.trim()
          .split(/\s+/)
          .map((id) => root.getElementById(id))
          .filter(Boolean) ?? [];
    }
  }

  #syncSubmitProxy() {
    if (this.href || this.#type() !== "submit") {
      this.#submitProxy?.remove();
      return;
    }

    if (!this.#submitProxy) {
      this.#submitProxy = this.ownerDocument.createElement("button");
      this.#submitProxy.hidden = true;
      this.#submitProxy.tabIndex = -1;
      this.#submitProxy.type = "submit";
      this.#submitProxy.setAttribute("aria-hidden", "true");
    }

    for (const [attribute, value] of [
      ["form", this.formId],
      ["formaction", this.formAction],
      ["formenctype", this.formEnctype],
      ["formmethod", this.formMethod],
      ["formtarget", this.formTarget],
      ["name", this.name],
      ["value", this.value],
    ]) {
      if (value === undefined || value === null) {
        this.#submitProxy.removeAttribute(attribute);
      } else {
        this.#submitProxy.setAttribute(attribute, value);
      }
    }

    this.#submitProxy.disabled = this.#isDisabled();
    this.#submitProxy.formNoValidate = this.formNoValidate;

    if (this.parentNode && this.nextSibling !== this.#submitProxy) {
      this.parentNode.insertBefore(this.#submitProxy, this.nextSibling);
    }
  }

  #formFromAttribute() {
    if (!this.formId) return null;

    const form = this.ownerDocument.getElementById(this.formId);
    return form instanceof HTMLFormElement ? form : null;
  }

  #isDisabled() {
    return this.disabled || this.#formDisabled;
  }

  #size() {
    return resolveContractValue(this.size, sizeAttribute);
  }

  #type() {
    return resolveContractValue(this.type, typeAttribute);
  }

  #variant() {
    return resolveContractValue(this.variant, variantAttribute);
  }
}

export function registerNooraButton() {
  if (!customElements.get(buttonContract.tagName)) {
    customElements.define(buttonContract.tagName, NooraButton);
  }
}
