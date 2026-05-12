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
  """
  use Oban.Worker, queue: :default, max_attempts: 7

  alias Tuist.Webhooks
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
        args: %{
          "webhook_endpoint_id" => endpoint_id,
          "event_id" => event_id,
          "event_type" => event_type,
          "payload" => payload
        }
      }) do
    case Webhooks.get_endpoint(endpoint_id) do
      {:ok, endpoint} ->
        post(endpoint, event_id, event_type, payload)

      {:error, :not_found} ->
        Logger.warning("Webhook delivery skipped: endpoint #{endpoint_id} not found for event #{event_id}")
        {:discard, :endpoint_not_found}
    end
  end

  defp post(endpoint, event_id, event_type, payload) do
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

    case Req.post(endpoint.url, headers: headers, body: body, receive_timeout: @request_timeout_ms, retry: false) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
