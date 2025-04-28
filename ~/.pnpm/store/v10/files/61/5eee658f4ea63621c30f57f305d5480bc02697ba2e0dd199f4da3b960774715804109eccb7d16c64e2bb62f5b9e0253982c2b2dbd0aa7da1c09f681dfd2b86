# Hyperjump - JSON Schema

A collection of modules for working with JSON Schemas.

* Validate JSON-compatible values against a JSON Schemas
  * Dialects: draft-2020-12, draft-2019-09, draft-07, draft-06, draft-04
  * Schemas can reference other schemas using a different dialect
  * Work directly with schemas on the filesystem or HTTP
* OpenAPI
  * Versions: 3.0, 3.1
  * Validate an OpenAPI document
  * Validate values against a schema from an OpenAPI document
* Create custom keywords, vocabularies, and dialects
* Bundle multiple schemas into one document
  * Uses the process defined in the 2020-12 specification but works with any
    dialect.
* Utilities for building non-validation JSON Schema tooling
* Utilities for working with annotations

## Install

Includes support for node.js/bun.js (ES Modules, TypeScript) and browsers (works
with CSP
[`unsafe-eval`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/script-src#unsafe_eval_expressions)).

### Node.js

```bash
npm install @hyperjump/json-schema
```

### TypeScript

This package uses the package.json "exports" field. [TypeScript understands
"exports"](https://devblogs.microsoft.com/typescript/announcing-typescript-4-5-beta/#packagejson-exports-imports-and-self-referencing),
but you need to change a couple settings in your `tsconfig.json` for it to work.

```jsonc
    "module": "Node16", // or "NodeNext"
    "moduleResolution": "Node16", // or "NodeNext"
```

### Versioning

The API for this library is divided into two categories: Stable and
Experimental. The Stable API follows semantic versioning, but the Experimental
API may have backward-incompatible changes between minor versions.

All experimental features are segregated into exports that include the word
"experimental" so you never accidentally depend on something that could change
or be removed in future releases.

## Validation

### Usage

This library supports many versions of JSON Schema. Use the pattern
`@hyperjump/json-schema/*` to import the version you need.

```javascript
import { registerSchema, validate } from "@hyperjump/json-schema/draft-2020-12";
```

You can import support for additional versions as needed.

```javascript
import { registerSchema, validate } from "@hyperjump/json-schema/draft-2020-12";
import "@hyperjump/json-schema/draft-07";
```

**Note**: The default export (`@hyperjump/json-schema`) is reserved for the
stable version of JSON Schema that will hopefully be released in near future.

**Validate schema from JavaScript**

```javascript
registerSchema({
  $schema: "https://json-schema.org/draft/2020-12/schema",
  type: "string"
}, "http://example.com/schemas/string");

const output = await validate("http://example.com/schemas/string", "foo");
if (output.valid) {
  console.log("Instance is valid :-)");
} else {
  console.log("Instance is invalid :-(");
}
```

**Compile schema**

If you need to validate multiple instances against the same schema, you can
compile the schema into a reusable validation function.

```javascript
const isString = await validate("http://example.com/schemas/string");
const output1 = isString("foo");
const output2 = isString(42);
```

**Fetching schemas**

Schemas that are available on the web can be loaded automatically without
needing to load them manually.

```javascript
const output = await validate("http://example.com/schemas/string", "foo");
```

When running on the server, you can also load schemas directly from the
filesystem. When fetching from the file system, there are limitations for
security reasons. You can only reference a schema identified by a file URI
scheme (**file**:///path/to/my/schemas) from another schema identified by a file
URI scheme. Also, a schema is not allowed to self-identify (`$id`) with a
`file:` URI scheme.

```javascript
const output = await validate(`file://${__dirname}/string.schema.json`, "foo");
```

If the schema URI is relative, the base URI in the browser is the browser
location and the base URI on the server is the current working directory. This
is the preferred way to work with file-based schemas on the server.

```javascript
const output = await validate(`./string.schema.json`, "foo");
```

You can add/modify/remove support for any URI scheme using the [plugin
system](https://github.com/hyperjump-io/browser/#uri-schemes) provided by
`@hyperjump/browser`.

**OpenAPI**

The OpenAPI 3.0 and 3.1 meta-schemas are pre-loaded and the OpenAPI JSON Schema
dialects for each of those versions is supported. A document with a Content-Type
of `application/openapi+json` (web) or a file extension of `openapi.json`
(filesystem) is understood as an OpenAPI document.

Use the pattern `@hyperjump/json-schema/*` to import the version you need. The
available versions are `openapi-3-0` for 3.0 and `openapi-3-1` for 3.1.

```javascript
import { validate } from "@hyperjump/json-schema/openapi-3-1";


// Validate an OpenAPI document
const output = await validate("https://spec.openapis.org/oas/3.1/schema-base", openapi);

// Validate an instance against a schema in an OpenAPI document
const output = await validate("./example.openapi.json#/components/schemas/foo", 42);
```

YAML support isn't built in, but you can add it by writing a
[MediaTypePlugin](https://github.com/hyperjump-io/browser/#media-types). You can
use the one at `lib/openapi.js` as an example and replace the JSON parts with
YAML.

**Media types**

This library uses media types to determine how to parse a retrieved document. It
will never assume the retrieved document is a schema. By default it's configured
to accept documents with a `application/schema+json` Content-Type header (web)
or a `.schema.json` file extension (filesystem).

You can add/modify/remove support for any media-type using the [plugin
system](https://github.com/hyperjump-io/browser/#media-types) provided by
`@hyperjump/browser`. The following example shows how to add support for JSON
Schemas written in YAML.

```javascript
import YAML from "yaml";
import contentTypeParser from "content-type";
import { addMediaTypePlugin } from "@hyperjump/browser";
import { buildSchemaDocument } from "@hyperjump/json-schema/experimental";


addMediaTypePlugin("application/schema+yaml", {
  parse: async (response) => {
    const contentType = contentTypeParser.parse(response.headers.get("content-type") ?? "");
    const contextDialectId = contentType.parameters.schema ?? contentType.parameters.profile;

    const foo = YAML.parse(await response.text());
    return buildSchemaDocument(foo, response.url, contextDialectId);
  },
  fileMatcher: (path) => path.endsWith(".schema.yml")
});
```

### API

These are available from any of the exports that refer to a version of JSON
Schema, such as `@hyperjump/json-schema/draft-2020-12`.

* **registerSchema**: (schema: object, retrievalUri?: string, defaultDialectId?: string) => void

    Add a schema the local schema registry. When this schema is needed, it will
    be loaded from the register rather than the filesystem or network. If a
    schema with the same identifier is already registered, an exception will be
    throw.
* **unregisterSchema**: (uri: string) => void

    Remove a schema from the local schema registry.
* **getAllRegisteredSchemaUris**: () => string[]

    This function returns the URIs of all registered schemas
* **hasSchema**: (uri: string) => boolean

    Check if a schema with the given URI is already registered.
* _(deprecated)_ **addSchema**: (schema: object, retrievalUri?: string, defaultDialectId?: string) => void

    Load a schema manually rather than fetching it from the filesystem or over
    the network. Any schema already registered with the same identifier will be
    replaced with no warning.
* **validate**: (schemaURI: string, instance: any, outputFormat: OutputFormat = FLAG) => Promise\<OutputUnit>

    Validate an instance against a schema. This function is curried to allow
    compiling the schema once and applying it to multiple instances.
* **validate**: (schemaURI: string) => Promise\<(instance: any, outputFormat: OutputFormat = FLAG) => OutputUnit>

    Compiling a schema to a validation function.
* **FLAG**: "FLAG"

    An identifier for the `FLAG` output format as defined by the 2019-09 and
    2020-12 specifications.
* **InvalidSchemaError**: Error & { output: OutputUnit }

    This error is thrown if the schema being compiled is found to be invalid.
    The `output` field contains an `OutputUnit` with information about the
    error. You can use the `setMetaSchemaOutputFormat` configuration to set the
    output format that is returned in `output`.
* **setMetaSchemaOutputFormat**: (outputFormat: OutputFormat) => void

    Set the output format used for validating schemas.
* **getMetaSchemaOutputFormat**: () => OutputFormat

    Get the output format used for validating schemas.
* **setShouldMetaValidate**: (isEnabled: boolean) => void

    Enable or disable validating schemas.
* **getShouldMetaValidate**: (isEnabled: boolean) => void

    Determine if validating schemas is enabled.

**Type Definitions**

The following types are used in the above definitions

* **OutputFormat**: **FLAG**

    Only the `FLAG` output format is part of the Stable API. Additional output
    formats are included as part of the Experimental API.
* **OutputUnit**: { valid: boolean }

    Output is an experimental feature of the JSON Schema specification. There
    may be additional fields present in the OutputUnit, but only the `valid`
    property should be considered part of the Stable API.

## Bundling

### Usage

You can bundle schemas with external references into a single deliverable using
the official JSON Schema bundling process introduced in the 2020-12
specification. Given a schema with external references, any external schemas
will be embedded in the schema resulting in a Compound Schema Document with all
the schemas necessary to evaluate the given schema in a single JSON document.

The bundling process allows schemas to be embedded without needing to modify any
references which means you get the same output details whether you validate the
bundle or the original unbundled schemas.

```javascript
import { registerSchema } from "@hyperjump/json-schema/draft-2020-12";
import { bundle } from "@hyperjump/json-schema/bundle";


registerSchema({
  "$schema": "https://json-schema.org/draft/2020-12/schema",

  "type": "object",
  "properties": {
    "foo": { "$ref": "/string" }
  }
}, "https://example.com/main");

registerSchema({
  "$schema": "https://json-schema.org/draft/2020-12/schema",

  "type": "string"
}, "https://example.com/string");

const bundledSchema = await bundle("https://example.com/main"); // {
//   "$schema": "https://json-schema.org/draft/2020-12/schema",
//
//   "type": "object",
//   "properties": {
//     "foo": { "$ref": "/string" }
//   },
//
//   "$defs": {
//     "string": {
//       "$id": "https://example.com/string",
//       "type": "string"
//     }
//   }
// }
```

### API

These are available from the `@hyperjump/json-schema/bundle` export.

* **bundle**: (uri: string, options: Options) => Promise\<SchemaObject>

    Create a bundled schema starting with the given schema. External schemas
    will be fetched from the filesystem, the network, or the local schema
    registry as needed.

    Options:
     * alwaysIncludeDialect: boolean (default: false) -- Include dialect even
       when it isn't strictly needed
     * definitionNamingStrategy: "uri" | "uuid" (default: "uri") -- By default
       the name used in definitions for embedded schemas will match the
       identifier of the embedded schema. Alternatively, you can use a UUID
       instead of the schema's URI.
     * externalSchemas: string[] (default: []) -- A list of schemas URIs that
       are available externally and should not be included in the bundle.

## Experimental

### Output Formats

**Change the validation output format**

The `FLAG` output format isn't very informative. You can change the output
format used for validation to get more information about failures. The official
output format is still evolving, so these may change or be replaced in the
future.

```javascript
import { BASIC } from "@hyperjump/json-schema/experimental";


const output = await validate("https://example.com/schema1", 42, BASIC);
```

**Change the schema validation output format**

The output format used for validating schemas can be changed as well.

```javascript
import { validate, setMetaSchemaOutputFormat } from "@hyperjump/json-schema/draft-2020-12";
import { BASIC } from "@hyperjump/json-schema/experimental";


setMetaSchemaOutputFormat(BASIC);
try {
  const output = await validate("https://example.com/invalid-schema");
} catch (error) {
  console.log(error.output);
}
```

### Custom Keywords, Vocabularies, and Dialects

In order to create and use a custom keyword, you need to define your keyword's
behavior, create a vocabulary that includes that keyword, and then create a
dialect that includes your vocabulary.

Schemas are represented using the
[`@hyperjump/browser`](https://github.com/hyperjump-io/browser) package. You'll
use that API to traverse schemas. `@hyperjump/browser` uses async generators to
iterate over arrays and objects. If you like using higher order functions like
`map`/`filter`/`reduce`, see
[`@hyperjump/pact`](https://github.com/hyperjump-io/pact) for utilities for
working with generators and async generators.

```javascript
import { registerSchema, validate } from "@hyperjump/json-schema/draft-2020-12";
import { addKeyword, defineVocabulary, Validation } from "@hyperjump/json-schema/experimental";
import * as Browser from "@hyperjump/browser";


// Define a keyword that's an array of schemas that are applied sequentially
// using implication: A -> B -> C -> D
addKeyword({
  id: "https://example.com/keyword/implication",

  compile: async (schema, ast) => {
    const subSchemas = [];
    for await (const subSchema of Browser.iter(schema)) {
      subSchemas.push(Validation.compile(subSchema, ast));
    }
    return subSchemas;

    // Alternative using @hyperjump/pact
    // return pipe(
    //   Browser.iter(schema),
    //   asyncMap((subSchema) => Validation.compile(subSchema, ast)),
    //   asyncCollectArray
    // );
  },

  interpret: (implies, instance, ast, dynamicAnchors, quiet) => {
    return implies.reduce((valid, schema) => {
      return !valid || Validation.interpret(schema, instance, ast, dynamicAnchors, quiet);
    }, true);
  }
});

// Create a vocabulary with this keyword and call it "implies"
defineVocabulary("https://example.com/vocab/logic", {
  "implies": "https://example.com/keyword/implication"
});

// Create a vocabulary schema for this vocabulary
registerSchema({
  "$id": "https://example.com/meta/logic",
  "$schema": "https://json-schema.org/draft/2020-12/schema",

  "$dynamicAnchor": "meta",
  "properties": {
    "implies": {
      "type": "array",
      "items": { "$dynamicRef": "meta" },
      "minItems": 2
    }
  }
});

// Create a dialect schema adding this vocabulary to the standard JSON Schema
// vocabularies
registerSchema({
  "$id": "https://example.com/dialect/logic",
  "$schema": "https://json-schema.org/draft/2020-12/schema",

  "$vocabulary": {
    "https://json-schema.org/draft/2020-12/vocab/core": true,
    "https://json-schema.org/draft/2020-12/vocab/applicator": true,
    "https://json-schema.org/draft/2020-12/vocab/unevaluated": true,
    "https://json-schema.org/draft/2020-12/vocab/validation": true,
    "https://json-schema.org/draft/2020-12/vocab/meta-data": true,
    "https://json-schema.org/draft/2020-12/vocab/format-annotation": true,
    "https://json-schema.org/draft/2020-12/vocab/content": true
    "https://example.com/vocab/logic": true
  },

  "$dynamicAnchor": "meta",

  "allOf": [
    { "$ref": "https://json-schema.org/draft/2020-12/schema" },
    { "$ref": "/meta/logic" }
  ]
});

// Use your dialect to validate a JSON instance
registerSchema({
  "$schema": "https://example.com/dialect/logic",

  "type": "number",
  "implies": [
    { "minimum": 10 },
    { "multipleOf": 2 }
  ]
}, "https://example.com/schema1");
const output = await validate("https://example.com/schema1", 42);
```

### Custom Meta Schema

You can use a custom meta-schema to restrict users to a subset of JSON Schema
functionality. This example requires that no unknown keywords are used in the
schema.

```javascript
registerSchema({
  "$id": "https://example.com/meta-schema1",
  "$schema": "https://json-schema.org/draft/2020-12/schema",

  "$vocabulary": {
    "https://json-schema.org/draft/2020-12/vocab/core": true,
    "https://json-schema.org/draft/2020-12/vocab/applicator": true,
    "https://json-schema.org/draft/2020-12/vocab/unevaluated": true,
    "https://json-schema.org/draft/2020-12/vocab/validation": true,
    "https://json-schema.org/draft/2020-12/vocab/meta-data": true,
    "https://json-schema.org/draft/2020-12/vocab/format-annotation": true,
    "https://json-schema.org/draft/2020-12/vocab/content": true
  },

  "$dynamicAnchor": "meta",

  "$ref": "https://json-schema.org/draft/2020-12/schema",
  "unevaluatedProperties": false
});

registerSchema({
  $schema: "https://example.com/meta-schema1",
  type: "number",
  foo: 42
}, "https://example.com/schema1");

const output = await validate("https://example.com/schema1", 42); // Expect InvalidSchemaError
```

### API

These are available from the `@hyperjump/json-schema/experimental` export.

* **addKeyword**: (keywordHandler: Keyword) => void

    Define a keyword for use in a vocabulary.

    * **Keyword**: object
      * id: string

          A URI that uniquely identifies the keyword. It should use a domain you
          own to avoid conflict with keywords defined by others.
      * compile: (schema: Browser, ast: AST, parentSchema: Browser) => Promise\<any>

          This function takes the keyword value, does whatever preprocessing it
          can on it without an instance, and returns the result. The returned
          value will be passed to the `interpret` function. The `ast` parameter
          is needed for compiling sub-schemas. The `parentSchema` parameter is
          primarily useful for looking up the value of an adjacent keyword that
          might effect this one.
      * interpret: (compiledKeywordValue: any, instance: JsonNode, ast: AST, dynamicAnchors: object, quiet: boolean, schemaLocation: string) => boolean

          This function takes the value returned by the `compile` function and
          the instance value that is being validated and returns whether the
          value is valid or not. The other parameters are only needed for
          validating sub-schemas.
      * collectEvaluatedProperties?: (compiledKeywordValue: any, instance: JsonNode, ast: AST, dynamicAnchors: object) => Set\<string> | false

          If the keyword is an applicator, it will need to implement this
          function for `unevaluatedProperties` to work as expected.
      * collectEvaluatedItems?: (compiledKeywordValue: A, instance: JsonNode, ast: AST, dynamicAnchors: object) => Set\<number> | false

          If the keyword is an applicator, it will need to implement this
          function for `unevaluatedItems` to work as expected.
      * collectExternalIds?: (visited: Set\<string>, parentSchema: Browser, schema: Browser) => Set\<string>
          If the keyword is an applicator, it will need to implement this
      function to work properly with the [bundle](#bundling) feature.
* **defineVocabulary**: (id: string, keywords: { [keyword: string]: string }) => void

    Define a vocabulary that maps keyword name to keyword URIs defined using
    `addKeyword`.
* **getKeywordId**: (keywordName: string, dialectId: string) => string

    Get the identifier for a keyword by its name.
* **getKeyword**: (keywordId: string) => Keyword

    Get a keyword object by its URI. This is useful for building non-validation
    tooling.
* **getKeywordByName**: (keywordName: string, dialectId: string) => Keyword

    Get a keyword object by its name. This is useful for building non-validation
    tooling.
* **getKeywordName**: (dialectId: string, keywordId: string) => string

    Determine a keyword's name given its URI a dialect URI. This is useful when
    defining a keyword that depends on the value of another keyword (such as how
    `contains` depends on `minContains` and `maxContains`).
* **loadDialect**: (dialectId: string, dialect: { [vocabularyId: string] }, allowUnknownKeywords: boolean = false) => void

    Define a dialect. In most cases, dialects are loaded automatically from the
    `$vocabulary` keyword in the meta-schema. The only time you would need to
    load a dialect manually is if you're creating a distinct version of JSON
    Schema rather than creating a dialect of an existing version of JSON Schema.
* **unloadDialect**: (dialectId: string) => void

    Remove a dialect. You shouldn't need to use this function. It's called for
    you when you call `unregisterSchema`.
* **Validation**: Keyword

    A Keyword object that represents a "validate" operation. You would use this
    for compiling and evaluating sub-schemas when defining a custom keyword.
        
* **getSchema**: (uri: string, browser?: Browser) => Promise\<Browser>

    Get a schema by it's URI taking the local schema registry into account.
* buildSchemaDocument: (schema: SchemaObject | boolean, retrievalUri?: string, contextDialectId?: string) => SchemaDocument

    Build a SchemaDocument from a JSON-compatible value. You might use this if
    you're creating a custom media type plugin, such as supporting JSON Schemas
    in YAML.
* **canonicalUri**: (schema: Browser) => string

    Returns a URI for the schema.
* **toSchema**: (schema: Browser, options: ToSchemaOptions) => object

    Get a raw schema from a Schema Document.

    * **ToSchemaOptions**: object

        * contextDialectId: string (default: "") -- If the dialect of the schema
          matches this value, the `$schema` keyword will be omitted.
        * includeDialect: "auto" | "always" | "never" (default: "auto") -- If
          "auto", `$schema` will only be included if it differs from
          `contextDialectId`.
        * contextUri: string (default: "") -- `$id`s will be relative to this
          URI.
        * includeEmbedded: boolean (default: true) -- If false, embedded schemas
          will be unbundled from the schema.
* **compile**: (schema: Browser) => Promise\<CompiledSchema>

    Return a compiled schema. This is useful if you're creating tooling for
    something other than validation.
* **interpret**: (schema: CompiledSchema, instance: JsonNode, outputFormat: OutputFormat = BASIC) => OutputUnit

    A curried function for validating an instance against a compiled schema.
    This can be useful for creating custom output formats.

* **OutputFormat**: **FLAG** | **BASIC**

    In addition to the `FLAG` output format in the Stable API, the Experimental
    API includes support for the `BASIC` format as specified in the 2019-09
    specification (with some minor customizations). This implementation doesn't
    include annotations or human readable error messages. The output can be
    processed to create human readable error messages as needed.

## Instance API (experimental)

These functions are available from the
`@hyperjump/json-schema/instance/experimental` export.

This library uses JsonNode objects to represent instances. You'll work with
these objects if you create a custom keyword.

This API uses generators to iterate over arrays and objects. If you like using
higher order functions like `map`/`filter`/`reduce`, see
[`@hyperjump/pact`](https://github.com/hyperjump-io/pact) for utilities for
working with generators and async generators.

* **fromJs**: (value: any, uri?: string) => JsonNode

    Construct a JsonNode from a JavaScript value.
* **cons**: (baseUri: string, pointer: string, value: any, type: string, children: JsonNode[], parent?: JsonNode) => JsonNode

    Construct a JsonNode. This is used internally. You probably want `fromJs`
    instead.
* **get**: (url: string, instance: JsonNode) => JsonNode

    Apply a same-resource reference to a JsonNode.
* **uri**: (instance: JsonNode) => string

    Returns a URI for the value the JsonNode represents.
* **value**: (instance: JsonNode) => any

    Returns the value the JsonNode represents.
* **has**: (key: string, instance: JsonNode) => boolean

    Returns whether or not "key" is a property name in a JsonNode that
    represents an object.
* **typeOf**: (instance: JsonNode) => string

    The JSON type of the JsonNode. In addition to the standard JSON types,
    there's also the `property` type that indicates a property name/value pair
    in an object.
* **step**: (key: string, instance: JsonNode) => JsonType

    Similar to indexing into a object or array using the `[]` operator.
* **iter**: (instance: JsonNode) => Generator\<JsonNode>

    Iterate over the items in the array that the JsonNode represents.
* **entries**: (instance: JsonNode) => Generator\<[JsonNode, JsonNode]>

    Similar to `Object.entries`, but yields JsonNodes for keys and values.
* **values**: (instance: JsonNode) => Generator\<JsonNode>

    Similar to `Object.values`, but yields JsonNodes for values.
* **keys**: (instance: JsonNode) => Generator\<JsonNode>

    Similar to `Object.keys`, but yields JsonNodes for keys.
* **length**: (instance: JsonNode) => number

    Similar to `Array.prototype.length`.

## Annotations (experimental)
JSON Schema is for annotating JSON instances as well as validating them. This
module provides utilities for working with JSON documents annotated with JSON
Schema.

### Usage
An annotated JSON document is represented as a
(JsonNode)[#/instance-api-experimental] AST. You can use this AST to traverse
the data structure and get annotations for the values it represents.

```javascript
import { registerSchema } from "@hyperjump/json-schema/draft/2020-12";
import { annotate } from "@hyperjump/json-schema/annotations/experimental";
import * as AnnotatedInstance from "@hyperjump/json-schema/annotated-instance/experimental";


const schemaId = "https://example.com/foo";
const dialectId = "https://json-schema.org/draft/2020-12/schema";

registerSchema({
  "$schema": dialectId,

  "title": "Person",
  "unknown": "foo",

  "type": "object",
  "properties": {
    "name": {
      "$ref": "#/$defs/name",
      "deprecated": true
    },
    "givenName": {
      "$ref": "#/$defs/name",
      "title": "Given Name"
    },
    "familyName": {
      "$ref": "#/$defs/name",
      "title": "Family Name"
    }
  },

  "$defs": {
    "name": {
      "type": "string",
      "title": "Name"
    }
  }
}, schemaId);

const instance = await annotate(schemaId, {
  name: "Jason Desrosiers",
  givenName: "Jason",
  familyName: "Desrosiers"
});

// Get the title of the instance
const titles = AnnotatedInstance.annotation(instance, "title", dialectId); // => ["Person"]

// Unknown keywords are collected as annotations
const unknowns = AnnotatedInstance.annotation(instance, "unknown", dialectId); // => ["foo"]

// The type keyword doesn't produce annotations
const types = AnnotatedInstance.annotation(instance, "type", dialectId); // => []

// Get the title of each of the properties in the object
for (const [propertyNameNode, propertyInstance] of AnnotatedInstance.entries(instance)) {
  const propertyName = AnnotatedInstance.value(propertyName);
  console.log(propertyName, AnnotatedInstance.annotation(propertyInstance, "title", dialectId));
}

// List all locations in the instance that are deprecated
for (const deprecated of AnnotatedInstance.annotatedWith(instance, "deprecated", dialectId)) {
  if (AnnotatedInstance.annotation(deprecated, "deprecated", dialectId)[0]) {
    logger.warn(`The value at '${deprecated.pointer}' has been deprecated.`); // => (Example) "WARN: The value at '/name' has been deprecated."
  }
}
```

### API
These are available from the `@hyperjump/json-schema/annotations/experimental`
export.

* **annotate**: (schemaUri: string, instance: any, outputFormat: OutputFormat = BASIC) => Promise\<JsonNode>

    Annotate an instance using the given schema. The function is curried to
    allow compiling the schema once and applying it to multiple instances. This
    may throw an [InvalidSchemaError](#api) if there is a problem with the
    schema or a ValidationError if the instance doesn't validate against the
    schema.
* **interpret**: (compiledSchema: CompiledSchema, instance: JsonNode, outputFormat: OutputFormat = BASIC) => JsonNode

    Annotate a JsonNode object rather than a plain JavaScript value. This might
    be useful when building tools on top of the annotation functionality, but
    you probably don't need it.
* **ValidationError**: Error & { output: OutputUnit }
    The `output` field contains an `OutputUnit` with information about the
    error.

## AnnotatedInstance API (experimental)
These are available from the
`@hyperjump/json-schema/annotated-instance/experimental` export. The
following functions are available in addition to the functions available in the
[Instance API](#instance-api-experimental).

* **annotation**: (instance: JsonNode, keyword: string, dialect?: string): any[];

    Get the annotations for a keyword for the value represented by the JsonNode.
* **annotatedWith**: (instance: JsonNode, keyword: string, dialect?: string): JsonNode[];

    Get all JsonNodes that are annotated with the given keyword.
* **setAnnotation**: (instance: JsonNode, keywordId: string, value: any) => JsonNode

    Add an annotation to an instance. This is used internally, you probably
    don't need it.

## Contributing

### Tests

Run the tests

```bash
npm test
```

Run the tests with a continuous test runner

```bash
npm test -- --watch
```
