defmodule Tuist.Shards.TestReport do
  @moduledoc """
  An immutable shard observation. Ordering is supplied by the producer, never
  inferred from an application's clock or the order in which replicas see rows.
  """
  use Ecto.Schema

  @primary_key false
  schema "shard_test_reports" do
    field :id, Ecto.UUID
    field :project_id, Ch, type: "Int64"
    field :duration, Ch, type: "Int32"
    field :macos_version, Ch, type: "String"
    field :xcode_version, Ch, type: "String"
    field :is_ci, :boolean
    field :model_identifier, Ch, type: "String"
    field :scheme, Ch, type: "String"
    field :status, Ch, type: "LowCardinality(String)"
    field :git_branch, Ch, type: "String"
    field :git_commit_sha, Ch, type: "String"
    field :git_ref, Ch, type: "String"
    field :account_id, Ch, type: "Int64"
    field :actor_account_id, Ch, type: "Int64"
    field :claimed_actor_id, Ch, type: "String"
    field :submission_auth, Ch, type: "LowCardinality(String)"
    field :ran_at, Ch, type: "DateTime64(6)"
    field :inserted_at, Ch, type: "DateTime64(6)"
    field :ci_run_id, Ch, type: "String"
    field :ci_project_handle, Ch, type: "String"
    field :ci_host, Ch, type: "String"
    field :ci_provider, Ch, type: "LowCardinality(Nullable(String))"
    field :build_run_id, Ch, type: "Nullable(UUID)"
    field :is_flaky, :boolean
    field :build_system, Ch, type: "LowCardinality(String)"
    field :gradle_build_id, Ch, type: "Nullable(UUID)"
    field :shard_plan_id, Ch, type: "Nullable(UUID)"
    field :only_test_identifiers, Ch, type: "Array(String)"
    field :skip_test_identifiers, Ch, type: "Array(String)"
    field :stress_mode, Ch, type: "LowCardinality(String)"
    field :stress_outcome, Ch, type: "LowCardinality(String)"
    field :stress_skip_reason, Ch, type: "String"
    field :stress_new_count, Ch, type: "UInt32"
    field :stress_stressed_count, Ch, type: "UInt32"
    field :stress_excluded_count, Ch, type: "UInt32"
    field :stress_known_count, Ch, type: "UInt32"
    field :bazel_invocation_id, Ch, type: "String"
    field :base_branch, Ch, type: "String"
    field :merge_base_sha, Ch, type: "String"
    field :is_pull_request, :boolean
    field :pull_request_number, Ch, type: "UInt32"
    field :git_object_format, Ch, type: "LowCardinality(String)"
    field :history_source, Ch, type: "LowCardinality(String)"
    field :history_fallback_reason, Ch, type: "String"
    field :git_repository_id, Ch, type: "Int64"
    field :git_dirty, :boolean
    field :execution_mode, Ch, type: "LowCardinality(String)"
    field :coverage_evidence_status, Ch, type: "LowCardinality(String)"
    field :once_run_id, Ch, type: "String"
    field :coverage_enabled, Ch, type: "Nullable(Bool)"
    field :reporting_version, Ch, type: "UInt8"
    field :fact_set_id, Ecto.UUID
    field :source_test_run_id, :string
    field :shard_index, Ch, type: "UInt16"
    field :shard_count, Ch, type: "UInt16"
    field :shard_attempt, Ch, type: "UInt32"
    field :shard_report_revision, Ch, type: "UInt32"
    field :report_phase, Ch, type: "UInt8"
    field :report_digest, Ch, type: "String"
    field :execution_started_at, Ch, type: "DateTime64(6)"
  end

  def phase(status) when status in ["processing", "in_progress"], do: 0
  def phase("failed_processing"), do: 1
  def phase(_status), do: 2

  # The shared native parser groups modules/suites with Swift dictionaries.
  # Normalize that incidental order for both local and remote producers, while
  # preserving repeated same-name modules and case/attachment occurrence order.
  def normalize_facts(attrs) do
    Map.update(attrs, :test_modules, [], fn modules ->
      modules
      |> Enum.sort_by(&Map.get(&1, :name))
      |> Enum.map(fn module ->
        Map.update(module, :test_suites, [], &Enum.sort_by(&1, fn suite -> Map.get(suite, :name) end))
      end)
    end)
  end

  def identity_digest(attrs) do
    attrs
    |> Map.drop([:id, :ran_at, :inserted_at, :xcode_coverage])
    |> without_local_paths()
    |> digest()
  end

  defp without_local_paths(%_{} = value), do: value

  defp without_local_paths(%{} = value) do
    Map.new(value, fn
      {key, %{} = report} when key in [:crash_report, "crash_report"] ->
        {key, Map.drop(report, [:file_path, "file_path"])}

      {key, nested} ->
        {key, without_local_paths(nested)}
    end)
  end

  defp without_local_paths(values) when is_list(values), do: Enum.map(values, &without_local_paths/1)
  defp without_local_paths(value), do: value

  def digest(row) do
    row
    |> Map.drop([:inserted_at, :report_digest])
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
