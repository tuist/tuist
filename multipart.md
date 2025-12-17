# Multipart Upload Implementation Plan for Module Cache

## Overview

Replace the current single-request module cache upload with a multipart upload system. The client will stream the artifact file in 10MB chunks, sending each chunk as a separate HTTP request. This eliminates the need to load entire artifacts into memory on the client side.

**Key Design Decisions:**
- No backward compatibility needed - old `upload/2` endpoint will be removed
- No client-side abort endpoint needed - server-side cleanup (5 min timeout) is sufficient
- Retry semantics: if any part fails, the entire multipart upload is restarted from scratch
- Server enforces size limits: 10MB per part, 500MB total per upload
- The `complete` request includes part numbers for verification against server state

---

## Current State Analysis

### Submodule API Mismatch (Critical Bug)

The submodule `cli/TuistCacheEE/Sources/Storage/ModuleCacheRemoteStorage.swift` is currently broken:

- **Line 305:** Calls `loadModuleCacheService.loadModuleCache(fullHandle:...)` 
  - Should be: `downloadModuleCacheArtifact(accountHandle:projectHandle:...)`
- **Line 377:** Calls `saveModuleCacheService.saveModuleCache(data, fullHandle:...)`
  - Should be: `uploadModuleCacheArtifact(data, accountHandle:projectHandle:...)`

The service interfaces (`SaveModuleCacheServicing`, `LoadModuleCacheServicing`) already use split handles and different method names, but the submodule hasn't been updated.

### Current Upload Flow (to be replaced)

**Client side (`ModuleCacheRemoteStorage.swift` lines 371-387):**
```swift
let data = try Data(contentsOf: zipPath.url)  // Loads entire file into memory!
try await retryProvider.runWithRetries {
    try await saveModuleCacheService.saveModuleCache(data, ...)
}
```

**Server side (`module_cache_controller.ex`):**
1. Check if artifact exists on disk → drain body and return 204
2. Read body via `BodyReader.read(conn)` (streams large files to temp file)
3. Call `Disk.module_put()` to persist
4. Track artifact access via `CacheArtifacts.track_artifact_access()`
5. Enqueue S3 upload via `S3Transfers.enqueue_module_upload()`

### Existing Patterns to Follow

**Temp files:** Use `System.tmp_dir!()` directly (see `cache/lib/cache/body_reader.ex` line 146-149)
```elixir
defp tmp_path do
  base = System.tmp_dir!()
  unique = :erlang.unique_integer([:positive, :monotonic])
  Path.join(base, "cache-upload-#{unique}")
end
```

**Body reading:** `BodyReader` has configurable options via `conn.private[:body_read_opts]`

**OpenAPI generation:** Run `mise run generate-api-cli-code` from `cache/` directory (see `cache/mise/tasks/generate-api-cli-code.sh`)

**Swift service pattern:** All services follow this structure:
```swift
@Mockable
public protocol <Name>Servicing: Sendable {
    func <operation>(...) async throws -> <Result>
}

public enum <Name>ServiceError: LocalizedError { ... }

public struct <Name>Service: <Name>Servicing {
    public init() {}
    public func <operation>(...) async throws -> <Result> {
        let client = Client.authenticated(...)
        let response = try await client.<openAPIMethod>(...)
        switch response { ... }
    }
}
```

---

## Phase 1: Submodule Fix (Prerequisite)

**File:** `cli/TuistCacheEE/Sources/Storage/ModuleCacheRemoteStorage.swift`

**Repository:** This is a git submodule (private, closed-source). Commit changes directly via git.

### Changes Required

1. **Split `fullHandle` into components** (add helper or inline):
```swift
// fullHandle format: "org/project"
let components = fullHandle.split(separator: "/", maxSplits: 1)
let accountHandle = String(components[0])
let projectHandle = String(components[1])
```

2. **Update `fetch()` method (line ~305):**
```swift
// OLD:
let data = try await loadModuleCacheService.loadModuleCache(
    fullHandle: fullHandle,
    hash: item.hash,
    ...
)

// NEW:
let data = try await loadModuleCacheService.downloadModuleCacheArtifact(
    accountHandle: accountHandle,
    projectHandle: projectHandle,
    hash: item.hash,
    ...
)
```

3. **Update `store()` method (line ~377):**
```swift
// OLD:
try await saveModuleCacheService.saveModuleCache(
    data,
    fullHandle: fullHandle,
    ...
)

// NEW:
try await saveModuleCacheService.uploadModuleCacheArtifact(
    data,
    accountHandle: accountHandle,
    projectHandle: projectHandle,
    ...
)
```

This phase can be done independently and fixes the current broken state.

---

## Phase 2: Cache Server (Elixir) Changes

### 2.1 New Module: `cache/lib/cache/multipart_uploads.ex`

GenServer with ETS-based state management for in-progress multipart uploads.

**Public Functions:**
```elixir
@spec start_upload(String.t(), String.t(), String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
def start_upload(account_handle, project_handle, category, hash, name)
# Initialize upload state, return upload_id (UUID)

@spec add_part(String.t(), pos_integer(), String.t(), pos_integer()) :: :ok | {:error, term()}
def add_part(upload_id, part_number, temp_file_path, size_bytes)
# Record a received part's temp file path and size
# Returns {:error, :upload_not_found} if upload_id invalid
# Returns {:error, :part_too_large} if size > 10MB
# Returns {:error, :total_size_exceeded} if cumulative > 500MB

@spec get_upload(String.t()) :: {:ok, map()} | {:error, :not_found}
def get_upload(upload_id)
# Get upload metadata and parts

@spec complete_upload(String.t()) :: {:ok, map()} | {:error, term()}
def complete_upload(upload_id)
# Return upload metadata with parts list for assembly, remove from ETS
# Does NOT delete temp files (caller handles after assembly)

@spec abort_upload(String.t()) :: :ok
def abort_upload(upload_id)
# Cleanup temp files and ETS entry
```

**ETS Table Structure:**
```elixir
# Table name: :multipart_uploads
# Key: upload_id (UUID string)
# Value: map with following structure
%{
  account_handle: String.t(),
  project_handle: String.t(),
  category: String.t(),
  hash: String.t(),
  name: String.t(),
  parts: %{
    # part_number => %{path: temp_file_path, size: bytes}
    1 => %{path: "/tmp/cache-part-12345", size: 10_485_760},
    2 => %{path: "/tmp/cache-part-12346", size: 5_242_880}
  },
  total_bytes: integer(),  # Cumulative size for 500MB limit enforcement
  created_at: DateTime.t()
}
```

**Size Limits (enforced in add_part):**
- Max part size: 10MB (`10 * 1024 * 1024` bytes)
- Max total size: 500MB (`500 * 1024 * 1024` bytes)

**Automatic Cleanup:**
- Use `Process.send_after(self(), :cleanup_abandoned, 60_000)` in `init/1`
- On `:cleanup_abandoned`, iterate ETS entries and delete those older than 5 minutes
- Delete associated temp files when cleaning up
- Reschedule cleanup after each run

### 2.2 Update Application: `cache/lib/cache/application.ex`

Add `Cache.MultipartUploads` to the supervision tree children list:

```elixir
children = [
  # ... existing children ...
  Cache.MultipartUploads,
  # ... rest of children ...
]
```

### 2.3 Update Router: `cache/lib/cache_web/router.ex`

**Remove** the existing single-upload route:
```elixir
# DELETE THIS:
post "/module", ModuleCacheController, :upload
```

**Add** new multipart routes under the existing `/api/cache` scope:
```elixir
scope "/api/cache", CacheWeb do
  pipe_through [:api_json, :open_api, :project_auth]
  
  # ... existing routes (download, exists, keyvalue, cas) ...
  
  # New multipart upload routes
  post "/module/start", ModuleCacheController, :start_multipart
  post "/module/part", ModuleCacheController, :upload_part
  post "/module/complete", ModuleCacheController, :complete_multipart
end
```

No abort endpoint needed - server-side cleanup handles abandoned uploads.

### 2.4 Update Controller: `cache/lib/cache_web/controllers/module_cache_controller.ex`

**Remove:**
- `upload/2` action and its OpenApiSpex operation
- `handle_existing_artifact/1` helper
- `save_new_artifact/6` helper  
- `persist_artifact/8` helper
- `get_data_size/1` helper
- `cleanup_tmp_file/1` helper

**Add three new actions:**

#### 2.4.1 `start_multipart/2`

```elixir
operation(:start_multipart,
  summary: "Start a multipart module cache upload",
  operation_id: "startModuleCacheMultipartUpload",
  parameters: [
    account_handle: [in: :query, type: :string, required: true, description: "The handle of the account"],
    project_handle: [in: :query, type: :string, required: true, description: "The handle of the project"],
    hash: [in: :query, type: :string, required: true, description: "Artifact hash"],
    name: [in: :query, type: :string, required: true, description: "Artifact name"],
    cache_category: [in: :query, type: :string, required: false, description: "Cache category (builds)"]
  ],
  responses: %{
    ok: {"Upload started", "application/json", CacheWeb.API.Schemas.StartMultipartUploadResponse},
    unauthorized: {"Unauthorized", "application/json", Error},
    forbidden: {"Forbidden", "application/json", Error},
    bad_request: {"Bad request", "application/json", Error}
  }
)

def start_multipart(conn, %{account_handle: account_handle, project_handle: project_handle, hash: hash, name: name} = params) do
  category = Map.get(params, :cache_category, "builds")
  
  # Check if artifact already exists
  if Disk.module_exists?(account_handle, project_handle, category, hash, name) do
    # Return nil upload_id to signal client should skip upload
    json(conn, %{upload_id: nil})
  else
    # Initialize new multipart upload
    {:ok, upload_id} = MultipartUploads.start_upload(account_handle, project_handle, category, hash, name)
    :telemetry.execute([:cache, :module, :multipart, :start], %{}, %{})
    json(conn, %{upload_id: upload_id})
  end
end
```

#### 2.4.2 `upload_part/2`

```elixir
operation(:upload_part,
  summary: "Upload a part of a multipart module cache upload",
  operation_id: "uploadModuleCachePart",
  parameters: [
    upload_id: [in: :query, type: :string, required: true, description: "The upload ID from start_multipart"],
    part_number: [in: :query, type: :integer, required: true, description: "Part number (1-indexed)"]
  ],
  request_body: {"The part data", "application/octet-stream", nil, required: true},
  responses: %{
    no_content: {"Part uploaded successfully", nil, nil},
    not_found: {"Upload not found", "application/json", Error},
    request_entity_too_large: {"Part exceeds 10MB limit", "application/json", Error},
    unprocessable_entity: {"Total upload size exceeds 500MB limit", "application/json", Error},
    request_timeout: {"Request body read timed out", "application/json", Error},
    unauthorized: {"Unauthorized", "application/json", Error},
    forbidden: {"Forbidden", "application/json", Error},
    bad_request: {"Bad request", "application/json", Error}
  }
)

def upload_part(conn, %{upload_id: upload_id, part_number: part_number}) do
  # Read body to temp file
  case read_part_body(conn) do
    {:ok, {:file, tmp_path}, size, conn_after} ->
      case MultipartUploads.add_part(upload_id, part_number, tmp_path, size) do
        :ok ->
          :telemetry.execute([:cache, :module, :multipart, :part], %{size: size, part_number: part_number}, %{})
          send_resp(conn_after, :no_content, "")
        
        {:error, :upload_not_found} ->
          File.rm(tmp_path)
          {:error, :not_found}
        
        {:error, :part_too_large} ->
          File.rm(tmp_path)
          {:error, :part_too_large}
        
        {:error, :total_size_exceeded} ->
          File.rm(tmp_path)
          {:error, :total_size_exceeded}
      end
    
    {:error, :too_large, _conn_after} ->
      {:error, :part_too_large}
    
    {:error, :timeout, _conn_after} ->
      {:error, :timeout}
    
    {:error, _reason, _conn_after} ->
      {:error, :read_error}
  end
end

# Helper to read part body (similar to BodyReader but always writes to file)
defp read_part_body(conn) do
  # Implementation streams body to temp file and returns path + size
  # Max 10MB enforced here
end
```

#### 2.4.3 `complete_multipart/2`

```elixir
operation(:complete_multipart,
  summary: "Complete a multipart module cache upload",
  operation_id: "completeModuleCacheMultipartUpload",
  parameters: [
    upload_id: [in: :query, type: :string, required: true, description: "The upload ID from start_multipart"]
  ],
  request_body: {"Completion request", "application/json", CacheWeb.API.Schemas.CompleteMultipartUploadRequest, required: true},
  responses: %{
    no_content: {"Upload completed successfully", nil, nil},
    not_found: {"Upload not found", "application/json", Error},
    bad_request: {"Parts mismatch or missing parts", "application/json", Error},
    internal_server_error: {"Failed to assemble artifact", "application/json", Error},
    unauthorized: {"Unauthorized", "application/json", Error},
    forbidden: {"Forbidden", "application/json", Error}
  }
)

def complete_multipart(conn, %{upload_id: upload_id}) do
  with {:ok, %{parts: parts_from_client}} <- get_request_body(conn),
       {:ok, upload} <- MultipartUploads.complete_upload(upload_id),
       :ok <- verify_parts(upload.parts, parts_from_client),
       part_paths <- get_ordered_part_paths(upload.parts, parts_from_client),
       :ok <- Disk.module_put_from_parts(
         upload.account_handle, 
         upload.project_handle, 
         upload.category, 
         upload.hash, 
         upload.name, 
         part_paths
       ) do
    
    # Cleanup temp files
    Enum.each(part_paths, &File.rm/1)
    
    # Track access and enqueue S3 upload
    key = Disk.module_key(upload.account_handle, upload.project_handle, upload.category, upload.hash, upload.name)
    :ok = CacheArtifacts.track_artifact_access(key)
    S3Transfers.enqueue_module_upload(upload.account_handle, upload.project_handle, upload.category, upload.hash, upload.name)
    
    :telemetry.execute([:cache, :module, :multipart, :complete], %{
      size: upload.total_bytes,
      parts_count: map_size(upload.parts)
    }, %{})
    
    send_resp(conn, :no_content, "")
  else
    {:error, :not_found} -> {:error, :not_found}
    {:error, :parts_mismatch} -> {:error, :parts_mismatch}
    {:error, _reason} -> {:error, :persist_error}
  end
end

defp verify_parts(server_parts, client_parts) do
  server_part_numbers = Map.keys(server_parts) |> Enum.sort()
  client_part_numbers = Enum.sort(client_parts)
  
  if server_part_numbers == client_part_numbers do
    :ok
  else
    {:error, :parts_mismatch}
  end
end

defp get_ordered_part_paths(server_parts, client_parts) do
  Enum.map(client_parts, fn part_num ->
    server_parts[part_num].path
  end)
end
```

### 2.5 New Schema: `cache/lib/cache_web/api/schemas/multipart_upload.ex`

```elixir
defmodule CacheWeb.API.Schemas.StartMultipartUploadResponse do
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "StartMultipartUploadResponse",
    description: "Response from starting a multipart upload",
    type: :object,
    properties: %{
      upload_id: %Schema{
        type: :string,
        nullable: true,
        description: "The upload ID to use for subsequent part uploads. Null if artifact already exists."
      }
    },
    required: [:upload_id]
  })
end

defmodule CacheWeb.API.Schemas.CompleteMultipartUploadRequest do
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "CompleteMultipartUploadRequest",
    description: "Request to complete a multipart upload",
    type: :object,
    properties: %{
      parts: %Schema{
        type: :array,
        items: %Schema{type: :integer},
        description: "Ordered list of part numbers that were uploaded"
      }
    },
    required: [:parts]
  })
end
```

### 2.6 Update Spec: `cache/lib/cache_web/api/spec.ex`

The schemas are auto-discovered via `OpenApiSpex.resolve_schema_modules/1`, but ensure the new schema module is in the `CacheWeb.API.Schemas` namespace.

### 2.7 Update Disk Module: `cache/lib/cache/disk.ex`

**Add new function:**

```elixir
@doc """
Assembles multiple part files into a single module cache artifact.
Parts are concatenated in the order provided.
"""
@spec module_put_from_parts(String.t(), String.t(), String.t(), String.t(), String.t(), [String.t()]) :: :ok | {:error, term()}
def module_put_from_parts(account_handle, project_handle, category, hash, name, part_paths) do
  key = module_key(account_handle, project_handle, category, hash, name)
  dest_path = artifact_path(key)
  
  # Ensure parent directory exists
  dest_path |> Path.dirname() |> File.mkdir_p!()
  
  # Check if already exists (race condition protection)
  if File.exists?(dest_path) do
    {:error, :exists}
  else
    # Write to temp file first, then rename for atomicity
    tmp_dest = dest_path <> ".tmp.#{:erlang.unique_integer([:positive])}"
    
    try do
      # Open destination file for writing
      {:ok, dest_file} = File.open(tmp_dest, [:write, :binary])
      
      # Stream each part into destination
      result = Enum.reduce_while(part_paths, :ok, fn part_path, :ok ->
        case stream_file_to_file(part_path, dest_file) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      
      File.close(dest_file)
      
      case result do
        :ok ->
          # Atomic rename
          case File.rename(tmp_dest, dest_path) do
            :ok -> :ok
            {:error, :eexist} -> 
              File.rm(tmp_dest)
              {:error, :exists}
            {:error, reason} -> 
              File.rm(tmp_dest)
              {:error, reason}
          end
        
        {:error, reason} ->
          File.rm(tmp_dest)
          {:error, reason}
      end
    rescue
      e ->
        File.rm(tmp_dest)
        {:error, e}
    end
  end
end

defp stream_file_to_file(src_path, dest_file) do
  case File.open(src_path, [:read, :binary]) do
    {:ok, src_file} ->
      result = do_stream_copy(src_file, dest_file)
      File.close(src_file)
      result
    
    {:error, reason} ->
      {:error, reason}
  end
end

defp do_stream_copy(src_file, dest_file) do
  case IO.binread(src_file, 65_536) do  # 64KB chunks
    :eof -> :ok
    {:error, reason} -> {:error, reason}
    data ->
      case IO.binwrite(dest_file, data) do
        :ok -> do_stream_copy(src_file, dest_file)
        {:error, reason} -> {:error, reason}
      end
  end
end
```

### 2.8 Tests

#### `test/cache/multipart_uploads_test.exs` (Create)

```elixir
defmodule Cache.MultipartUploadsTest do
  use ExUnit.Case, async: true
  
  alias Cache.MultipartUploads
  
  setup do
    # Each test gets fresh state since MultipartUploads is a singleton
    # Consider using unique identifiers or cleaning up in setup
    :ok
  end
  
  describe "start_upload/5" do
    test "creates upload and returns UUID" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")
      assert is_binary(upload_id)
      assert String.length(upload_id) == 36  # UUID format
    end
  end
  
  describe "add_part/4" do
    test "records part for valid upload" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")
      
      # Create temp file
      tmp_path = Path.join(System.tmp_dir!(), "test-part-#{:erlang.unique_integer([:positive])}")
      File.write!(tmp_path, String.duplicate("x", 1000))
      
      assert :ok = MultipartUploads.add_part(upload_id, 1, tmp_path, 1000)
      
      # Cleanup
      File.rm(tmp_path)
    end
    
    test "returns error for unknown upload" do
      assert {:error, :upload_not_found} = MultipartUploads.add_part("nonexistent", 1, "/tmp/foo", 100)
    end
    
    test "returns error when part exceeds 10MB" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")
      size = 11 * 1024 * 1024  # 11MB
      
      assert {:error, :part_too_large} = MultipartUploads.add_part(upload_id, 1, "/tmp/foo", size)
    end
    
    test "returns error when total exceeds 500MB" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")
      
      # Add parts totaling 500MB
      part_size = 10 * 1024 * 1024  # 10MB
      for i <- 1..50 do
        MultipartUploads.add_part(upload_id, i, "/tmp/part#{i}", part_size)
      end
      
      # 51st part should fail
      assert {:error, :total_size_exceeded} = MultipartUploads.add_part(upload_id, 51, "/tmp/part51", part_size)
    end
  end
  
  describe "complete_upload/1" do
    test "returns upload data and removes from state" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")
      
      tmp_path = Path.join(System.tmp_dir!(), "test-part-#{:erlang.unique_integer([:positive])}")
      File.write!(tmp_path, "data")
      MultipartUploads.add_part(upload_id, 1, tmp_path, 4)
      
      {:ok, upload} = MultipartUploads.complete_upload(upload_id)
      
      assert upload.account_handle == "acc"
      assert upload.project_handle == "proj"
      assert Map.has_key?(upload.parts, 1)
      
      # Should be removed from state
      assert {:error, :not_found} = MultipartUploads.get_upload(upload_id)
      
      File.rm(tmp_path)
    end
  end
  
  describe "abort_upload/1" do
    test "removes upload and cleans up temp files" do
      {:ok, upload_id} = MultipartUploads.start_upload("acc", "proj", "builds", "abc123", "test.zip")
      
      tmp_path = Path.join(System.tmp_dir!(), "test-part-#{:erlang.unique_integer([:positive])}")
      File.write!(tmp_path, "data")
      MultipartUploads.add_part(upload_id, 1, tmp_path, 4)
      
      assert :ok = MultipartUploads.abort_upload(upload_id)
      assert {:error, :not_found} = MultipartUploads.get_upload(upload_id)
      refute File.exists?(tmp_path)
    end
  end
end
```

#### `test/cache_web/controllers/module_cache_controller_test.exs` (Update)

- Remove all tests for `upload/2` action
- Add integration tests for `start_multipart`, `upload_part`, `complete_multipart`
- Test full upload flow: start → parts → complete
- Test error cases: missing upload, size limits, parts mismatch

---

## Phase 3: Generate OpenAPI Spec & Swift Client Code

After implementing the Elixir server changes:

```bash
cd cache && mise run generate-api-cli-code
```

This runs `cache/mise/tasks/generate-api-cli-code.sh` which:
1. Generates `cli/Sources/TuistCache/OpenAPI/cache.yml` from `CacheWeb.API.Spec` via `mix openapi.spec.yaml`
2. Generates `cli/Sources/TuistCache/OpenAPI/Client.swift` and `Types.swift` via `swift-openapi-generator`

---

## Phase 4: Swift Client Services

### 4.1 New Service: `cli/Sources/TuistCache/Services/StartModuleCacheMultipartUploadService.swift`

```swift
import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol StartModuleCacheMultipartUploadServicing: Sendable {
    /// Starts a multipart upload. Returns nil if artifact already exists (skip upload).
    func startUpload(
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> String?
}

public enum StartModuleCacheMultipartUploadServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case badRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to start multipart upload due to an unknown response of \(statusCode)."
        case let .unauthorized(message),
             let .forbidden(message),
             let .badRequest(message):
            return message
        }
    }
}

public struct StartModuleCacheMultipartUploadService: StartModuleCacheMultipartUploadServicing {
    public init() {}

    public func startUpload(
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws -> String? {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )

        let response = try await client.startModuleCacheMultipartUpload(
            .init(
                query: .init(
                    account_handle: accountHandle,
                    project_handle: projectHandle,
                    hash: hash,
                    name: name,
                    cache_category: cacheCategory
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(body):
                return body.upload_id  // nil if artifact exists
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw StartModuleCacheMultipartUploadServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw StartModuleCacheMultipartUploadServiceError.forbidden(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw StartModuleCacheMultipartUploadServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw StartModuleCacheMultipartUploadServiceError.unknownError(statusCode)
        }
    }
}
```

### 4.2 New Service: `cli/Sources/TuistCache/Services/UploadModuleCachePartService.swift`

```swift
import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol UploadModuleCachePartServicing: Sendable {
    func uploadPart(
        uploadId: String,
        partNumber: Int,
        data: Data,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws
}

public enum UploadModuleCachePartServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case badRequest(String)
    case notFound(String)
    case partTooLarge(String)
    case totalSizeExceeded(String)
    case requestTimeout(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to upload part due to an unknown response of \(statusCode)."
        case let .unauthorized(message),
             let .forbidden(message),
             let .badRequest(message),
             let .notFound(message),
             let .partTooLarge(message),
             let .totalSizeExceeded(message),
             let .requestTimeout(message):
            return message
        }
    }
}

public struct UploadModuleCachePartService: UploadModuleCachePartServicing {
    public init() {}

    public func uploadPart(
        uploadId: String,
        partNumber: Int,
        data: Data,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )

        let response = try await client.uploadModuleCachePart(
            .init(
                query: .init(
                    upload_id: uploadId,
                    part_number: partNumber
                ),
                body: .binary(HTTPBody(data))
            )
        )

        switch response {
        case .noContent:
            return
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.notFound(error.message)
            }
        case let .requestEntityTooLarge(tooLarge):
            switch tooLarge.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.partTooLarge(error.message)
            }
        case let .unprocessableContent(unprocessable):
            switch unprocessable.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.totalSizeExceeded(error.message)
            }
        case let .requestTimeout(timeout):
            switch timeout.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.requestTimeout(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.forbidden(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw UploadModuleCachePartServiceError.badRequest(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw UploadModuleCachePartServiceError.unknownError(statusCode)
        }
    }
}
```

### 4.3 New Service: `cli/Sources/TuistCache/Services/CompleteModuleCacheMultipartUploadService.swift`

```swift
import Foundation
import Mockable
import OpenAPIRuntime
import OpenAPIURLSession
import TuistHTTP
import TuistServer

@Mockable
public protocol CompleteModuleCacheMultipartUploadServicing: Sendable {
    func completeUpload(
        uploadId: String,
        parts: [Int],
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws
}

public enum CompleteModuleCacheMultipartUploadServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case badRequest(String)
    case notFound(String)
    case internalServerError(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "Failed to complete multipart upload due to an unknown response of \(statusCode)."
        case let .unauthorized(message),
             let .forbidden(message),
             let .badRequest(message),
             let .notFound(message),
             let .internalServerError(message):
            return message
        }
    }
}

public struct CompleteModuleCacheMultipartUploadService: CompleteModuleCacheMultipartUploadServicing {
    public init() {}

    public func completeUpload(
        uploadId: String,
        parts: [Int],
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws {
        let client = Client.authenticated(
            cacheURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )

        let response = try await client.completeModuleCacheMultipartUpload(
            .init(
                query: .init(upload_id: uploadId),
                body: .json(.init(parts: parts))
            )
        )

        switch response {
        case .noContent:
            return
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw CompleteModuleCacheMultipartUploadServiceError.notFound(error.message)
            }
        case let .badRequest(badRequest):
            switch badRequest.body {
            case let .json(error):
                throw CompleteModuleCacheMultipartUploadServiceError.badRequest(error.message)
            }
        case let .internalServerError(serverError):
            switch serverError.body {
            case let .json(error):
                throw CompleteModuleCacheMultipartUploadServiceError.internalServerError(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw CompleteModuleCacheMultipartUploadServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw CompleteModuleCacheMultipartUploadServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CompleteModuleCacheMultipartUploadServiceError.unknownError(statusCode)
        }
    }
}
```

### 4.4 New Service: `cli/Sources/TuistCache/Services/MultipartModuleCacheUploadService.swift`

Orchestrator service that coordinates the entire multipart upload flow:

```swift
import Foundation
import Mockable
import Path
import TuistServer
import TuistSupport

@Mockable
public protocol MultipartModuleCacheUploadServicing: Sendable {
    func uploadArtifact(
        artifactPath: AbsolutePath,
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws
}

public enum MultipartModuleCacheUploadServiceError: LocalizedError {
    case fileNotFound(AbsolutePath)
    case fileReadError(AbsolutePath, Error)

    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            return "Artifact file not found at \(path.pathString)"
        case let .fileReadError(path, error):
            return "Failed to read artifact file at \(path.pathString): \(error.localizedDescription)"
        }
    }
}

public struct MultipartModuleCacheUploadService: MultipartModuleCacheUploadServicing {
    private let startUploadService: StartModuleCacheMultipartUploadServicing
    private let uploadPartService: UploadModuleCachePartServicing
    private let completeUploadService: CompleteModuleCacheMultipartUploadServicing
    
    private static let partSize = 10 * 1024 * 1024  // 10MB

    public init(
        startUploadService: StartModuleCacheMultipartUploadServicing = StartModuleCacheMultipartUploadService(),
        uploadPartService: UploadModuleCachePartServicing = UploadModuleCachePartService(),
        completeUploadService: CompleteModuleCacheMultipartUploadServicing = CompleteModuleCacheMultipartUploadService()
    ) {
        self.startUploadService = startUploadService
        self.uploadPartService = uploadPartService
        self.completeUploadService = completeUploadService
    }

    public func uploadArtifact(
        artifactPath: AbsolutePath,
        accountHandle: String,
        projectHandle: String,
        hash: String,
        name: String,
        cacheCategory: String,
        serverURL: URL,
        authenticationURL: URL,
        serverAuthenticationController: ServerAuthenticationControlling
    ) async throws {
        // Step 1: Start the multipart upload
        guard let uploadId = try await startUploadService.startUpload(
            accountHandle: accountHandle,
            projectHandle: projectHandle,
            hash: hash,
            name: name,
            cacheCategory: cacheCategory,
            serverURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        ) else {
            // Artifact already exists, nothing to do
            return
        }

        // Step 2: Read file and upload parts
        guard FileManager.default.fileExists(atPath: artifactPath.pathString) else {
            throw MultipartModuleCacheUploadServiceError.fileNotFound(artifactPath)
        }

        guard let inputStream = InputStream(fileAtPath: artifactPath.pathString) else {
            throw MultipartModuleCacheUploadServiceError.fileNotFound(artifactPath)
        }

        inputStream.open()
        defer { inputStream.close() }

        var partNumber = 1
        var uploadedParts: [Int] = []
        var buffer = [UInt8](repeating: 0, count: Self.partSize)

        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(&buffer, maxLength: Self.partSize)
            
            if bytesRead < 0 {
                if let error = inputStream.streamError {
                    throw MultipartModuleCacheUploadServiceError.fileReadError(artifactPath, error)
                }
                break
            }
            
            if bytesRead == 0 {
                break
            }

            let partData = Data(bytes: buffer, count: bytesRead)

            try await uploadPartService.uploadPart(
                uploadId: uploadId,
                partNumber: partNumber,
                data: partData,
                serverURL: serverURL,
                authenticationURL: authenticationURL,
                serverAuthenticationController: serverAuthenticationController
            )

            uploadedParts.append(partNumber)
            partNumber += 1
        }

        // Step 3: Complete the upload
        try await completeUploadService.completeUpload(
            uploadId: uploadId,
            parts: uploadedParts,
            serverURL: serverURL,
            authenticationURL: authenticationURL,
            serverAuthenticationController: serverAuthenticationController
        )
    }
}
```

### 4.5 Remove: `cli/Sources/TuistCache/Services/SaveModuleCacheService.swift`

Delete this file - it's replaced by the multipart upload services.

---

## Phase 5: Update Submodule to Use Multipart

**File:** `cli/TuistCacheEE/Sources/Storage/ModuleCacheRemoteStorage.swift`

**Repository:** Git submodule (commit changes via git, not jj)

### 5.1 Update Dependencies

**Remove:**
```swift
private let saveModuleCacheService: SaveModuleCacheServicing
```

**Add:**
```swift
private let multipartModuleCacheUploadService: MultipartModuleCacheUploadServicing
```

**Update both initializers** to use the new service.

### 5.2 Update Error Handling

Update `catchingUploadErrors` to handle new error types:

```swift
private func catchingUploadErrors<T>(
    item: CacheStorableItem,
    action: @escaping () async throws -> T
) async throws -> T? {
    do {
        return try await action()
    } catch let error as MultipartModuleCacheUploadServiceError {
        AlertController.current.warning(.alert(
            "Failed to upload \(item.name) with hash \(item.hash): \(error.localizedDescription)"
        ))
        return nil
    } catch let error as StartModuleCacheMultipartUploadServiceError {
        // Handle start errors
        ...
    } catch let error as UploadModuleCachePartServiceError {
        // Handle part upload errors (includes size limits)
        ...
    } catch let error as CompleteModuleCacheMultipartUploadServiceError {
        // Handle completion errors
        ...
    }
    // ... rest of existing error handling
}
```

### 5.3 Update `store()` Method

Replace lines ~371-387:

```swift
// OLD:
let data = try Data(contentsOf: zipPath.url)  // Loads entire file into memory!
try await retryProvider.runWithRetries {
    try await saveModuleCacheService.saveModuleCache(
        data,
        fullHandle: fullHandle,
        hash: item.key.hash,
        name: "\(item.key.name).zip",
        cacheCategory: category,
        serverURL: cacheURL,
        authenticationURL: authenticationURL,
        serverAuthenticationController: serverAuthenticationController
    )
}

// NEW:
try await retryProvider.runWithRetries {
    try await multipartModuleCacheUploadService.uploadArtifact(
        artifactPath: zipPath,
        accountHandle: accountHandle,
        projectHandle: projectHandle,
        hash: item.key.hash,
        name: "\(item.key.name).zip",
        cacheCategory: category,
        serverURL: cacheURL,
        authenticationURL: authenticationURL,
        serverAuthenticationController: serverAuthenticationController
    )
}
```

**Note:** The retry wraps the entire multipart upload. If any part fails, the whole upload is retried from scratch (new upload_id, all parts re-sent).

### 5.4 Add Handle Splitting

Add helper to split `fullHandle`:

```swift
private func splitHandle(_ fullHandle: String) -> (accountHandle: String, projectHandle: String) {
    let components = fullHandle.split(separator: "/", maxSplits: 1)
    return (String(components[0]), String(components[1]))
}
```

Use in both `fetch()` and `store()` methods.

---

## File Summary

| Location | File | Action |
|----------|------|--------|
| `cache/` | `lib/cache/multipart_uploads.ex` | **Create** - ETS state GenServer |
| `cache/` | `lib/cache/application.ex` | **Update** - Add to supervision tree |
| `cache/` | `lib/cache/disk.ex` | **Update** - Add `module_put_from_parts/6` |
| `cache/` | `lib/cache_web/router.ex` | **Update** - Add 3 new routes, remove old upload route |
| `cache/` | `lib/cache_web/controllers/module_cache_controller.ex` | **Update** - Add 3 new actions, remove `upload/2` |
| `cache/` | `lib/cache_web/api/schemas/multipart_upload.ex` | **Create** - OpenApiSpex schemas |
| `cache/` | `lib/cache_web/api/spec.ex` | **Update** - Register schemas (auto-discovered) |
| `cache/` | `test/cache/multipart_uploads_test.exs` | **Create** - Unit tests |
| `cache/` | `test/cache_web/controllers/module_cache_controller_test.exs` | **Update** - Integration tests |
| `cli/` | `Sources/TuistCache/OpenAPI/cache.yml` | **Generated** |
| `cli/` | `Sources/TuistCache/OpenAPI/Client.swift` | **Generated** |
| `cli/` | `Sources/TuistCache/OpenAPI/Types.swift` | **Generated** |
| `cli/` | `Sources/TuistCache/Services/SaveModuleCacheService.swift` | **Remove** |
| `cli/` | `Sources/TuistCache/Services/StartModuleCacheMultipartUploadService.swift` | **Create** |
| `cli/` | `Sources/TuistCache/Services/UploadModuleCachePartService.swift` | **Create** |
| `cli/` | `Sources/TuistCache/Services/CompleteModuleCacheMultipartUploadService.swift` | **Create** |
| `cli/` | `Sources/TuistCache/Services/MultipartModuleCacheUploadService.swift` | **Create** - Orchestrator |
| `cli/TuistCacheEE/` | `Sources/Storage/ModuleCacheRemoteStorage.swift` | **Update** - Use multipart, fix method names |

---

## Implementation Order

1. **Phase 1** - Fix submodule method rename (can be done independently, commit to TuistCacheEE repo via git)
2. **Phase 2** - Implement Elixir server changes
3. **Phase 3** - Generate OpenAPI spec and Swift client code
4. **Phase 4** - Implement Swift client services
5. **Phase 5** - Update submodule to use multipart

**Important:** Phases 2-5 must be done together as they are interdependent. Phase 1 can be done independently to fix the current broken state.

---

## Version Control Notes

- **Root repo (tuist):** Uses jj (backed by git). Use `jj` commands for all operations.
- **Submodule (cli/TuistCacheEE):** Uses git directly. Use `git` commands for commits in this directory.
