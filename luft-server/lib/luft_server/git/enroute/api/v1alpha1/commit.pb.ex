defmodule LuftServer.Git.Enroute.Api.V1alpha1.FileMode do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "enroute.api.v1alpha1.FileMode",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :FILE_MODE_UNSPECIFIED, 0
  field :FILE_MODE_REGULAR, 1
  field :FILE_MODE_EXECUTABLE, 2
  field :FILE_MODE_SYMLINK, 3
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.CreateCommitRequest do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.CreateCommitRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repo, 1, type: LuftServer.Git.Enroute.Common.V1alpha1.RepoKey
  field :branch, 2, type: :string

  field :expected_old_commit, 3,
    type: LuftServer.Git.Enroute.Api.V1alpha1.ExpectedOldCommit,
    json_name: "expectedOldCommit"

  field :message, 4, type: :string
  field :author, 5, type: LuftServer.Git.Enroute.Api.V1alpha1.Identity
  field :committer, 6, type: LuftServer.Git.Enroute.Api.V1alpha1.Identity
  field :changes, 7, repeated: true, type: LuftServer.Git.Enroute.Api.V1alpha1.PathChange
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.ExpectedOldCommit.Absent do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.ExpectedOldCommit.Absent",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.ExpectedOldCommit do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.ExpectedOldCommit",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  oneof(:expectation, 0)

  field :commit_id, 1,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "commitId",
    oneof: 0

  field :absent, 2, type: LuftServer.Git.Enroute.Api.V1alpha1.ExpectedOldCommit.Absent, oneof: 0
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.PathChange do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.PathChange",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  oneof(:change, 0)

  field :path, 1, type: :string
  field :put, 2, type: LuftServer.Git.Enroute.Api.V1alpha1.PutFile, oneof: 0
  field :delete, 3, type: LuftServer.Git.Enroute.Api.V1alpha1.DeleteFile, oneof: 0
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.PutFile do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.PutFile",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :content, 1, type: :bytes
  field :mode, 2, type: LuftServer.Git.Enroute.Api.V1alpha1.FileMode, enum: true
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.DeleteFile do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.DeleteFile",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.CreateCommitResponse do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.CreateCommitResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :commit_id, 1,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "commitId"

  field :tree_id, 2, type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId, json_name: "treeId"

  field :parent_commit_id, 3,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "parentCommitId"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.CommitService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "enroute.api.v1alpha1.CommitService",
    protoc_gen_elixir_version: "0.17.1"

  rpc(
    :CreateCommit,
    LuftServer.Git.Enroute.Api.V1alpha1.CreateCommitRequest,
    LuftServer.Git.Enroute.Api.V1alpha1.CreateCommitResponse
  )
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.CommitService.Stub do
  @moduledoc false

  use GRPC.Stub, service: LuftServer.Git.Enroute.Api.V1alpha1.CommitService.Service
end
