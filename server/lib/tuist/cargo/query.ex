defmodule Tuist.Cargo.Query do
  @moduledoc "Project-scoped Cargo build reads shared by the HTTP API and MCP tools."
  alias Tuist.Cargo
  alias Tuist.Cargo.CacheMetrics
  alias Tuist.ReportActor

  @filters ~w(git_branch status is_ci command)
  @compilation_limit 500

  def list_builds(project_id, params) do
    filters =
      for key <- @filters,
          not is_nil(params[key]),
          do: %{field: String.to_existing_atom(key), op: :==, value: params[key]}

    {builds, meta} =
      Cargo.list_builds(project_id, %{
        filters: filters,
        order_by: [:inserted_at, :id],
        order_directions: [:desc, :desc],
        page: Map.get(params, "page", 1),
        page_size: Map.get(params, "page_size", 20)
      })

    %{
      builds: builds |> ReportActor.preload() |> Enum.map(&build/1),
      pagination_metadata: %{
        has_next_page: meta.has_next_page?,
        has_previous_page: meta.has_previous_page?,
        current_page: meta.current_page,
        page_size: meta.page_size,
        total_count: meta.total_count,
        total_pages: meta.total_pages
      }
    }
  end

  def get_build(project_id, build_id, opts \\ []) do
    with {:ok, build} <- Cargo.get_build(build_id, project_id) do
      build = ReportActor.preload(build)
      rows = Cargo.compilations(build, @compilation_limit + 1)
      metrics = CacheMetrics.read(build)

      {:ok,
       Map.merge(build(build), %{
         cache: cache(metrics),
         cache_inspection: if(Keyword.get(opts, :include_cache_inspection, false), do: metrics && metrics[:details]),
         compilations: rows |> Enum.take(@compilation_limit) |> Enum.map(&compilation/1),
         compilations_truncated: length(rows) > @compilation_limit
       })}
    end
  end

  defp compilation(row) do
    diagnostics =
      row.diagnostics
      |> JSON.decode!()
      |> Enum.map(&Map.take(&1, ~w(severity message file line)))

    row
    |> Map.take([:id, :name, :source, :kind, :dependencies, :start_offset_ms, :duration_ms, :status])
    |> Map.put(:diagnostics, diagnostics)
  end

  defp build(build) do
    %{
      id: build.id,
      actor: ReportActor.actor(build),
      command: presence(build.command),
      custom_metadata: %{tags: build.custom_tags || [], values: build.custom_values || %{}},
      tuist_version: presence(build.tuist_version),
      rust_version: presence(build.rust_version),
      status: build.status,
      duration_ms: build.duration_ms,
      is_ci: build.is_ci,
      git_branch: presence(build.git_branch),
      git_commit_sha: presence(build.git_commit_sha),
      git_ref: presence(build.git_ref),
      ci_provider: presence(build.ci_provider),
      ci_run_id: presence(build.ci_run_id),
      ci_project_handle: presence(build.ci_project_handle),
      ci_host: presence(build.ci_host),
      started_at: timestamp(build.started_at),
      inserted_at: timestamp(build.inserted_at)
    }
  end

  defp cache(nil), do: nil

  defp cache(metrics) do
    metrics
    |> Map.take(CacheMetrics.counters())
    |> Map.merge(%{task_misses: CacheMetrics.task_misses(metrics), hit_rate: CacheMetrics.hit_rate(metrics)})
  end

  defp presence(""), do: nil
  defp presence(value), do: value

  defp timestamp(nil), do: nil

  defp timestamp(%NaiveDateTime{} = value),
    do: value |> NaiveDateTime.truncate(:second) |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
end
