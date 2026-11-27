defmodule LuftServer.Git.Enroute.Api.V1alpha1.RefUpdateOutcome.Rejection.Reason do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "enroute.api.v1alpha1.RefUpdateOutcome.Rejection.Reason",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :REASON_UNSPECIFIED, 0
  field :REASON_MISSING_OBJECTS, 1
  field :REASON_FUNNY_REFNAME, 2
  field :REASON_NON_COMMIT_OBJECT, 3
  field :REASON_POLICY, 4
  field :REASON_NON_FAST_FORWARD, 5
  field :REASON_ALREADY_EXISTS, 6
  field :REASON_INVALID_REFNAME, 7
  field :REASON_ATOMIC_FAILURE, 8
  field :REASON_REPEATED_REF, 9
  field :REASON_DELETE_CURRENT, 10
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.Ref do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.Ref",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :name, 1, type: :string

  field :object_id, 2,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "objectId"

  field :updated_at, 3, type: Google.Protobuf.Timestamp, json_name: "updatedAt"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.ListRefsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.ListRefsRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repo, 1, type: LuftServer.Git.Enroute.Common.V1alpha1.RepoKey
  field :prefixes, 2, repeated: true, type: :string
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.ListRefsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.ListRefsResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :refs, 1, repeated: true, type: LuftServer.Git.Enroute.Api.V1alpha1.Ref
  field :default_branch, 2, type: :string, json_name: "defaultBranch"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.RefUpdate do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.RefUpdate",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :refname, 1, type: :string

  field :old_object_id, 2,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "oldObjectId"

  field :new_object_id, 3,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "newObjectId"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.UpdateRefsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.UpdateRefsRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repo, 1, type: LuftServer.Git.Enroute.Common.V1alpha1.RepoKey
  field :updates, 2, repeated: true, type: LuftServer.Git.Enroute.Api.V1alpha1.RefUpdate
  field :atomic, 3, type: :bool
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.IsAncestorRequest do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.IsAncestorRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :repo, 1, type: LuftServer.Git.Enroute.Common.V1alpha1.RepoKey

  field :ancestor_commit_id, 2,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "ancestorCommitId"

  field :descendant_commit_id, 3,
    type: LuftServer.Git.Enroute.Common.V1alpha1.ObjectId,
    json_name: "descendantCommitId"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.IsAncestorResponse do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.IsAncestorResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :is_ancestor, 1, type: :bool, json_name: "isAncestor"
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.UpdateRefsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.UpdateRefsResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :outcomes, 1, repeated: true, type: LuftServer.Git.Enroute.Api.V1alpha1.RefUpdateOutcome
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.RefUpdateOutcome.Rejection do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.RefUpdateOutcome.Rejection",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :reason, 1,
    type: LuftServer.Git.Enroute.Api.V1alpha1.RefUpdateOutcome.Rejection.Reason,
    enum: true

  field :message, 2, type: :string
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.RefUpdateOutcome do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.api.v1alpha1.RefUpdateOutcome",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :refname, 1, type: :string
  field :rejection, 2, type: LuftServer.Git.Enroute.Api.V1alpha1.RefUpdateOutcome.Rejection
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.RefService.Service do
  @moduledoc false

  use GRPC.Service, name: "enroute.api.v1alpha1.RefService", protoc_gen_elixir_version: "0.17.1"

  rpc(
    :ListRefs,
    LuftServer.Git.Enroute.Api.V1alpha1.ListRefsRequest,
    LuftServer.Git.Enroute.Api.V1alpha1.ListRefsResponse
  )

  rpc(
    :UpdateRefs,
    LuftServer.Git.Enroute.Api.V1alpha1.UpdateRefsRequest,
    LuftServer.Git.Enroute.Api.V1alpha1.UpdateRefsResponse
  )

  rpc(
    :IsAncestor,
    LuftServer.Git.Enroute.Api.V1alpha1.IsAncestorRequest,
    LuftServer.Git.Enroute.Api.V1alpha1.IsAncestorResponse
  )
end

defmodule LuftServer.Git.Enroute.Api.V1alpha1.RefService.Stub do
  @moduledoc false

  use GRPC.Stub, service: LuftServer.Git.Enroute.Api.V1alpha1.RefService.Service
end
