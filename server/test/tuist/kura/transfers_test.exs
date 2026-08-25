defmodule Tuist.Kura.TransfersTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Transfers
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @region "us-east"

  defp account do
    Accounts.get_account_from_user(AccountsFixtures.user_fixture())
  end

  defp tracked_account(opts \\ []) do
    account = account()
    {:ok, _} = Demand.upsert(account.id, Keyword.get(opts, :region, @region), ago(30))
    account
  end

  defp ago(days), do: DateTime.utc_now() |> DateTime.add(-days * 86_400, :second) |> DateTime.truncate(:second)

  defp rollup(account, opts \\ []) do
    %{
      account_id: account.id,
      region: Keyword.get(opts, :region, @region),
      bytes: Keyword.get(opts, :bytes, 4_096),
      window_start:
        opts
        |> Keyword.get(:at, ago(0))
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)
    }
  end

  defp days_since(nil), do: nil
  defp days_since(%DateTime{} = at), do: DateTime.diff(DateTime.utc_now(), at, :day)

  describe "record/1" do
    test "advances the transfer clock for the account-regions in a batch" do
      account = tracked_account()

      assert 1 = Transfers.record([rollup(account)])

      assert days_since(Demand.get(account.id, @region).last_transfer_at) == 0
    end

    test "counts ingress as well as egress, so a cold instance's first uploads keep it" do
      account = tracked_account()

      assert 1 = Transfers.record([account |> rollup() |> Map.put(:direction, "ingress")])

      assert Demand.get(account.id, @region).last_transfer_at
    end

    test "ignores rollups that moved no bytes, which is the population being separated out" do
      account = tracked_account()

      assert 0 = Transfers.record([rollup(account, bytes: 0)])

      refute Demand.get(account.id, @region).last_transfer_at
    end

    test "ignores traffic that could not be attributed to an account" do
      account = tracked_account()

      assert 0 = Transfers.record([account |> rollup() |> Map.put(:account_id, 0)])

      refute Demand.get(account.id, @region).last_transfer_at
    end

    test "never moves the clock backwards" do
      account = tracked_account()
      Transfers.record([rollup(account)])

      Transfers.record([rollup(account, at: ago(10))])

      assert days_since(Demand.get(account.id, @region).last_transfer_at) == 0
    end

    test "keeps each region's own clock" do
      account = tracked_account()
      {:ok, _} = Demand.upsert(account.id, "eu-central", ago(30))

      Transfers.record([rollup(account, region: "eu-central")])

      refute Demand.get(account.id, @region).last_transfer_at
      assert Demand.get(account.id, "eu-central").last_transfer_at
    end

    test "does not create a lifecycle row, because a transfer presupposes one" do
      account = account()

      assert 0 = Transfers.record([rollup(account)])

      refute Demand.get(account.id, @region)
    end

    test "starts a clock that has none, and leaves an existing one alone" do
      account = tracked_account()
      started_at = Demand.get(account.id, @region).transfer_tracking_started_at

      Transfers.record([rollup(account)])

      assert Demand.get(account.id, @region).transfer_tracking_started_at == started_at
    end
  end

  describe "seed/2" do
    test "seeds an observed transfer and starts the clock" do
      account = tracked_account()

      assert 1 =
               Transfers.seed(
                 [%{account_id: account.id, service_region: @region, last_transfer_at: ago(40)}],
                 ago(0)
               )

      lifecycle = Demand.get(account.id, @region)
      assert days_since(lifecycle.last_transfer_at) == 40
      assert days_since(lifecycle.transfer_tracking_started_at) == 0
    end

    test "keeps the later of the seeded and the observed timestamp" do
      account = tracked_account()
      Transfers.record([rollup(account)])

      Transfers.seed([%{account_id: account.id, service_region: @region, last_transfer_at: ago(40)}], ago(0))

      assert days_since(Demand.get(account.id, @region).last_transfer_at) == 0
    end
  end

  describe "start_tracking/2" do
    test "starts the clock on account-regions with no observed transfer" do
      account = tracked_account()

      account.id
      |> Demand.get(@region)
      |> Ecto.Changeset.change(%{transfer_tracking_started_at: nil})
      |> Repo.update!()

      assert 1 = Transfers.start_tracking([@region], ago(0))

      lifecycle = Demand.get(account.id, @region)
      assert days_since(lifecycle.transfer_tracking_started_at) == 0
      refute lifecycle.last_transfer_at
    end

    test "leaves a clock that has already started alone, so the grace period is not restarted" do
      account = tracked_account()
      started_at = Demand.get(account.id, @region).transfer_tracking_started_at

      assert 0 = Transfers.start_tracking([@region], ago(0))

      assert Demand.get(account.id, @region).transfer_tracking_started_at == started_at
    end
  end
end
