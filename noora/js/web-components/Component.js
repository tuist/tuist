import { LitElement, css } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { contractProperties, initializeContractDefaults } from "./Contract.js";
import iconMarkup from "./icons.json";

// Directional icons from `icons.json` carry `data-rtl-mirror`. Light-DOM ancestors' `dir`
// attributes are not visible to selectors inside shadow roots, so match the element's
// inherited directionality instead. Mirrors `css/icon.css`.
const rtlMirroredIconStyles = css`
  [data-rtl-mirror]:dir(rtl) {
    scale: -1 1;
  }
`;

export class NooraElement extends LitElement {
  static contract;
  static properties = {};

  static finalizeStyles(styles) {
    return [...super.finalizeStyles(styles), rtlMirroredIconStyles];
  }

  #handleConfigurationChange = (event) => {
    if (event.target !== this) {
      event.stopPropagation();
      this.requestUpdate();
    }
  };

  constructor() {
    super();
    initializeContractDefaults(this, this.constructor.contract);
  }

  connectedCallback() {
    super.connectedCallback();
    this.addEventListener(
      "noora-configuration-change",
      this.#handleConfigurationChange,
    );
  }

  disconnectedCallback() {
    this.removeEventListener(
      "noora-configuration-change",
      this.#handleConfigurationChange,
    );
    super.disconnectedCallback();
  }

  emit(name, detail = {}, { cancelable = false } = {}) {
    return this.dispatchEvent(
      new CustomEvent(name, {
        bubbles: true,
        cancelable,
        composed: true,
        detail,
      }),
    );
  }
}

export function nooraIcon(name) {
  return unsafeSVG(iconMarkup[name] ?? "");
}

export function registerNooraElement(contract, elementClass) {
  if (!customElements.get(contract.tagName)) {
    if (!Object.hasOwn(elementClass, "properties")) {
      elementClass.properties = contractProperties(contract);
    }
    customElements.define(contract.tagName, elementClass);
  }
}
