defmodule LuftServer.Git.Enroute.Api.V1alpha1.ObjectFormat do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "enroute.api.v1alpha1.ObjectFormat",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :OBJECT_FORMAT_UNSPECIFIED, 0
  field :OBJECT_FORMAT_SHA1, 1
  field :OBJECT_FORMAT_SHA256, 2
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.Repository do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.Repository",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repo, 1, type: LuftServer.Git.Enroute.Common.V1alpha1.RepoKey
  field :default_branch, 2, type: :string, json_name: "defaultBranch"
  field :last_push, 3, type: Google.Protobuf.Timestamp, json_name: "lastPush"

  field :object_format, 4,
    type: LuftServer.Git.Enroute.Api.V1alpha1.ObjectFormat,
    json_name: "objectFormat",
    enum: true
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.CreateRepositoryRequest do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.CreateRepositoryRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :default_branch, 1, type: :string, json_name: "defaultBranch"
  field :repo, 2, type: LuftServer.Git.Enroute.Common.V1alpha1.RepoKey

  field :object_format, 3,
    type: LuftServer.Git.Enroute.Api.V1alpha1.ObjectFormat,
    json_name: "objectFormat",
    enum: true
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.CreateRepositoryResponse do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.CreateRepositoryResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repository, 1, type: LuftServer.Git.Enroute.Api.V1alpha1.Repository
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.GetRepositoryRequest do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.GetRepositoryRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repo, 1, type: LuftServer.Git.Enroute.Common.V1alpha1.RepoKey
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.GetRepositoryResponse do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.GetRepositoryResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repository, 1, type: LuftServer.Git.Enroute.Api.V1alpha1.Repository
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.ListRepositoriesRequest do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.ListRepositoriesRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :limit, 1, type: :uint32
  field :page_token, 2, type: :string, json_name: "pageToken"
  field :prefix, 3, type: :string
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.ListRepositoriesResponse do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.ListRepositoriesResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repositories, 1, repeated: true, type: LuftServer.Git.Enroute.Api.V1alpha1.Repository
  field :next_page_token, 2, type: :string, json_name: "nextPageToken"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.DeleteRepositoryRequest do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.DeleteRepositoryRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repo, 1, type: LuftServer.Git.Enroute.Common.V1alpha1.RepoKey
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.DeleteRepositoryResponse do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.DeleteRepositoryResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.RepositoryService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "enroute.api.v1alpha1.RepositoryService",
    protoc_gen_elixir_version: "0.17.1"

  rpc(
    :CreateRepository,
    LuftServer.Git.Enroute.Api.V1alpha1.CreateRepositoryRequest,
    LuftServer.Git.Enroute.Api.V1alpha1.CreateRepositoryResponse
  )

  rpc(
    :GetRepository,
    LuftServer.Git.Enroute.Api.V1alpha1.GetRepositoryRequest,
    LuftServer.Git.Enroute.Api.V1alpha1.GetRepositoryResponse
  )

  rpc(
    :ListRepositories,
    LuftServer.Git.Enroute.Api.V1alpha1.ListRepositoriesRequest,
    LuftServer.Git.Enroute.Api.V1alpha1.ListRepositoriesResponse
  )

  rpc(
    :DeleteRepository,
    LuftServer.Git.Enroute.Api.V1alpha1.DeleteRepositoryRequest,
    LuftServer.Git.Enroute.Api.V1alpha1.DeleteRepositoryResponse
  )
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.RepositoryService.Stub do
  @moduledoc false

  use GRPC.Stub, service: LuftServer.Git.Enroute.Api.V1alpha1.RepositoryService.Service
end
