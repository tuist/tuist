# Organization-Level Custom Cache Endpoints

## Overview

Allow users to configure custom cache endpoints at the organization (account) level for self-hosted cache scenarios. When custom endpoints are configured for an organization, the CLI will use those instead of the default Tuist-hosted cache endpoints.

### Current Behavior

1. **Server** (`lib/tuist_web/controllers/api/cache_controller.ex:60-63`):
   - The `/api/cache/endpoints` endpoint returns global, environment-based endpoints from `Tuist.Environment.cache_endpoints()`
   - Production returns: `cache-eu-central.tuist.dev`, `cache-us-east.tuist.dev`, `cache-us-west.tuist.dev`, `cache-ap-southeast.tuist.dev`
   - No organization-specific configuration exists

2. **CLI** (`Sources/TuistCAS/Services/CacheURLStore.swift`):
   - Fetches endpoints from the server via `GetCacheEndpointsService`
   - Measures latency to all endpoints and selects the fastest one
   - Caches the best endpoint for 1 hour
   - Currently does not pass organization information when requesting endpoints

### Desired Behavior

1. Each organization can optionally configure one or more custom cache endpoint URLs
2. When an organization has custom endpoints configured, the API returns ONLY those (not the defaults)
3. When no custom endpoints are configured, the API returns the default Tuist-hosted endpoints (unchanged behavior)
4. The CLI passes the account handle as a query parameter to fetch organization-specific endpoints

## Server Changes

### 1. Database Migration

**File**: `server/priv/repo/migrations/YYYYMMDDHHMMSS_add_account_cache_endpoints_table.exs`

```elixir
defmodule Tuist.Repo.Migrations.AddAccountCacheEndpointsTable do
  use Ecto.Migration

  def change do
    create table(:account_cache_endpoints, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :url, :string, null: false

      timestamps(type: :timestamptz)
    end

    create index(:account_cache_endpoints, [:account_id])
  end
end
```

### 2. Ecto Schema

**File**: `server/lib/tuist/accounts/account_cache_endpoint.ex` (new)

```elixir
defmodule Tuist.Accounts.AccountCacheEndpoint do
  use Ecto.Schema
  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "account_cache_endpoints" do
    field :url, :string

    belongs_to :account, Account

    timestamps()
  end

  def create_changeset(endpoint \\ %__MODULE__{}, attrs) do
    endpoint
    |> cast(attrs, [:url, :account_id])
    |> validate_required([:url, :account_id])
    |> validate_url(:url)
    |> foreign_key_constraint(:account_id)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
          []
        _ ->
          [{field, "must be a valid HTTP or HTTPS URL"}]
      end
    end)
  end
end
```

### 3. Update Account Schema

**File**: `server/lib/tuist/accounts/account.ex`

Add the association:

```elixir
has_many :cache_endpoints, Tuist.Accounts.AccountCacheEndpoint
```

### 4. Context Functions

**File**: `server/lib/tuist/accounts.ex`

Add these functions:

```elixir
alias Tuist.Accounts.AccountCacheEndpoint

def list_account_cache_endpoints(%Account{} = account) do
  AccountCacheEndpoint
  |> where(account_id: ^account.id)
  |> Repo.all()
end

def create_account_cache_endpoint(%Account{} = account, attrs) do
  %AccountCacheEndpoint{}
  |> AccountCacheEndpoint.create_changeset(Map.put(attrs, :account_id, account.id))
  |> Repo.insert()
end

def delete_account_cache_endpoint(%AccountCacheEndpoint{} = endpoint) do
  Repo.delete(endpoint)
end

def get_account_cache_endpoint!(id) do
  Repo.get!(AccountCacheEndpoint, id)
end
```

### 5. Update Existing API Endpoint

**File**: `server/lib/tuist_web/controllers/api/cache_controller.ex`

Modify the existing `endpoints` action to accept an optional `account_handle` query parameter:

```elixir
operation(:endpoints,
  summary: "Get cache endpoints.",
  description: "Returns custom cache endpoints if configured for the account, otherwise returns default endpoints.",
  operation_id: "getCacheEndpoints",
  parameters: [
    account_handle: [
      in: :query,
      type: :string,
      required: false,
      description: "The name of the account to get custom cache endpoints for."
    ]
  ],
  responses: %{
    ok:
      {"List of cache endpoints", "application/json",
       %Schema{
         title: "CacheEndpoints",
         description: "List of available cache endpoints",
         type: :object,
         required: [:endpoints],
         properties: %{
           endpoints: %Schema{
             type: :array,
             items: %Schema{type: :string}
           }
         }
       }},
    unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
    not_found: {"The account was not found", "application/json", Error}
  }
)

def endpoints(conn, params) do
  endpoints =
    case params do
      %{account_handle: account_handle} when is_binary(account_handle) ->
        case Tuist.Accounts.get_account_by_name(account_handle) do
          nil ->
            # Account not found, return defaults
            Tuist.Environment.cache_endpoints()

          account ->
            custom_endpoints = Tuist.Accounts.list_account_cache_endpoints(account)

            if Enum.empty?(custom_endpoints) do
              Tuist.Environment.cache_endpoints()
            else
              Enum.map(custom_endpoints, & &1.url)
            end
        end

      _ ->
        Tuist.Environment.cache_endpoints()
    end

  json(conn, %{endpoints: endpoints})
end
```

### 6. Update AccountSettingsLive

**File**: `server/lib/tuist_web/live/account_settings_live.ex`

Add cache endpoint management to the existing LiveView (following the pattern of region selection):

- Add `cache_endpoints` to the assigns via preload
- Add `add_cache_endpoint_form` assign
- Add event handlers: `create_cache_endpoint`, `delete_cache_endpoint`, `close_add_cache_endpoint_modal`

### 7. Update AccountSettingsLive Template

**File**: `server/lib/tuist_web/live/account_settings_live.html.heex`

Add a cache endpoints section below the region selection section. This should include:
- A card with title "Custom cache endpoints"
- An "Add endpoint" button that opens a modal
- A table showing existing endpoints with delete buttons
- Info alerts explaining the behavior

## CLI Changes

### 8. Update GetCacheEndpointsService

**File**: `cli/Sources/TuistServer/Services/GetCacheEndpointsService.swift`

The service needs to pass an optional `account_handle` query parameter:

```swift
@Mockable
public protocol GetCacheEndpointsServicing: Sendable {
    func getCacheEndpoints(
        serverURL: URL,
        accountHandle: String?
    ) async throws -> [String]
}

public struct GetCacheEndpointsService: GetCacheEndpointsServicing {
    public init() {}

    public func getCacheEndpoints(
        serverURL: URL,
        accountHandle: String?
    ) async throws -> [String] {
        let client = Client.authenticated(serverURL: serverURL)

        let response = try await client.getCacheEndpoints(
            .init(query: .init(account_handle: accountHandle))
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(endpoints):
                return endpoints.endpoints
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetCacheEndpointsServiceError.unknownError(statusCode)
        case let .notFound(notFoundResponse):
            throw GetCacheEndpointsServiceError.accountNotFound(accountHandle ?? "unknown")
        }
    }
}

enum GetCacheEndpointsServiceError: LocalizedError {
    case unknownError(Int)
    case accountNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to retrieve cache endpoints due to an unknown server response of \(statusCode)."
        case let .accountNotFound(handle):
            return "Account not found: \(handle)"
        }
    }
}
```

### 9. Update CacheURLStore

**File**: `cli/Sources/TuistCAS/Services/CacheURLStore.swift`

Update the protocol and implementation to accept `accountHandle`:

```swift
@Mockable
public protocol CacheURLStoring: Sendable {
    func getCacheURL(for serverURL: URL, accountHandle: String?) async throws -> URL
}

public struct CacheURLStore: CacheURLStoring {
    // ... existing properties ...

    public func getCacheURL(for serverURL: URL, accountHandle: String?) async throws -> URL {
        // Include accountHandle in cache key to cache per-account
        let key = "cache_url_\(serverURL.absoluteString)_\(accountHandle ?? "global")"
        let nsKey = key as NSString

        // ... rest of implementation with accountHandle passed to selectBestEndpoint ...
    }

    private func selectBestEndpoint(for serverURL: URL, accountHandle: String?) async throws -> (value: String, expiresAt: Date?)? {
        let endpoints = try await getCacheEndpointsService.getCacheEndpoints(
            serverURL: serverURL,
            accountHandle: accountHandle
        )
        // ... rest of implementation unchanged ...
    }
}
```

### 10. Update Callers

Update all callers of `CacheURLStore.getCacheURL` to pass the `accountHandle`:

**Files to update**:
- `cli/Sources/TuistCAS/Services/CASService.swift` - extract account from `fullHandle` and pass to `cacheURLStore.getCacheURL`
- `cli/Sources/TuistCAS/Services/KeyValueService.swift` - extract account from `fullHandle` and pass to `cacheURLStore.getCacheURL`

Example for extracting account handle:
```swift
let accountHandle = fullHandle.split(separator: "/").first.map(String.init)
let cacheURL = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)
```

### 11. Regenerate OpenAPI Client

After the server changes are deployed and the OpenAPI spec is updated:

```bash
cd server && mise run generate-api-cli-code
```

This will regenerate `cli/Sources/TuistServer/OpenAPI/Client.swift` and `Types.swift` with the updated `getCacheEndpoints` operation including the query parameter.

## Tests

### Server Tests

**File**: `server/test/tuist/accounts/account_cache_endpoint_test.exs` (new)

Test the schema changesets and validations.

**File**: `server/test/tuist/accounts_test.exs`

Add tests for new context functions:
- `list_account_cache_endpoints/1`
- `create_account_cache_endpoint/2`
- `delete_account_cache_endpoint/1`

**File**: `server/test/tuist_web/controllers/api/cache_controller_test.exs`

Add tests for updated `endpoints` action:
- Returns default endpoints when no account_handle provided
- Returns default endpoints when account has no custom endpoints configured
- Returns only custom endpoints when account has them configured
- Returns default endpoints when account_handle not found (graceful fallback)

**File**: `server/test/tuist_web/live/account_settings_live_test.exs`

Add tests for cache endpoint management:
- Renders cache endpoints section
- Can add a new endpoint
- Can delete an endpoint

### CLI Tests

**File**: `cli/Tests/TuistServerTests/Services/GetCacheEndpointsServiceTests.swift`

Update existing tests and add:
- Test with accountHandle provided
- Test with nil accountHandle (backward compatibility)

**File**: `cli/Tests/TuistCASTests/CacheURLStoreTests.swift`

Update tests to pass accountHandle parameter.

## Documentation Update

**File**: `server/data-export.md`

Add documentation for the new `account_cache_endpoints` table:

```markdown
### Account Cache Endpoints

**Table**: `account_cache_endpoints`

Stores custom cache endpoint URLs configured for accounts/organizations.

| Column | Description |
|--------|-------------|
| id | Unique identifier (UUID) |
| account_id | Reference to the account |
| url | The cache endpoint URL |
| inserted_at | Creation timestamp |
| updated_at | Last update timestamp |

**Export**: Included in account data exports.
```

## Implementation Order

1. **Server: Database & Schema**
   - Create migration
   - Create `AccountCacheEndpoint` schema
   - Update `Account` schema with association
   - Add context functions to `Accounts`

2. **Server: API Endpoint**
   - Update `endpoints` action in `CacheController` to accept query parameter
   - Write controller tests

3. **Server: Settings UI**
   - Update `AccountSettingsLive` with cache endpoint management
   - Update template with cache endpoints section
   - Write LiveView tests

4. **CLI: Service Updates**
   - Update `GetCacheEndpointsService` protocol and implementation
   - Update `CacheURLStore` protocol and implementation
   - Update callers (`CASService`, `KeyValueService`)
   - Update tests

5. **CLI: OpenAPI Regeneration**
   - Regenerate OpenAPI client code
   - Verify generated code compiles

6. **Documentation**
   - Update `data-export.md`
