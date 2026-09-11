defmodule TuistWeb.API.OnceInvocationsController do
  @moduledoc """
  Ingestion and listing of Once invocation summaries.

  The Once CLI posts a batch after each `once exec` completes. Each event is
  the summary of a single wrapped action: what the CLI ran, whether it came
  from the action cache, and how long the whole exec cycle took wall-clock.
  """
  use TuistWeb, :controller

  alias Tuist.Once
  alias Tuist.Once.Invocation
  alias Tuist.Projects.Project

  require Logger

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :build)

  @max_events_per_request 100
  @max_invocation_id_bytes 256
  @max_argv_entries 128
  @max_argv_entry_bytes 1024
  @max_git_field_bytes 1024

  def create(%{assigns: %{selected_project: %Project{} = project}} = conn, %{"events" => events}) when is_list(events) do
    if project.build_system == :once do
      {events, overflow} = Enum.split(events, @max_events_per_request)
      received = length(events) + length(overflow)

      invocations =
        events
        |> Enum.map(&invocation_attrs(&1, project))
        |> Enum.reject(&is_nil/1)

      {inserted, _} = Once.create_invocations(invocations)

      conn
      |> put_status(:accepted)
      |> json(%{accepted: inserted, rejected: received - inserted})
      |> halt()
    else
      conn
      |> put_status(:conflict)
      |> json(%{
        error: "project_build_system_mismatch",
        message: "The project is not configured as an Once project."
      })
      |> halt()
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_payload", message: "Expected a JSON object with an `events` array."})
    |> halt()
  end

  def index(%{assigns: %{selected_project: %Project{} = project}} = conn, params) do
    limit =
      params
      |> Map.get("limit", "50")
      |> to_string()
      |> Integer.parse()
      |> case do
        {value, _} when value > 0 and value <= 200 -> value
        _ -> 50
      end

    invocations =
      project.id
      |> Once.list_invocations(limit: limit)
      |> Enum.map(&invocation_json/1)

    json(conn, %{invocations: invocations})
  end

  def show(%{assigns: %{selected_project: %Project{} = project}} = conn, %{"invocation_id" => invocation_id}) do
    case Once.get_invocation(project.id, invocation_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "invocation_not_found"})
        |> halt()

      %Invocation{} = invocation ->
        json(conn, invocation_json(invocation))
    end
  end

  defp invocation_attrs(event, project) when is_map(event) do
    with %{
           "invocation_id" => invocation_id,
           "status" => status,
           "exit_code" => exit_code,
           "started_at_ms" => started_at_ms,
           "finished_at_ms" => finished_at_ms
         } <- event,
         true <- valid_string?(invocation_id, @max_invocation_id_bytes),
         true <- status in ["success", "failure"],
         true <- is_integer(exit_code) and exit_code >= -2_147_483_648 and exit_code <= 2_147_483_647,
         true <- valid_timestamps?(started_at_ms, finished_at_ms),
         {:ok, started_at} <- DateTime.from_unix(started_at_ms, :millisecond),
         {:ok, finished_at} <- DateTime.from_unix(finished_at_ms, :millisecond),
         true <- DateTime.compare(finished_at, started_at) != :lt do
      cache = Map.get(event, "cache", "miss")
      cache = if cache in ["hit", "miss", "bypass"], do: cache, else: "miss"
      argv = event |> Map.get("argv", []) |> sanitize_argv()
      command = event |> Map.get("command", "exec") |> sanitize_command()

      %{
        project_id: project.id,
        invocation_id: invocation_id,
        command: command,
        argv: argv,
        cwd: sanitize_bounded_string(Map.get(event, "cwd"), 1024),
        action_digest: sanitize_bounded_string(Map.get(event, "action_digest"), 256),
        cache: cache,
        status: status,
        exit_code: exit_code,
        duration_ms: finished_at_ms - started_at_ms,
        started_at: DateTime.truncate(started_at, :second),
        finished_at: DateTime.truncate(finished_at, :second),
        git_branch: sanitize_bounded_string(Map.get(event, "git_branch", ""), @max_git_field_bytes) || "",
        git_commit_sha: sanitize_bounded_string(Map.get(event, "git_commit_sha", ""), 128) || "",
        is_ci: Map.get(event, "is_ci", false) == true,
        remote_execution: sanitize_bounded_string(Map.get(event, "remote_execution"), 64),
        os: sanitize_bounded_string(Map.get(event, "os", ""), 64) || "",
        arch: sanitize_bounded_string(Map.get(event, "arch", ""), 64) || "",
        once_version: sanitize_bounded_string(Map.get(event, "once_version", ""), 64) || "",
        workspace: sanitize_bounded_string(Map.get(event, "workspace", ""), 1024) || "",
        provider_name: sanitize_bounded_string(Map.get(event, "provider_name", ""), 128) || ""
      }
    else
      _ ->
        Logger.warning("Rejecting invalid Once invocation payload for project #{project.id}")
        nil
    end
  end

  defp invocation_attrs(_, _), do: nil

  defp valid_string?(value, max_bytes) do
    is_binary(value) and value != "" and byte_size(value) <= max_bytes
  end

  defp valid_timestamps?(started_at_ms, finished_at_ms) do
    is_integer(started_at_ms) and started_at_ms >= 0 and
      is_integer(finished_at_ms) and finished_at_ms >= 0 and
      plausible_timestamp?(started_at_ms) and plausible_timestamp?(finished_at_ms)
  end

  defp plausible_timestamp?(timestamp_ms) do
    case DateTime.from_unix(timestamp_ms, :millisecond) do
      {:ok, timestamp} -> DateTime.compare(timestamp, DateTime.add(DateTime.utc_now(), 1, :hour)) != :gt
      _ -> false
    end
  end

  defp sanitize_argv(argv) when is_list(argv) do
    argv
    |> Enum.take(@max_argv_entries)
    |> Enum.filter(&is_binary/1)
    |> Enum.map(fn arg ->
      if byte_size(arg) > @max_argv_entry_bytes, do: binary_part(arg, 0, @max_argv_entry_bytes), else: arg
    end)
  end

  defp sanitize_argv(_), do: []

  defp sanitize_command(command) when is_binary(command) do
    if byte_size(command) > 64, do: binary_part(command, 0, 64), else: command
  end

  defp sanitize_command(_), do: "exec"

  defp sanitize_bounded_string(nil, _), do: nil
  defp sanitize_bounded_string("", _), do: ""

  defp sanitize_bounded_string(value, max) when is_binary(value) do
    if byte_size(value) > max, do: binary_part(value, 0, max), else: value
  end

  defp sanitize_bounded_string(_, _), do: nil

  defp invocation_json(%Invocation{} = invocation) do
    %{
      id: invocation.id,
      invocation_id: invocation.invocation_id,
      command: invocation.command,
      argv: invocation.argv,
      cwd: invocation.cwd,
      action_digest: invocation.action_digest,
      cache: invocation.cache,
      status: invocation.status,
      exit_code: invocation.exit_code,
      duration_ms: invocation.duration_ms,
      started_at: invocation.started_at,
      finished_at: invocation.finished_at,
      git_branch: invocation.git_branch,
      git_commit_sha: invocation.git_commit_sha,
      is_ci: invocation.is_ci,
      remote_execution: invocation.remote_execution,
      os: invocation.os,
      arch: invocation.arch,
      once_version: invocation.once_version,
      workspace: invocation.workspace,
      provider_name: invocation.provider_name,
      inserted_at: invocation.inserted_at
    }
  end
end
