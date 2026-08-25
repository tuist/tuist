defmodule Tuist.Kura.Workers.BackfillCacheTransfersWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.IngestRepo
  alias Tuist.Kura.Demand
  alias Tuist.Kura.UsageEvent
  alias Tuist.Kura.Workers.BackfillCacheTransfersWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  setup do
    stub(Environment, :env, fn -> :prod end)
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :kura_available_region_ids, fn -> ["us-east"] end)
    :ok
  end

  defp tracked_account(opts \\ []) do
    account = Accounts.get_account_from_user(AccountsFixtures.user_fixture())
    {:ok, _} = Demand.upsert(account.id, Keyword.get(opts, :region, "us-east"), ago(30))

    account.id
    |> Demand.get(Keyword.get(opts, :region, "us-east"))
    |> Ecto.Changeset.change(%{transfer_tracking_started_at: nil})
    |> Repo.update!()

    account
  end

  defp ago(days), do: DateTime.utc_now() |> DateTime.add(-days * 86_400, :second) |> DateTime.truncate(:second)

  defp insert_usage(account_id, opts \\ []) do
    window_start =
      opts
      |> Keyword.get(:at, ago(10))
      |> DateTime.to_naive()
      |> NaiveDateTime.truncate(:second)

    IngestRepo.insert_all(UsageEvent, [
      %{
        event_id: "evt-#{System.unique_integer([:positive])}",
        account_id: account_id,
        project_id: 0,
        node_id: "kura-test",
        region: Keyword.get(opts, :region, "us-east"),
        traffic_plane: "public",
        direction: Keyword.get(opts, :direction, "egress"),
        operation: "download",
        protocol: "http",
        artifact_kind: "xcframework",
        bytes: Keyword.get(opts, :bytes, 4_096),
        request_count: 1,
        window_start: window_start,
        window_seconds: 3_600,
        inserted_at: window_start
      }
    ])
  end

  defp days_since(nil), do: nil
  defp days_since(%DateTime{} = at), do: DateTime.diff(DateTime.utc_now(), at, :day)

  test "seeds the transfer clock from the usage history" do
    account = tracked_account()
    insert_usage(account.id, at: ago(10))

    assert :ok = BackfillCacheTransfersWorker.perform(%Oban.Job{args: %{}})

    assert days_since(Demand.get(account.id, "us-east").last_transfer_at) == 10
  end

  test "seeds from uploads as well as downloads" do
    account = tracked_account()
    insert_usage(account.id, direction: "ingress")

    assert :ok = BackfillCacheTransfersWorker.perform(%Oban.Job{args: %{}})

    assert Demand.get(account.id, "us-east").last_transfer_at
  end

  test "does not seed from rollups that moved no bytes" do
    account = tracked_account()
    insert_usage(account.id, bytes: 0)

    assert :ok = BackfillCacheTransfersWorker.perform(%Oban.Job{args: %{}})

    refute Demand.get(account.id, "us-east").last_transfer_at
  end

  test "keeps the most recent transfer per account-region" do
    account = tracked_account()
    insert_usage(account.id, at: ago(80))
    insert_usage(account.id, at: ago(4))

    assert :ok = BackfillCacheTransfersWorker.perform(%Oban.Job{args: %{}})

    assert days_since(Demand.get(account.id, "us-east").last_transfer_at) == 4
  end

  test "ignores traffic older than the lookback window" do
    account = tracked_account()
    insert_usage(account.id, at: ago(400))

    assert :ok = BackfillCacheTransfersWorker.perform(%Oban.Job{args: %{"lookback_days" => 90}})

    refute Demand.get(account.id, "us-east").last_transfer_at
  end

  test "starts the clock even where there is no transfer to seed, so the coldest instances are reachable" do
    # Exactly the population the sweep exists to reclaim: an account-region
    # whose instance has never moved a byte. Left untracked it could never be
    # archived at all.
    account = tracked_account()

    assert :ok = BackfillCacheTransfersWorker.perform(%Oban.Job{args: %{}})

    lifecycle = Demand.get(account.id, "us-east")
    assert days_since(lifecycle.transfer_tracking_started_at) == 0
    refute lifecycle.last_transfer_at
  end

  test "leaves an already-started clock alone, so seeding cannot restart the grace period" do
    account = tracked_account()

    account.id
    |> Demand.get("us-east")
    |> Ecto.Changeset.change(%{transfer_tracking_started_at: ago(30)})
    |> Repo.update!()

    assert :ok = BackfillCacheTransfersWorker.perform(%Oban.Job{args: %{}})

    assert days_since(Demand.get(account.id, "us-east").transfer_tracking_started_at) == 30
  end

  test "leaves regions outside the lifecycle alone" do
    account = tracked_account(region: "eu-central")
    insert_usage(account.id, region: "eu-central")

    assert :ok = BackfillCacheTransfersWorker.perform(%Oban.Job{args: %{}})

    lifecycle = Demand.get(account.id, "eu-central")
    refute lifecycle.last_transfer_at
    refute lifecycle.transfer_tracking_started_at
  end
end
