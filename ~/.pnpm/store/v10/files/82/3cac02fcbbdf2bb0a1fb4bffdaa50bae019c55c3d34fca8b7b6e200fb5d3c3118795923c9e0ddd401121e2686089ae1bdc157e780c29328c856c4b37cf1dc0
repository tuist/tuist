export type JRef = null | boolean | string | number | Reference | JRefObject | JRef[];
export type JRefObject = { // eslint-disable-line @typescript-eslint/consistent-indexed-object-style
  [property: string]: JRef;
};

export const parse: (jref: string, reviver?: Reviver) => JRef;
export type Reviver = (key: string, value: JRef) => JRef | undefined;

export const stringify: (value: JRef, replacer?: (string | number)[] | null | Replacer, space?: string | number) => string;
export type Replacer = (key: string, value: unknown) => unknown;

export type JRefType = "object" | "array" | "string" | "number" | "boolean" | "null" | "reference" | "undefined";
export const jrefTypeOf: (value: unknown) => JRefType;

export class Reference {
  constructor(href: string, value?: unknown);

  get href(): string;
  toJSON(): unknown;
}
