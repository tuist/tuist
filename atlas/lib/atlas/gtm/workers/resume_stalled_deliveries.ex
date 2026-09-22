defmodule Atlas.GTM.Workers.ResumeStalledDeliveries do
  @moduledoc """
  Re-queues email delivery work that stopped part way through.

  `DeliverBroadcast` and `DeliverAutomatedEmail` retry through Oban, but once a
  job exhausts its attempts Oban discards it and nothing picks the work back up.
  A provider outage lasting longer than the backoff window therefore leaves a
  broadcast sitting in `sending` with undelivered recipients forever. This
  worker runs on a schedule and enqueues those jobs again.

  Resuming is safe because delivery is idempotent per recipient: recipients are
  snapshotted when the broadcast is queued, `Broadcasts.list_pending_deliveries/1`
  only returns recipients that are not yet delivered, and every email carries a
  per-delivery provider idempotency key.

  Recipients that have failed `Broadcasts.max_delivery_attempts/0` times are left
  alone so a permanently undeliverable address is not retried forever.
  """

  use Oban.Worker, queue: :mailing, max_attempts: 3

  alias Atlas.GTM.Broadcasts
  alias Atlas.GTM.Workers.DeliverAutomatedEmail
  alias Atlas.GTM.Workers.DeliverBroadcast

  require Logger

  # Long enough that a run which is merely slow is never treated as stalled.
  @stale_after_minutes 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    stale_before = stale_before(args)

    broadcasts = resume_broadcasts(stale_before)
    deliveries = resume_automated_deliveries(stale_before)

    if broadcasts > 0 or deliveries > 0 do
      Logger.info("Resumed #{broadcasts} stalled broadcast(s) and #{deliveries} automated delivery(ies)")
    end

    {:ok, %{broadcasts: broadcasts, deliveries: deliveries}}
  end

  defp resume_broadcasts(stale_before) do
    stale_before
    |> Broadcasts.list_resumable_broadcasts()
    |> Enum.count(fn broadcast ->
      %{"broadcast_id" => broadcast.id}
      |> DeliverBroadcast.new()
      |> insert_job()
    end)
  end

  defp resume_automated_deliveries(stale_before) do
    stale_before
    |> Broadcasts.list_resumable_automated_deliveries()
    |> Enum.count(fn delivery ->
      %{"delivery_id" => delivery.id}
      |> DeliverAutomatedEmail.new()
      |> insert_job()
    end)
  end

  # Both workers are unique on their args, so a job that is still queued or
  # running is returned as a conflict rather than duplicated. Only genuinely
  # new jobs are counted as resumed.
  defp insert_job(changeset) do
    case Oban.insert(changeset) do
      {:ok, %Oban.Job{conflict?: true}} -> false
      {:ok, %Oban.Job{}} -> true
      {:error, reason} -> log_failure(reason)
    end
  end

  defp log_failure(reason) do
    Logger.error("Could not resume stalled delivery: #{inspect(reason)}")
    false
  end

  defp stale_before(args) do
    minutes = Map.get(args, "stale_after_minutes", @stale_after_minutes)
    DateTime.utc_now() |> DateTime.add(-minutes * 60, :second) |> DateTime.truncate(:second)
  end
end
