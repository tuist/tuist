defmodule TuistWeb.Webhooks.BazelInvocationsController do
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

      invocations =
        events
        |> Enum.map(&invocation_from_event(&1, projects_map, cache_endpoint))
        |> Enum.reject(&is_nil/1)

      Bazel.create_invocations(invocations)

      conn
      |> put_status(:accepted)
      |> json(%{accepted: length(invocations), rejected: length(events) - length(invocations)})
      |> halt()
    end
  end

  def handle(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid payload"})
    |> halt()
  end

  defp invocation_from_event(event, projects_map, cache_endpoint) when is_map(event) do
    with %{
           "account_handle" => account_handle,
           "project_handle" => project_handle,
           "invocation_id" => invocation_id,
           "command" => command,
           "status" => status,
           "exit_code" => exit_code,
           "started_at_ms" => started_at_ms,
           "finished_at_ms" => finished_at_ms
         } <- event,
         %{id: project_id, build_system: :bazel} <- Map.get(projects_map, "#{account_handle}/#{project_handle}"),
         true <- valid_event?(invocation_id, command, status, exit_code, started_at_ms, finished_at_ms),
         {:ok, started_at} <- DateTime.from_unix(started_at_ms, :millisecond),
         {:ok, finished_at} <- DateTime.from_unix(finished_at_ms, :millisecond),
         true <- DateTime.compare(finished_at, started_at) != :lt do
      %{
        invocation_id: invocation_id,
        command: command,
        status: status,
        exit_code: exit_code,
        started_at: started_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second),
        finished_at: finished_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second),
        duration_ms: finished_at_ms - started_at_ms,
        project_id: project_id,
        account_handle: account_handle,
        project_handle: project_handle,
        cache_endpoint: cache_endpoint
      }
    else
      nil ->
        Logger.warning(
          "Project not found for Bazel invocation: #{Map.get(event, "account_handle", "unknown")}/#{Map.get(event, "project_handle", "unknown")}"
        )

        nil

      _ ->
        Logger.warning(
          "Invalid Bazel invocation for #{Map.get(event, "account_handle", "unknown")}/#{Map.get(event, "project_handle", "unknown")}"
        )

        nil
    end
  end

  defp invocation_from_event(_, _, _), do: nil

  defp valid_event?(invocation_id, command, status, exit_code, started_at_ms, finished_at_ms) do
    valid_identifiers?(invocation_id, command) and valid_result?(status, exit_code) and
      valid_timestamps?(started_at_ms, finished_at_ms)
  end

  defp valid_identifiers?(invocation_id, command),
    do: is_binary(invocation_id) and invocation_id != "" and is_binary(command)

  defp valid_result?(status, exit_code), do: status in ["success", "failure"] and is_integer(exit_code)

  defp valid_timestamps?(started_at_ms, finished_at_ms) do
    is_integer(started_at_ms) and started_at_ms >= 0 and is_integer(finished_at_ms) and finished_at_ms >= 0 and
      plausible_timestamp?(started_at_ms) and plausible_timestamp?(finished_at_ms)
  end

  defp plausible_timestamp?(timestamp_ms) do
    case DateTime.from_unix(timestamp_ms, :millisecond) do
      {:ok, timestamp} -> DateTime.compare(timestamp, DateTime.add(DateTime.utc_now(), 1, :hour)) != :gt
      _ -> false
    end
  end
end
