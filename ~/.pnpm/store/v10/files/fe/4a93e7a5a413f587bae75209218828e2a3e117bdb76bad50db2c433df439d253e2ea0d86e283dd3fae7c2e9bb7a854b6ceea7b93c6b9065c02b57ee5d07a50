import type { SchemaObject } from "../lib/index.js";


export const bundle: <A = SchemaObject>(uri: string, options?: BundleOptions) => Promise<A>;
export const URI: "uri";
export const UUID: "uuid";

export type BundleOptions = {
  alwaysIncludeDialect?: boolean;
  definitionNamingStrategy?: DefinitionNamingStrategy;
  externalSchemas?: string[];
};

export type DefinitionNamingStrategy = "uri" | "uuid";
