defmodule TuistWeb.Webhooks.BazelTestArtifactsController do
  use TuistWeb, :controller

  alias Tuist.Bazel
  alias Tuist.Projects
  alias TuistWeb.Plugs.RequireCacheEndpointPlug

  require Logger

  @max_artifact_bytes 256 * 1_024
  @max_artifacts_per_result 2
  @valid_statuses ["success", "failure", "flaky", "skipped"]

  def handle(conn, payload) when is_map(payload) do
    conn = RequireCacheEndpointPlug.call(conn, [])

    if conn.halted do
      conn
    else
      with {:ok, event} <- parse_event(payload),
           {:ok, project} <- bazel_project(event) do
        persist_event(conn, project, event)
      else
        {:error, :invalid_payload} -> invalid_payload(conn)
      end
    end
  rescue
    exception ->
      Logger.error("bazel: could not persist test event: #{Exception.message(exception)}")
      service_unavailable(conn)
  end

  def handle(conn, _params), do: invalid_payload(conn)

  defp persist_event(conn, project, %{event_kind: "test_result"} = event) do
    result =
      event
      |> Map.drop([:account_handle, :project_handle, :event_kind])
      |> Map.put(:project_id, project.id)
      |> Bazel.stage_test_result()

    case result do
      :ok -> accepted(conn)
      {:error, :artifact_limit_exceeded} -> payload_too_large(conn)
      {:error, _reason} -> service_unavailable(conn)
    end
  end

  defp persist_event(conn, project, %{event_kind: "test_summary"} = event) do
    event
    |> Map.drop([:account_handle, :project_handle, :event_kind])
    |> Map.put(:project_id, project.id)
    |> Bazel.stage_test_summary()

    accepted(conn)
  end

  defp persist_event(conn, project, %{event_kind: "invocation_finished"} = event) do
    case Bazel.complete_test_invocation(project.id, event.invocation_id) do
      {:ok, _job} -> accepted(conn)
      {:error, _reason} -> service_unavailable(conn)
    end
  end

  defp bazel_project(%{account_handle: account_handle, project_handle: project_handle}) do
    full_handle = "#{account_handle}/#{project_handle}"

    case [full_handle] |> Projects.projects_by_full_handles() |> Map.get(full_handle) do
      %{build_system: :bazel} = project -> {:ok, project}
      _ -> {:error, :invalid_payload}
    end
  end

  defp parse_event(%{
         "event_kind" => "test_result",
         "account_handle" => account_handle,
         "project_handle" => project_handle,
         "invocation_id" => invocation_id,
         "target_label" => target_label,
         "run" => run,
         "shard" => shard,
         "attempt" => attempt,
         "status" => status,
         "duration_ms" => duration_ms,
         "started_at_ms" => started_at_ms,
         "cached" => cached,
         "is_ci" => is_ci,
         "sequence_number" => sequence_number,
         "artifacts" => artifacts
       }) do
    with :ok <- valid_identity(account_handle, project_handle, invocation_id),
         true <- valid_string?(target_label, 1_024),
         true <- non_negative_integer?(run),
         true <- non_negative_integer?(shard),
         true <- positive_integer?(attempt),
         true <- status in @valid_statuses,
         true <- non_negative_integer?(duration_ms),
         true <- non_negative_integer?(started_at_ms),
         {:ok, started_at} <- DateTime.from_unix(started_at_ms, :millisecond),
         true <- is_boolean(cached),
         true <- is_boolean(is_ci),
         true <- non_negative_integer?(sequence_number),
         {:ok, artifact_attributes} <- parse_artifacts(artifacts) do
      {:ok,
       Map.merge(artifact_attributes, %{
         event_kind: "test_result",
         account_handle: account_handle,
         project_handle: project_handle,
         invocation_id: invocation_id,
         target_label: target_label,
         run: run,
         shard: shard,
         attempt: attempt,
         status: status,
         duration_ms: min(duration_ms, 2_147_483_647),
         started_at: DateTime.truncate(started_at, :second),
         cached: cached,
         is_ci: is_ci,
         sequence_number: sequence_number
       })}
    else
      _ -> {:error, :invalid_payload}
    end
  end

  defp parse_event(%{
         "event_kind" => "test_summary",
         "account_handle" => account_handle,
         "project_handle" => project_handle,
         "invocation_id" => invocation_id,
         "target_label" => target_label,
         "status" => status,
         "total_run_count" => total_run_count,
         "total_num_cached" => total_num_cached,
         "duration_ms" => duration_ms,
         "started_at_ms" => started_at_ms,
         "finished_at_ms" => finished_at_ms
       }) do
    with :ok <- valid_identity(account_handle, project_handle, invocation_id),
         true <- valid_string?(target_label, 1_024),
         true <- status in @valid_statuses,
         true <- non_negative_integer?(total_run_count),
         true <- non_negative_integer?(total_num_cached),
         true <- total_num_cached <= total_run_count,
         true <- non_negative_integer?(duration_ms),
         true <- non_negative_integer?(started_at_ms),
         true <- non_negative_integer?(finished_at_ms),
         true <- started_at_ms <= finished_at_ms,
         {:ok, started_at} <- DateTime.from_unix(started_at_ms, :millisecond),
         {:ok, finished_at} <- DateTime.from_unix(finished_at_ms, :millisecond) do
      {:ok,
       %{
         event_kind: "test_summary",
         account_handle: account_handle,
         project_handle: project_handle,
         invocation_id: invocation_id,
         target_label: target_label,
         status: status,
         total_run_count: min(total_run_count, 2_147_483_647),
         total_num_cached: min(total_num_cached, 2_147_483_647),
         duration_ms: min(duration_ms, 2_147_483_647),
         started_at: DateTime.truncate(started_at, :second),
         finished_at: DateTime.truncate(finished_at, :second)
       }}
    else
      _ -> {:error, :invalid_payload}
    end
  end

  defp parse_event(%{
         "event_kind" => "invocation_finished",
         "account_handle" => account_handle,
         "project_handle" => project_handle,
         "invocation_id" => invocation_id
       }) do
    with :ok <- valid_identity(account_handle, project_handle, invocation_id) do
      {:ok,
       %{
         event_kind: "invocation_finished",
         account_handle: account_handle,
         project_handle: project_handle,
         invocation_id: invocation_id
       }}
    end
  end

  defp parse_event(_payload), do: {:error, :invalid_payload}

  defp parse_artifacts(artifacts) when is_list(artifacts) and length(artifacts) <= @max_artifacts_per_result do
    Enum.reduce_while(artifacts, {:ok, %{}}, fn artifact, {:ok, attributes} ->
      case parse_artifact(artifact) do
        {:ok, kind, digest, content} ->
          if Map.has_key?(attributes, artifact_content_key(kind)) do
            {:halt, {:error, :invalid_payload}}
          else
            {:cont, {:ok, Map.merge(attributes, artifact_attributes(kind, digest, content))}}
          end

        {:error, :invalid_payload} ->
          {:halt, {:error, :invalid_payload}}
      end
    end)
  end

  defp parse_artifacts(_artifacts), do: {:error, :invalid_payload}

  defp artifact_attributes("junit", digest, content), do: %{junit_digest: digest, junit_content: content}
  defp artifact_attributes("log", digest, content), do: %{log_digest: digest, log_content: content}
  defp artifact_content_key("junit"), do: :junit_content
  defp artifact_content_key("log"), do: :log_content

  defp parse_artifact(%{"artifact_kind" => kind, "digest" => digest, "content_base64" => content_base64})
       when kind in ["junit", "log"] do
    with true <- valid_digest?(digest),
         {:ok, content} <- Base.decode64(content_base64),
         true <- byte_size(content) in 1..@max_artifact_bytes,
         true <- String.valid?(content) do
      {:ok, kind, String.downcase(digest), content}
    else
      _ -> {:error, :invalid_payload}
    end
  end

  defp parse_artifact(_artifact), do: {:error, :invalid_payload}

  defp valid_identity(account_handle, project_handle, invocation_id) do
    if valid_string?(account_handle, 255) and valid_string?(project_handle, 255) and
         valid_string?(invocation_id, 255) do
      :ok
    else
      {:error, :invalid_payload}
    end
  end

  defp valid_string?(value, max_bytes), do: is_binary(value) and byte_size(value) in 1..max_bytes
  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp non_negative_integer?(value), do: is_integer(value) and value >= 0

  defp valid_digest?(digest) do
    is_binary(digest) and byte_size(digest) == 64 and digest =~ ~r/\A[0-9a-fA-F]{64}\z/
  end

  defp invalid_payload(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid Bazel test event"})
    |> halt()
  end

  defp service_unavailable(conn) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Bazel test event could not be persisted"})
    |> halt()
  end

  defp payload_too_large(conn) do
    conn
    |> put_status(:payload_too_large)
    |> json(%{error: "Bazel test invocation artifact limit exceeded"})
    |> halt()
  end

  defp accepted(conn) do
    conn
    |> put_status(:accepted)
    |> json(%{})
    |> halt()
  end
end
