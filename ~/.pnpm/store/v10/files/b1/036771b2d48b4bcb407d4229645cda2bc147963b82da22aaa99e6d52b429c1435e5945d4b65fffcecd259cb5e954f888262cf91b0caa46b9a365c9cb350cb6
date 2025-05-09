import type { Json } from "@hyperjump/json-pointer";
import type { JsonSchemaType } from "../lib/common.js";


export type JsonSchemaDraft06 = boolean | {
  $ref: string;
} | {
  $schema?: "http://json-schema.org/draft-06/schema#";
  $id?: string;
  title?: string;
  description?: string;
  default?: Json;
  examples?: Json[];
  multipleOf?: number;
  maximum?: number;
  exclusiveMaximum?: number;
  minimum?: number;
  exclusiveMinimum?: number;
  maxLength?: number;
  minLength?: number;
  pattern?: string;
  additionalItems?: JsonSchemaDraft06;
  items?: JsonSchemaDraft06 | JsonSchemaDraft06[];
  maxItems?: number;
  minItems?: number;
  uniqueItems?: boolean;
  contains?: JsonSchemaDraft06;
  maxProperties?: number;
  minProperties?: number;
  required?: string[];
  additionalProperties?: JsonSchemaDraft06;
  definitions?: Record<string, JsonSchemaDraft06>;
  properties?: Record<string, JsonSchemaDraft06>;
  patternProperties?: Record<string, JsonSchemaDraft06>;
  dependencies?: Record<string, JsonSchemaDraft06 | string[]>;
  propertyNames?: JsonSchemaDraft06;
  const?: Json;
  enum?: Json[];
  type?: JsonSchemaType | JsonSchemaType[];
  format?: "date-time" | "email" | "hostname" | "ipv4" | "ipv6" | "uri" | "uri-reference" | "uri-template" | "json-pointer";
  allOf?: JsonSchemaDraft06[];
  anyOf?: JsonSchemaDraft06[];
  oneOf?: JsonSchemaDraft06[];
  not?: JsonSchemaDraft06;
};

export * from "../lib/index.js";
