defmodule Tuist.Sandboxes.Anthropic.Client do
  @moduledoc """
  Thin client for the Anthropic Managed Agents self-hosted work queue
  (`/v1/environments/{id}/work/*`). Authenticates with the environment
  key of the `self_hosted` environment being served.
  """

  alias Tuist.Environment

  require Logger

  @anthropic_version "2023-06-01"
  @anthropic_beta "managed-agents-2026-04-01"
  @default_block_ms 999
  @max_block_ms 999
  @request_timeout_slack_ms 10_000

  @doc """
  Long-polls the queue for at most `block_ms` (1..999). Returns the work
  item, `{:ok, :none}` when nothing is queued, or an error.
  """
  def poll(environment_id, environment_key, worker_id, block_ms \\ @default_block_ms) do
    block_ms = block_ms |> max(1) |> min(@max_block_ms)

    environment_key
    |> request(worker_id)
    |> Req.get(
      url: work_path(environment_id, "poll"),
      params: [block_ms: block_ms],
      receive_timeout: block_ms + @request_timeout_slack_ms
    )
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"id" => _} = item}} -> {:ok, item}
      {:ok, %Req.Response{status: status}} when status in [200, 204] -> {:ok, :none}
      {:ok, %Req.Response{} = response} -> error(response, environment_id)
      {:error, reason} -> {:error, reason}
    end
  end

  def ack(environment_id, environment_key, work_id) do
    environment_key
    |> request()
    |> Req.post(url: work_path(environment_id, "#{encode(work_id)}/ack"), json: %{})
    |> handle_response(environment_id)
  end

  def stop(environment_id, environment_key, work_id, force \\ true) do
    environment_key
    |> request()
    |> Req.post(url: work_path(environment_id, "#{encode(work_id)}/stop"), json: %{force: force})
    |> handle_response(environment_id)
  end

  def stats(environment_id, environment_key) do
    environment_key
    |> request()
    |> Req.get(url: work_path(environment_id, "stats"))
    |> handle_response(environment_id)
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}, _environment_id) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{} = response}, environment_id), do: error(response, environment_id)
  defp handle_response({:error, reason}, _environment_id), do: {:error, reason}

  defp error(%Req.Response{status: 429} = response, environment_id) do
    Logger.warning("sandboxes: anthropic work queue rate limited",
      environment_id: environment_id,
      retry_after: retry_after(response)
    )

    {:error, :rate_limited}
  end

  defp error(%Req.Response{status: status}, _environment_id) when status in [401, 403], do: {:error, :unauthorized}
  defp error(%Req.Response{status: 404}, _environment_id), do: {:error, :not_found}

  defp error(%Req.Response{status: status, body: body}, _environment_id) do
    {:error, {:http, status, error_detail(body)}}
  end

  defp error_detail(%{"error" => %{"message" => message}}) when is_binary(message), do: message
  defp error_detail(body) when is_binary(body), do: String.slice(body, 0, 500)
  defp error_detail(body), do: inspect(body)

  defp retry_after(%Req.Response{} = response) do
    case Req.Response.get_header(response, "retry-after") do
      [value | _] -> value
      [] -> nil
    end
  end

  defp request(environment_key, worker_id \\ nil) do
    headers =
      [
        {"authorization", "Bearer " <> environment_key},
        {"anthropic-version", @anthropic_version},
        {"anthropic-beta", @anthropic_beta}
      ] ++ if(is_binary(worker_id), do: [{"anthropic-worker-id", worker_id}], else: [])

    Req.new(base_url: Environment.anthropic_api_url(), headers: headers, retry: false)
  end

  defp work_path(environment_id, suffix), do: "/v1/environments/#{encode(environment_id)}/work/#{suffix}"

  defp encode(segment), do: URI.encode(to_string(segment), &URI.char_unreserved?/1)
end
