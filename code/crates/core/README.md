# Mobile core contract

The Tuist Code native clients use this crate; it does not migrate or replace the
shipping apps' credential stores. Keep its vault in a separate Tuist Code secure
storage namespace. On macOS only, it also uses the shipping Tuist app's Keychain
session through the `shared_*` actions below, without copying its tokens into
the vault. Never log host actions, HTTP authorization/body fields, or the
vault. Run calls on a background thread; they are synchronous and serialized for
the entire operation, including native callbacks. A callback must not reenter.

## Bridges

Apple uses `include/tuist_app.h`. `tuist_app_call(request_json, host, context)`
returns an owned NUL-terminated UTF-8 string, freed once with `tuist_app_free`.
The host's NUL-terminated response remains **host-owned** and valid until the next
host invocation. Rust copies it immediately; no host free callback is needed.
Inputs need only remain valid for the duration of their call.

Android exports `Java_dev_tuist_code_AppCore_request`, implementing
`AppCore.private external fun request(input: String, host: AppHost): String`.
`AppHost` exposes `public fun perform(action: String): String`. Keep these names
and the callback method from obfuscation. JNI callback exceptions become sanitized
errors, not exception messages. The JNI dependency is Android-only for normal
builds, and also a test dependency to compile-check marshalling on Linux.

Existing tab IDs (`previews`, `profile`) and catalog C/JNI symbols are unchanged.
Rust callers can instantiate `MobileClient` and implement `Host` independently.

## Native host actions

| Action | Response |
| --- | --- |
| `{"type":"read"}` | `{"value":null}` or `{"value":"<opaque vault JSON>"}` |
| `{"type":"write","value":"<opaque vault JSON>"}` | `{"ok":true}` |
| `{"type":"http","method":"GET","url":"https://…","headers":{"Accept":"application/json",…},"body":"optional string"}` | `{"status":200,"body":"<response text>"}` |
| macOS only: `{"type":"shared_list"}` | `{"servers":["https://tuist.dev",…]}`, the canonical URLs the Tuist app holds a refresh token for |
| macOS only: `{"type":"shared_read","server":"https://tuist.dev"}` | `{"value":null}` or `{"value":{"access_token":"…","refresh_token":"…" or null,"oauth_client_id":"…" or null,"rejected":false}}` |
| macOS only: `{"type":"shared_write","server":"…","access_token":"…","refresh_token":"…"}` | `{"ok":true}` after updating the existing refresh then access items in place |

The `shared_*` actions use `ServerCredentialsStore`'s Keychain layout: internet
passwords for the server's host, HTTPS, default authentication type, with
accounts `<server>_access_token`, `_refresh_token`, `_oauth_client_id` and
`_rejected`. Hosts must never create or delete those items. The core calls
`shared_write`, and the reread that decides whether to refresh, only while it
holds `<state>/cached_value_store/credential-refresh-<fnv1a64(server)>.lock`,
the lock the Tuist app and CLI hold for the same storage key. iOS and Android
hosts answer them with an error.

Every action may instead return `{"error":"…"}`. The core deliberately does not
display that message. Write success means durable completion, not a queued write.
Read failures must be errors, never `value:null`. HTTP must use platform TLS,
forbid insecure HTTP except loopback, and forbid cross-origin redirects. No
credential-bearing request may be redirected to another origin. Native hosts
must enforce response size/time limits. The core does not follow redirects or
retry HTTP itself; transient failures preserve saved credentials for a later call.

## Operations

Requests are `{"operation":"…","args":{…}}`. No-argument operations may omit
`args`. Responses always have `view` and `data`, plus `error` on failure:

```json
{
  "view": {
    "profiles": [{"id":"opaque","server":"https://tuist.dev/","handle":"ana","email":"ana@example.com","organization":null,"organizations":[],"rejected":false,"shared":false}],
    "active_profile_id":"opaque",
    "generation":1
  },
  "data":null
}
```

Tokens never belong in a view. Raw API data is retained except secret fields and
credential strings are scrubbed; errors are fixed, credential-free messages.
`rejected` also includes membership-access denial: do not offer these profiles
for organization selection. Generation advances on durable profile/selection or
membership commits, not on token rotation. Always render the returned view even
when an operation reports an error.

| Operation | Args | Data |
| --- | --- | --- |
| `snapshot` | none | null |
| `begin_sign_in` | `server`, optional `provider`: `tuist` (default), `github`, `google`, `apple` | `{url,callback_scheme:"tuist-code"}` |
| `finish_sign_in` | `url` | null |
| `cancel_sign_in` | none | null |
| `switch_profile` | `id` | null |
| `select_organization` | profile `id`, `name` (null or account handle selects personal account) | null |
| `sign_out` | none | null; removes active profile, selects first eligible fallback |
| `organizations` | none | `[{id:<profile ID>,response:<raw organizations response>},…]` |
| `projects` | none | `{projects:[…]}`; complete enumeration, deduplicated and account-scoped |
| `previews` | `project`: `account/project`, optional nullable `track`, `search`, `page` (default 1), `page_size` (default 20, maximum 100) | raw previews response |
| `tracks` | `project` | raw full-project `{total_count,tracks:[{name,count}]}` |
| `preview` | `project`, preview `id` | raw preview response |
| `delete_preview` | `project`, preview `id` | null on 204 |
| `delete_account` | none | null; deletes personal account and removes active profile |

Project requests must match the selected organization, or personal account when
none is selected. The verified paths are `/api/projects`, `/api/organizations`,
`/api/projects/{account}/{project}/previews`, that path plus `/tracks` or
`/{id}`, and `/api/accounts/{personal_handle}` for account deletion. Self-hosted
base paths are retained. Project pagination is followed only when the server
advertises more pages; repeated/empty nonterminal pages are errors. The current
server returns all projects without pagination. Ignored track/search semantics
are rejected when returned rows do not match, never repaired into partial totals.
Track discovery does not derive choices/counts from downloaded previews. An older
server's missing discovery is an error for that operation; browsing still works.

Sign-in dynamically registers a public PKCE client using the same-origin server
metadata endpoint, with the distinct `tuist-code://oauth-callback` redirect.
The exact callback authority/path, a unique state and code are required. Every
finish consumes its pending attempt, including malformed/tampered callbacks.
Cancel preserves the current selection. PKCE, authorization URL construction and
JWT identity/expiry parsing reuse the existing OAuth/JWT crates. Credentials are
deduplicated by normalized origin and JWT user identity, not email or username.

Token refresh starts 30 seconds before expiry at the profile's own `/oauth2/token`
with its issuing client ID. Transient failures retain the pair; invalid_grant,
401 and tokenless success mark the profile rejected. A rotated pair is retained
in memory even if secure storage fails. Every subsequent operation first retries
the pending durable write, and performs no other work until it succeeds. Native
storage failure must remain visible; restarting the process before a failed write
can be recovered cannot preserve memory-only credentials.

On macOS, `snapshot` also adds a profile with `"shared":true` for each Tuist app
session, unless the user signed out of it here or already has a profile for that
identity, and drops shared profiles whose session is gone. Refreshing one holds
the lock above, rereads the items, and uses a peer's pair when it is no longer
expiring. Otherwise it refreshes with the stored client ID (the built-in Tuist
app client when absent), or `/api/auth/refresh_token` for legacy tokens, and
updates the items. A peer's newer pair wins over a replayed or rejected
response. A rejection disables the profile here without marking the Tuist app's
items. `sign_out` on a shared profile only unlinks it.
