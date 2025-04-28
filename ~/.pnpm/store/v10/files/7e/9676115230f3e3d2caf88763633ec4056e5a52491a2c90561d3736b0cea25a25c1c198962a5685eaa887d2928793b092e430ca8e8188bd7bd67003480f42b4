interface Options {
  /**
   * Determinate how to stringify primitives values.
   * @default JSON.stringify
   */
  stringify?: typeof JSON["stringify"];

  /**
   * Determinate how to resolve cycles.
   * Under true, when a cycle is detected, [Circular] will be inserted in the node.
   * @default false
   */
  cycles?: boolean;

  /**
   * Custom comparison function for object keys.
   * @param a first key-value pair.
   * @param b second key-value pair.
   * @returns a number whose sign indicates the relative order of the two elements.
   */
  compare?: (a: KeyValue, b: KeyValue) => number;

  /**
   * Indent the output for pretty-printing.
   */
  space?: string;

  /**
   * Replacer function that behaves the same as the replacer from the core JSON object.
   */
  replacer?: (key: string, value: unknown) => unknown;
}

interface KeyValue {
  key: string;
  value: unknown;
}

/**
 * Deterministic version of JSON.stringify(), so you can get a consistent hash from stringified results.
 * @param obj The input object to be serialized.
 * @param opts options.
 */
declare function stringify(obj: unknown, opts?: Options): string;

export = stringify;
