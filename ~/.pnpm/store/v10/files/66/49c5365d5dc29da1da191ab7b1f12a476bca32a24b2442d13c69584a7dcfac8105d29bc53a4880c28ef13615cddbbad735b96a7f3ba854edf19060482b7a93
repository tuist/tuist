# Hyperjump - Browser

The Hyperjump Browser is a generic client for traversing JSON Reference ([JRef])
and other [JRef]-compatible media types in a way that abstracts the references
without loosing information.

## Install

This module is designed for node.js (ES Modules, TypeScript) and browsers. It
should work in Bun and Deno as well, but the test runner doesn't work in these
environments, so this module may be less stable in those environments.

### Node.js

```bash
npm install @hyperjump/browser
```

## JRef Browser

This example uses the API at
[https://swapi.hyperjump.io](https://explore.hyperjump.io#https://swapi.hyperjump.io/api/films/1).
It's a variation of the [Star Wars API (SWAPI)](https://swapi.dev) implemented
using the [JRef] media type.

```javascript
import { get, step, value, iter } from "@hyperjump/browser";

const aNewHope = await get("https://swapi.hyperjump.io/api/films/1");
const characters = await get("#/characters", aNewHope); // Or
const characters = await step("characters", aNewHope);

for await (const character of iter(characters)) {
  const name = await step("name", character);
  value(name); // => Luke Skywalker, etc.
}
```

You can also work with files on the file system. When working with files, media
types are determined by file extensions. The [JRef] media type uses the `.jref`
extension.

```javascript
import { get, value } from "@hyperjump/browser";

const lukeSkywalker = await get("./api/people/1.jref"); // Paths resolve relative to the current working directory
const name = await step("name", lukeSkywalker);
value(name); // => Luke Skywalker
```

### API

* get(uri: string, browser?: Browser): Promise\<Browser>

    Retrieve a document located at the given URI. Support for [JRef] is built
    in. See the [Media Types](#media-type) section for information on how
    to support other media types. Support for `http(s):` and `file:` URI schemes
    are built in. See the [Uri Schemes](#uri-schemes) section for information on
    how to support other URI schemes.
* value(browser: Browser) => JRef

    Get the JRef compatible value the document represents.
* typeOf(browser: Browser) => JRefType

    Works the same as the `typeof` keyword. It will return one of the JSON types
    (null, boolean, number, string, array, object) or "reference". If the value
    is not one of these types, it will throw an error.
* has(key: string, browser: Browser) => boolean

    Returns whether or not a property is present in the object that the browser
    represents.
* length(browser: Browser) => number

    Get the length of the array that the browser represents.
* step(key: string | number, browser: Browser) => Promise\<Browser>

    Move the browser cursor by the given "key" value. This is analogous to
    indexing into an object or array (`foo[key]`). This function supports
    curried application.
* iter(browser: Browser) => AsyncGenerator\<Browser>

    Iterate over the items in the array that the document represents.
* entries(browser: Browser) => AsyncGenerator\<[string, Browser]>

    Similar to `Object.entries`, but yields Browsers for values.
* values(browser: Browser) => AsyncGenerator\<Browser>

    Similar to `Object.values`, but yields Browsers for values.
* keys(browser: Browser) => Generator\<string>

    Similar to `Object.keys`.

## Media Types

Support for the [JRef] media type is included by default, but you can add
support for any media type you like as long as it can be represented in a
[JRef]-compatible way.

```javascript
import { addMediaTypePlugin, removeMediaTypePlugin, setMediaTypeQuality } from "@hyperjump/browser";
import YAML from "yaml";

// Add support for YAML version of JRef (YRef)
addMediaTypePlugin("application/reference+yaml", {
  parse: async (response) => {
    return {
      baseUri: response.url,
      root: (response) => YAML.parse(await response.text(), (key, value) => {
        return value !== null && typeof value.$ref === "string"
          ? new Reference(value.$ref)
          : value;
      },
      anchorLocation: (fragment) => decodeUri(fragment ?? "");
    };
  },
  fileMatcher: (path) => path.endsWith(".jref")
});

// Prefer "YRef" over JRef by reducing the quality for JRef.
setMediaTypeQuality("application/reference+json", 0.9);

// Only support YRef by removing JRef support.
removeMediaTypePlugin("application/reference+json");
```

### API

* addMediaTypePlugin(contentType: string, plugin: MediaTypePlugin): void

    Add support for additional media types.

  * type MediaTypePlugin
    * parse: (response: Response) => Document
    * [quality](https://developer.mozilla.org/en-US/docs/Glossary/Quality_values):
      number (defaults to `1`)
* removeMediaTypePlugin(contentType: string): void

    Removed support or a media type.
* setMediaTypeQuality(contentType: string, quality: number): void;

    Set the
    [quality](https://developer.mozilla.org/en-US/docs/Glossary/Quality_values)
    that will be used in the
    [Accept](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Accept)
    header of requests to indicate to servers what media types are preferred
    over others.
* acceptableMediaTypes(): string;

    Build an `Accept` request header from the registered media type plugins.
    This function is used internally. You would only need it if you're writing a
    custom `http(s):` URI scheme plugin.

## URI Schemes

By default, `http(s):` and `file:` URIs are supported. You can add support for
additional URI schemes using plugins.

```javascript
import { addUriSchemePlugin, removeUriSchemePlugin, retrieve } from "@hyperjump/browser";

// Add support for the `urn:` scheme
addUriSchemePlugin("urn", {
  parse: (urn, baseUri) => {
    let { nid, nss, query, fragment } = parseUrn(urn);
    nid = nid.toLowerCase();

    if (!mappings[nid]?.[nss]) {
      throw Error(`Not Found -- ${urn}`);
    }

    let uri = mappings[nid][nss];
    uri += query ? "?" + query : "";
    uri += fragment ? "#" + fragment : "";

    return retrieve(uri, baseUri);
  }
});

// Only support `urn:` by removing default plugins
removeUriSchemePlugin("http");
removeUriSchemePlugin("https");
removeUriSchemePlugin("file");
```

### API
* addUriSchemePlugin(scheme: string, plugin: UriSchemePlugin): void

    Add support for additional URI schemes.

  * type UriSchemePlugin
    * retrieve: (uri: string, baseUri?: string) => Promise\<Response>
* removeUriSchemePlugin(scheme: string): void

    Remove support for a URI scheme.
* retrieve(uri: string, baseUri?: string) => Promise\<Response>

    This is used internally, but you may need it if mapping names to locators
    such as in the example above.

## JRef

`parse` and `stringify` [JRef] values using the same API as the `JSON` built-in
functions including `reviver` and `replacer` functions.

```javascript
import { parse, stringify, jrefTypeOf } from "@hyperjump/browser/jref";

const blogPostJref = `{
  "title": "Working with JRef",
  "author": { "$ref": "/author/jdesrosiers" },
  "content": "lorem ipsum dolor sit amet",
}`;
const blogPost = parse(blogPostJref);
jrefTypeOf(blogPost.author) // => "reference"
blogPost.author.href; // => "/author/jdesrosiers"

stringify(blogPost, null, "  ") === blogPostJref // => true
```

### API
export type Replacer = (key: string, value: unknown) => unknown;

* parse: (jref: string, reviver?: (key: string, value: unknown) => unknown) => JRef;

    Same as `JSON.parse`, but converts `{ "$ref": "..." }` to `Reference`
    objects.
* stringify: (value: JRef, replacer?: (string | number)[] | null | Replacer, space?: string | number) => string;

    Same as `JSON.stringify`, but converts `Reference` objects to `{ "$ref":
    "... " }`
* jrefTypeOf: (value: unknown) => "object" | "array" | "string" | "number" | "boolean" | "null" | "reference" | "undefined";

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

[JRef]: https://github.com/hyperjump-io/browser/blob/main/lib/jref/SPECIFICATION.md
