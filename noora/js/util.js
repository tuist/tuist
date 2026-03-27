import { createNormalizer } from "@zag-js/types";

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
 * Generates a CSS selector string for a part name, handling nesting.
 *
 * @param {string} name The name of the part. Use ':' as a separator for nested parts (e.g., "dialog:title").
 * @returns {string} The CSS selector string (e.g., ":scope > [data-part='dialog'] > [data-part='title']").
 */
export const getPartSelector = (name) => {
  if (typeof name !== "string" || name.trim() === "") {
    console.warn("[getPartSelector] Invalid name provided.");
    return;
  }

  if (name.includes(":")) {
    const nameParts = name.split(":");
    return (
      ":scope" + nameParts.map((part) => ` > [data-part='${part}']`).join("")
    );
  } else {
    return `:scope > [data-part='${name}']`;
  }
};

/**
 * Spreads props onto a specific part element within a root container.
 * Handles simple names (e.g., "button") and nested names (e.g., "root:list").
 *
 * @param {Element} root The root container element.
 * @param {string} name The name of the part. Use ':' as a separator for nested parts (e.g., "dialog:title").
 * @param {object} api An object containing getter functions for props (e.g., { getButtonProps: () => ({...}), getListProps: () => ({...}) }).
 */
export const renderPart = (root, name, api) => {
  const selector = getPartSelector(name);

  const getterNamePart = name.includes(":")
    ? name.substring(name.lastIndexOf(":") + 1)
    : name;

  const camelizedGetterPart = getterNamePart.replace(
    /(^|-)([a-z])/g,
    (_match, _prefix, letter) => letter.toUpperCase(),
  );
  const getterName = `get${camelizedGetterPart}Props`;

  const part = root.querySelector(selector);

  if (part && typeof api[getterName] === "function") {
    spreadProps(part, api[getterName]());
  } else if (part && typeof api[getterName] !== "function") {
    console.warn(
      `[renderPart] Getter function '${getterName}' not found in API for part name '${name}'.`,
    );
  }
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
  // We need to check both for `name` and `kebabName` due to differences between browser engines.
  let initial = el.dataset[name] || el.dataset[kebabName];

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
  for (const attributeMap of attributeMaps.filter((val) => Boolean(val))) {
    const part = root.querySelector(`[data-part='${attributeMap.part}']`);
    if (!part) return;

    for (const attr of attributeMap.attrs) {
      part.setAttribute(attr.name, attr.value);
    }
    part.style.cssText = attributeMap.cssText;
    if (attributeMap.hasFocus) part.focus();
  }
};
