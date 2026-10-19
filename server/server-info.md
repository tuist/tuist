# Server information discovery

`GET /.well-known/tuist` returns optional, public deployment metadata for native
clients. This is a Tuist-specific JSON contract, not a standard application-version
endpoint. Deployments mounted below a base path expose it below that path, like the
existing OAuth discovery document.

```http
GET /.well-known/tuist
Accept: application/json

HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: public, max-age=300

{"version":"1.37.0"}
```

`version` is the deployment's `Tuist.Environment.version()` value: `TUIST_VERSION`
when set, otherwise the application version. Hosted releases may use deployment
identifiers rather than semantic versions. It is distinct from the native app
version and the MCP server's advertised version. No credentials, customer data,
internal topology, or development branch names are included.

## Compatibility contract

- The endpoint is additive and unauthenticated. Existing clients do not need to
  request it, send a client version, or change their authentication flow.
- Clients must ignore unknown JSON fields. Existing field names and types remain
  stable; future metadata is added as optional fields.
- `version` is optional: clients accept an absent or null field and ignore an empty
  or unusable value. They must not require a particular release-string format.
- Older servers may return 404, an HTML fallback, or another non-success response.
  Clients must continue to sign in and browse normally without server metadata.
- Metadata is informational, never an authentication or capability-negotiation
  mechanism. Check API capabilities independently rather than comparing versions.
- The connected server address comes from the session, not the response. A
  discovery document cannot change a client's selected server.

## Apple clients

The iOS Profile and macOS Account settings always show the session's server
address, including any port or base path. They show Server version only when a
usable value is available. Discovery is lazy and never blocks authentication or
browsing, and failures do not produce an alert.

`AppServerInfoService` is a stateless, `Sendable` value type. It uses a separate
ephemeral session without cookies, stored credentials, or a client-side metadata
cache. It does not follow redirects, retains normal TLS validation, and bounds
responses to 64 KiB while reading, including responses without Content-Length.
Each lookup uses the complete connected server base URL. A server upgraded from
an older version can therefore supply metadata on the next visit to Profile or
Account settings, without waiting for a negative cache to expire.

The views discard cancelled or superseded results and only display metadata tagged
with their current server URL. No metadata is persisted with authentication state.
The five-minute public cache header is for intermediary caches, not an application
version-negotiation mechanism.
