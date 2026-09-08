defmodule Tuist.Bazel.TestInvocation do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: false}
  schema "bazel_test_invocations" do
    field :project_id, :integer
    field :invocation_id, :string
    field :state, :string, default: "collecting"
    field :test_run_id, Ecto.UUID
    field :artifact_bytes, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end
