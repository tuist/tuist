# URI
A small and fast library for validating, parsing, and resolving URIs
([RFC 3986](https://www.rfc-editor.org/rfc/rfc3986)) and IRIs
([RFC 3987](https://www.rfc-editor.org/rfc/rfc3987)).

## Install
Designed for node.js (ES Modules, TypeScript) and browsers.

```
npm install @hyperjump/uri
```

## Usage
```javascript
import { resolveUri, parseUri, isUri, isIri } from "@hyperjump/uri"

const resolved = resolveUri("foo/bar", "http://example.com/aaa/bbb"); // https://example.com/aaa/foo/bar

const components = parseUri("https://jason@example.com:80/foo?bar#baz"); // {
//   scheme: "https",
//   authority: "jason@example.com:80",
//   userinfo: "jason",
//   host: "example.com",
//   port: "80",
//   path: "/foo",
//   query: "bar",
//   fragment: "baz"
// }

const a = isUri("http://examplé.org/rosé#"); // false
const a = isIri("http://examplé.org/rosé#"); // true
```

## API
### Resolve Relative References
These functions resolve relative-references against a base URI/IRI. The base
URI/IRI must be absolute, meaning it must have a scheme (`https`) and no
fragment (`#foo`). The resolution process will [normalize](#normalize) the
result.

* **resolveUri**: (uriReference: string, baseUri: string) => string
* **resolveIri**: (iriReference: string, baseIri: string) => string

### Normalize
These functions apply the following normalization rules.
1. Decode any unnecessarily percent-encoded characters.
2. Convert any lowercase characters in the hex numbers of percent-encoded
   characters to uppercase.
3. Resolve and remove any dot-segments (`/.`, `/..`) in paths.
4. Convert the scheme to lowercase.
5. Convert the authority to lowercase.

* **normalizeUri**: (uri: string) => string
* **normalizeIri**: (iri: string) => string

### To Relative
These functions convert a non-relative URI/IRI into a relative URI/IRI given a
base.

* **toRelativeUri**: (uri: string, relativeTo: string) => string
* **toRelativeIri**: (iri: string, relativeTo: string) => string

### URI
A [URI](https://www.rfc-editor.org/rfc/rfc3986#section-3) is not relative and
may include a fragment.

* **isUri**: (value: string) => boolean
* **parseUri**: (value: string) => IdentifierComponents
* **toAbsoluteUri**: (value: string) => string

    Takes a URI and strips its fragment component if it exists.

### URI-Reference
A [URI-reference](https://www.rfc-editor.org/rfc/rfc3986#section-4.1) may be
relative.

* **isUriReference**: (value: string) => boolean
* **parseUriReference**: (value: string) => IdentifierComponents

### absolute-URI
An [absolute-URI](https://www.rfc-editor.org/rfc/rfc3986#section-4.3) is not
relative an does not include a fragment.

* **isAbsoluteUri**: (value: string) => boolean
* **parseAbsoluteUri**: (value: string) => IdentifierComponents

### IRI
An IRI is not relative and may include a fragment.

* **isIri**: (value: string) => boolean
* **parseIri**: (value: string) => IdentifierComponents
* **toAbsoluteIri**: (value: string) => string

    Takes an IRI and strips its fragment component if it exists.

### IRI-reference
An IRI-reference may be relative.

* **isIriReference**: (value: string) => boolean
* **parseIriReference**: (value: string) => IdentifierComponents

### absolute-IRI
An absolute-IRI is not relative an does not include a fragment.

* **isAbsoluteIri**: (value: string) => boolean
* **parseAbsoluteIri**: (value: string) => IdentifierComponents

### Types
* **IdentifierComponents**
  * **scheme**: string
  * **authority**: string
  * **userinfo**: string
  * **host**: string
  * **port**: string
  * **path**: string
  * **query**: string
  * **fragment**: string

## Contributing
### Tests
Run the tests
```
npm test
```

Run the tests with a continuous test runner
```
npm test -- --watch
```
