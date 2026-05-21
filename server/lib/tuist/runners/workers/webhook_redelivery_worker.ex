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

    1. For each App in `Tuist.VCS.list_github_apps/0` (the global
       github.com App plus any per-installation GHES manifest-flow
       Apps), `GET /app/hook/deliveries` paginated across the
       `@lookback_minutes` window.
    2. Filter to `event="workflow_job"`.
    3. Group attempts by `guid`. A GUID is constant across the
       original delivery and any redelivery attempts of the same
       logical event.
    4. For each GUID whose attempts include no successful one,
       `POST /app/hook/deliveries/{id}/attempts` on the most recent
       attempt. GitHub re-fires through that App's webhook URL.

  ## Why list all deliveries instead of `?status=failure`

  GitHub does support a server-side `status=failure` filter, but
  using it breaks GUID-based dedup: a successful redelivery from a
  previous cycle has `status="OK"` and gets filtered out, so the
  dedup check `Enum.any?(attempts, &succeeded?/1)` never sees it
  and we'd re-redeliver the same GUID until it aged out. GitHub's
  documented pattern fetches all and groups locally for exactly
  this reason.

  ## Why redeliver instead of inserting locally

  Redelivery goes through the same `handle_workflow_job` path as a
  fresh webhook. No separate code path to maintain, no risk of
  recovery-side enqueue diverging from webhook-side enqueue, no
  payload reconstruction.

  ## Cost shape

  App-wide endpoint per App, single call per page. Independent of
  repo or installation count under an App — a customer with 1000
  repos costs the same as one with 10. Multiple Apps (github.com +
  GHES manifest-flow Apps) multiply linearly, but the App count is
  small.

  Emits `tuist_runners_recovery_count{kind="redelivered"}` per
  successful redelivery request.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners.Telemetry
  alias Tuist.VCS

  require Logger

  @lookback_minutes 15

  @impl Oban.Worker
  def perform(_job) do
    threshold = DateTime.add(DateTime.utc_now(), -@lookback_minutes * 60, :second)

    requested =
      Enum.reduce(VCS.list_github_apps(), 0, fn app, acc -> acc + redeliver_for_app(app, threshold) end)

    if requested > 0 do
      Logger.warning("runners: requested webhook redeliveries", count: requested)
    end

    :ok
  end

  defp redeliver_for_app(%{credentials: creds, api_url: api_url}, threshold) do
    threshold
    |> list_deliveries_since(creds, api_url)
    |> Enum.filter(&workflow_job?/1)
    |> Enum.group_by(& &1.guid)
    |> Enum.count(fn {guid, attempts} ->
      redeliver_if_unrecovered(guid, attempts, creds, api_url)
    end)
  end

  defp list_deliveries_since(threshold, creds, api_url) do
    fetch_pages(threshold, [credentials: creds, api_url: api_url], [])
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
          fetch_pages(threshold, Keyword.put(opts, :next_url, next_url), acc)
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
  defp redeliver_if_unrecovered(_guid, attempts, creds, api_url) do
    cond do
      Enum.any?(attempts, &succeeded?/1) ->
        false

      latest = pick_latest(attempts) ->
        case GitHubClient.redeliver_app_hook_delivery(latest.id, credentials: creds, api_url: api_url) do
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
