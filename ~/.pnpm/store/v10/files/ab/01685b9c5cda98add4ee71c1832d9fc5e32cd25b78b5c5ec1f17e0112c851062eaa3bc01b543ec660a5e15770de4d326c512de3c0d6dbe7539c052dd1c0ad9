import type { Json } from "@hyperjump/json-pointer";


export type SchemaFragment = string | number | boolean | null | SchemaObject | SchemaFragment[];
export type SchemaObject = { // eslint-disable-line @typescript-eslint/consistent-indexed-object-style
  [keyword: string]: SchemaFragment;
};

export const registerSchema: (schema: SchemaObject | boolean, retrievalUri?: string, contextDialectId?: string) => void;
export const unregisterSchema: (retrievalUri: string) => void;
export const hasSchema: (uri: string) => boolean;
export const getAllRegisteredSchemaUris: () => string[];

/**
 * @deprecated since 1.7.0. Use registerSchema instead.
 */
export const addSchema: typeof registerSchema;

export const validate: (
  (url: string, value: Json, outputFormat?: OutputFormat) => Promise<OutputUnit>
) & (
  (url: string) => Promise<Validator>
);

export type Validator = (value: Json, outputFormat?: OutputFormat) => OutputUnit;

export type OutputUnit = {
  keyword: string;
  absoluteKeywordLocation: string;
  instanceLocation: string;
  valid: boolean;
  errors?: OutputUnit[];
};

export const FLAG: "FLAG";

export type OutputFormat = "FLAG" | "BASIC" | "DETAILED" | "VERBOSE";

export const setMetaSchemaOutputFormat: (format: OutputFormat) => void;
export const getMetaSchemaOutputFormat: () => OutputFormat;
export const setShouldValidateSchema: (isEnabled: boolean) => void;
export const getShouldValidateSchema: () => boolean;

export class InvalidSchemaError extends Error {
  public output: OutputUnit;

  public constructor(output: OutputUnit);
}
