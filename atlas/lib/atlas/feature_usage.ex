defmodule Atlas.FeatureUsage do
  @moduledoc """
  Tracks which Tuist product features each account uses.

  For every account that has an `AccountHandle` we periodically try to resolve it
  to a Tuist account (any handle can be a Tuist org handle; account handles are
  not tagged with a dedicated "tuist" source in production) and measure
  per-feature usage over the last 24h / 7d / prior-7d windows through the Tuist
  read-only proxies (see `Atlas.FeatureUsage.Collector`), persist a `Snapshot`
  per feature, and raise a Slack notification on transitions:

    * active -> inactive ("stopped using a feature") and
    * inactive -> active ("started using a feature")

  Accounts whose handles do not resolve to a Tuist account are skipped (no
  snapshots written).
  """

  import Ecto.Query

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Audit
  alias Atlas.FeatureUsage.Catalog
  alias Atlas.FeatureUsage.Collector
  alias Atlas.FeatureUsage.Snapshot
  alias Atlas.FeatureUsage.UsageNotifier
  alias Atlas.Repo

  @doc "Ids of accounts that have at least one handle and are therefore candidates for tracking."
  def list_tracked_account_ids do
    AccountHandle
    |> distinct(true)
    |> select([h], h.account_id)
    |> Repo.all()
  end

  @doc "Candidate handle strings for an account (any source), oldest first."
  def account_handles(account_id) when is_binary(account_id) do
    AccountHandle
    |> where([h], h.account_id == ^account_id)
    |> order_by([h], asc: h.inserted_at)
    |> select([h], h.handle)
    |> Repo.all()
    |> Enum.uniq()
  end

  @doc """
  Most recent snapshot for each tracked usage signal of an account, newest
  `computed_at` per signal. Returns a list of `Snapshot` structs ordered by the
  catalog.
  """
  def latest_usage_for_account(account_id) when is_binary(account_id) do
    snapshots = latest_snapshots_map(account_id)

    Catalog.tracked()
    |> Enum.map(&Map.get(snapshots, &1.slug))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Map of the newest snapshot for every stored slug (features + build systems)
  for an account, keyed by slug. Used by the dashboard view.
  """
  def latest_snapshots_map(account_id) when is_binary(account_id) do
    Snapshot
    |> where([s], s.account_id == ^account_id)
    |> distinct([s], [s.feature])
    |> order_by([s], asc: s.feature, desc: s.computed_at)
    |> Repo.all()
    |> Map.new(&{&1.feature, &1})
  end

  @doc """
  Recent "stopped using a feature" transitions across accounts, newest first.

  A transition is a snapshot that is inactive now but whose immediately previous
  snapshot for the same (account, feature) was active.
  """
  def list_recent_stops(opts \\ []) do
    limit = opts |> Keyword.get(:limit, 50) |> min(200) |> max(1)
    since = Keyword.get(opts, :since)
    feature = Keyword.get(opts, :feature)

    Snapshot
    |> where([s], s.active == false and s.active_previous == true)
    |> maybe_since(since)
    |> maybe_feature(feature)
    |> order_by([s], desc: s.computed_at)
    |> limit(^limit)
    |> preload(:account)
    |> Repo.all()
  end

  defp maybe_since(query, %DateTime{} = since), do: where(query, [s], s.computed_at >= ^since)
  defp maybe_since(query, _since), do: query

  defp maybe_feature(query, feature) when is_binary(feature) and feature != "",
    do: where(query, [s], s.feature == ^feature)

  defp maybe_feature(query, _feature), do: query

  @doc """
  Recompute and persist the feature-usage snapshot for a single account and fire
  Slack notifications on both active -> inactive ("stopped") and inactive ->
  active ("started") transitions.

  Options:
    * `:now` — reference timestamp (defaults to `DateTime.utc_now/0`).
    * `:notify` — 3-arity fn `(account, snapshot, change) -> term` (defaults to
      `UsageNotifier.notify/3`); called once per transition with `change` being
      `:started` or `:stopped`.

  Returns `{:ok, %{account:, snapshots:, alerts:}}` or `{:error, reason}`
  (`:not_found` when the account or its Tuist handle is missing). Each entry in
  `alerts` is a `{change, snapshot}` tuple.
  """
  def refresh_account(account_id, opts \\ []) when is_binary(account_id) do
    now = opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:second)
    notify = Keyword.get(opts, :notify, &UsageNotifier.notify/3)

    with %Account{} = account <- Repo.get(Account, account_id),
         {:ok, resolution} <- resolve_account(account_id),
         {:ok, metrics} <- Collector.measure(resolution) do
      previous = latest_snapshots_map(account_id)

      {snapshots, alerts} =
        Enum.reduce(metrics, {[], []}, fn metric, {snapshots, alerts} ->
          {:ok, snapshot} = insert_snapshot(account, metric, now)
          previous_snapshot = Map.get(previous, metric.feature)

          alerts =
            case alertable_change(previous_snapshot, snapshot) do
              nil -> alerts
              change -> [{change, snapshot} | alerts]
            end

          {[snapshot | snapshots], alerts}
        end)

      alerts = Enum.reverse(alerts)
      Enum.each(alerts, fn {change, snapshot} -> alert(account, snapshot, change, notify) end)

      result = %{account: account, snapshots: Enum.reverse(snapshots), alerts: alerts}

      Audit.record(
        "account.feature_usage_refreshed",
        %{
          target_type: "account",
          target_id: account.id,
          target_label: account.name,
          metadata: %{
            "path" => "/commercial/sales/accounts/#{account.id}",
            "snapshot_count" => length(result.snapshots),
            "alert_count" => length(alerts),
            "computed_at" => now
          }
        },
        interface: "worker"
      )

      Accounts.enqueue_account_attention_suggestion_generation(account.id, "feature_usage_refreshed")

      {:ok, result}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # Try each of the account's handles against the Tuist proxy and use the first
  # that resolves to a Tuist account. Handles that don't match (a Slack channel,
  # a GitHub org, etc.) are skipped; a transport error propagates so the job retries.
  defp resolve_account(account_id) do
    account_id
    |> account_handles()
    |> Enum.reduce_while({:error, :not_found}, fn handle, acc ->
      case Collector.resolve(handle) do
        {:ok, resolution} -> {:halt, {:ok, resolution}}
        {:error, reason} when reason in [:not_found, :invalid_handle] -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # Only widget features raise notifications; build-system presence does not.
  # Returns `:stopped`, `:started`, or `nil`.
  defp alertable_change(previous, snapshot) do
    cond do
      snapshot.feature not in Catalog.slugs() -> nil
      stopped?(previous, snapshot) -> :stopped
      started?(previous, snapshot) -> :started
      true -> nil
    end
  end

  defp insert_snapshot(%Account{} = account, metric, now) do
    attrs = %{
      account_id: account.id,
      feature: metric.feature,
      events_last_24h: metric.events_last_24h,
      events_last_7d: metric.events_last_7d,
      events_prior_7d: metric.events_prior_7d,
      last_used_at: metric.last_used_at,
      active: metric.events_last_7d > 0,
      active_previous: metric.events_prior_7d > 0,
      computed_at: now
    }

    %Snapshot{}
    |> Snapshot.changeset(attrs)
    |> Repo.insert()
  end

  # A feature "stopped" when it is inactive now and was active in the previous
  # snapshot (day-over-day transition). On the first-ever snapshot we fall back to
  # the within-snapshot signal (used in the prior-7d window but not the last-7d).
  defp stopped?(_previous, %Snapshot{active: true}), do: false
  defp stopped?(%Snapshot{active: true}, %Snapshot{active: false}), do: true
  defp stopped?(nil, %Snapshot{active: false, active_previous: true}), do: true
  defp stopped?(_previous, _current), do: false

  # A feature "started" when it is active now and was inactive in the previous
  # snapshot. On the first-ever snapshot we fall back to the within-snapshot
  # signal (active this week, no activity the prior week) so that a truly fresh
  # adoption fires exactly once rather than being missed for lack of history.
  defp started?(_previous, %Snapshot{active: false}), do: false
  defp started?(%Snapshot{active: false}, %Snapshot{active: true}), do: true
  defp started?(nil, %Snapshot{active: true, active_previous: false}), do: true
  defp started?(_previous, _current), do: false

  defp alert(%Account{} = account, %Snapshot{} = snapshot, change, notify) do
    Audit.record(audit_action(change), %{
      target_type: "account",
      target_id: account.id,
      target_label: account.name,
      metadata: %{
        "path" => "/commercial/sales/accounts/#{account.id}",
        "feature" => snapshot.feature,
        "feature_label" => Catalog.label(snapshot.feature),
        "last_used_at" => snapshot.last_used_at && DateTime.to_iso8601(snapshot.last_used_at),
        "events_prior_7d" => snapshot.events_prior_7d,
        "events_last_7d" => snapshot.events_last_7d
      }
    })

    notify.(account, snapshot, change)
  end

  defp audit_action(:stopped), do: "account.feature_usage_dropped"
  defp audit_action(:started), do: "account.feature_usage_started"
end
