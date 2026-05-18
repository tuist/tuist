defmodule Tuist.Webhooks.Workers.DeliveryWorker do
  @moduledoc """
  Delivers a single webhook event to the destination configured on its
  `Tuist.Webhooks.WebhookEndpoint`.

  The endpoint is re-read on each attempt so URL and signing-secret edits
  (including rotations) take effect on the next retry, and a deleted
  endpoint is a permanent failure (`:discard`) instead of retrying forever.
  Retries follow the RFC schedule (1m, 5m, 30m, 2h, 8h, 24h) implemented in
  `backoff/1`; `max_attempts: 7` covers the initial send plus those six
  retries.

  Each HTTP call writes a row to the ClickHouse `webhook_delivery_attempts`
  table capturing the request body, response status, response headers,
  response body and duration — that's what powers the per-event detail
  page on the dashboard. The Oban job stays the unit of "deliver this
  event"; the row is the unit of "we tried, here's what happened".
  """
  use Oban.Worker, queue: :webhooks, max_attempts: 7

  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Webhooks
  alias Tuist.Webhooks.DeliveryAttempt
  alias Tuist.Webhooks.Signature

  require Logger

  @request_timeout_ms 10_000
  @user_agent "Tuist-Webhooks/1.0"

  # Seconds: 1m, 5m, 30m, 2h, 8h, 24h. Applied between attempt N and N+1, so
  # six values pair with max_attempts: 7 (initial + 6 retries).
  @backoff_seconds [60, 300, 1800, 7200, 28_800, 86_400]

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    Enum.at(@backoff_seconds, attempt - 1, List.last(@backoff_seconds))
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        attempt: attempt,
        args: %{
          "webhook_endpoint_id" => endpoint_id,
          "event_id" => event_id,
          "event_type" => event_type,
          "payload" => payload
        }
      }) do
    case Webhooks.get_endpoint(endpoint_id) do
      {:ok, endpoint} ->
        post(endpoint, event_id, event_type, payload, attempt)

      {:error, :not_found} ->
        Logger.warning("Webhook delivery skipped: endpoint #{endpoint_id} not found for event #{event_id}")
        {:discard, :endpoint_not_found}
    end
  end

  defp post(endpoint, event_id, event_type, payload, attempt) do
    body = JSON.encode!(payload)
    timestamp = System.system_time(:second)
    signature = Signature.sign(body, endpoint.signing_secret, timestamp)

    headers = [
      {"Content-Type", "application/json"},
      {"User-Agent", @user_agent},
      {"Tuist-Signature", signature},
      {"Tuist-Event-Id", event_id},
      {"Tuist-Event-Type", event_type}
    ]

    started_at = System.monotonic_time(:millisecond)

    {response, result} =
      case SSRFGuard.pin(endpoint.url) do
        {:ok, pinned_url, hostname} ->
          resp =
            Req.post(pinned_url,
              headers: headers,
              body: body,
              receive_timeout: @request_timeout_ms,
              retry: false,
              # SSRFGuard.pin/1 only validates the first hop. Following
              # a 3xx would bypass the guard if the upstream redirects
              # to a private / metadata address, so we treat redirects
              # as a failed delivery and let the receiver land on the
              # canonical URL themselves.
              redirect: false,
              connect_options: SSRFGuard.connect_options(hostname)
            )

          {resp, classify(resp)}

        {:error, reason} ->
          # Reject before the request leaves the process — an account
          # owner can't point a webhook at localhost, RFC1918, link-local
          # metadata IPs, etc. The attempt is still recorded so the
          # dashboard surfaces *why* the delivery never happened.
          {{:error, reason}, {:error, "blocked: #{reason}"}}
      end

    duration_ms = System.monotonic_time(:millisecond) - started_at

    record_attempt(endpoint, %{
      event_id: event_id,
      event_type: event_type,
      attempt: attempt,
      request_body: body,
      request_headers: headers_to_map(headers),
      response: response,
      result: result,
      duration_ms: duration_ms
    })

    result
  end

  defp classify({:ok, %Req.Response{status: status}}) when status in 200..299, do: :ok
  defp classify({:ok, %Req.Response{status: status}}), do: {:error, "HTTP #{status}"}
  defp classify({:error, reason}), do: {:error, reason}

  defp record_attempt(endpoint, fields) do
    %{response: response, result: result} = fields

    # ClickHouse `insert_all` skips changesets — we provide the raw row
    # map directly. Map-shaped headers are stored as JSON-encoded
    # strings; `response_status: 0` is the sentinel for "no HTTP
    # response received", which the dashboard already branches on.
    row = %{
      id: Ecto.UUID.generate(),
      webhook_endpoint_id: endpoint.id,
      event_id: fields.event_id,
      event_type: fields.event_type,
      attempt: fields.attempt,
      status: if(result == :ok, do: "delivered", else: "failed"),
      request_body: fields.request_body,
      request_headers: encode_headers(fields.request_headers),
      response_status: response_status(response),
      response_headers: encode_headers(response_headers_map(response)),
      response_body: response_body(response),
      error: error_message(result),
      duration_ms: fields.duration_ms,
      inserted_at: DateTime.utc_now()
    }

    DeliveryAttempt.Buffer.insert(row)
  rescue
    e ->
      # We never want bookkeeping to take down a delivery. Surface the
      # failure as a log entry; the underlying delivery result still
      # propagates to Oban via the return value.
      Logger.error("Failed to record webhook delivery attempt: #{inspect(e)}")
      :ok
  end

  defp response_status({:ok, %Req.Response{status: status}}), do: status
  defp response_status(_), do: 0

  defp response_headers_map({:ok, %Req.Response{headers: headers}}) when is_map(headers), do: headers

  defp response_headers_map({:ok, %Req.Response{headers: headers}}) when is_list(headers),
    do: Map.new(headers, fn {k, v} -> {k, v} end)

  defp response_headers_map(_), do: %{}

  defp response_body({:ok, %Req.Response{body: body}}) when is_binary(body), do: truncate(body)
  defp response_body({:ok, %Req.Response{body: body}}), do: body |> inspect() |> truncate()
  defp response_body(_), do: ""

  defp error_message({:error, reason}) when is_binary(reason), do: reason
  defp error_message({:error, reason}), do: inspect(reason)
  defp error_message(:ok), do: ""

  defp encode_headers(headers) when headers == %{}, do: ""
  defp encode_headers(headers) when is_map(headers), do: JSON.encode!(headers)
  defp encode_headers(_), do: ""

  # Cap response bodies so a chatty upstream can't bloat the row. The
  # dashboard surfaces a "response truncated" hint when this kicks in.
  @max_response_body_bytes 64 * 1024
  defp truncate(binary) when is_binary(binary) and byte_size(binary) > @max_response_body_bytes,
    do: binary_part(binary, 0, @max_response_body_bytes)

  defp truncate(binary), do: binary

  defp headers_to_map(headers) do
    Enum.reduce(headers, %{}, fn {key, value}, acc ->
      Map.update(acc, key, value, fn existing -> "#{existing}, #{value}" end)
    end)
  end
end
