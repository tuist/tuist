defmodule Tuist.Mix do
  @moduledoc """
  Context module for Mix (Elixir) compile-time analytics.

  All data is stored in ClickHouse. `create_build/1` inserts the build
  record plus each captured diagnostic through the same Bufferable
  pipeline used for Gradle and Xcode analytics.
  """

  alias Tuist.Builds.Build, as: BuildRun
  alias Tuist.Builds.BuildMachineMetric
  alias Tuist.Mix.Build
  alias Tuist.Mix.Diagnostic

  @doc """
  Creates a Mix compile build with associated diagnostics.

  ## Parameters
    * `attrs` — build attributes:
      * `:id` — client-generated UUID for the build (required)
      * `:project_id` — the project id (required)
      * `:account_id` — the account id (required)
      * `:duration_ms` — total compile duration in milliseconds (required)
      * `:status` — `"success"` or `"failure"` (required)
      * `:is_ci` — boolean, defaults to false
      * `:elixir_version`, `:otp_version`, `:mix_env` — strings, optional
      * `:git_branch`, `:git_commit_sha`, `:git_ref`,
        `:git_remote_url_origin` — strings, optional
      * `:ci_provider`, `:ci_run_id`, `:ci_project_handle` — strings, optional
      * `:contract_version` — string, optional
      * `:started_at` — `%DateTime{}` or ISO 8601 string, optional
      * `:custom_tags` — list of strings, optional
      * `:custom_values` — map of string → string, optional
      * `:diagnostics` — list of diagnostic maps (see below), optional

  Each diagnostic map:
      %{severity: "warning" | "error", file: string, module: string,
        message: string, line: integer | nil, column: integer | nil,
        compiler: string}

  ## Returns
    * `{:ok, build_id}` on success
    * `{:error, reason}` when the custom metadata is invalid
  """
  def create_build(attrs) do
    with :ok <-
           BuildRun.validate_custom_metadata(
             Map.get(attrs, :custom_tags, []),
             Map.get(attrs, :custom_values, %{})
           ) do
      now = Map.get(attrs, :inserted_at) || NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      build_id = attrs.id
      diagnostics = Map.get(attrs, :diagnostics, [])

      counts = diagnostic_counts(diagnostics)
      build_entry = build_entry(attrs, build_id, counts, now)

      Build.Buffer.insert(build_entry)

      insert_diagnostics(build_id, attrs.project_id, diagnostics, now)
      insert_machine_metrics(build_id, Map.get(attrs, :machine_metrics, []), now)

      {:ok, build_id}
    end
  end

  defp build_entry(attrs, build_id, counts, now) do
    %{
      id: build_id,
      project_id: attrs.project_id,
      account_id: attrs.account_id,
      duration_ms: Map.get(attrs, :duration_ms, 0),
      status: attrs.status,
      is_ci: Map.get(attrs, :is_ci, false),
      elixir_version: Map.get(attrs, :elixir_version) || "",
      otp_version: Map.get(attrs, :otp_version) || "",
      mix_env: Map.get(attrs, :mix_env) || "",
      git_branch: Map.get(attrs, :git_branch) || "",
      git_commit_sha: Map.get(attrs, :git_commit_sha) || "",
      git_ref: Map.get(attrs, :git_ref) || "",
      git_remote_url_origin: Map.get(attrs, :git_remote_url_origin) || "",
      ci_provider: Map.get(attrs, :ci_provider) || "",
      ci_run_id: Map.get(attrs, :ci_run_id) || "",
      ci_project_handle: Map.get(attrs, :ci_project_handle) || "",
      ci_host: Map.get(attrs, :ci_host) || "",
      custom_tags: Map.get(attrs, :custom_tags, []),
      custom_values: Map.get(attrs, :custom_values, %{}),
      contract_version: Map.get(attrs, :contract_version) || "",
      started_at: to_naive_datetime(Map.get(attrs, :started_at)),
      diagnostics_error_count: counts.errors,
      diagnostics_warning_count: counts.warnings,
      inserted_at: now
    }
  end

  defp diagnostic_counts(diagnostics) do
    Enum.reduce(diagnostics, %{errors: 0, warnings: 0}, fn diagnostic, acc ->
      case diagnostic_severity(diagnostic) do
        "error" -> Map.update!(acc, :errors, &(&1 + 1))
        _ -> Map.update!(acc, :warnings, &(&1 + 1))
      end
    end)
  end

  defp insert_machine_metrics(_build_id, [], _now), do: :ok

  defp insert_machine_metrics(build_id, machine_metrics, now) do
    rows =
      Enum.map(machine_metrics, fn sample ->
        %{
          build_run_id: nil,
          gradle_build_id: nil,
          mix_build_id: build_id,
          timestamp: number(sample, :timestamp) || 0.0,
          offset_ms: number(sample, :offset_ms),
          cpu_usage_percent: number(sample, :cpu_usage_percent) || 0.0,
          memory_used_bytes: integer_value(sample, :memory_used_bytes) || 0,
          memory_total_bytes: integer_value(sample, :memory_total_bytes) || 0,
          network_bytes_in: integer_value(sample, :network_bytes_in) || 0,
          network_bytes_out: integer_value(sample, :network_bytes_out) || 0,
          disk_bytes_read: integer_value(sample, :disk_bytes_read) || 0,
          disk_bytes_written: integer_value(sample, :disk_bytes_written) || 0,
          inserted_at: now
        }
      end)

    BuildMachineMetric.Buffer.insert_all(rows)
    :ok
  end

  defp number(sample, key) do
    case Map.get(sample, key) || Map.get(sample, Atom.to_string(key)) do
      value when is_number(value) -> value
      _ -> nil
    end
  end

  defp integer_value(sample, key) do
    case Map.get(sample, key) || Map.get(sample, Atom.to_string(key)) do
      value when is_integer(value) -> value
      _ -> nil
    end
  end

  defp insert_diagnostics(_build_id, _project_id, [], _now), do: :ok

  defp insert_diagnostics(build_id, project_id, diagnostics, now) do
    rows =
      Enum.map(diagnostics, fn diagnostic ->
        %{
          id: UUIDv7.generate(),
          build_id: build_id,
          project_id: project_id,
          severity: diagnostic_severity(diagnostic),
          file: string_field(diagnostic, :file),
          module: string_field(diagnostic, :module),
          message: string_field(diagnostic, :message),
          line: integer_field(diagnostic, :line),
          column: integer_field(diagnostic, :column),
          compiler: string_field(diagnostic, :compiler),
          inserted_at: now
        }
      end)

    Diagnostic.Buffer.insert_all(rows)
    :ok
  end

  defp diagnostic_severity(diagnostic) do
    case string_field(diagnostic, :severity) do
      "error" -> "error"
      _ -> "warning"
    end
  end

  defp string_field(diagnostic, key) do
    value = Map.get(diagnostic, key) || Map.get(diagnostic, Atom.to_string(key))

    case value do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp integer_field(diagnostic, key) do
    value = Map.get(diagnostic, key) || Map.get(diagnostic, Atom.to_string(key))

    case value do
      value when is_integer(value) and value >= 0 -> value
      _ -> nil
    end
  end

  defp to_naive_datetime(nil), do: nil

  defp to_naive_datetime(%DateTime{} = dt), do: dt |> DateTime.to_naive() |> NaiveDateTime.truncate(:microsecond)

  defp to_naive_datetime(%NaiveDateTime{} = ndt), do: NaiveDateTime.truncate(ndt, :microsecond)

  defp to_naive_datetime(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> to_naive_datetime(dt)
      _ -> nil
    end
  end

  defp to_naive_datetime(_), do: nil
end
