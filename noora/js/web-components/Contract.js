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
  const propertyEntries = (contract.properties ?? []).map((property) => [
    property.name,
    { attribute: false },
  ]);

  return Object.fromEntries([
    ...contract.attributes.map((attribute) => {
      const options = {};
      const defaultValue = () =>
        Object.hasOwn(attribute, "default")
          ? structuredClone(attribute.default)
          : undefined;

      if (attribute.property !== attribute.name) {
        options.attribute = attribute.name;
      }
      if (attribute.type === "boolean") {
        options.type = Boolean;
      }
      if (attribute.type === "number") {
        options.converter = {
          fromAttribute(value) {
            if (value === null) return defaultValue();
            const number = Number(value);
            return Number.isFinite(number) ? number : defaultValue();
          },
          toAttribute(value) {
            return Number.isFinite(value) ? String(value) : null;
          },
        };
      }
      if (attribute.type === "json") {
        options.converter = {
          fromAttribute(value) {
            if (value === null) return defaultValue();

            try {
              const parsed = JSON.parse(value);
              const fallback = defaultValue();

              if (Array.isArray(fallback) && !Array.isArray(parsed)) {
                return fallback;
              }
              if (
                fallback &&
                typeof fallback === "object" &&
                !Array.isArray(fallback) &&
                (typeof parsed !== "object" ||
                  parsed === null ||
                  Array.isArray(parsed))
              ) {
                return fallback;
              }

              return parsed;
            } catch {
              return defaultValue();
            }
          },
          toAttribute(value) {
            return value === undefined ? null : JSON.stringify(value);
          },
        };
      }
      if (attribute.reflect) {
        options.reflect = true;
      }

      return [attribute.property, options];
    }),
    ...propertyEntries,
  ]);
}

export function initializeContractDefaults(element, contract) {
  const inputs = [
    ...contract.attributes.map((attribute) => ({
      ...attribute,
      name: attribute.property,
    })),
    ...(contract.properties ?? []),
  ];

  for (const input of inputs) {
    if (Object.hasOwn(input, "default")) {
      element[input.name] =
        input.type === "json" ? structuredClone(input.default) : input.default;
    }
  }
}

export function resolveContractValue(value, attribute) {
  return !attribute.values || attribute.values.includes(value)
    ? value
    : attribute.default;
}

export function contractByTag(contracts, tagName) {
  const contract = contracts.find((candidate) => candidate.tagName === tagName);

  if (!contract) {
    throw new Error(`Missing contract for ${tagName}`);
  }

  return contract;
}
