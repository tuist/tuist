defmodule Tuist.Bazel.TestResult do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: false}
  schema "bazel_test_results" do
    field :project_id, :integer
    field :invocation_id, :string
    field :target_label, :string
    field :run, :integer
    field :shard, :integer
    field :attempt, :integer
    field :status, :string
    field :duration_ms, :integer
    field :started_at, :utc_datetime
    field :cached, :boolean
    field :is_ci, :boolean
    field :sequence_number, :integer
    field :junit_digest, :string
    field :junit_content, :binary
    field :log_digest, :string
    field :log_content, :binary

    timestamps(type: :utc_datetime)
  end
end
