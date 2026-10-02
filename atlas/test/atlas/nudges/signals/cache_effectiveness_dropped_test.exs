defmodule Atlas.Nudges.Signals.CacheEffectivenessDroppedTest do
  use Atlas.DataCase, async: true

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Nudges.Analytics.MetricBucket
  alias Atlas.Nudges.Nudge
  alias Atlas.Nudges.Proposal
  alias Atlas.Nudges.SignalEpisode
  alias Atlas.Nudges.Signals.CacheEffectivenessDropped
  alias Atlas.Repo

  describe "evaluate/1" do
    test "fires when the 7-day ratio is under the floor and >= 15pp below the 28-day baseline" do
      account = insert_account!()
      # 28-day baseline high (80% for the older 21 days), 7-day dropped (40%).
      seed_daily_buckets(account, 21, offset: 8, hits: 80, lookups: 100)
      seed_daily_buckets(account, 7, offset: 1, hits: 40, lookups: 100)

      assert {:ok, %Proposal{} = proposal} = CacheEffectivenessDropped.evaluate(account)
      assert proposal.title =~ "cache hit rate"
      assert proposal.evidence["current_ratio"] < 0.5
      assert proposal.evidence["baseline_ratio"] > 0.6
      assert has_open_episode?(account, "cache_effectiveness_dropped")
    end

    test "skips when the recent 7-day ratio has recovered (closes any open episode)" do
      account = insert_account!()
      seed_daily_buckets(account, 28, offset: 1, hits: 80, lookups: 100)

      assert :skip = CacheEffectivenessDropped.evaluate(account)
      refute has_open_episode?(account, "cache_effectiveness_dropped")
    end

    test "does not double-fire while an episode is already open" do
      account = insert_account!()
      seed_daily_buckets(account, 21, offset: 8, hits: 80, lookups: 100)
      seed_daily_buckets(account, 7, offset: 1, hits: 40, lookups: 100)

      {:ok, _} = CacheEffectivenessDropped.evaluate(account)
      assert :skip = CacheEffectivenessDropped.evaluate(account)

      count = Repo.aggregate(Nudge, :count, :id)
      assert count == 0
    end

    test "skips when history is insufficient" do
      account = insert_account!()
      seed_daily_buckets(account, 3, offset: 1, hits: 40, lookups: 100)

      assert :skip = CacheEffectivenessDropped.evaluate(account)
    end
  end

  defp seed_daily_buckets(account, days, opts) do
    hits = Keyword.fetch!(opts, :hits)
    lookups = Keyword.fetch!(opts, :lookups)
    start_offset = Keyword.get(opts, :offset, 1)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    for offset <- start_offset..(start_offset + days - 1) do
      %MetricBucket{}
      |> MetricBucket.changeset(%{
        account_id: account.id,
        bucket_date: Date.utc_today() |> Date.add(-offset),
        daily_cache_hits: hits,
        daily_cache_lookups: lookups,
        refresh_status: "ok",
        computed_at: now
      })
      |> Repo.insert!(
        on_conflict: [
          set: [
            daily_cache_hits: hits,
            daily_cache_lookups: lookups,
            refresh_status: "ok",
            computed_at: now,
            updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
          ]
        ],
        conflict_target: [:account_id, :bucket_date]
      )
    end
  end

  defp has_open_episode?(account, signal) do
    Repo.exists?(
      from e in SignalEpisode,
        where: e.account_id == ^account.id and e.signal == ^signal and e.state == "open"
    )
  end

  defp insert_account!(attrs \\ %{}) do
    defaults = %{
      account_key: "cache-signal:#{System.unique_integer([:positive])}",
      name: "Cache Signal Customer",
      segment: :customer,
      plan_tier: "pro"
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
