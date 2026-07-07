defmodule Tuist.Runners.Workers.DispatchWorker do
  @moduledoc """
  Runs the `workflow_job` webhook pipeline asynchronously off the
  HTTP request path.

  ## Why

  The synchronous controller hits PG (account lookup), the K8s
  apiserver (RunnerPool LIST) and ClickHouse (job INSERT) before
  it can respond to GitHub. Any one of those stalling burns a
  Phoenix worker for the full 10 s GitHub timeout — and during the
  2026-05-19 incident every webhook hung that long, so the HTTP
  body-read pool saturated and ingress started returning 502/504
  to GitHub. Moving the work behind Oban lets the controller
  respond 200 the moment the signature is verified, and the
  `:webhooks` queue (concurrency 20, retry-with-backoff) absorbs
  the spike instead of the request path.

  ## Retries

  Real failures (`{:error, _}`) propagate back to Oban so it
  retries with exponential backoff. Deliberate ignores
  (`{:ignored, _}` for no-account / no-matching-pool /
  runners-disabled / etc.) are terminal — Oban marks the job
  successful so we don't redeliver a webhook GitHub will never
  send again.

  ## Idempotency

  GitHub may redeliver the same webhook on its own retry budget.
  The `unique` directive collapses repeated inserts that arrive
  within five minutes by their `X-GitHub-Delivery` GUID, so a
  duplicate is a no-op INSERT (and a `pick_queued` race in
  ClickHouse merges duplicate rows on `workflow_job_id` anyway).
  """

  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 6,
    unique: [period: 300, keys: [:delivery_guid]]

  alias Tuist.Runners.Dispatch

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    payload = Map.fetch!(args, "payload")
    installation_id = Map.fetch!(args, "installation_id")

    case Dispatch.handle_webhook(payload, installation_id) do
      {:ok, _kind} -> :ok
      {:ignored, _reason} -> :ok
      :ignored -> :ok
    end
  end
end
