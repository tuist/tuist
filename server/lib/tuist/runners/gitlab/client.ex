defmodule Tuist.Runners.GitLab.Client do
  @moduledoc "GitLab Runner protocol. Reusable runner credentials never leave this client."

  alias Tuist.OAuth2.SSRFGuard

  # Keep aligned with infra/linux-runner-image/gitlab-runner/go.mod. Advertise only features
  # supported by the shell executor in our isolated runner images.
  @version "18.11.1"
  @max_response_bytes 16 * 1024 * 1024

  def request_job(connection) do
    request(connection.url, :post, "/jobs/request", %{
      token: connection.runner_token,
      system_id: "r_tuist_#{connection.id}",
      info: %{
        name: "gitlab-runner",
        version: @version,
        platform: "linux",
        architecture: "amd64",
        executor: "shell",
        shell: "bash",
        features: %{
          variables: true,
          artifacts: true,
          cache: true,
          upload_multiple_artifacts: true,
          upload_raw_artifacts: true,
          artifacts_exclude: true,
          multi_build_steps: true,
          cancelable: true,
          trace_reset: true,
          trace_checksum: true,
          trace_size: true,
          refspecs: true,
          extended_statuses: true,
          masking: true
        }
      }
    })
  end

  def update_job(url, %{"id" => id, "token" => token}, state, reason) do
    request(url, :put, "/jobs/#{id}", %{token: token, state: state, failure_reason: reason})
  end

  def reject_job(url, %{"id" => id, "token" => token} = payload, message) do
    trace = "Tuist: #{message}\n"

    case request(url, :patch, "/jobs/#{id}/trace", %{token: token}, trace) do
      {:ok, _} -> update_job(url, payload, "failed", "script_failure")
      {:error, {:http_status, 416}} -> update_job(url, payload, "failed", "script_failure")
      error -> error
    end
  end

  defp request(url, method, path, body, trace \\ nil) do
    with {:ok, pinned_url, hostname} <- SSRFGuard.pin(url <> "/api/v4" <> path) do
      response =
        Req.request(
          [
            method: method,
            url: pinned_url,
            headers: request_headers(url, path, body) ++ trace_headers(trace),
            raw: true,
            into: &bounded_body/2,
            connect_options: SSRFGuard.connect_options(hostname),
            redirect: false,
            retry: false,
            receive_timeout: to_timeout(minute: 1)
          ] ++ if(trace, do: [body: trace], else: [json: body])
        )

      handle_response(response, method)
    end
  end

  defp handle_response({:ok, %{headers: %{"job-status" => [state]}}}, _method) when state in ["canceled", "canceling"],
    do: {:error, :cancelled}

  defp handle_response({:ok, %{status: 204}}, _method), do: {:ok, nil}

  defp handle_response({:ok, %{status: status}}, method) when method in [:put, :patch] and status in 200..299,
    do: {:ok, nil}

  defp handle_response({:ok, %{status: status, body: response}}, _method) when status in 200..299,
    do: decode_response(response)

  defp handle_response({:ok, %{status: status}}, _method) when status in [401, 403], do: {:error, :unauthorized}
  defp handle_response({:ok, %{status: 404}}, _method), do: {:error, :not_found}
  defp handle_response({:ok, %{status: 429}}, _method), do: {:error, :rate_limited}
  defp handle_response({:ok, %{status: status}}, _method), do: {:error, {:http_status, status}}
  defp handle_response({:error, _}, _method), do: {:error, :transport}

  defp request_headers(url, path, body) do
    headers = [{"host", URI.parse(url).authority}, {"accept-encoding", "identity"}]
    token_header = if path == "/jobs/request", do: "runner-token", else: "job-token"
    [{token_header, body.token} | headers]
  end

  defp trace_headers(nil), do: []

  defp trace_headers(trace), do: [{"content-type", "text/plain"}, {"content-range", "0-#{byte_size(trace) - 1}"}]

  defp bounded_body({:data, chunk}, {request, response}) do
    if byte_size(response.body) + byte_size(chunk) <= @max_response_bytes do
      {:cont, {request, %{response | body: response.body <> chunk}}}
    else
      {:halt, {request, %{response | status: 413, body: ""}}}
    end
  end

  defp decode_response(""), do: {:ok, nil}

  defp decode_response(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      _ -> {:error, :invalid_response}
    end
  end
end
