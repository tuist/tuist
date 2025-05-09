import type { Json } from "@hyperjump/json-pointer";


export const fromJs: (value: Json, uri?: string) => JsonNode;

export const cons: (
  baseUri: string,
  pointer: string,
  value: Json | undefined,
  type: JsonNodeType,
  children: JsonNode[],
  parent?: JsonNode
) => JsonNode;
export const get: <T extends JsonNode>(url: string, context: T) => T | undefined;
export const uri: (node: JsonNode) => string;
export const value: <A>(node: JsonNode) => A;
export const has: (key: string, node: JsonNode) => boolean;
export const typeOf: (node: JsonNode) => JsonNodeType;
export const step: <T extends JsonNode>(key: string, node: T) => T | undefined;
export const iter: <T extends JsonNode>(node: T) => Generator<T>;
export const keys: <T extends JsonNode>(node: T) => Generator<T>;
export const values: <T extends JsonNode>(node: T) => Generator<T>;
export const entries: <T extends JsonNode>(node: T) => Generator<[T, T]>;
export const length: <T extends JsonNode>(node: T) => number;

export const allNodes: <T extends JsonNode>(node: T) => Generator<T>;

export type JsonNode = {
  baseUri: string;
  pointer: string;
  type: JsonNodeType;
  children: JsonNode[];
  parent?: JsonNode;
  root: JsonNode;
  valid: boolean;
  errors: Record<string, string>;
  annotations: Record<string, Record<string, unknown>>;
};

type JsonNodeType = "object" | "array" | "string" | "number" | "boolean" | "null" | "property";
