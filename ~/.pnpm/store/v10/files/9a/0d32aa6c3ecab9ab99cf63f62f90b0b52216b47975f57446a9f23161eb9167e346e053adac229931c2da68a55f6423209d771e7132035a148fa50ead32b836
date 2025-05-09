import type { Json } from "@hyperjump/json-pointer";
import type { JsonSchemaType } from "../lib/common.js";


export type JsonSchemaDraft04 = {
  $ref: string;
} | {
  $schema?: "http://json-schema.org/draft-04/schema#";
  id?: string;
  title?: string;
  description?: string;
  default?: Json;
  multipleOf?: number;
  maximum?: number;
  exclusiveMaximum?: boolean;
  minimum?: number;
  exclusiveMinimum?: boolean;
  maxLength?: number;
  minLength?: number;
  pattern?: string;
  additionalItems?: boolean | JsonSchemaDraft04;
  items?: JsonSchemaDraft04 | JsonSchemaDraft04[];
  maxItems?: number;
  minItems?: number;
  uniqueItems?: boolean;
  maxProperties?: number;
  minProperties?: number;
  required?: string[];
  additionalProperties?: boolean | JsonSchemaDraft04;
  definitions?: Record<string, JsonSchemaDraft04>;
  properties?: Record<string, JsonSchemaDraft04>;
  patternProperties?: Record<string, JsonSchemaDraft04>;
  dependencies?: Record<string, JsonSchemaDraft04 | string[]>;
  enum?: Json[];
  type?: JsonSchemaType | JsonSchemaType[];
  format?: "date-time" | "email" | "hostname" | "ipv4" | "ipv6" | "uri";
  allOf?: JsonSchemaDraft04[];
  anyOf?: JsonSchemaDraft04[];
  oneOf?: JsonSchemaDraft04[];
  not?: JsonSchemaDraft04;
};

export * from "../lib/index.js";
