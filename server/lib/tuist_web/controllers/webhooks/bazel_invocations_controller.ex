defmodule TuistWeb.Webhooks.BazelInvocationsController do
  use TuistWeb, :controller

  alias Tuist.Bazel
  alias Tuist.Projects
  alias TuistWeb.Plugs.RequireCacheEndpointPlug

  require Logger

  @max_events_per_request 100
  @max_uint64 18_446_744_073_709_551_615
  @max_handle_bytes 256
  @max_invocation_id_bytes 256
  @max_command_bytes 256
  @max_action_spans 33
  @max_action_description_bytes 256
  @max_critical_path_actions 32
  @max_invocation_logs 32
  @max_invocation_log_message_bytes 2 * 1_024
  @max_invocation_log_total_bytes 32 * 1_024

  def handle(conn, %{"events" => events}) when is_list(events) do
    {events, overflow_events} = Enum.split(events, @max_events_per_request)
    received_count = length(events) + length(overflow_events)
    conn = RequireCacheEndpointPlug.call(conn, [])

    if conn.halted do
      conn
    else
      cache_endpoint = conn.assigns.cache_endpoint

      projects_map =
        events
        |> Enum.filter(&valid_project_reference?/1)
        |> Enum.map(&"#{&1["account_handle"]}/#{&1["project_handle"]}")
        |> Enum.uniq()
        |> Projects.projects_by_full_handles()

      {invocations, logs} =
        Enum.reduce(events, {[], []}, fn event, {invocations, logs} ->
          case invocation_from_event(event, projects_map, cache_endpoint) do
            {invocation, invocation_logs} ->
              {[invocation | invocations], [invocation_logs | logs]}

            nil ->
              {invocations, logs}
          end
        end)

      invocations = Enum.reverse(invocations)
      logs = logs |> Enum.reverse() |> List.flatten()

      Bazel.create_invocations(invocations)
      Bazel.create_invocation_logs(logs)

      conn
      |> put_status(:accepted)
      |> json(%{accepted: length(invocations), rejected: received_count - length(invocations)})
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
    target_patterns = Map.get(event, "target_patterns", [])
    git_branch = Map.get(event, "git_branch", "")
    git_commit_sha = Map.get(event, "git_commit_sha", "")
    is_ci = Map.get(event, "is_ci", false)

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
         true <- valid_event?(event),
         %{id: project_id, build_system: :bazel} <- Map.get(projects_map, "#{account_handle}/#{project_handle}"),
         {:ok, started_at} <- DateTime.from_unix(started_at_ms, :millisecond),
         {:ok, finished_at} <- DateTime.from_unix(finished_at_ms, :millisecond),
         true <- DateTime.compare(finished_at, started_at) != :lt do
      invocation = %{
        invocation_id: invocation_id,
        command: command,
        target_patterns: target_patterns,
        git_branch: git_branch,
        git_commit_sha: git_commit_sha,
        is_ci: is_ci,
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

      invocation = Map.merge(invocation, invocation_diagnostics(event))

      {invocation, invocation_logs(event, project_id, invocation_id)}
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

  defp valid_event?(event) do
    valid_project_reference?(event) and
      valid_identifiers?(event["invocation_id"], event["command"]) and
      valid_context?(
        Map.get(event, "target_patterns", []),
        Map.get(event, "git_branch", ""),
        Map.get(event, "git_commit_sha", ""),
        Map.get(event, "is_ci", false)
      ) and
      valid_diagnostics?(event) and
      valid_logs?(Map.get(event, "logs", [])) and
      valid_result?(event["status"], event["exit_code"]) and
      valid_timestamps?(event["started_at_ms"], event["finished_at_ms"])
  end

  defp valid_identifiers?(invocation_id, command),
    do:
      is_binary(invocation_id) and invocation_id != "" and byte_size(invocation_id) <= @max_invocation_id_bytes and
        is_binary(command) and byte_size(command) <= @max_command_bytes

  defp valid_project_reference?(%{"account_handle" => account_handle, "project_handle" => project_handle}) do
    is_binary(account_handle) and account_handle != "" and byte_size(account_handle) <= @max_handle_bytes and
      is_binary(project_handle) and project_handle != "" and byte_size(project_handle) <= @max_handle_bytes
  end

  defp valid_project_reference?(_), do: false

  defp valid_context?(target_patterns, git_branch, git_commit_sha, is_ci) do
    is_list(target_patterns) and length(target_patterns) <= 128 and
      Enum.all?(target_patterns, &(is_binary(&1) and byte_size(&1) <= 1_024)) and
      is_binary(git_branch) and byte_size(git_branch) <= 1_024 and
      is_binary(git_commit_sha) and byte_size(git_commit_sha) <= 1_024 and is_boolean(is_ci)
  end

  defp valid_result?(status, exit_code),
    do:
      status in ["success", "failure"] and is_integer(exit_code) and exit_code >= -2_147_483_648 and
        exit_code <= 2_147_483_647

  defp valid_diagnostics?(event) do
    timeline_lanes = Map.get(event, "build_timeline_lanes", [])
    timeline_span_lanes = Map.get(event, "build_timeline_span_lanes", [])
    timeline_span_start_ms = Map.get(event, "build_timeline_span_start_ms", [])
    timeline_span_durations_ms = Map.get(event, "build_timeline_span_durations_ms", [])
    timeline_span_categories = Map.get(event, "build_timeline_span_categories", [])
    timeline_span_descriptions = Map.get(event, "build_timeline_span_descriptions", [])
    critical_path_action_descriptions = Map.get(event, "critical_path_action_descriptions", [])
    critical_path_action_durations_ms = Map.get(event, "critical_path_action_durations_ms", [])

    valid_metric_fields?(event) and
      valid_timeline?(
        timeline_lanes,
        timeline_span_lanes,
        timeline_span_start_ms,
        timeline_span_durations_ms,
        timeline_span_categories,
        timeline_span_descriptions
      ) and
      valid_critical_path?(critical_path_action_descriptions, critical_path_action_durations_ms)
  end

  defp valid_metric_fields?(event) do
    is_binary(Map.get(event, "bazel_version", "")) and byte_size(Map.get(event, "bazel_version", "")) <= 256 and
      Enum.all?(
        [
          Map.get(event, "cpu_time_ms", 0),
          Map.get(event, "actions_created", 0),
          Map.get(event, "actions_executed", 0),
          Map.get(event, "targets_configured", 0),
          Map.get(event, "packages_loaded", 0),
          Map.get(event, "build_timeline_duration_ms", 0),
          Map.get(event, "critical_path_duration_ms", 0)
        ],
        &valid_uint64?/1
      )
  end

  defp valid_timeline?(
         timeline_lanes,
         timeline_span_lanes,
         timeline_span_start_ms,
         timeline_span_durations_ms,
         timeline_span_categories,
         timeline_span_descriptions
       ) do
    valid_strings?(timeline_lanes, @max_action_spans, @max_action_description_bytes) and
      valid_integers?(timeline_span_lanes, @max_action_spans, &valid_uint8?/1) and
      valid_integers?(timeline_span_start_ms, @max_action_spans, &valid_uint64?/1) and
      valid_integers?(timeline_span_durations_ms, @max_action_spans, &valid_uint64?/1) and
      valid_strings?(timeline_span_categories, @max_action_spans, 32) and
      Enum.all?(timeline_span_categories, &(&1 in ["analysis", "execution"])) and
      valid_strings?(timeline_span_descriptions, @max_action_spans, @max_action_description_bytes) and
      equal_lengths?([
        timeline_span_lanes,
        timeline_span_start_ms,
        timeline_span_durations_ms,
        timeline_span_categories,
        timeline_span_descriptions
      ]) and
      Enum.all?(timeline_span_lanes, &(&1 < length(timeline_lanes)))
  end

  defp valid_critical_path?(critical_path_action_descriptions, critical_path_action_durations_ms) do
    valid_strings?(critical_path_action_descriptions, @max_critical_path_actions, @max_action_description_bytes) and
      valid_integers?(critical_path_action_durations_ms, @max_critical_path_actions, &valid_uint64?/1) and
      length(critical_path_action_descriptions) == length(critical_path_action_durations_ms)
  end

  defp valid_logs?(logs) when is_list(logs) and length(logs) <= @max_invocation_logs do
    Enum.all?(logs, fn log ->
      is_map(log) and valid_uint64?(log["sequence_number"]) and log["stream"] in ["stdout", "stderr"] and
        is_binary(log["message"]) and byte_size(log["message"]) <= @max_invocation_log_message_bytes and
        valid_uint64?(log["observed_at_ms"]) and plausible_timestamp?(log["observed_at_ms"])
    end) and Enum.sum(Enum.map(logs, &byte_size(&1["message"]))) <= @max_invocation_log_total_bytes
  end

  defp valid_logs?(_), do: false

  defp valid_strings?(values, max_count, max_bytes) when is_list(values) and length(values) <= max_count do
    Enum.all?(values, &(is_binary(&1) and byte_size(&1) <= max_bytes))
  end

  defp valid_strings?(_, _, _), do: false

  defp valid_integers?(values, max_count, validator) when is_list(values) and length(values) <= max_count do
    Enum.all?(values, validator)
  end

  defp valid_integers?(_, _, _), do: false

  defp equal_lengths?([first | rest]) do
    Enum.all?(rest, &(length(&1) == length(first)))
  end

  defp valid_uint8?(value), do: is_integer(value) and value >= 0 and value <= 255
  defp valid_uint64?(value), do: is_integer(value) and value >= 0 and value <= @max_uint64

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

  defp invocation_diagnostics(event) do
    %{
      bazel_version: Map.get(event, "bazel_version", ""),
      cpu_time_ms: Map.get(event, "cpu_time_ms", 0),
      actions_created: Map.get(event, "actions_created", 0),
      actions_executed: Map.get(event, "actions_executed", 0),
      targets_configured: Map.get(event, "targets_configured", 0),
      packages_loaded: Map.get(event, "packages_loaded", 0),
      build_timeline_duration_ms: Map.get(event, "build_timeline_duration_ms", 0),
      build_timeline_lanes: Map.get(event, "build_timeline_lanes", []),
      build_timeline_span_lanes: Map.get(event, "build_timeline_span_lanes", []),
      build_timeline_span_start_ms: Map.get(event, "build_timeline_span_start_ms", []),
      build_timeline_span_durations_ms: Map.get(event, "build_timeline_span_durations_ms", []),
      build_timeline_span_categories: Map.get(event, "build_timeline_span_categories", []),
      build_timeline_span_descriptions: Map.get(event, "build_timeline_span_descriptions", []),
      critical_path_duration_ms: Map.get(event, "critical_path_duration_ms", 0),
      critical_path_action_descriptions: Map.get(event, "critical_path_action_descriptions", []),
      critical_path_action_durations_ms: Map.get(event, "critical_path_action_durations_ms", [])
    }
  end

  defp invocation_logs(event, project_id, invocation_id) do
    Enum.map(Map.get(event, "logs", []), fn log ->
      {:ok, observed_at} = DateTime.from_unix(log["observed_at_ms"], :millisecond)

      %{
        invocation_id: invocation_id,
        sequence_number: log["sequence_number"],
        stream: log["stream"],
        message: Bazel.sanitize_invocation_log(log["message"]),
        project_id: project_id,
        observed_at: observed_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
      }
    end)
  end
end
