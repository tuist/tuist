export const parse = (jref, reviver = undefined) => {
  return JSON.parse(jref, (key, value) => {
    const newValue = value !== null && typeof value.$ref === "string" ? new Reference(value.$ref) : value;

    return reviver ? reviver(key, newValue) : newValue;
  });
};

export const stringify = JSON.stringify;

export class Reference {
  #href;
  #value;

  constructor(href, value = undefined) {
    this.#href = href;
    this.#value = value ?? { $ref: href };
  }

  get href() {
    return this.#href;
  }

  toJSON() {
    return this.#value;
  }
}

export const jrefTypeOf = (value) => {
  const jsType = typeof value;

  switch (jsType) {
    case "bigint":
      return "number";
    case "number":
    case "string":
    case "boolean":
    case "undefined":
      return jsType;
    case "object":
      if (value instanceof Reference) {
        return "reference";
      } else if (Array.isArray(value)) {
        return "array";
      } else if (value === null) {
        return "null";
      } else if (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null) {
        return "object";
      }
    default: {
      const type = jsType === "object" ? Object.getPrototypeOf(value).constructor.name || "anonymous" : jsType;
      throw Error(`Not a JRef compatible type: ${type}`);
    }
  }
};
