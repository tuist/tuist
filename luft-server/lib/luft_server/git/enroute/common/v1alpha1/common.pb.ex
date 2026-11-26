defmodule LuftServer.Git.Enroute.Common.V1alpha1.RepoKey do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.common.v1alpha1.RepoKey",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :key, 1, type: :string
end

defmodule LuftServer.Git.Enroute.Common.V1alpha1.ObjectId do
  @moduledoc false

  use Protobuf,
    full_name: "enroute.common.v1alpha1.ObjectId",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :hex, 1, type: :string
end
