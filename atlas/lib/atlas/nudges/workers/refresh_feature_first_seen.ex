defmodule Atlas.Nudges.Workers.RefreshFeatureFirstSeen do
  @moduledoc """
  Populates `Atlas.Nudges.Analytics.FeatureFirstSeen` by scanning
  `Atlas.FeatureUsage.Snapshot` for the earliest snapshot per
  `(account, feature)` that shows any activity in its 7-day window.

  Insert-only: once we have observed a first-use timestamp for a
  (account, feature) pair, we never rewrite it. That means a signal in
  the "first X event" family can fire off the transition
  (row-just-inserted) without caring whether the account later stops and
  restarts using the feature.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  alias Atlas.FeatureUsage.Snapshot
  alias Atlas.Nudges.Analytics.FeatureFirstSeen
  alias Atlas.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # For each (account, feature) with any activity ever seen and no
    # first-seen row yet, insert one at the earliest snapshot that had
    # a positive 7-day count. `on_conflict: :nothing` keeps repeat runs
    # idempotent and preserves the earliest observed timestamp.
    missing =
      from s in Snapshot,
        left_join: f in FeatureFirstSeen,
        on: f.account_id == s.account_id and f.feature == s.feature,
        where: s.events_last_7d > 0 and is_nil(f.id),
        group_by: [s.account_id, s.feature],
        select: %{
          account_id: s.account_id,
          feature: s.feature,
          first_use_at: min(s.computed_at)
        }

    Repo.all(missing)
    |> Enum.each(fn %{account_id: account_id, feature: feature, first_use_at: first_use_at} ->
      %FeatureFirstSeen{}
      |> FeatureFirstSeen.changeset(%{
        account_id: account_id,
        feature: feature,
        first_use_at: first_use_at,
        first_seen_computed_at: now
      })
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:account_id, :feature]
      )
    end)

    :ok
  end
end
