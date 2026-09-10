defmodule Tuist.Runners.GitLab.Client do
  @moduledoc "GitLab Runner protocol. Reusable runner credentials never leave this client."

  alias Tuist.OAuth2.SSRFGuard

  # Keep aligned with infra/linux-runner-image/gitlab-runner/go.mod. Advertise only features
  # supported by the shell executor in our isolated runner images.
  @version "18.11.1"
  @max_response_bytes 16 * 1024 * 1024

  def request_job(connection, platform) do
    request(connection.url, :post, "/jobs/request", %{
      token: connection.runner_token,
      system_id: "r_tuist_#{connection.id}",
      info: %{
        name: "gitlab-runner",
        version: @version,
        platform: if(platform == :macos, do: "darwin", else: "linux"),
        architecture: if(platform == :macos, do: "arm64", else: "amd64"),
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

  defp request(url, method, path, body) do
    with {:ok, pinned_url, hostname} <- SSRFGuard.pin(url <> "/api/v4" <> path) do
      case Req.request(
             method: method,
             url: pinned_url,
             headers: request_headers(url, path, body),
             raw: true,
             into: &bounded_body/2,
             connect_options: SSRFGuard.connect_options(hostname),
             json: body,
             redirect: false,
             retry: false,
             receive_timeout: to_timeout(minute: 1)
           ) do
        {:ok, %{headers: %{"job-status" => [state]}}} when state in ["canceled", "canceling"] ->
          {:error, :cancelled}

        {:ok, %{status: 204}} ->
          {:ok, nil}

        {:ok, %{status: status}} when method == :put and status in 200..299 ->
          {:ok, nil}

        {:ok, %{status: status, body: response}} when status in 200..299 ->
          decode_response(response)

        {:ok, %{status: status}} when status in [401, 403] ->
          {:error, :unauthorized}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: 429}} ->
          {:error, :rate_limited}

        {:ok, %{status: status}} ->
          {:error, {:http_status, status}}

        {:error, _} ->
          {:error, :transport}
      end
    end
  end

  defp request_headers(url, path, body) do
    headers = [{"host", URI.parse(url).authority}, {"accept-encoding", "identity"}]
    token_header = if path == "/jobs/request", do: "runner-token", else: "job-token"
    [{token_header, body.token} | headers]
  end

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
