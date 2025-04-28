import type { Json } from "@hyperjump/json-pointer";
import type { JsonSchemaType } from "../lib/common.js";


export type JsonSchemaDraft07 = boolean | {
  $ref: string;
} | {
  $schema?: "http://json-schema.org/draft-07/schema#";
  $id?: string;
  $comment?: string;
  title?: string;
  description?: string;
  default?: Json;
  readOnly?: boolean;
  writeOnly?: boolean;
  examples?: Json[];
  multipleOf?: number;
  maximum?: number;
  exclusiveMaximum?: number;
  minimum?: number;
  exclusiveMinimum?: number;
  maxLength?: number;
  minLength?: number;
  pattern?: string;
  additionalItems?: JsonSchemaDraft07;
  items?: JsonSchemaDraft07 | JsonSchemaDraft07[];
  maxItems?: number;
  minItems?: number;
  uniqueItems?: boolean;
  contains?: JsonSchemaDraft07;
  maxProperties?: number;
  minProperties?: number;
  required?: string[];
  additionalProperties?: JsonSchemaDraft07;
  definitions?: Record<string, JsonSchemaDraft07>;
  properties?: Record<string, JsonSchemaDraft07>;
  patternProperties?: Record<string, JsonSchemaDraft07>;
  dependencies?: Record<string, JsonSchemaDraft07 | string[]>;
  propertyNames?: JsonSchemaDraft07;
  const?: Json;
  enum?: Json[];
  type?: JsonSchemaType | JsonSchemaType[];
  format?: "date-time" | "date" | "time" | "email" | "idn-email" | "hostname" | "idn-hostname" | "ipv4" | "ipv6" | "uri" | "uri-reference" | "iri" | "iri-reference" | "uri-template" | "json-pointer" | "relative-json-pointer" | "regex";
  contentMediaType?: string;
  contentEncoding?: string;
  if?: JsonSchemaDraft07;
  then?: JsonSchemaDraft07;
  else?: JsonSchemaDraft07;
  allOf?: JsonSchemaDraft07[];
  anyOf?: JsonSchemaDraft07[];
  oneOf?: JsonSchemaDraft07[];
  not?: JsonSchemaDraft07;
};

export * from "../lib/index.js";
