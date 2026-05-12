defmodule Tuist.Webhooks.Workers.DeliveryWorker do
  @moduledoc """
  Delivers a single webhook event to its destination via HTTPS POST.

  Retries follow the RFC schedule (1m, 5m, 30m, 2h, 8h, 24h) implemented in
  `backoff/1`; `max_attempts: 7` covers the initial send plus those six
  retries.

  The job carries everything needed to deliver the event inline (URL,
  encrypted signing secret, payload, event id, event type). No DB lookup is
  required — endpoints are not registered as separate entities in this slice;
  they live inside an automation's `trigger_actions` JSON.
  """
  use Oban.Worker, queue: :default, max_attempts: 7

  alias Tuist.Webhooks
  alias Tuist.Webhooks.Signature

  require Logger

  @request_timeout_ms 10_000
  @user_agent "Tuist-Webhooks/1.0"

  # Seconds: 1m, 5m, 30m, 2h, 8h, 24h. Applied between attempt N and N+1, so
  # six values pair with @max_attempts: 7 (initial + 6 retries).
  @backoff_seconds [60, 300, 1800, 7200, 28_800, 86_400]

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    Enum.at(@backoff_seconds, attempt - 1, List.last(@backoff_seconds))
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "url" => url,
          "signing_secret_encrypted" => encrypted,
          "event_id" => event_id,
          "event_type" => event_type,
          "payload" => payload
        }
      }) do
    case Webhooks.decrypt_signing_secret(encrypted) do
      {:ok, secret} ->
        post(url, secret, event_id, event_type, payload)

      {:error, :invalid_signing_secret} ->
        Logger.warning("Webhook delivery skipped: signing secret failed to decrypt for event #{event_id}")

        {:discard, :invalid_signing_secret}
    end
  end

  defp post(url, secret, event_id, event_type, payload) do
    body = JSON.encode!(payload)
    timestamp = System.system_time(:second)
    signature = Signature.sign(body, secret, timestamp)

    headers = [
      {"Content-Type", "application/json"},
      {"User-Agent", @user_agent},
      {"Tuist-Signature", signature},
      {"Tuist-Event-Id", event_id},
      {"Tuist-Event-Type", event_type}
    ]

    case Req.post(url, headers: headers, body: body, receive_timeout: @request_timeout_ms, retry: false) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
