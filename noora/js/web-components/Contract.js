export function contractAttribute(contract, name) {
  const attribute = contract.attributes.find(
    (candidate) => candidate.name === name,
  );

  if (!attribute) {
    throw new Error(`${contract.tagName} does not define ${name}`);
  }

  return attribute;
}

export function contractProperties(contract) {
  return Object.fromEntries(
    contract.attributes.map((attribute) => {
      const options = {};

      if (attribute.property !== attribute.name) {
        options.attribute = attribute.name;
      }
      if (attribute.type === "boolean") {
        options.type = Boolean;
      }
      if (attribute.reflect) {
        options.reflect = true;
      }

      return [attribute.property, options];
    }),
  );
}

export function initializeContractDefaults(element, contract) {
  for (const attribute of contract.attributes) {
    if (Object.hasOwn(attribute, "default")) {
      element[attribute.property] = attribute.default;
    }
  }
}

export function resolveContractValue(value, attribute) {
  return !attribute.values || attribute.values.includes(value)
    ? value
    : attribute.default;
}
