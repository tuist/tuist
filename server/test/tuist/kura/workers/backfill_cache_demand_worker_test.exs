defmodule Tuist.Kura.Workers.BackfillCacheDemandWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.Cache.CASEvent
  alias Tuist.Gradle.CacheEvent
  alias Tuist.IngestRepo
  alias Tuist.Kura.Demand
  alias Tuist.Kura.UsageEvent
  alias Tuist.Kura.Workers.BackfillCacheDemandWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  defp account_with_project do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    {account, project}
  end

  defp days_ago(days) do
    DateTime.utc_now()
    |> DateTime.add(-days * 86_400, :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_naive()
  end

  defp insert_kura_usage(account_id, window_start) do
    IngestRepo.insert_all(UsageEvent, [
      %{
        event_id: "evt-#{System.unique_integer([:positive])}",
        account_id: account_id,
        project_id: 0,
        node_id: "kura-test",
        region: "us-east",
        traffic_plane: "public",
        direction: "egress",
        operation: "download",
        protocol: "http",
        artifact_kind: "xcframework",
        bytes: 1,
        request_count: 1,
        window_start: window_start,
        window_seconds: 3_600,
        inserted_at: window_start
      }
    ])
  end

  defp insert_cas_event(project_id, inserted_at) do
    IngestRepo.insert_all(CASEvent, [
      %{
        id: UUIDv7.generate(),
        action: "download",
        size: 1,
        cas_id: "cas-#{System.unique_integer([:positive])}",
        project_id: project_id,
        cache_endpoint: "https://cache.tuist.dev",
        inserted_at: inserted_at
      }
    ])
  end

  defp insert_gradle_event(project_id, account_handle, project_handle, inserted_at) do
    IngestRepo.insert_all(CacheEvent, [
      %{
        id: UUIDv7.generate(),
        action: "download",
        cache_key: "key-#{System.unique_integer([:positive])}",
        size: 1,
        duration_ms: 1,
        is_hit: true,
        is_ci: false,
        gradle_build_id: nil,
        project_id: project_id,
        account_handle: account_handle,
        project_handle: project_handle,
        cache_endpoint: "https://cache.tuist.dev",
        inserted_at: inserted_at
      }
    ])
  end

  test "seeds demand from Kura usage rollups" do
    {account, _project} = account_with_project()
    insert_kura_usage(account.id, days_ago(10))

    assert :ok = BackfillCacheDemandWorker.perform(%Oban.Job{args: %{}})

    assert %{last_cache_demand_at: at} = Demand.get(account.id, "us-east")
    assert DateTime.diff(DateTime.utc_now(), at, :day) == 10
  end

  test "seeds demand from CAS events through the project's account" do
    {account, project} = account_with_project()
    insert_cas_event(project.id, days_ago(20))

    assert :ok = BackfillCacheDemandWorker.perform(%Oban.Job{args: %{}})

    assert Demand.get(account.id, "us-east")
  end

  test "seeds demand from Gradle cache events" do
    {account, project} = account_with_project()
    insert_gradle_event(project.id, account.name, project.name, days_ago(30))

    assert :ok = BackfillCacheDemandWorker.perform(%Oban.Job{args: %{}})

    assert Demand.get(account.id, "us-east")
  end

  test "keeps the latest demand across sources" do
    {account, project} = account_with_project()
    insert_cas_event(project.id, days_ago(40))
    insert_kura_usage(account.id, days_ago(5))

    assert :ok = BackfillCacheDemandWorker.perform(%Oban.Job{args: %{}})

    assert DateTime.diff(DateTime.utc_now(), Demand.get(account.id, "us-east").last_cache_demand_at, :day) == 5
  end

  test "ignores traffic older than the lookback window" do
    {account, project} = account_with_project()
    insert_cas_event(project.id, days_ago(120))

    assert :ok = BackfillCacheDemandWorker.perform(%Oban.Job{args: %{}})

    refute Demand.get(account.id, "us-east")
  end

  test "resolves each account's own service region" do
    {account, project} = account_with_project()
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
    {:ok, _account} = Accounts.update_account(account, %{region: :europe})

    insert_cas_event(project.id, days_ago(10))

    assert :ok = BackfillCacheDemandWorker.perform(%Oban.Job{args: %{}})

    assert Demand.get(account.id, "eu-central")
    refute Demand.get(account.id, "us-east")
  end

  test "skips accounts with no resolvable service region" do
    {account, project} = account_with_project()
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
    {:ok, _account} = Accounts.update_account(account, %{region: :all})

    insert_cas_event(project.id, days_ago(10))

    assert :ok = BackfillCacheDemandWorker.perform(%Oban.Job{args: %{}})

    refute Demand.get(account.id, "us-east")
    refute Demand.get(account.id, "eu-central")
  end
end
