defmodule Tuist.Kura.Workers.SeedLegacyCacheDemandWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Cache.CASEvent
  alias Tuist.Environment
  alias Tuist.Gradle.CacheEvent
  alias Tuist.IngestRepo
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura
  alias Tuist.Kura.AccountRegionLifecycle
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Lifecycle
  alias Tuist.Kura.Origins
  alias Tuist.Kura.PlacerRegion
  alias Tuist.Kura.PlacerRegions
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Server
  alias Tuist.Kura.Workers.SeedLegacyCacheDemandWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :set_mimic_from_context

  @legacy_endpoint "https://cache-us-east.tuist.dev"
  @image_tag "0.5.2"
  # An Air or Pro instance in us-east and eu-west: an 8Gi claim on each of two
  # replicas.
  @instance_gib 16

  setup do
    stub(Environment, :env, fn -> :prod end)
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :kura_available_region_ids, fn -> ["us-east", "eu-west"] end)
    stub(Environment, :kura_runtime_image_tag, fn -> @image_tag end)
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
    stub(Client, :list_nodes, fn _selector -> {:ok, %{"items" => []}} end)
    stub(Client, :list_pods, fn _namespace, _selector -> {:ok, []} end)
    :ok
  end

  defp account(opts \\ []) do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    case Keyword.get(opts, :plan) do
      nil -> :ok
      plan -> BillingFixtures.subscription_fixture(account_id: account.id, plan: plan)
    end

    case Keyword.get(opts, :region) do
      nil -> account
      region -> account |> Accounts.update_account(%{region: region}) |> elem(1)
    end
  end

  defp project(account), do: ProjectsFixtures.project_fixture(account_id: account.id)

  defp ago(days), do: DateTime.add(DateTime.utc_now(), -round(days * 86_400), :second)
  defp seconds(%DateTime{} = at), do: DateTime.truncate(at, :second)

  defp module_cache_run(account, opts) do
    ran_at = Keyword.fetch!(opts, :at)

    CommandEventsFixtures.command_event_fixture(
      project_id: Keyword.get_lazy(opts, :project_id, fn -> project(account).id end),
      cache_endpoint: Keyword.get(opts, :endpoint, @legacy_endpoint),
      created_at: ran_at,
      ran_at: ran_at
    )
  end

  defp xcode_cache_event(account, inserted_at) do
    IngestRepo.insert_all(CASEvent, [
      %{
        id: UUIDv7.generate(),
        action: "download",
        size: 1,
        cas_id: "cas-#{System.unique_integer([:positive])}",
        project_id: project(account).id,
        cache_endpoint: "cache-eu-central.tuist.dev",
        inserted_at: inserted_at |> seconds() |> DateTime.to_naive()
      }
    ])
  end

  defp gradle_cache_event(account, inserted_at) do
    project = project(account)

    IngestRepo.insert_all(CacheEvent, [
      %{
        id: UUIDv7.generate(),
        action: "download",
        cache_key: "key-#{System.unique_integer([:positive])}",
        size: 1,
        duration_ms: 1,
        is_hit: true,
        is_ci: true,
        gradle_build_id: nil,
        project_id: project.id,
        account_handle: account.name,
        project_handle: project.name,
        cache_endpoint: "cache-us-east-3.tuist.dev",
        inserted_at: inserted_at |> seconds() |> DateTime.to_naive()
      }
    ])
  end

  defp run(args \\ %{}), do: SeedLegacyCacheDemandWorker.run(args)
  defp seed(args \\ %{}), do: run(Map.put(args, "dry_run", false))

  defp entries_for(report, account), do: Enum.filter(report.entries, &(&1.account_id == account.id))

  defp servers_for(account), do: Repo.all(from(s in Server, where: s.account_id == ^account.id))

  defp lifecycle_rows_for(account), do: Repo.all(from(l in AccountRegionLifecycle, where: l.account_id == ^account.id))

  defp instance(account, region, status, updated_at \\ DateTime.utc_now()) do
    %Server{
      account_id: account.id,
      region: region,
      status: status,
      url: "https://#{account.name}-#{region}-1.kura.tuist.dev",
      current_image_tag: @image_tag,
      provisioner_node_ref: "kura-#{account.id}-#{region}",
      storage_claim_size: "8Gi"
    }
    |> Repo.insert!()
    |> Ecto.Changeset.change(%{updated_at: updated_at})
    |> Repo.update!()
  end

  defp admission(headroom_by_region) do
    stub(Environment, :kura_capacity_admission_required?, fn -> true end)
    stub(Capacity, :pressure_line_gib, fn region -> Map.fetch!(headroom_by_region, region) end)
    stub(Capacity, :reserved_gib, fn _region -> 0 end)
  end

  describe "finding accounts on the legacy cache lane" do
    test "seeds demand at the account's latest legacy request, and the reconciler provisions an instance" do
      account = account()
      module_cache_run(account, at: ago(3))
      last = ago(1)
      module_cache_run(account, at: last)

      report = seed()

      assert [%{outcome: :provision, region: "us-east", reason: nil}] = entries_for(report, account)
      assert Demand.get(account.id, "us-east").last_cache_demand_at == seconds(last)

      assert :ok = Lifecycle.reconcile()
      assert [%Server{status: :provisioning, region: "us-east"}] = servers_for(account)
    end

    # Xcode and Gradle events carry the host the legacy node reported, with no
    # scheme, and numbered nodes such as cache-us-east-3.
    test "counts Xcode and Gradle traffic to the legacy nodes" do
      xcode = account()
      xcode_cache_event(xcode, ago(1))
      gradle = account()
      gradle_cache_event(gradle, ago(1))

      report = seed()

      assert [%{outcome: :provision, legacy: %{lanes: [:xcode]}}] = entries_for(report, xcode)
      assert [%{outcome: :provision, legacy: %{lanes: [:gradle]}}] = entries_for(report, gradle)
      assert Demand.get(xcode.id, "us-east")
      assert Demand.get(gradle.id, "us-east")
    end

    test "ignores traffic to Kura instances, including one whose handle starts with cache-" do
      account = account()
      module_cache_run(account, at: ago(1), endpoint: "https://#{account.name}-us-east-1.kura.tuist.dev")
      module_cache_run(account, at: ago(1), endpoint: "https://cache-#{account.name}-us-east-1.kura.tuist.dev")

      module_cache_run(account,
        at: ago(1),
        endpoint: "kura-cache-us-east-1-1.kura-cache-us-east-1-headless.kura.svc.cluster.local:7443"
      )

      report = seed()

      assert entries_for(report, account) == []
      assert lifecycle_rows_for(account) == []
    end

    test "ignores legacy traffic older than the lookback" do
      account = account()
      module_cache_run(account, at: ago(10))

      report = seed(%{"lookback_days" => 7})

      assert entries_for(report, account) == []
      assert lifecycle_rows_for(account) == []
    end

    test "never stamps demand later than now" do
      account = account()
      module_cache_run(account, at: DateTime.add(DateTime.utc_now(), 7 * 86_400, :second))

      seed()

      assert DateTime.diff(DateTime.utc_now(), Demand.get(account.id, "us-east").last_cache_demand_at) in 0..60
    end
  end

  describe "dry run" do
    test "is the default, reports the plan and writes nothing" do
      admission(%{"us-east" => 0, "eu-west" => 1_000})
      account = account()
      module_cache_run(account, at: ago(1))

      report = run()

      assert report.dry_run
      assert [%{outcome: :provision, region: "eu-west", preferred_region: "us-east"}] = entries_for(report, account)
      assert lifecycle_rows_for(account) == []
      assert PlacerRegions.primary_region(account) == nil
    end
  end

  describe "placement" do
    test "places the instance nearest the account's traffic origin" do
      account = account()
      module_cache_run(account, at: ago(1))

      Origins.upsert_many([
        %{account_id: account.id, origin: "FR", date: Date.utc_today(), run_count: 10, demand_count: 0}
      ])

      report = seed()

      assert [%{outcome: :provision, region: "eu-west", origin: "FR"}] = entries_for(report, account)
      assert :ok = Lifecycle.reconcile()
      assert [%Server{region: "eu-west"}] = servers_for(account)
    end
  end

  describe "accounts that are not provisioned" do
    test "reports an Open Source account, which Kura never serves" do
      account = account(plan: :open_source)
      module_cache_run(account, at: ago(1))

      report = seed()

      assert [%{outcome: :skipped, reason: :plan_not_supported, region: nil}] = entries_for(report, account)
      assert lifecycle_rows_for(account) == []
    end

    test "reports an account whose last legacy request is older than the inactivity window" do
      stub(Environment, :kura_inactive_days, fn -> 1 end)
      account = account()
      module_cache_run(account, at: ago(2))

      report = seed()

      assert [%{outcome: :skipped, reason: :inactive, region: "us-east"}] = entries_for(report, account)
      assert lifecycle_rows_for(account) == []
    end

    test "refreshes demand for an account already served, without reserving capacity for it" do
      admission(%{"us-east" => 0, "eu-west" => 0})
      account = account()
      instance(account, "us-east", :active)
      {:ok, _} = Demand.upsert(account.id, "us-east", ago(30))
      last = ago(1)
      module_cache_run(account, at: last)

      report = seed()

      assert [%{outcome: :serving, region: "us-east", reservation_gib: nil}] = entries_for(report, account)
      assert Demand.get(account.id, "us-east").last_cache_demand_at == seconds(last)
    end

    test "reports an instance that exists but is not serving" do
      account = account()
      instance(account, "us-east", :failed)
      module_cache_run(account, at: ago(1))

      report = seed()

      assert [%{outcome: :waiting, region: "us-east", kura_status: :failed}] = entries_for(report, account)
    end

    test "does not provision past an operator destroy newer than the account's legacy traffic" do
      account = account()
      module_cache_run(account, at: ago(2))
      instance(account, "us-east", :destroyed, ago(1))

      report = seed()

      assert [%{outcome: :skipped, reason: :destroyed_after_demand, region: "us-east"}] = entries_for(report, account)
      assert lifecycle_rows_for(account) == []
    end

    test "provisions past a destroy the account's legacy traffic came after" do
      account = account()
      instance(account, "us-east", :destroyed, ago(2))
      module_cache_run(account, at: ago(1))

      report = seed()

      assert [%{outcome: :provision, region: "us-east"}] = entries_for(report, account)
    end

    test "returns an instance archived as unused when the account kept using the legacy nodes after" do
      account = account()
      archived = instance(account, "us-east", :archived, ago(2))
      {:ok, _} = Demand.upsert(account.id, "us-east", ago(20))

      account.id
      |> Demand.get("us-east")
      |> AccountRegionLifecycle.phase_changeset(%{drain_reason: :unused, archived_at: seconds(ago(2))})
      |> Repo.update!()

      module_cache_run(account, at: ago(1))

      report = seed()

      assert [%{outcome: :provision, region: "us-east", kura_status: nil}] = entries_for(report, account)
      assert :ok = Lifecycle.reconcile()
      assert %Server{status: :provisioning} = Repo.get!(Server, archived.id)
    end

    test "reports an instance archived as unused after the account's last legacy request" do
      account = account()
      instance(account, "us-east", :archived, ago(1))
      {:ok, _} = Demand.upsert(account.id, "us-east", ago(20))

      account.id
      |> Demand.get("us-east")
      |> AccountRegionLifecycle.phase_changeset(%{drain_reason: :unused, archived_at: seconds(ago(1))})
      |> Repo.update!()

      module_cache_run(account, at: ago(2))

      report = seed()

      assert [%{outcome: :skipped, reason: :archived_unused_after_demand}] = entries_for(report, account)
    end
  end

  describe "capacity" do
    test "admits up to what the region can hold, paid plans first" do
      admission(%{"us-east" => @instance_gib, "eu-west" => 0})
      busy_air = account(region: :usa)
      for days <- [1, 2, 3], do: module_cache_run(busy_air, at: ago(days))
      pro = account(plan: :pro, region: :usa)
      module_cache_run(pro, at: ago(1))

      report = seed()

      assert [%{outcome: :provision, region: "us-east", reservation_gib: @instance_gib}] = entries_for(report, pro)
      assert [%{outcome: :skipped, reason: :capacity_exhausted, region: "us-east"}] = entries_for(report, busy_air)
      assert Demand.get(pro.id, "us-east")
      assert lifecycle_rows_for(busy_air) == []

      assert %{"us-east" => %{headroom_gib: @instance_gib, admitted_gib: @instance_gib, provisions: 1, refused: 1}} =
               report.regions
    end

    test "spills an account with nothing placed to the nearest region with room, and records it as first placement would" do
      admission(%{"us-east" => 0, "eu-west" => 1_000})
      account = account()
      module_cache_run(account, at: ago(1))

      report = seed()

      assert [%{outcome: :provision, region: "eu-west", preferred_region: "us-east"}] = entries_for(report, account)

      assert %PlacerRegion{region: "eu-west", evidence: %{"signal" => "capacity_spill", "preferred_region" => "us-east"}} =
               Repo.get_by(PlacerRegion, account_id: account.id, role: :primary)

      assert %{"us-east" => %{spilled_out: 1}, "eu-west" => %{spilled_in: 1, provisions: 1}} = report.regions

      assert :ok = Lifecycle.reconcile()
      assert [%Server{status: :provisioning, region: "eu-west"}] = servers_for(account)
    end

    test "does not spill an account placement already decided for" do
      admission(%{"us-east" => 0, "eu-west" => 1_000})
      account = account()
      {:recorded, _} = PlacerRegions.record_first_primary(account, "us-east", %{"signal" => "relocate"})
      module_cache_run(account, at: ago(1))

      report = seed()

      assert [%{outcome: :skipped, reason: :capacity_exhausted, region: "us-east"}] = entries_for(report, account)
      assert lifecycle_rows_for(account) == []
    end

    test "refuses rather than guesses when the region's capacity cannot be read" do
      stub(Environment, :kura_capacity_admission_required?, fn -> true end)
      stub(Capacity, :pressure_line_gib, fn _region -> nil end)
      account = account(region: :usa)
      module_cache_run(account, at: ago(1))

      report = seed()

      assert [%{outcome: :skipped, reason: :capacity_exhausted}] = entries_for(report, account)
      assert %{"us-east" => %{headroom_gib: nil}} = report.regions
    end
  end

  describe "prepare" do
    setup do
      stub(Provisioner, :destroy, fn _server -> :ok end)
      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)
      :ok
    end

    defp prepare_pass(started_at, extra \\ %{}) do
      %{"dry_run" => false, "prepare" => true, "started_at" => DateTime.to_iso8601(started_at)}
      |> Map.merge(extra)
      |> run()
    end

    defp activate(account) do
      [server] = Enum.reject(servers_for(account), &(&1.status in [:archived, :destroyed]))
      server |> Ecto.Changeset.change(%{status: :active}) |> Repo.update!()
    end

    defp elapse_drain(account, region \\ "us-east") do
      started_at = DateTime.truncate(DateTime.add(DateTime.utc_now(), -Kura.drain_seconds() - 60, :second), :second)

      account.id
      |> Demand.get(region)
      |> Ecto.Changeset.change(%{drain_started_at: started_at})
      |> Repo.update!()
    end

    defp started_at, do: DateTime.truncate(DateTime.add(DateTime.utc_now(), -1, :second), :second)

    test "seeds an instance, archives it once it is active, and leaves it archived" do
      account = account()
      module_cache_run(account, at: ago(1))
      started_at = started_at()

      first = prepare_pass(started_at)
      assert [%{outcome: :provision, region: "us-east"}] = entries_for(first, account)
      assert first.in_flight

      assert :ok = Lifecycle.reconcile()
      server = activate(account)

      second = prepare_pass(started_at)
      assert [%{outcome: :prepare, region: "us-east"}] = entries_for(second, account)
      assert %Server{status: :drain_pending} = Repo.get!(Server, server.id)
      assert second.prepared == ["#{account.id}:us-east"]
      assert second.in_flight

      elapse_drain(account)
      assert :ok = Lifecycle.reconcile()
      assert %Server{status: :archived} = Repo.get!(Server, server.id)

      module_cache_run(account, at: ago(0.001))
      third = prepare_pass(started_at, %{"prepared" => second.prepared})

      assert [%{outcome: :prepared, region: "us-east"}] = entries_for(third, account)
      refute third.in_flight

      assert :ok = Lifecycle.reconcile()
      assert %Server{status: :archived} = Repo.get!(Server, server.id)
    end

    test "seeds the next account once the instance ahead of it has released its reservation" do
      admission(%{"us-east" => @instance_gib, "eu-west" => 0})
      first_account = account(region: :usa)
      for days <- [1, 2], do: module_cache_run(first_account, at: ago(days))
      second_account = account(region: :usa)
      module_cache_run(second_account, at: ago(1))
      started_at = started_at()

      first = prepare_pass(started_at)
      assert [%{outcome: :provision}] = entries_for(first, first_account)
      assert [%{outcome: :skipped, reason: :capacity_exhausted}] = entries_for(first, second_account)

      assert :ok = Lifecycle.reconcile()
      activate(first_account)

      second = prepare_pass(started_at)
      assert [%{outcome: :prepare}] = entries_for(second, first_account)
      assert [%{outcome: :skipped, reason: :capacity_exhausted}] = entries_for(second, second_account)

      elapse_drain(first_account)
      assert :ok = Lifecycle.reconcile()

      third = prepare_pass(started_at, %{"prepared" => second.prepared})
      assert [%{outcome: :prepared}] = entries_for(third, first_account)
      assert [%{outcome: :provision}] = entries_for(third, second_account)
      assert third.in_flight
    end

    test "leaves an instance in service once its account asks for the cache through Kura" do
      account = account()
      module_cache_run(account, at: ago(1))
      started_at = started_at()

      prepare_pass(started_at)
      assert :ok = Lifecycle.reconcile()
      server = activate(account)
      Demand.record(account.id)

      report = prepare_pass(started_at)

      assert [%{outcome: :serving}] = entries_for(report, account)
      assert %Server{status: :active} = Repo.get!(Server, server.id)
    end

    test "never archives an instance that was serving before the backfill started" do
      account = account()
      server = instance(account, "us-east", :active)
      server |> Ecto.Changeset.change(%{inserted_at: ago(30)}) |> Repo.update!()
      {:ok, _} = Demand.upsert(account.id, "us-east", ago(1))
      module_cache_run(account, at: ago(1))

      report = prepare_pass(started_at())

      assert [%{outcome: :serving}] = entries_for(report, account)
      assert %Server{status: :active} = Repo.get!(Server, server.id)
      refute report.in_flight
    end

    test "archives an instance at most once in a backfill" do
      account = account()
      module_cache_run(account, at: ago(1))
      started_at = started_at()

      prepare_pass(started_at)
      assert :ok = Lifecycle.reconcile()
      activate(account)

      report = prepare_pass(started_at, %{"prepared" => ["#{account.id}:us-east"]})

      assert [%{outcome: :serving}] = entries_for(report, account)
    end

    test "the job snoozes while instances are on their way and finishes when none are" do
      account = account()
      module_cache_run(account, at: ago(1))

      {:ok, job} =
        %{"dry_run" => false, "prepare" => true}
        |> SeedLegacyCacheDemandWorker.new()
        |> Oban.insert()

      assert {:snooze, _seconds} = SeedLegacyCacheDemandWorker.perform(job)
      assert [%Oban.Job{args: %{"started_at" => _}}] = all_enqueued(worker: SeedLegacyCacheDemandWorker)

      Repo.delete_all(from(l in AccountRegionLifecycle, where: l.account_id == ^account.id))
      Repo.delete_all(from(s in Server, where: s.account_id == ^account.id))
      Repo.delete_all(from(p in Tuist.Projects.Project, where: p.account_id == ^account.id))

      [job] = all_enqueued(worker: SeedLegacyCacheDemandWorker)
      assert :ok = SeedLegacyCacheDemandWorker.perform(job)
    end
  end

  test "the job runs a dry run by default" do
    account = account()
    module_cache_run(account, at: ago(1))

    assert :ok = perform_job(SeedLegacyCacheDemandWorker, %{})
    assert lifecycle_rows_for(account) == []
  end
end
