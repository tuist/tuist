defmodule Atlas.Nudges.Signals.HeavyUsageEnterpriseFitTest do
  use Atlas.DataCase, async: true

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Nudges.Analytics.AirStatus
  alias Atlas.Nudges.Proposal
  alias Atlas.Nudges.SignalEpisode
  alias Atlas.Nudges.Signals.HeavyUsageEnterpriseFit
  alias Atlas.Repo

  describe "evaluate/1" do
    test "fires when distinct thresholds delivered >= 3 and plan is not enterprise" do
      account = insert_account!(%{plan_tier: "pro"})
      insert_air_status!(account, distinct_thresholds_delivered: 4)

      assert {:ok, %Proposal{} = proposal} = HeavyUsageEnterpriseFit.evaluate(account)
      assert proposal.title =~ "enterprise conversation"
      assert proposal.evidence["distinct_thresholds_delivered"] == 4
      assert has_open_episode?(account, "heavy_usage_enterprise_fit")
    end

    test "skips when under the threshold, and closes any open episode" do
      account = insert_account!(%{plan_tier: "pro"})
      insert_air_status!(account, distinct_thresholds_delivered: 1)

      assert :skip = HeavyUsageEnterpriseFit.evaluate(account)
      refute has_open_episode?(account, "heavy_usage_enterprise_fit")
    end

    test "skips when the status refresh failed" do
      account = insert_account!(%{plan_tier: "pro"})
      insert_air_status!(account, distinct_thresholds_delivered: 4, refresh_status: "failed")

      assert :skip = HeavyUsageEnterpriseFit.evaluate(account)
    end

    test "skips when the status was computed too long ago" do
      account = insert_account!(%{plan_tier: "pro"})

      insert_air_status!(account,
        distinct_thresholds_delivered: 4,
        computed_at: DateTime.utc_now() |> DateTime.add(-96, :hour) |> DateTime.truncate(:second)
      )

      assert :skip = HeavyUsageEnterpriseFit.evaluate(account)
    end
  end

  defp insert_air_status!(account, opts) do
    defaults = %{
      account_id: account.id,
      period_start: Date.utc_today() |> Date.beginning_of_month(),
      metric: "runner_minutes",
      distinct_thresholds_delivered: 0,
      refresh_status: "ok",
      computed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    %AirStatus{}
    |> AirStatus.changeset(Map.merge(defaults, Map.new(opts)))
    |> Repo.insert!()
  end

  defp has_open_episode?(account, signal) do
    Repo.exists?(
      from e in SignalEpisode,
        where: e.account_id == ^account.id and e.signal == ^signal and e.state == "open"
    )
  end

  defp insert_account!(attrs \\ %{}) do
    defaults = %{
      account_key: "air-signal:#{System.unique_integer([:positive])}",
      name: "Air Signal Customer",
      segment: :customer,
      plan_tier: "pro"
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
