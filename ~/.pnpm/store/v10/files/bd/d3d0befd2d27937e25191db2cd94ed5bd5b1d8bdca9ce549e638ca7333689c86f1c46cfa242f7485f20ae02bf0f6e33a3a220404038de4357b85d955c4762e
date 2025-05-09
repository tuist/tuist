import type { Json } from "@hyperjump/json-pointer";
import type { JsonSchemaType } from "../lib/common.js";


export type OasSchema31 = boolean | {
  $schema?: "https://json-schema.org/draft/2020-12/schema";
  $id?: string;
  $anchor?: string;
  $ref?: string;
  $dynamicRef?: string;
  $dynamicAnchor?: string;
  $vocabulary?: Record<string, boolean>;
  $comment?: string;
  $defs?: Record<string, OasSchema31>;
  additionalItems?: OasSchema31;
  unevaluatedItems?: OasSchema31;
  prefixItems?: OasSchema31[];
  items?: OasSchema31;
  contains?: OasSchema31;
  additionalProperties?: OasSchema31;
  unevaluatedProperties?: OasSchema31;
  properties?: Record<string, OasSchema31>;
  patternProperties?: Record<string, OasSchema31>;
  dependentSchemas?: Record<string, OasSchema31>;
  propertyNames?: OasSchema31;
  if?: OasSchema31;
  then?: OasSchema31;
  else?: OasSchema31;
  allOf?: OasSchema31[];
  anyOf?: OasSchema31[];
  oneOf?: OasSchema31[];
  not?: OasSchema31;
  multipleOf?: number;
  maximum?: number;
  exclusiveMaximum?: number;
  minimum?: number;
  exclusiveMinimum?: number;
  maxLength?: number;
  minLength?: number;
  pattern?: string;
  maxItems?: number;
  minItems?: number;
  uniqueItems?: boolean;
  maxContains?: number;
  minContains?: number;
  maxProperties?: number;
  minProperties?: number;
  required?: string[];
  dependentRequired?: Record<string, string[]>;
  const?: Json;
  enum?: Json[];
  type?: JsonSchemaType | JsonSchemaType[];
  title?: string;
  description?: string;
  default?: Json;
  deprecated?: boolean;
  readOnly?: boolean;
  writeOnly?: boolean;
  examples?: Json[];
  format?: "date-time" | "date" | "time" | "duration" | "email" | "idn-email" | "hostname" | "idn-hostname" | "ipv4" | "ipv6" | "uri" | "uri-reference" | "iri" | "iri-reference" | "uuid" | "uri-template" | "json-pointer" | "relative-json-pointer" | "regex";
  contentMediaType?: string;
  contentEncoding?: string;
  contentSchema?: OasSchema31;
  example?: Json;
  discriminator?: Discriminator;
  externalDocs?: ExternalDocs;
  xml?: Xml;
};

type Discriminator = {
  propertyName: string;
  mappings?: Record<string, string>;
};

type ExternalDocs = {
  url: string;
  description?: string;
};

type Xml = {
  name?: string;
  namespace?: string;
  prefix?: string;
  attribute?: boolean;
  wrapped?: boolean;
};

export type OpenApi = {
  openapi: string;
  info: Info;
  jsonSchemaDialect?: string;
  servers?: Server[];
  security?: SecurityRequirement[];
  tags?: Tag[];
  externalDocs?: ExternalDocumentation;
  paths?: Record<string, PathItem>;
  webhooks?: Record<string, PathItem | Reference>;
  components?: Components;
};

type Info = {
  title: string;
  summary?: string;
  description?: string;
  termsOfService?: string;
  contact?: Contact;
  license?: License;
  version: string;
};

type Contact = {
  name?: string;
  url?: string;
  email?: string;
};

type License = {
  name: string;
  url?: string;
  identifier?: string;
};

type Server = {
  url: string;
  description?: string;
  variables?: Record<string, ServerVariable>;
};

type ServerVariable = {
  enum?: string[];
  default: string;
  description?: string;
};

type Components = {
  schemas?: Record<string, OasSchema31>;
  responses?: Record<string, Response | Reference>;
  parameters?: Record<string, Parameter | Reference>;
  examples?: Record<string, Example | Reference>;
  requestBodies?: Record<string, RequestBody | Reference>;
  headers?: Record<string, Header | Reference>;
  securitySchemes?: Record<string, SecurityScheme | Reference>;
  links?: Record<string, Link | Reference>;
  callbacks?: Record<string, Callbacks | Reference>;
  pathItems?: Record<string, PathItem | Reference>;
};

type PathItem = {
  summary?: string;
  description?: string;
  servers?: Server[];
  parameters?: (Parameter | Reference)[];
  get?: Operation;
  put?: Operation;
  post?: Operation;
  delete?: Operation;
  options?: Operation;
  head?: Operation;
  patch?: Operation;
  trace?: Operation;
};

type Operation = {
  tags?: string[];
  summary?: string;
  description?: string;
  externalDocs?: ExternalDocumentation;
  operationId?: string;
  parameters?: (Parameter | Reference)[];
  requestBody?: RequestBody | Reference;
  responses?: Record<string, Response | Reference>;
  callbacks?: Record<string, Callbacks | Reference>;
  deprecated?: boolean;
  security?: SecurityRequirement[];
  servers?: Server[];
};

type ExternalDocumentation = {
  description?: string;
  url: string;
};

type Parameter = {
  name: string;
  in: "query" | "header" | "path" | "cookie";
  description?: string;
  required?: boolean;
  deprecated?: boolean;
  allowEmptyValue?: boolean;
  style?: "matrix" | "label" | "form" | "simple" | "spaceDelimited" | "pipeDelimited" | "deepObject";
  explode?: boolean;
  allowReserved?: boolean;
  schema?: OasSchema31;
  content?: Content;
} & Examples;

type RequestBody = {
  description?: string;
  content: Content;
  required?: boolean;
};

type Content = Record<string, MediaType>;

type MediaType = {
  schema?: OasSchema31;
  encoding?: Record<string, Encoding>;
} & Examples;

type Encoding = {
  contentType?: string;
  headers?: Record<string, Header | Reference>;
  style?: "form" | "spaceDelimited" | "pipeDelimited" | "deepObject";
  explode?: boolean;
  allowReserved?: boolean;
};

type Response = {
  description: string;
  headers?: Record<string, Header | Reference>;
  content?: Content;
  links?: Record<string, Link | Reference>;
};

type Callbacks = Record<string, PathItem | Reference>;

type Example = {
  summary?: string;
  description?: string;
  value?: Json;
  externalValue?: string;
};

type Link = {
  operationRef?: string;
  operationId?: string;
  parameters?: Record<string, string>;
  requestBody?: Json;
  description?: string;
  body?: Server;
};

type Header = {
  description?: string;
  required?: boolean;
  deprecated?: boolean;
  schema?: OasSchema31;
  style?: "simple";
  explode?: boolean;
  content?: Content;
};

type Tag = {
  name: string;
  description?: string;
  externalDocs?: ExternalDocumentation;
};

type Reference = {
  $ref: string;
  summary?: string;
  descriptions?: string;
};

type SecurityScheme = {
  type: "apiKey" | "http" | "mutualTLS" | "oauth2" | "openIdConnect";
  description?: string;
  name?: string;
  in?: "query" | "header" | "cookie";
  scheme?: string;
  bearerFormat?: string;
  flows?: OauthFlows;
  openIdConnectUrl?: string;
};

type OauthFlows = {
  implicit: Implicit;
  Password: Password;
  clientCredentials: ClientCredentials;
  authorizationCode: AuthorizationCode;
};

type Implicit = {
  authorizationUrl: string;
  refreshUrl?: string;
  scopes: Record<string, string>;
};

type Password = {
  tokenUrl: string;
  refreshUrl?: string;
  scopes: Record<string, string>;
};

type ClientCredentials = {
  tokenUrl: string;
  refreshUrl?: string;
  scopes: Record<string, string>;
};

type AuthorizationCode = {
  authorizationUrl: string;
  tokenUrl: string;
  refreshUrl?: string;
  scopes: Record<string, string>;
};

type SecurityRequirement = Record<string, string[]>;

type Examples = {
  example?: Json;
  examples?: Record<string, Example | Reference>;
};

export * from "../lib/index.js";
