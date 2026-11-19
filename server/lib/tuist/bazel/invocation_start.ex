defmodule Tuist.Bazel.InvocationStart do
  @moduledoc """
  A Bazel invocation Kura saw start, before it finishes and becomes a
  `Tuist.Bazel.Invocation`.
  """
  use Ecto.Schema

  @primary_key false
  schema "bazel_invocation_starts" do
    field :project_id, Ch, type: "Int64"
    field :invocation_id, Ch, type: "String"
    field :command, Ch, type: "LowCardinality(String)"
    field :target_patterns, {:array, Ch}, type: "String", default: []
    field :git_branch, Ch, type: "String", default: ""
    field :git_commit_sha, Ch, type: "String", default: ""
    field :is_ci, :boolean, default: false
    field :started_at, Ch, type: "DateTime64(3)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
