defmodule Tuist.Runners.Workers.WebhookRedeliveryWorker do
  @moduledoc """
  Asks GitHub to redeliver `workflow_job` webhook deliveries that
  failed (status_code outside 2xx) within the lookback window.

  The webhook is the only path that inserts a row into CH
  `runner_jobs`. `OrphanedRunnersWorker` reconciles rows already in
  `status='running'` — neither it nor the normal dispatch path can
  recover a `workflow_job.queued` (or `.completed`) delivery GitHub
  failed to deliver to us in the first place.

  Algorithm (mirrors GitHub's documented pattern at
  https://docs.github.com/en/webhooks/using-webhooks/automatically-redelivering-failed-deliveries-for-a-github-app-webhook):

    1. `GET /app/hook/deliveries?status=failure` (App-wide, paginated)
       across the `@lookback_minutes` window.
    2. Filter to `event="workflow_job"`.
    3. Group attempts by `guid`. A GUID is constant across the
       original delivery and any redelivery attempts of the same
       logical event.
    4. For each GUID whose latest attempt is still a failure,
       `POST /app/hook/deliveries/{id}/attempts` on the most recent
       attempt. GitHub re-fires through our normal webhook URL.

  ## Why redeliver instead of inserting locally

  Redelivery goes through the same `handle_workflow_job` path as a
  fresh webhook. No separate code path to maintain, no risk of
  recovery-side enqueue diverging from webhook-side enqueue, no
  payload reconstruction.

  ## Cost shape

  App-wide endpoint, single call per page. Failed deliveries are
  rare in steady state, so the list call usually returns an empty
  body or a small page. Independent of repo count or installation
  count — a customer with 1000 repos costs the same as one with 10.

  ## Idempotency

  GUID dedup means a delivery already successfully redelivered (its
  GUID has a status="OK" attempt) is skipped on subsequent cycles.
  A redelivery still in flight when the next cycle runs may be
  re-requested — harmless because the webhook handler is idempotent
  on `workflow_job_id` (RMT collapse on the CH side, advisory-lock
  + ON CONFLICT on the PG side).

  Emits `tuist_runners_recovery_count{kind="redelivered"}` per
  successful redelivery request.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners.Telemetry

  require Logger

  @lookback_minutes 15

  @impl Oban.Worker
  def perform(_job) do
    threshold = DateTime.add(DateTime.utc_now(), -@lookback_minutes * 60, :second)

    requested =
      threshold
      |> list_failed_deliveries_since()
      |> Enum.filter(&workflow_job?/1)
      |> Enum.group_by(& &1.guid)
      |> Enum.count(fn {guid, attempts} -> redeliver_if_unrecovered(guid, attempts) end)

    if requested > 0 do
      Logger.warning("runners: requested webhook redeliveries", count: requested)
    end

    :ok
  end

  defp list_failed_deliveries_since(threshold) do
    fetch_pages(threshold, [status: "failure"], [])
  end

  defp fetch_pages(threshold, opts, acc) do
    case GitHubClient.list_app_hook_deliveries(opts) do
      {:ok, %{meta: %{next_url: next_url}, deliveries: deliveries}} ->
        # Pages are ordered newest-first. Stop as soon as a page's
        # last entry is older than `threshold` — every subsequent
        # page is older still.
        in_window = Enum.filter(deliveries, &within_window?(&1, threshold))
        acc = acc ++ in_window

        if next_url == nil or has_pre_threshold?(deliveries, threshold) do
          acc
        else
          fetch_pages(threshold, [next_url: next_url], acc)
        end

      {:error, reason} ->
        Logger.warning("runners: webhook redelivery list failed; will retry next tick",
          reason: inspect(reason)
        )

        acc
    end
  end

  defp within_window?(%{delivered_at: %DateTime{} = at}, threshold), do: DateTime.compare(at, threshold) != :lt
  defp within_window?(_, _), do: false

  defp has_pre_threshold?(deliveries, threshold) do
    Enum.any?(deliveries, fn d ->
      case d do
        %{delivered_at: %DateTime{} = at} -> DateTime.before?(at, threshold)
        _ -> false
      end
    end)
  end

  defp workflow_job?(%{event: "workflow_job"}), do: true
  defp workflow_job?(_), do: false

  # GitHub's documented dedup: if ANY attempt for this GUID
  # succeeded (status="OK" / 2xx), we're done — that's our
  # redelivery from a previous cycle landing. Otherwise, the
  # most-recent failed attempt is the one to redeliver from.
  defp redeliver_if_unrecovered(_guid, attempts) do
    cond do
      Enum.any?(attempts, &succeeded?/1) ->
        false

      latest = pick_latest(attempts) ->
        case GitHubClient.redeliver_app_hook_delivery(latest.id) do
          :ok ->
            Logger.warning("runners: redelivered failed webhook",
              delivery_id: latest.id,
              action: latest.action,
              installation_id: latest.installation_id
            )

            :telemetry.execute(
              Telemetry.event_name_recovery(),
              %{count: 1},
              %{kind: "redelivered"}
            )

            true

          {:error, reason} ->
            Logger.warning("runners: redelivery request failed; will retry next tick",
              delivery_id: latest.id,
              reason: inspect(reason)
            )

            false
        end

      true ->
        false
    end
  end

  defp succeeded?(%{status_code: code}) when is_integer(code) and code in 200..299, do: true
  defp succeeded?(%{status: "OK"}), do: true
  defp succeeded?(_), do: false

  defp pick_latest([]), do: nil

  defp pick_latest(attempts) do
    Enum.max_by(attempts, fn
      %{delivered_at: %DateTime{} = at} -> DateTime.to_unix(at, :microsecond)
      _ -> 0
    end)
  end
end
