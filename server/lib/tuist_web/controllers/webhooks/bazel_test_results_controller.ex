defmodule TuistWeb.Webhooks.BazelTestResultsController do
  use TuistWeb, :controller

  alias Tuist.Bazel
  alias Tuist.Projects
  alias TuistWeb.Plugs.RequireCacheEndpointPlug

  require Logger

  def handle(conn, %{"events" => events}) when is_list(events) do
    conn = RequireCacheEndpointPlug.call(conn, [])

    if conn.halted do
      conn
    else
      cache_endpoint = conn.assigns.cache_endpoint

      projects_map =
        events
        |> Enum.filter(&is_map/1)
        |> Enum.map(&"#{&1["account_handle"]}/#{&1["project_handle"]}")
        |> Enum.uniq()
        |> Projects.projects_by_full_handles()

      test_results =
        events
        |> Enum.map(&test_result_from_event(&1, projects_map, cache_endpoint))
        |> Enum.reject(&is_nil/1)

      Bazel.create_test_results(test_results)

      conn
      |> put_status(:accepted)
      |> json(%{})
      |> halt()
    end
  end

  def handle(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid payload"})
    |> halt()
  end

  defp test_result_from_event(event, projects_map, cache_endpoint) when is_map(event) do
    with %{
           "account_handle" => account_handle,
           "project_handle" => project_handle,
           "invocation_id" => invocation_id,
           "target_label" => target_label,
           "status" => status,
           "duration_ms" => duration_ms,
           "attempt_count" => attempt_count,
           "finished_at_ms" => finished_at_ms
         } <- event,
         %{id: project_id, build_system: :bazel} <- Map.get(projects_map, "#{account_handle}/#{project_handle}"),
         true <- valid_event?(invocation_id, target_label, status, duration_ms, attempt_count, finished_at_ms),
         {:ok, finished_at} <- DateTime.from_unix(finished_at_ms, :millisecond) do
      %{
        invocation_id: invocation_id,
        target_label: target_label,
        status: status,
        duration_ms: duration_ms,
        attempt_count: attempt_count,
        finished_at: finished_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second),
        project_id: project_id,
        account_handle: account_handle,
        project_handle: project_handle,
        cache_endpoint: cache_endpoint
      }
    else
      nil ->
        Logger.warning("Project not found for Bazel test result")
        nil

      _ ->
        Logger.warning("Invalid Bazel test result")
        nil
    end
  end

  defp test_result_from_event(_, _, _), do: nil

  defp valid_event?(invocation_id, target_label, status, duration_ms, attempt_count, finished_at_ms) do
    is_binary(invocation_id) and invocation_id != "" and is_binary(target_label) and target_label != "" and
      status in ["success", "failure", "flaky", "skipped"] and is_integer(duration_ms) and duration_ms >= 0 and
      is_integer(attempt_count) and attempt_count >= 1 and is_integer(finished_at_ms) and finished_at_ms >= 0
  end
end
