defmodule TuistWeb.Webhooks.BazelTestArtifactsController do
  use TuistWeb, :controller

  alias Tuist.Bazel
  alias Tuist.Projects
  alias TuistWeb.Plugs.RequireCacheEndpointPlug

  @max_artifact_bytes 256 * 1_024
  @test_log_sequence_offset 1_000_000_000_000

  def handle(conn, payload) when is_map(payload) do
    conn = RequireCacheEndpointPlug.call(conn, [])

    if conn.halted do
      conn
    else
      with {:ok, artifact} <- parse_artifact(payload),
           {:ok, project} <- bazel_project(artifact),
           {:ok, invocation} <- Bazel.get_invocation(project.id, artifact.invocation_id) do
        receipt = receipt_attributes(project, artifact)

        case Bazel.claim_test_artifact_receipt(receipt) do
          :already_claimed ->
            accepted(conn, project, artifact)

          :claimed ->
            try do
              persist_artifact(conn, project, invocation, artifact, receipt)
            rescue
              exception ->
                Bazel.delete_test_artifact_receipt(receipt)
                reraise exception, __STACKTRACE__
            end
        end
      else
        {:error, :invalid_payload} -> invalid_payload(conn)
        {:error, :not_found} -> retry_later(conn)
      end
    end
  end

  def handle(conn, _params), do: invalid_payload(conn)

  defp persist_artifact(conn, project, invocation, artifact, receipt) do
    case artifact.artifact_kind do
      "junit" ->
        case Bazel.ingest_test_report(project, invocation, test_result(artifact, invocation), artifact.content) do
          :ok ->
            accepted(conn, project, artifact)

          {:error, _reason} ->
            Bazel.delete_test_artifact_receipt(receipt)
            invalid_payload(conn)
        end

      "log" ->
        Bazel.create_invocation_logs([test_log(project.id, artifact)])
        accepted(conn, project, artifact)
    end
  end

  defp bazel_project(%{account_handle: account_handle, project_handle: project_handle}) do
    full_handle = "#{account_handle}/#{project_handle}"

    case [full_handle] |> Projects.projects_by_full_handles() |> Map.get(full_handle) do
      %{build_system: :bazel} = project -> {:ok, project}
      _ -> {:error, :invalid_payload}
    end
  end

  defp parse_artifact(payload) do
    with %{
           "account_handle" => account_handle,
           "project_handle" => project_handle,
           "invocation_id" => invocation_id,
           "target_label" => target_label,
           "action_digest" => action_digest,
           "artifact_kind" => artifact_kind,
           "digest" => digest,
           "content_base64" => content_base64
         } <- payload,
         true <- valid_string?(account_handle, 255),
         true <- valid_string?(project_handle, 255),
         true <- valid_string?(invocation_id, 255),
         true <- valid_string?(target_label, 1_024),
         true <- valid_digest?(action_digest),
         true <- artifact_kind in ["junit", "log"],
         true <- valid_digest?(digest),
         {:ok, content} <- Base.decode64(content_base64),
         true <- byte_size(content) in 1..@max_artifact_bytes,
         true <- valid_content?(artifact_kind, content) do
      {:ok,
       %{
         account_handle: account_handle,
         project_handle: project_handle,
         invocation_id: invocation_id,
         target_label: target_label,
         action_digest: String.downcase(action_digest),
         artifact_kind: artifact_kind,
         digest: String.downcase(digest),
         content: content
       }}
    else
      _ -> {:error, :invalid_payload}
    end
  end

  defp valid_string?(value, max_bytes), do: is_binary(value) and byte_size(value) in 1..max_bytes

  defp valid_digest?(digest) do
    is_binary(digest) and byte_size(digest) == 64 and digest =~ ~r/\A[0-9a-fA-F]{64}\z/
  end

  defp valid_content?("junit", _content), do: true
  defp valid_content?("log", content), do: String.valid?(content)

  defp receipt_attributes(project, artifact) do
    %{
      project_id: project.id,
      invocation_id: artifact.invocation_id,
      target_label: artifact.target_label,
      action_digest: artifact.action_digest,
      artifact_kind: artifact.artifact_kind,
      artifact_digest: artifact.digest
    }
  end

  defp test_log(project_id, artifact) do
    message =
      "[Bazel test log for #{artifact.target_label}]\n" <>
        Bazel.sanitize_log_message(artifact.content)

    %{
      invocation_id: artifact.invocation_id,
      sequence_number:
        @test_log_sequence_offset + :erlang.phash2({artifact.target_label, artifact.digest}, 1_000_000_000),
      stream: "stdout",
      message: message,
      project_id: project_id,
      observed_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    }
  end

  defp test_result(artifact, invocation) do
    %{
      target_label: artifact.target_label,
      status: if(invocation.status == "failure", do: "failure", else: "success"),
      duration_ms: 0
    }
  end

  defp retry_later(conn) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Bazel invocation is not ready"})
    |> halt()
  end

  defp invalid_payload(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid Bazel test artifact"})
    |> halt()
  end

  defp accepted(conn, _project, _artifact) do
    conn
    |> put_status(:accepted)
    |> json(%{})
    |> halt()
  end
end
