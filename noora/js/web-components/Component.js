import { LitElement } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { contractProperties, initializeContractDefaults } from "./Contract.js";
import iconMarkup from "./icons.json";

export class NooraElement extends LitElement {
  static contract;
  static properties = {};

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
