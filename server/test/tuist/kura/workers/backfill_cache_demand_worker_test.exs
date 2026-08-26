defmodule Tuist.Kura.Workers.BackfillCacheDemandWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Cache.CASEvent
  alias Tuist.Environment
  alias Tuist.Gradle.CacheEvent
  alias Tuist.IngestRepo
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Server
  alias Tuist.Kura.UsageEvent
  alias Tuist.Kura.Workers.BackfillCacheDemandWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :set_mimic_from_context

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

  describe "live instances with no event in the lookback window" do
    setup do
      stub(Environment, :env, fn -> :prod end)
      stub(Environment, :dev?, fn -> false end)
      stub(Environment, :test?, fn -> false end)
      stub(Environment, :kura_available_region_ids, fn -> ["us-east"] end)
      :ok
    end

    defp instance(account, region, status \\ :active) do
      Repo.insert!(%Server{
        account_id: account.id,
        region: region,
        status: status,
        provisioner_node_ref: "kura-#{account.id}-#{region}"
      })
    end

    test "are seeded at the lookback boundary, so the coldest instances are still archivable" do
      # The whole point of the lifecycle is reclaiming instances like this one:
      # provisioned, and silent for longer than any analytics source covers.
      {account, _project} = account_with_project()
      instance(account, "us-east")

      assert :ok = BackfillCacheDemandWorker.perform(%Oban.Job{args: %{}})

      assert %{last_cache_demand_at: at} = Demand.get(account.id, "us-east")
      assert DateTime.diff(DateTime.utc_now(), at, :day) == 90
    end

    test "keep observed demand when it is more recent than the floor" do
      {account, project} = account_with_project()
      instance(account, "us-east")
      insert_cas_event(project.id, days_ago(10))

      assert :ok = BackfillCacheDemandWorker.perform(%Oban.Job{args: %{}})

      assert DateTime.diff(DateTime.utc_now(), Demand.get(account.id, "us-east").last_cache_demand_at, :day) == 10
    end

    test "are not seeded for archived or destroyed instances, which hold nothing" do
      {archived, _} = account_with_project()
      instance(archived, "us-east", :archived)

      {destroyed, _} = account_with_project()
      instance(destroyed, "us-east", :destroyed)

      assert :ok = BackfillCacheDemandWorker.perform(%Oban.Job{args: %{}})

      refute Demand.get(archived.id, "us-east")
      refute Demand.get(destroyed.id, "us-east")
    end

    test "are not seeded for private runner-cache regions, which the lifecycle does not own" do
      stub(Environment, :kura_available_region_ids, fn -> ["us-east", "scw-fr-par-runners"] end)

      {account, _project} = account_with_project()
      instance(account, "scw-fr-par-runners")

      assert :ok = BackfillCacheDemandWorker.perform(%Oban.Job{args: %{}})

      refute Demand.get(account.id, "scw-fr-par-runners")
    end
  end

  test "seeds a paid account allowing every region against the default" do
    {account, project} = account_with_project()
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
    {:ok, _account} = Accounts.update_account(account, %{region: :all})

    insert_cas_event(project.id, days_ago(10))

    assert :ok = BackfillCacheDemandWorker.perform(%Oban.Job{args: %{}})

    assert Demand.get(account.id, "us-east")
    refute Demand.get(account.id, "eu-central")
  end

  test "skips accounts with no resolvable service region" do
    {account, project} = account_with_project()
    BillingFixtures.subscription_fixture(account_id: account.id, plan: :open_source)

    insert_cas_event(project.id, days_ago(10))

    assert :ok = BackfillCacheDemandWorker.perform(%Oban.Job{args: %{}})

    refute Demand.get(account.id, "us-east")
    refute Demand.get(account.id, "eu-central")
  end
end
