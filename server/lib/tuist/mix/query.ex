defmodule Tuist.Mix.Query do
  @moduledoc "Project-scoped Mix build reads shared by the HTTP API and MCP tools."
  alias Tuist.Mix.Cache

  @filters ~w(git_branch status is_ci mix_env)
  @cache_fields ~w(hits local_hits remote_hits misses bypasses hit_rate saved_duration_ms read_bytes write_bytes avg_read_duration_us p50_read_duration_us p90_read_duration_us p99_read_duration_us avg_write_duration_us p50_write_duration_us p90_write_duration_us p99_write_duration_us)a

  def list_builds(project_id, params) do
    filters =
      for key <- @filters,
          not is_nil(params[key]),
          do: %{field: String.to_existing_atom(key), op: :==, value: params[key]}

    {builds, meta} =
      Tuist.Mix.list_builds(project_id, %{
        filters: filters,
        order_by: [:inserted_at, :id],
        order_directions: [:desc, :desc],
        page: Map.get(params, "page", 1),
        page_size: Map.get(params, "page_size", 20)
      })

    %{
      builds: Enum.map(builds, &build/1),
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

  def get_build(project_id, build_id) do
    with {:ok, build} <- Tuist.Mix.get_build(build_id, project_id) do
      cache = project_id |> Cache.build_summary(build.id) |> Map.take(@cache_fields)
      {:ok, Map.put(build(build), :cache, cache)}
    end
  end

  defp build(build) do
    %{
      id: build.id,
      actor: Tuist.ReportActor.actor(build),
      status: build.status,
      duration_ms: build.duration_ms,
      is_ci: build.is_ci,
      elixir_version: presence(build.elixir_version),
      otp_version: presence(build.otp_version),
      mix_env: presence(build.mix_env),
      git_branch: presence(build.git_branch),
      git_commit_sha: presence(build.git_commit_sha),
      git_ref: presence(build.git_ref),
      ci_provider: presence(build.ci_provider),
      ci_run_id: presence(build.ci_run_id),
      ci_project_handle: presence(build.ci_project_handle),
      ci_host: presence(build.ci_host),
      custom_metadata: %{tags: build.custom_tags, values: build.custom_values},
      diagnostics_error_count: build.diagnostics_error_count,
      diagnostics_warning_count: build.diagnostics_warning_count,
      started_at: timestamp(build.started_at),
      inserted_at: timestamp(build.inserted_at)
    }
  end

  defp presence(""), do: nil
  defp presence(value), do: value

  defp timestamp(nil), do: nil
  defp timestamp(%NaiveDateTime{} = value), do: value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()
end
