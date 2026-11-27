defmodule LuftServer.Git.Enroute.Api.V1alpha1.ObjectKind do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "enroute.api.v1alpha1.ObjectKind",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :OBJECT_KIND_UNSPECIFIED, 0
  field :OBJECT_KIND_COMMIT, 1
  field :OBJECT_KIND_TREE, 2
  field :OBJECT_KIND_BLOB, 3
  field :OBJECT_KIND_TAG, 4
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.GetObjectRequest do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.GetObjectRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repo, 1, type: LuftServer.Git.Enroute.Common.V1alpha1.RepoKey

  field :object_id, 2,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "objectId"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.ListTreeRequest do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.ListTreeRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repo, 1, type: LuftServer.Git.Enroute.Common.V1alpha1.RepoKey

  field :object_id, 2,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "objectId"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.TreeEntry do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.TreeEntry",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :path, 1, type: :string
  field :kind, 2, type: LuftServer.Git.Enroute.Api.V1alpha1.ObjectKind, enum: true

  field :object_id, 3,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "objectId"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.ListTreeResponse do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.ListTreeResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :entries, 1, repeated: true, type: LuftServer.Git.Enroute.Api.V1alpha1.TreeEntry
  field :truncated, 2, type: :bool
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.GetObjectResponse do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.GetObjectResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  oneof(:chunk, 0)

  field :header, 1, type: LuftServer.Git.Enroute.Api.V1alpha1.ObjectHeader, oneof: 0
  field :data, 2, type: :bytes, oneof: 0
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.ObjectHeader do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.ObjectHeader",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :kind, 1, type: LuftServer.Git.Enroute.Api.V1alpha1.ObjectKind, enum: true
  field :size, 2, type: :uint64
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.ListCommitsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.ListCommitsRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repo, 1, type: LuftServer.Git.Enroute.Common.V1alpha1.RepoKey

  field :commit_id, 2,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "commitId"

  field :limit, 3, type: :uint32
  field :page_token, 4, type: :string, json_name: "pageToken"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.Commit do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.Commit",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :commit_id, 1,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "commitId"

  field :parent_commit_ids, 2,
    repeated: true,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "parentCommitIds"

  field :tree_id, 3, type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId, json_name: "treeId"
  field :author, 4, type: LuftServer.Git.Enroute.Api.V1alpha1.Identity
  field :committer, 5, type: LuftServer.Git.Enroute.Api.V1alpha1.Identity
  field :summary, 6, type: :string
  field :body, 7, type: :string
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.Identity do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.Identity",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :name, 1, type: :string
  field :email, 2, type: :string
  field :timestamp, 3, type: Google.Protobuf.Timestamp
  field :utc_offset_seconds, 4, type: :int32, json_name: "utcOffsetSeconds"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.ListCommitsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.ListCommitsResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :commits, 1, repeated: true, type: LuftServer.Git.Enroute.Api.V1alpha1.Commit
  field :next_page_token, 2, type: :string, json_name: "nextPageToken"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.FindMergeBasesRequest do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.FindMergeBasesRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repo, 1, type: LuftServer.Git.Enroute.Common.V1alpha1.RepoKey

  field :commit_id_a, 2,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "commitIdA"

  field :commit_id_b, 3,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "commitIdB"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.FindMergeBasesResponse do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.FindMergeBasesResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :base_commit_ids, 1,
    repeated: true,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "baseCommitIds"

  field :exhausted, 2, type: :bool
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.DiffCommitRequest do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.DiffCommitRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repo, 1, type: LuftServer.Git.Enroute.Common.V1alpha1.RepoKey

  field :commit_id, 2,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "commitId"

  field :base_commit_id, 3,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "baseCommitId"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.FileChange do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.FileChange",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :path, 1, type: :string

  field :old_object_id, 2,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "oldObjectId"

  field :new_object_id, 3,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "newObjectId"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.DiffCommitResponse do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.DiffCommitResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :changes, 1, repeated: true, type: LuftServer.Git.Enroute.Api.V1alpha1.FileChange
  field :truncated, 2, type: :bool
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.ObjectService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "enroute.api.v1alpha1.ObjectService",
    protoc_gen_elixir_version: "0.17.1"

  rpc(
    :GetObject,
    LuftServer.Git.Enroute.Api.V1alpha1.GetObjectRequest,
    stream(LuftServer.Git.Enroute.Api.V1alpha1.GetObjectResponse)
  )

  rpc(
    :ListTree,
    LuftServer.Git.Enroute.Api.V1alpha1.ListTreeRequest,
    stream(LuftServer.Git.Enroute.Api.V1alpha1.ListTreeResponse)
  )

  rpc(
    :ListCommits,
    LuftServer.Git.Enroute.Api.V1alpha1.ListCommitsRequest,
    stream(LuftServer.Git.Enroute.Api.V1alpha1.ListCommitsResponse)
  )

  rpc(
    :DiffCommit,
    LuftServer.Git.Enroute.Api.V1alpha1.DiffCommitRequest,
    stream(LuftServer.Git.Enroute.Api.V1alpha1.DiffCommitResponse)
  )

  rpc(
    :FindMergeBases,
    LuftServer.Git.Enroute.Api.V1alpha1.FindMergeBasesRequest,
    LuftServer.Git.Enroute.Api.V1alpha1.FindMergeBasesResponse
  )
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.ObjectService.Stub do
  @moduledoc false

  use GRPC.Stub, service: LuftServer.Git.Enroute.Api.V1alpha1.ObjectService.Service
end
