export type JsonType = "object" | "array" | "string" | "number" | "boolean" | "null";
export type JsonSchemaType = JsonType | "integer";

export const toRelativeIri: (from: string, to: string) => string;

export type Replacer = (key: string, value: unknown) => unknown;
export const jsonStringify: (value: unknown, replacer?: Replacer, space?: string) => string;
