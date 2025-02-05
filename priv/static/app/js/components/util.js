import { createNormalizer } from "https://cdn.jsdelivr.net/npm/@zag-js/types@0.81.2/+esm";

const propMap = {
  onFocus: "onFocusin",
  onBlur: "onFocusout",
  onChange: "onInput",
  onDoubleClick: "onDblclick",
  htmlFor: "for",
  className: "class",
  defaultValue: "value",
  defaultChecked: "checked",
};

const prevAttrsMap = new WeakMap();

/**
 * Converts a style object to a CSS string
 * @param {Object} style - Style object to convert
 * @returns {string} CSS string
 */
const toStyleString = (style) => {
  return Object.entries(style).reduce((styleString, [key, value]) => {
    if (value === null || value === undefined) return styleString;
    const formattedKey = key.startsWith("--")
      ? key
      : key.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`);
    return `${styleString}${formattedKey}:${value};`;
  }, "");
};

export const normalizeProps = createNormalizer((props) => {
  return Object.entries(props).reduce((acc, [key, value]) => {
    if (value === undefined) return acc;
    key = propMap[key] || key;

    if (key === "style" && typeof value === "object") {
      acc.style = toStyleString(value);
    } else {
      acc[key.toLowerCase()] = value;
    }

    return acc;
  }, {});
});

/**
 * Spreads properties onto a DOM node
 * @param {HTMLElement} node - Target DOM node
 * @param {Object} attrs - Attributes to apply
 * @returns {Function} Cleanup function
 */
export const spreadProps = (node, attrs) => {
  const oldAttrs = prevAttrsMap.get(node) || {};
  const attrKeys = Object.keys(attrs);

  const addEvent = (event, callback) => {
    node.addEventListener(event.toLowerCase(), callback);
  };

  const removeEvent = (event, callback) => {
    node.removeEventListener(event.toLowerCase(), callback);
  };

  const onEvents = (attr) => attr.startsWith("on");
  const others = (attr) => !attr.startsWith("on");

  const setup = (attr) => addEvent(attr.substring(2), attrs[attr]);
  const teardown = (attr) => removeEvent(attr.substring(2), attrs[attr]);

  const apply = (attrName) => {
    let value = attrs[attrName];
    const oldValue = oldAttrs[attrName];
    if (value === oldValue) return;

    if (typeof value === "boolean") {
      value = value || undefined;
    }

    if (value != null) {
      if (["value", "checked", "htmlFor"].includes(attrName)) {
        node[attrName] = value;
      } else {
        node.setAttribute(attrName.toLowerCase(), value);
      }
      return;
    }

    node.removeAttribute(attrName.toLowerCase());
  };

  for (const key in oldAttrs) {
    if (attrs[key] == null) {
      node.removeAttribute(key.toLowerCase());
    }
  }

  const oldEvents = Object.keys(oldAttrs).filter(onEvents);
  for (const oldEvent of oldEvents)
    removeEvent(oldEvent.substring(2), oldAttrs[oldEvent]);

  attrKeys.filter(onEvents).forEach(setup);
  attrKeys.filter(others).forEach(apply);

  prevAttrsMap.set(node, attrs);

  return function cleanup() {
    attrKeys.filter(onEvents).forEach(teardown);
  };
};

/**
 * Renders a specific part of the component
 * @param {HTMLElement} root - Root element
 * @param {string} name - Part name
 * @param {Object} api - Component API
 */
export const renderPart = (root, name, api) => {
  const camelizedName = name.replace(
    /(^|-)([a-z])/g,
    (_match, _prefix, letter) => letter.toUpperCase(),
  );
  const part = root.querySelector(`[data-part='${name}']`);
  const getterName = `get${camelizedName}Props`;

  if (part) spreadProps(part, api[getterName]());
};

/**
 * Gets an option value from element's dataset
 * @param {HTMLElement} el - Element to check
 * @param {string} name - Option name
 * @param {string[]} validOptions - Valid option values
 * @returns {string|undefined}
 */
export const getOption = (el, name, validOptions) => {
  const kebabName = name.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase();
  let initial = el.dataset[kebabName];

  if (
    validOptions &&
    initial !== undefined &&
    !validOptions.includes(initial)
  ) {
    console.error(
      `Invalid '${name}' specified: '${initial}'. Expected one of '${validOptions.join("', '")}'.`,
    );
    initial = undefined;
  }

  return initial;
};

/**
 * Gets a boolean option from element's dataset
 * @param {HTMLElement} el - Element to check
 * @param {string} name - Option name
 * @returns {boolean}
 */
export const getBooleanOption = (el, name) => {
  const kebabName = name.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase();
  return (
    el.dataset[name] === "true" ||
    el.dataset[name] === "" ||
    el.dataset[kebabName] === "true" ||
    el.dataset[kebabName] === ""
  );
};

/**
 * Gets attributes for a specific part
 * @param {HTMLElement} root - Root element
 * @param {string} name - Part name
 * @returns {Object|undefined}
 */
export const getAttributes = (root, name) => {
  const part = root.querySelector(`[data-part='${name}']`);
  if (!part) return;

  const attrs = [];
  for (const attr of part.attributes) {
    if (attr.name.startsWith("data-") || attr.name.startsWith("aria-")) {
      attrs.push({ name: attr.name, value: attr.value });
    }
  }

  return {
    part: name,
    cssText: part.style.cssText,
    hasFocus: part === document.activeElement,
    attrs,
  };
};

/**
 * Restores attributes to elements
 * @param {HTMLElement} root - Root element
 * @param {Array} attributeMaps - Array of attribute maps to restore
 */
export const restoreAttributes = (root, attributeMaps) => {
  for (const attributeMap of attributeMaps) {
    const part = root.querySelector(`[data-part='${attributeMap.part}']`);
    if (!part) return;

    for (const attr of attributeMap.attrs) {
      part.setAttribute(attr.name, attr.value);
    }
    part.style.cssText = attributeMap.cssText;
    if (attributeMap.hasFocus) part.focus();
  }
};
