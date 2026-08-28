defmodule TuistWeb.Webhooks.BazelInvocationsController do
  use TuistWeb, :controller

  alias Tuist.Bazel
  alias Tuist.Projects
  alias TuistWeb.Plugs.RequireCacheEndpointPlug

  require Logger

  @max_target_patterns 100
  @max_target_pattern_length 1024
  @max_configurations 20
  @max_configuration_length 128
  @max_bazel_version_length 128
  @max_git_branch_length 255
  @max_git_commit_sha_length 64

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

  defp invocation_from_event(event, projects_map, cache_endpoint) when is_map(event) do
    target_patterns = target_patterns(event)
    command_configuration = command_configuration(event)
    git_metadata = git_metadata(event)

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
        target_patterns: target_patterns,
        requested_command: "",
        original_command_line: [],
        canonical_command_line: [],
        bazel_version: command_configuration.bazel_version,
        git_branch: git_metadata.branch,
        git_commit_sha: git_metadata.commit_sha,
        configurations: command_configuration.configurations,
        compilation_mode: command_configuration.compilation_mode,
        remote_cache_enabled: command_configuration.remote_cache_enabled,
        remote_execution_enabled: command_configuration.remote_execution_enabled,
        project_id: project_id,
        account_handle: account_handle,
        project_handle: project_handle,
        cache_endpoint: cache_endpoint
      }
    else
      nil ->
        Logger.warning("Project not found for Bazel invocation")
        nil

      _ ->
        Logger.warning("Invalid Bazel invocation")
        nil
    end
  end

  defp invocation_from_event(_, _, _), do: nil

  defp valid_event?(invocation_id, command, status, exit_code, started_at_ms, finished_at_ms) do
    is_binary(invocation_id) and invocation_id != "" and is_binary(command) and status in ["success", "failure"] and
      is_integer(exit_code) and is_integer(started_at_ms) and started_at_ms >= 0 and is_integer(finished_at_ms) and
      finished_at_ms >= 0
  end

  defp target_patterns(event) do
    case Map.get(event, "target_patterns") do
      target_patterns when is_list(target_patterns) ->
        target_patterns
        |> Enum.filter(&(is_binary(&1) and String.length(String.trim(&1)) in 1..@max_target_pattern_length))
        |> Enum.map(&String.trim/1)
        |> Enum.uniq()
        |> Enum.take(@max_target_patterns)

      _ ->
        []
    end
  end

  defp command_configuration(event) do
    %{
      bazel_version: bazel_version(event),
      configurations: configurations(event),
      compilation_mode: compilation_mode(event),
      remote_cache_enabled: Map.get(event, "remote_cache_enabled") == true,
      remote_execution_enabled: Map.get(event, "remote_execution_enabled") == true
    }
  end

  defp bazel_version(event) do
    case Map.get(event, "bazel_version") do
      version when is_binary(version) ->
        version = String.trim(version)

        if String.length(version) <= @max_bazel_version_length and String.printable?(version),
          do: version,
          else: ""

      _ ->
        ""
    end
  end

  defp configurations(event) do
    case Map.get(event, "configurations") do
      configurations when is_list(configurations) ->
        configurations
        |> Enum.filter(&safe_configuration_name?/1)
        |> Enum.uniq()
        |> Enum.take(@max_configurations)

      _ ->
        []
    end
  end

  defp safe_configuration_name?(configuration) when is_binary(configuration) do
    String.length(configuration) in 1..@max_configuration_length and
      String.match?(configuration, ~r/^[A-Za-z0-9_.\/-]+$/)
  end

  defp safe_configuration_name?(_), do: false

  defp compilation_mode(event) do
    case Map.get(event, "compilation_mode") do
      mode when mode in ["dbg", "fastbuild", "opt"] -> mode
      _ -> ""
    end
  end

  defp git_metadata(event) do
    %{
      branch: git_branch(event),
      commit_sha: git_commit_sha(event)
    }
  end

  defp git_branch(event) do
    case Map.get(event, "git_branch") do
      git_branch when is_binary(git_branch) ->
        git_branch = String.trim(git_branch)

        if String.length(git_branch) in 1..@max_git_branch_length and
             String.match?(git_branch, ~r/^[A-Za-z0-9][A-Za-z0-9._\/-]*$/) and
             not String.contains?(git_branch, "..") and not String.contains?(git_branch, "//"),
           do: git_branch,
           else: ""

      _ ->
        ""
    end
  end

  defp git_commit_sha(event) do
    case Map.get(event, "git_commit_sha") do
      git_commit_sha when is_binary(git_commit_sha) ->
        git_commit_sha = String.trim(git_commit_sha)

        if String.length(git_commit_sha) in 7..@max_git_commit_sha_length and
             String.match?(git_commit_sha, ~r/^[A-Fa-f0-9]+$/),
           do: git_commit_sha,
           else: ""

      _ ->
        ""
    end
  end
end
