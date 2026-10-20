defmodule Tuist.Bazel.TestSummary do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: false}
  schema "bazel_test_summaries" do
    field :project_id, :integer
    field :invocation_id, :string
    field :target_label, :string
    field :status, :string
    field :total_run_count, :integer
    field :total_num_cached, :integer
    field :duration_ms, :integer
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
