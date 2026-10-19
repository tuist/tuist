defmodule Tuist.OnceEvents.Query do
  @moduledoc "Project-scoped Once run reads shared by the HTTP API and MCP tools."
  alias Tuist.OnceEvents
  alias Tuist.OnceEvents.Analytics

  def list_runs(project_id, params) do
    page = Map.get(params, "page", 1)
    page_size = Map.get(params, "page_size", 20)

    filters =
      for key <- [:status, :git_branch],
          not is_nil(params[to_string(key)]),
          do: %{field: key, op: :==, value: params[to_string(key)]}

    {runs, meta} =
      Analytics.list_invocations(
        project_id,
        %{
          filters: filters,
          order_by: [:started_at, :id],
          order_directions: [:desc, :desc],
          page: page,
          page_size: page_size
        },
        commands: params["kind"],
        is_ci: params["is_ci"]
      )

    # list_invocations clamps a page past the end to the last page; an API
    # page past the end is empty, as it is for Cargo and Mix builds.
    runs = if page > meta.current_page, do: [], else: runs

    %{
      runs: Enum.map(runs, &run/1),
      pagination_metadata: %{
        has_next_page: page < meta.total_pages,
        has_previous_page: page > 1,
        current_page: page,
        page_size: page_size,
        total_count: meta.total_count,
        total_pages: meta.total_pages
      }
    }
  end

  def get_run(project_id, run_id) do
    case OnceEvents.get_run(project_id, run_id) do
      nil ->
        {:error, :not_found}

      run ->
        {:ok,
         run
         |> Analytics.to_invocation()
         |> run()
         |> Map.merge(%{
           once_version: run.once_version,
           git_dirty: run.git_dirty,
           exit_status: run.exit_status,
           cancellation_reason: run.cancellation_reason,
           actions: %{
             total: run.total_actions,
             cached: run.cached_actions,
             executed: run.executed_actions,
             failed: run.failed_actions
           },
           cache: OnceEvents.cache_summary(run),
           tests: tests(run)
         })}
    end
  end

  defp run(invocation) do
    %{
      run_id: invocation.invocation_id,
      kind: invocation.kind,
      command: invocation.command,
      status: invocation.status,
      duration_ms: invocation.duration_ms,
      is_ci: invocation.is_ci,
      git_rev: invocation.git_rev,
      git_branch: if(invocation.git_branch != "", do: invocation.git_branch),
      host_class: invocation.host_class,
      started_at: timestamp(invocation.started_at),
      finished_at: timestamp(invocation.finalized_at),
      cache: invocation.cache
    }
  end

  defp tests(%{kind: "test"} = run) do
    %{
      test_cases: run.test_case_count,
      passed: run.passed_test_cases,
      failed: run.failed_test_cases,
      skipped: run.skipped_test_cases,
      test_suites: run.test_suite_count
    }
  end

  defp tests(_run), do: nil

  defp timestamp(nil), do: nil
  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
