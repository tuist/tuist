defmodule Tuist.TestImpactAnalysis.Run do
  @moduledoc """
  The selection coverage-based test selection made for one `tuist test`
  invocation: the commits and diff it used, its scope, the outcome (`selected`,
  or `fallback` when the run continued as default selective testing) and why,
  the trace of the rules that decided it, and the counts. Shard plans and test
  runs point to it; it knows nothing about either. This is a ClickHouse entity.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_impact_runs" do
    field :project_id, Ch, type: "Int64"
    field :inserted_at, Ch, type: "DateTime64(6)"
    field :head_sha, Ch, type: "String"
    field :commit_sha, Ch, type: "String"
    field :baseline_sha, Ch, type: "Nullable(String)"
    field :baseline_run_ids, Ch, type: "Array(UUID)", default: []
    field :git_branch, Ch, type: "String", default: ""
    field :dirty, :boolean, default: false
    field :strategy, Ch, type: "LowCardinality(String)", default: "coverage"
    field :build_system, Ch, type: "LowCardinality(String)"
    field :platform, Ch, type: "LowCardinality(String)", default: ""
    field :build_context, Ch, type: "Map(LowCardinality(String), String)", default: %{}
    field :requested_modules, Ch, type: "Array(LowCardinality(String))", default: []
    field :outcome, Ch, type: "LowCardinality(String)"
    field :reason, Ch, type: "LowCardinality(String)", default: ""
    field :matched_path, Ch, type: "String", default: ""
    field :rules_version, Ch, type: "LowCardinality(String)", default: ""

    field :rule_trace, Ch,
      type: "Array(Tuple(LowCardinality(String), UInt32, UInt32, LowCardinality(String)))",
      default: []

    field :requested_count, Ch, type: "UInt32", default: 0
    field :skipped_count, Ch, type: "UInt32", default: 0
    field :selected_count, Ch, type: "UInt32", default: 0
  end

  def create_changeset(run \\ %__MODULE__{}, attrs) do
    run
    |> cast(attrs, [
      :id,
      :project_id,
      :inserted_at,
      :head_sha,
      :commit_sha,
      :baseline_sha,
      :baseline_run_ids,
      :git_branch,
      :dirty,
      :strategy,
      :build_system,
      :platform,
      :build_context,
      :requested_modules,
      :outcome,
      :reason,
      :matched_path,
      :rules_version,
      :rule_trace,
      :requested_count,
      :skipped_count,
      :selected_count
    ])
    |> validate_required([:id, :project_id, :inserted_at, :head_sha, :commit_sha, :build_system, :outcome])
  end
end
