defmodule Tuist.Kura.LifecycleTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.Admission
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Lifecycle
  alias Tuist.Kura.PlacerRegions
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Reconciler
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.StableEndpoint
  alias Tuist.Kura.StorageRollup
  alias Tuist.Kura.Workers.ProvisionOnDemandWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  @region "us-east"
  # Roughly what one of the region's real boxes reports allocatable.
  @node_allocatable_bytes 847_551_469_804
  # us-east co-locates an account's two replicas on one box, so an instance
  # reserves its plan's claim twice.
  @replicas 2
  @air_resident_gib 8 * @replicas
  @enterprise_resident_gib 16 * @replicas
  # What a Pro instance holds once sizing has grown it. Plans no longer start
  # apart, so a footprint that differs from Air's is one sizing produced.
  @grown_pro_gib 32
  @pro_resident_gib @grown_pro_gib * @replicas
  @pressure_line_gib trunc(@node_allocatable_bytes * 0.85 / (1024 * 1024 * 1024))
  # The fewest Air instances that leave the region too little headroom for a new
  # enterprise instance, though still enough for another Air one. Derived rather
  # than counted out so the fixtures track the real sizing.
  @instances_to_pressure div(@pressure_line_gib - @enterprise_resident_gib, @air_resident_gib) + 1
  @image_tag "0.5.2"
  @gib 1024 * 1024 * 1024

  # Drive `Regions.available/0` to the real `us-east` managed region rather
  # than the dev-only local controller, so the loop runs against the same
  # region catalog and service-region resolution production uses.
  # `KubernetesController.provision/3` is pure (it builds the instance name),
  # so provisioning runs for real against the sandbox; only the observation
  # and teardown calls that would reach the apiserver are stubbed.
  setup do
    stub(Environment, :env, fn -> :prod end)
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    # Instances are sized from their account's plan on the hosted server; a
    # self-hosted deployment has no subscriptions and sizes everything at
    # enterprise, which is not the loop under test here.
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :kura_available_region_ids, fn -> [@region] end)
    stub(Environment, :kura_runtime_image_tag, fn -> @image_tag end)
    stub_region_nodes([])

    # Exercise the real buffer rather than the write-through path tests use by
    # default, so the sweep's "flush before reading demand" step is covered.
    # Safe because the case is synchronous.
    stub(Environment, :kura_demand_write_through_repo?, fn -> false end)

    Demand.flush()
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

  # An account whose demand tracking and instance are old enough to clear the
  # tracking grace period, with the last cache request `days` ago.
  defp with_demand(account, days_ago, opts \\ []) do
    demand_at = ago(days_ago)

    {:ok, _} = Demand.upsert(account.id, @region, demand_at)

    lifecycle = Demand.get(account.id, @region)
    aged = ago(Keyword.get(opts, :tracked_for_days, 120))

    lifecycle
    |> Ecto.Changeset.change(%{inserted_at: aged, updated_at: aged})
    |> Repo.update!()
  end

  defp ago(days), do: DateTime.truncate(ago_usec(days), :second)
  defp ago_usec(days), do: DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

  # Built the way `Kura.create_server/1` builds one, footprint included: the
  # pressure arithmetic reads each instance's own claim, so an instance inserted
  # without one would not reserve what its plan reserves in production.
  defp active_instance(account, opts \\ []) do
    inserted_at =
      DateTime.add(DateTime.utc_now(), -Keyword.get(opts, :age_hours, Keyword.get(opts, :age_days, 120) * 24), :hour)

    claim_size =
      Keyword.get_lazy(opts, :claim_size, fn ->
        %{claim_size: claim_size} = Regions.storage_profile(AccountPolicies.sizing_plan(account))
        claim_size
      end)

    %Server{
      account_id: account.id,
      region: @region,
      status: :active,
      url: "https://#{account.name}-us-east-1.kura.tuist.dev",
      current_image_tag: @image_tag,
      provisioner_node_ref: "kura-#{account.id}-us-east",
      storage_claim_size: claim_size
    }
    |> Repo.insert!()
    |> Ecto.Changeset.change(%{inserted_at: inserted_at, updated_at: inserted_at})
    |> Repo.update!()
  end

  # A region whose pressure line cannot fit a single Air instance, with
  # admission enforced as it is in production.
  defp refuse_admission do
    stub(Environment, :kura_capacity_admission_required?, fn -> true end)
    stub(Capacity, :pressure_line_gib, fn @region -> @air_resident_gib - 1 end)
    stub(Capacity, :reserved_gib, fn @region -> 0 end)
  end

  defp reload(%Server{id: id}), do: Repo.get!(Server, id)
  defp reload_lifecycle(account), do: Demand.get(account.id, @region)

  defp servers_for(account) do
    Repo.all(from(s in Server, where: s.account_id == ^account.id))
  end

  defp start_drain(account, server) do
    with_demand(account, 200)
    Lifecycle.sweep()
    assert reload(server).status == :drain_pending
    reload_lifecycle(account)
  end

  # Rewinds the drain clock so the next tick sees the drain window as elapsed.
  defp elapse_drain(account) do
    started_at =
      DateTime.utc_now()
      |> DateTime.add(-Kura.drain_seconds() - 60, :second)
      |> DateTime.truncate(:second)

    account
    |> reload_lifecycle()
    |> Ecto.Changeset.change(%{drain_started_at: started_at})
    |> Repo.update!()
  end

  describe "provisioning on demand" do
    test "cold-provisions an instance for an account on each plan" do
      for {plan, region} <- [{nil, nil}, {:pro, :usa}, {:enterprise, :usa}] do
        account = account(plan: plan, region: region)
        Demand.record(account.id)

        assert :ok = Lifecycle.reconcile()

        assert [%Server{status: :provisioning, region: @region}] = servers_for(account)
        assert [%Deployment{image_tag: @image_tag}] = Repo.all(from(d in Deployment))
        Repo.delete_all(Deployment)
      end
    end

    test "does not provision for an account with no cache demand" do
      account = account()

      assert :ok = Lifecycle.reconcile()

      assert servers_for(account) == []
    end

    test "provisions regardless of how full the region is, because the scheduler decides that" do
      # Admission is the scheduler's: every cache pod requests its claim's
      # worth of ephemeral storage, so a region with no room leaves the
      # instance Pending rather than this pass declining to create it.
      stub_region_nodes([{@region, List.duplicate(@node_allocatable_bytes, 1)}])
      stub_region_pods(List.duplicate(reserved_pod(50), 100))

      account = account()
      Demand.record(account.id)

      assert :ok = Lifecycle.reconcile()

      assert [%Server{status: :provisioning}] = servers_for(account)
    end

    test "counts a provisioning capacity admission refused, by region and reason" do
      # A refused account keeps being served by whatever lane it is on and
      # raises nothing, so this counter is the only trace a full region leaves.
      refuse_admission()

      account = account()
      Demand.record(account.id)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :provision_refused]])

      assert :ok = Lifecycle.reconcile()

      assert servers_for(account) == []

      assert_received {[:tuist, :kura, :lifecycle, :provision_refused], ^ref, %{count: 1},
                       %{plan: "air", region: @region, reason: "capacity_exhausted", cold_return: "false"}}
    end

    test "does not recreate an instance the account explicitly destroyed" do
      account = account()
      Demand.record(account.id)
      assert :ok = Lifecycle.reconcile()

      [server] = servers_for(account)
      {:ok, _} = Kura.destroy_server(server)
      server |> Ecto.Changeset.change(%{status: :destroyed}) |> Repo.update!()

      assert :ok = Lifecycle.reconcile()

      assert [%Server{status: :destroyed}] = servers_for(account)
    end

    test "provisions again when the account asks for the cache after destroying it" do
      account = account()
      Demand.record(account.id)
      assert :ok = Lifecycle.reconcile()

      [server] = servers_for(account)
      {:ok, _} = Kura.destroy_server(server)

      server
      |> Ecto.Changeset.change(%{status: :destroyed, updated_at: ago_usec(1)})
      |> Repo.update!()

      Demand.record(account.id)

      assert :ok = Lifecycle.reconcile()

      assert [_destroyed, %Server{status: :provisioning}] =
               Enum.sort_by(servers_for(account), & &1.status)
    end

    test "does not provision an account whose plan no longer supports a cache" do
      account = account(plan: :pro, region: :usa)
      Demand.record(account.id)
      Demand.flush()

      {:ok, _} = Accounts.update_account(account, %{region: :europe})

      assert :ok = Lifecycle.reconcile()

      assert servers_for(account) == []
    end
  end

  describe "entering drain-pending" do
    test "drains an instance after a complete inactive window, taking it out of resolution" do
      account = account()
      server = active_instance(account)
      assert Kura.managed_cache_endpoint_urls(account) == [server.url]
      with_demand(account, 91)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :drain_pending
      assert Kura.managed_cache_endpoint_urls(account) == []
      assert reload_lifecycle(account).drain_started_at
    end

    test "leaves an instance alone inside its inactive window" do
      account = account()
      server = active_instance(account)
      with_demand(account, 89)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "never archives an instance with no recorded demand" do
      account = account()
      server = active_instance(account)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "never archives an account-region whose demand tracking is younger than the grace period" do
      account = account()
      server = active_instance(account)
      with_demand(account, 200, tracked_for_days: 1)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "never archives a freshly deployed instance" do
      account = account()
      server = active_instance(account, age_days: 1)
      with_demand(account, 200)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "never archives a keep-warm instance" do
      account = account()
      server = active_instance(account)
      with_demand(account, 200)
      {:ok, _} = Demand.set_keep_warm(account.id, @region, true)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "never archives an Enterprise instance, however long it has been inactive" do
      account = account(plan: :enterprise, region: :usa)
      server = active_instance(account)
      with_demand(account, 400)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "still archives Air and Pro" do
      for {plan, region} <- [{nil, nil}, {:pro, :usa}] do
        account = account(plan: plan, region: region)
        server = active_instance(account)
        with_demand(account, 91)

        assert :ok = Lifecycle.sweep()

        assert reload(server).status == :drain_pending
      end
    end
  end

  describe "Air capacity pressure" do
    setup do
      stub(Environment, :kura_capacity_admission_required?, fn -> true end)
      stub_region_nodes([{@region, List.duplicate(@node_allocatable_bytes, 1)}])
      :ok
    end

    test "drains Air at 60 days once a new enterprise instance no longer fits, while admission still admits" do
      pressured =
        for _ <- 1..@instances_to_pressure do
          account = account()
          server = active_instance(account)
          with_demand(account, 61)
          {account, server}
        end

      under_pressure()

      {:ok, region} = Regions.fetch(@region)
      assert :ok = Admission.admit?(region, %Server{region: @region, status: :provisioning, storage_claim_size: "8Gi"})

      assert :ok = Lifecycle.sweep()

      drained = Enum.count(pressured, fn {_a, server} -> reload(server).status == :drain_pending end)

      # Only as many as it takes to fit: the region is a few gibibytes short of
      # a new enterprise instance, so reclaiming one Air instance makes the room.
      assert drained == 1
    end

    test "preserves the 90-day target when there is room" do
      stub_region_pods([reserved_pod(50)])
      account = account()
      server = active_instance(account)
      with_demand(account, 61)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "orders pressure archival by least-recent demand" do
      recent = account()
      recent_server = active_instance(recent)
      with_demand(recent, 61)

      coldest = account()
      coldest_server = active_instance(coldest)
      with_demand(coldest, 80)

      for _ <- 1..(@instances_to_pressure - 2) do
        filler = account()
        active_instance(filler)
        with_demand(filler, 10)
      end

      under_pressure()

      assert :ok = Lifecycle.sweep()

      assert reload(coldest_server).status == :drain_pending
      assert reload(recent_server).status == :active
    end

    test "counts what each unconditional archival actually frees" do
      # A Pro instance past the full window is archived regardless, and it frees
      # what it actually holds — 64Gi for one sizing has grown — rather than an
      # Air instance's 16Gi. The region has room for exactly one new enterprise
      # instance once that room is counted, so no Air instance is pressured.
      # Counted at a uniform per-instance figure it would land 48Gi short and
      # take three.
      pro = account(plan: :pro, region: :usa)
      pro_server = active_instance(pro, claim_size: "#{@grown_pro_gib}Gi")
      with_demand(pro, 200)

      air =
        for _ <- 1..3 do
          account = account()
          server = active_instance(account)
          with_demand(account, 61)
          server
        end

      # 702Gi reserved against a 670Gi line: 64Gi short of room for a new
      # 32Gi enterprise instance, exactly what the grown Pro instance holds
      # across its two replicas.
      stub_region_pods([reserved_pod(2) | List.duplicate(reserved_pod(10), 70)])

      assert :ok = Lifecycle.sweep()

      assert reload(pro_server).status == :drain_pending
      assert Enum.all?(air, &(reload(&1).status == :active))
    end

    test "never pressures a paid plan below its 90-day window" do
      for _ <- 1..@instances_to_pressure do
        account = account()
        active_instance(account)
        with_demand(account, 10)
      end

      pro = account(plan: :pro, region: :usa)
      server = active_instance(pro)
      with_demand(pro, 61)

      under_pressure()

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "never pressures an Air account before 60 complete inactive days" do
      for _ <- 1..47 do
        account = account()
        active_instance(account)
        with_demand(account, 10)
      end

      account = account()
      server = active_instance(account)
      with_demand(account, 59)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "does not provision an instance archived under pressure again on the demand it already had" do
      account = account()
      server = archive_under_pressure(account)

      assert :ok = Lifecycle.reconcile()

      assert reload(server).status == :archived
    end

    test "returns an instance archived under pressure when the account asks for the cache" do
      account = account()
      server = archive_under_pressure(account)

      Demand.record(account.id)
      assert :ok = Lifecycle.reconcile()

      assert reload(server).status == :provisioning
    end

    # Archives an Air instance at 61 inactive days under pressure, then gives
    # the region its room back.
    defp archive_under_pressure(account) do
      stub(Provisioner, :destroy, fn _server -> :ok end)
      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)

      server = active_instance(account)
      with_demand(account, 61)
      stub_region_pods([reserved_pod(@pressure_line_gib - @air_resident_gib)])

      assert :ok = Lifecycle.sweep()
      assert reload_lifecycle(account).drain_reason == :capacity_pressure
      elapse_drain(account)
      assert :ok = Lifecycle.reconcile()
      assert reload(server).status == :archived

      account
      |> reload_lifecycle()
      |> Ecto.Changeset.change(%{archived_at: DateTime.truncate(DateTime.add(DateTime.utc_now(), -60, :second), :second)})
      |> Repo.update!()

      stub_region_pods([])
      refute Capacity.under_pressure?(@region)

      server
    end
  end

  describe "archive cancellation" do
    test "returns a draining instance to service when demand arrives mid-drain" do
      account = account()
      server = active_instance(account)
      start_drain(account, server)

      Demand.record(account.id)

      assert :ok = Lifecycle.reconcile()

      assert reload(server).status == :active
      assert reload_lifecycle(account).drain_started_at == nil
      reject(&Provisioner.destroy/1)
    end

    test "returns the drained instance to resolution" do
      account = account()
      server = active_instance(account)
      start_drain(account, server)
      assert Kura.managed_cache_endpoint_urls(account) == []

      Demand.record(account.id)
      Lifecycle.reconcile()

      assert Kura.managed_cache_endpoint_urls(account) == [server.url]
    end

    test "emits an archive cancellation" do
      account = account()
      server = active_instance(account)
      start_drain(account, server)
      Demand.record(account.id)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :archive_cancelled]])

      Lifecycle.reconcile()

      assert_received {[:tuist, :kura, :lifecycle, :archive_cancelled], ^ref, %{count: 1}, %{region: @region}}
    end

    test "returns a draining instance to service when the account upgrades to Enterprise" do
      account = account()
      server = active_instance(account)
      start_drain(account, server)

      # Mid-drain upgrade: the instance must not be reclaimed under the plan the
      # account has just left.
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert :ok = Lifecycle.reconcile()

      assert reload(server).status == :active
      reject(&Provisioner.destroy/1)
    end

    test "does not tear down when the drain clock is missing" do
      account = account()
      server = active_instance(account)
      lifecycle = start_drain(account, server)

      # A drain-pending row with no clock has not waited out its window,
      # whatever left it that way.
      lifecycle |> Ecto.Changeset.change(%{drain_started_at: nil}) |> Repo.update!()
      reject(&Provisioner.destroy/1)

      assert :ok = Lifecycle.reconcile()

      assert reload(server).status == :drain_pending
      assert reload_lifecycle(account).teardown_started_at == nil
      assert reload_lifecycle(account).drain_started_at
    end

    test "does not cancel once teardown has been issued" do
      stub(Provisioner, :destroy, fn _server -> :ok end)
      stub(Provisioner, :current_image_tag, fn _server -> {:ok, @image_tag} end)

      account = account()
      server = active_instance(account)
      start_drain(account, server)
      elapse_drain(account)

      Lifecycle.reconcile()
      assert reload_lifecycle(account).teardown_started_at

      Demand.record(account.id)
      Lifecycle.reconcile()

      assert reload(server).status == :drain_pending
    end
  end

  describe "archiving" do
    setup do
      stub(Provisioner, :destroy, fn _server -> :ok end)
      :ok
    end

    test "archives only once the backing resource is observably gone" do
      stub(Provisioner, :current_image_tag, fn _server -> {:ok, @image_tag} end)

      account = account()
      server = active_instance(account)
      start_drain(account, server)
      elapse_drain(account)

      Lifecycle.reconcile()
      assert reload(server).status == :drain_pending

      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)
      Lifecycle.reconcile()

      assert reload(server).status == :archived
    end

    test "records reclaimed bytes and drain duration" do
      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)

      account = account()
      server = active_instance(account)
      start_drain(account, server)
      elapse_drain(account)

      Lifecycle.reconcile()

      lifecycle = reload_lifecycle(account)
      assert reload(server).status == :archived
      assert lifecycle.archived_at
      assert lifecycle.last_reclaimed_bytes == @air_resident_gib * @gib
      assert lifecycle.last_drain_duration_ms >= Kura.drain_seconds() * 1000
    end

    test "records the paid plan's larger reclaimed quota" do
      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)

      account = account(plan: :pro, region: :usa)
      server = active_instance(account, claim_size: "#{@grown_pro_gib}Gi")
      start_drain(account, server)
      elapse_drain(account)

      Lifecycle.reconcile()

      assert reload_lifecycle(account).last_reclaimed_bytes == @pro_resident_gib * @gib
    end

    test "clears every field describing a running instance" do
      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)

      account = account()
      server = active_instance(account)
      start_drain(account, server)
      elapse_drain(account)

      Lifecycle.reconcile()

      archived = reload(server)
      assert archived.url == nil
      assert archived.current_image_tag == nil
      assert archived.observed_image_tag == nil
    end

    test "emits reclaimed bytes and drain duration" do
      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)

      account = account()
      server = active_instance(account)
      start_drain(account, server)
      elapse_drain(account)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :archived]])

      Lifecycle.reconcile()

      assert_received {[:tuist, :kura, :lifecycle, :archived], ^ref, measurements, %{region: @region, plan: "air"}}
      assert measurements.reclaimed_bytes == @air_resident_gib * @gib
      assert measurements.drain_duration_ms > 0
    end

    test "stops advertising an archived region as a mesh peer" do
      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)

      account = account()
      server = active_instance(account)
      start_drain(account, server)
      elapse_drain(account)
      Lifecycle.reconcile()

      assert reload(server).status == :archived
      assert Kura.server_regions_for_account(account.id) == []
    end
  end

  describe "cold return" do
    setup do
      stub(Provisioner, :destroy, fn _server -> :ok end)
      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)
      :ok
    end

    defp archive(account) do
      server = active_instance(account)
      start_drain(account, server)
      elapse_drain(account)
      Lifecycle.reconcile()
      assert reload(server).status == :archived
      server
    end

    test "brings an archived account back on the same row when demand returns" do
      account = account()
      server = archive(account)

      Demand.record(account.id)
      Lifecycle.reconcile()

      returned = reload(server)
      assert returned.id == server.id
      assert returned.status == :provisioning
      assert returned.current_image_tag == nil
    end

    test "takes the cold-provision path for every archivable plan" do
      for {plan, region} <- [{nil, nil}, {:pro, :usa}] do
        account = account(plan: plan, region: region)
        archive(account)

        Demand.record(account.id)
        Lifecycle.reconcile()

        assert [%Server{status: :provisioning}] = servers_for(account)
      end
    end

    test "schedules a fresh deployment for the returning instance" do
      account = account()
      server = archive(account)
      assert Repo.all(from(d in Deployment, where: d.kura_server_id == ^server.id)) == []

      Demand.record(account.id)
      Lifecycle.reconcile()

      assert [%Deployment{status: :pending, image_tag: @image_tag}] =
               Repo.all(from(d in Deployment, where: d.kura_server_id == ^server.id))
    end

    test "returns an Enterprise instance archived before the plan was excluded" do
      # The exclusion is on the archival side only. A row archived while the
      # policy still allowed it must still come back on demand, otherwise the
      # account would be stranded with no instance and no way to earn one.
      account = account(plan: :enterprise, region: :usa)

      server =
        Repo.insert!(%Server{
          account_id: account.id,
          region: @region,
          status: :archived,
          provisioner_node_ref: "kura-#{account.id}-us-east"
        })

      Demand.record(account.id)
      Lifecycle.reconcile()

      assert reload(server).status == :provisioning
    end

    test "counts a cold return capacity admission refused, leaving the instance archived" do
      account = account()
      server = archive(account)
      refuse_admission()
      Demand.record(account.id)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :provision_refused]])

      Lifecycle.reconcile()

      assert reload(server).status == :archived

      assert_received {[:tuist, :kura, :lifecycle, :provision_refused], ^ref, %{count: 1},
                       %{plan: "air", region: @region, reason: "capacity_exhausted", cold_return: "true"}}
    end

    test "reports the return as a cold provision" do
      account = account()
      archive(account)
      Demand.record(account.id)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :provisioned]])

      Lifecycle.reconcile()

      assert_received {[:tuist, :kura, :lifecycle, :provisioned], ^ref, %{count: 1}, %{cold_return: "true"}}
    end

    test "clears the archival clocks so the returned instance is not immediately re-drained" do
      account = account()
      archive(account)

      Demand.record(account.id)
      Lifecycle.reconcile()

      lifecycle = reload_lifecycle(account)
      assert lifecycle.drain_started_at == nil
      assert lifecycle.teardown_started_at == nil
      assert lifecycle.last_returned_at
    end

    test "does not wait on a replication that can never complete" do
      account = account()
      server = archive(account)

      Demand.record(account.id)
      Lifecycle.reconcile()

      refute Kura.replication_source?(reload(server))
    end

    test "still reports a replication source when the account serves another region" do
      account = account()
      server = archive(account)

      Repo.insert!(%Server{
        account_id: account.id,
        region: "eu-west",
        status: :active,
        url: "https://peer.example.com",
        current_image_tag: @image_tag,
        provisioner_node_ref: "kura-#{account.id}-eu-west"
      })

      assert Kura.replication_source?(reload(server))
    end
  end

  describe "open rollouts" do
    test "are cancelled when an instance enters drain, so no rollout can act on it" do
      account = account()
      server = active_instance(account)

      deployment =
        Repo.insert!(%Deployment{
          cluster_id: "us-east-1",
          image_tag: @image_tag,
          status: :running,
          kura_server_id: server.id
        })

      start_drain(account, server)

      assert %Deployment{status: :cancelled} = Repo.get!(Deployment, deployment.id)
    end

    test "are rescheduled when the drain is cancelled, so the instance is not stranded on an old image" do
      # Cancelling the rollout on drain entry must not read as "this image was
      # already delivered", or the instance would sit on its old image until
      # some newer release came along.
      account = account()
      server = active_instance(account)

      Repo.insert!(%Deployment{
        cluster_id: "us-east-1",
        image_tag: @image_tag,
        status: :running,
        kura_server_id: server.id
      })

      start_drain(account, server)
      assert [%Deployment{status: :cancelled}] = Repo.all(from(d in Deployment, where: d.kura_server_id == ^server.id))

      Demand.record(account.id)
      Lifecycle.reconcile()
      assert reload(server).status == :active

      # The runtime rollout is scheduled again on the next reconciler pass.
      Repo.update_all(from(s in Server, where: s.id == ^server.id), set: [current_image_tag: "0.4.0"])
      {:ok, %{scheduled: scheduled}} = Kura.schedule_runtime_image_deployments()

      assert Enum.any?(scheduled, &(&1.kura_server_id == server.id and &1.image_tag == @image_tag))
    end

    test "leave the row able to cold-return, which requires no open deployment" do
      stub(Provisioner, :destroy, fn _server -> :ok end)
      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)

      account = account()
      server = active_instance(account)

      Repo.insert!(%Deployment{
        cluster_id: "us-east-1",
        image_tag: @image_tag,
        status: :pending,
        kura_server_id: server.id
      })

      start_drain(account, server)
      elapse_drain(account)
      Lifecycle.reconcile()
      assert reload(server).status == :archived

      Demand.record(account.id)
      Lifecycle.reconcile()

      assert reload(server).status == :provisioning
    end
  end

  describe "concurrency with the reconciler" do
    test "activation cannot pull a draining instance back into service" do
      stub(Provisioner, :public_url, fn _account, _server -> "http://localhost:4100" end)
      # The sweep runs alongside the reconciler, so a deployment loop that
      # preloaded this server as active can reach activation after it entered
      # drain-pending. The lock is the authority, not the preloaded status.
      account = account()
      server = active_instance(account)
      start_drain(account, server)

      assert {:error, :server_reclaimed} = Kura.activate_server(reload(server), @image_tag)
      assert reload(server).status == :drain_pending
    end

    test "activation cannot resurrect an archived instance" do
      stub(Provisioner, :public_url, fn _account, _server -> "http://localhost:4100" end)
      stub(Provisioner, :destroy, fn _server -> :ok end)
      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)

      account = account()
      server = active_instance(account)
      start_drain(account, server)
      elapse_drain(account)
      Lifecycle.reconcile()
      assert reload(server).status == :archived

      assert {:error, :server_reclaimed} = Kura.activate_server(reload(server), @image_tag)
      assert reload(server).status == :archived
    end

    test "an observation cannot overwrite a lifecycle state" do
      account = account()
      server = active_instance(account)
      start_drain(account, server)

      assert {:ok, _server} =
               Kura.record_observation(reload(server), %{
                 status: :active,
                 last_observed_at: DateTime.truncate(DateTime.utc_now(), :second)
               })

      assert reload(server).status == :drain_pending
    end

    test "a failure hint cannot overwrite a lifecycle state" do
      account = account()
      server = active_instance(account)
      start_drain(account, server)

      assert {:ok, _server} = Kura.fail_server(reload(server))
      assert reload(server).status == :drain_pending
    end
  end

  describe "keep-warm" do
    test "returns a draining keep-warm instance to service" do
      account = account()
      server = active_instance(account)
      start_drain(account, server)

      {:ok, _} = Demand.set_keep_warm(account.id, @region, true)
      Lifecycle.reconcile()

      assert reload(server).status == :active
    end
  end

  describe "private regions" do
    test "leaves runner-cache nodes to their own identity rule" do
      stub(Environment, :kura_available_region_ids, fn -> ["scw-fr-par-runners"] end)

      account = account()

      server =
        Repo.insert!(%Server{
          account_id: account.id,
          region: "scw-fr-par-runners",
          status: :active,
          url: "http://kura.svc.cluster.local:4000",
          current_image_tag: @image_tag,
          provisioner_node_ref: "kura-#{account.id}-runners"
        })

      {:ok, _} = Demand.upsert(account.id, "scw-fr-par-runners", ago(200))

      assert :ok = Lifecycle.sweep()
      assert :ok = Lifecycle.reconcile()

      assert reload(server).status == :active
    end
  end

  describe "reconcile/0" do
    test "persists buffered demand before reading it, so a just-served account is not read as inactive" do
      account = account()
      server = active_instance(account)
      with_demand(account, 200)

      Demand.record(account.id)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "does not provision with no runtime image tag configured" do
      stub(Environment, :kura_runtime_image_tag, fn -> nil end)

      account = account()
      Demand.record(account.id)

      assert :ok = Lifecycle.reconcile()

      assert servers_for(account) == []
    end

    test "still drains with no runtime image tag configured, so an inactive instance is freed" do
      stub(Environment, :kura_runtime_image_tag, fn -> nil end)

      account = account()
      server = active_instance(account)
      with_demand(account, 91)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :drain_pending
    end

    test "is a no-op when no public region is available" do
      stub(Environment, :kura_available_region_ids, fn -> [] end)

      account = account()
      Demand.record(account.id)

      assert :ok = Lifecycle.reconcile()

      assert servers_for(account) == []
    end
  end

  describe "sweep/0" do
    test "runs the archival decision on its own daily cadence" do
      account = account()
      server = active_instance(account)
      with_demand(account, 91)

      # The reconciler tick does not decide inactivity; the daily sweep does.
      assert :ok = Lifecycle.reconcile()
      assert reload(server).status == :active

      assert :ok = Tuist.Kura.Workers.ArchiveInactiveInstancesWorker.perform(%Oban.Job{})
      assert reload(server).status == :drain_pending
    end
  end

  # `installed_gib/1` sums the allocatable ephemeral storage of a region's
  # Ready nodes, so sizing a region in a test means answering the node list.
  # Answers the pod list with exactly the reservation the fixtures imply, so
  # the region reads as just short of room for a new enterprise instance.
  defp under_pressure do
    stub_region_pods(List.duplicate(reserved_pod(div(@air_resident_gib, @replicas)), @instances_to_pressure * @replicas))
  end

  defp stub_region_pods(pods) do
    stub(Client, :list_pods, fn _namespace, _selector -> {:ok, pods} end)
  end

  defp reserved_pod(gib) do
    %{
      "status" => %{"phase" => "Running"},
      "spec" => %{
        "containers" => [%{"resources" => %{"requests" => %{"ephemeral-storage" => "#{gib}Gi"}}}]
      }
    }
  end

  describe "never-used instances" do
    setup do
      stub(Provisioner, :destroy, fn _server -> :ok end)
      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)
      :ok
    end

    test "drains an instance that has stored nothing since it was created, once the unused window has passed" do
      account = account()
      server = unused_instance(account)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :drain_pending]])

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :drain_pending
      assert_received {[:tuist, :kura, :lifecycle, :drain_pending], ^ref, %{count: 1}, %{reason: "unused"}}
    end

    test "leaves a never-used instance alone inside the unused window" do
      account = account()
      server = active_instance(account, age_hours: 23)
      with_demand(account, 0)
      storage_rollups(account, 0..1)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "drains unused Air after 24 hours without waiting for seven days of demand tracking" do
      account = account()
      server = active_instance(account, age_hours: 25)
      with_demand(account, 0, tracked_for_days: 2)
      storage_rollups(account, 0..2)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :drain_pending
      assert reload_lifecycle(account).drain_reason == :unused
    end

    test "keeps the unused window configurable for Air" do
      stub(Environment, :kura_air_unused_hours, fn -> 48 end)
      account = account()
      server = active_instance(account, age_hours: 25)
      with_demand(account, 0)
      storage_rollups(account, 0..2)

      assert :ok = Lifecycle.sweep()
      assert reload(server).status == :active
    end

    test "still gives newly tracked Air instances their shorter tracking grace" do
      account = account()
      server = active_instance(account, age_days: 8)
      with_demand(account, 0, tracked_for_days: 0)
      storage_rollups(account, 0..8)

      assert :ok = Lifecycle.sweep()
      assert reload(server).status == :active
    end

    test "keeps Pro's seven-day unused window and full tracking grace" do
      recent = account(plan: :pro)
      recent_server = active_instance(recent, age_days: 2)
      with_demand(recent, 0)
      storage_rollups(recent, 0..2)

      newly_tracked = account(plan: :pro)
      newly_tracked_server = active_instance(newly_tracked, age_days: 8)
      with_demand(newly_tracked, 0, tracked_for_days: 2)
      storage_rollups(newly_tracked, 0..8)

      eligible = account(plan: :pro)
      eligible_server = unused_instance(eligible)

      assert :ok = Lifecycle.sweep()
      assert reload(recent_server).status == :active
      assert reload(newly_tracked_server).status == :active
      assert reload(eligible_server).status == :drain_pending
    end

    test "both plans reclaim old instances whose first partial day had no snapshots" do
      for plan <- [:air, :pro] do
        account = account(plan: plan)
        server = active_instance(account, age_days: 30)
        with_demand(account, 0)
        storage_rollups(account, 0..29)

        assert :ok = Lifecycle.sweep()
        assert reload(server).status == :drain_pending
      end
    end

    test "reclaims Air when provisioning crosses midnight without snapshots on either boundary day" do
      freeze_clock(~U[2026-09-22 00:30:00.000000Z])
      account = account()
      server = active_instance(account, age_hours: 25)
      with_demand(account, 0, tracked_for_days: 2)
      storage_rollups(account, [1])

      assert :ok = Lifecycle.sweep()
      assert reload(server).status == :drain_pending
    end

    test "the midnight sweep can reclaim before today's rollup arrives" do
      freeze_clock(~U[2026-09-22 00:00:00.000000Z])
      account = account()
      server = active_instance(account, age_days: 2)
      with_demand(account, 0)
      storage_rollups(account, 1..2)

      assert :ok = Lifecycle.sweep()
      assert reload(server).status == :drain_pending
    end

    test "a single snapshot cannot establish that a 25-hour Air instance stayed unused" do
      account = account()
      server = active_instance(account, age_hours: 25)
      with_demand(account, 0)
      storage_rollups(account, [0], snapshot_count: 1)

      assert :ok = Lifecycle.sweep()
      assert reload(server).status == :active
    end

    test "coverage counts the expected snapshots from every replica" do
      account = account()
      server = active_instance(account, age_days: 2)
      with_demand(account, 0)
      storage_rollups(account, 0..2, snapshot_count: 96)

      assert :ok = Lifecycle.sweep()
      assert reload(server).status == :active
    end

    test "excess samples on one day cannot compensate for thin coverage on another" do
      account = account()
      server = active_instance(account, age_days: 2)
      with_demand(account, 0)
      storage_rollups(account, [2], snapshot_count: 1000)
      storage_rollups(account, [1], snapshot_count: 1)
      storage_rollups(account, [0])

      assert :ok = Lifecycle.sweep()
      assert reload(server).status == :active
    end

    test "a missing full day vetoes otherwise sufficient snapshot counts" do
      account = account()
      server = active_instance(account, age_days: 30)
      with_demand(account, 0)
      storage_rollups(account, Enum.reject(0..30, &(&1 == 12)))

      assert :ok = Lifecycle.sweep()
      assert reload(server).status == :active
    end

    test "leaves an instance alone once it has stored bytes" do
      account = account()
      server = active_instance(account, age_days: 30)
      with_demand(account, 1)
      storage_rollups(account, Enum.reject(0..30, &(&1 == 12)))
      storage_rollups(account, [12], max_live_segment_bytes: @gib, max_occupancy_percent: 20)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "leaves an instance alone when it has no storage telemetry" do
      account = account()
      server = active_instance(account, age_days: 8)
      with_demand(account, 1)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "leaves an instance alone when its telemetry starts after it was created" do
      account = account()
      server = active_instance(account, age_days: 30)
      with_demand(account, 1)
      storage_rollups(account, 0..10)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "leaves an instance alone when its telemetry has stopped arriving" do
      account = account()
      server = active_instance(account, age_days: 10)
      with_demand(account, 1)
      storage_rollups(account, 4..10)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "leaves an instance alone when its telemetry has a gap" do
      account = account()
      server = active_instance(account, age_days: 8)
      with_demand(account, 1)
      storage_rollups(account, [0, 1, 2, 6, 7, 8])

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "leaves an instance alone once it has evicted content" do
      account = account()
      server = active_instance(account, age_days: 8)
      with_demand(account, 1)
      storage_rollups(account, Enum.reject(0..8, &(&1 == 3)))
      storage_rollups(account, [3], eviction_count: 2, evicted_bytes: @gib, evicted_artifact_count: 10)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "measures the window from the instance's return from archive" do
      account = account()
      server = active_instance(account, age_days: 30)

      account
      |> with_demand(1)
      |> Ecto.Changeset.change(%{
        last_returned_at: DateTime.truncate(DateTime.add(DateTime.utc_now(), -23, :hour), :second)
      })
      |> Repo.update!()

      storage_rollups(account, 0..30)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "reclaims an unused Air return after its new 24-hour window" do
      account = account()
      server = active_instance(account, age_days: 30)

      account
      |> with_demand(0)
      |> Ecto.Changeset.change(%{
        last_returned_at: DateTime.truncate(DateTime.add(DateTime.utc_now(), -25, :hour), :second)
      })
      |> Repo.update!()

      storage_rollups(account, 0..2)
      storage_rollups(account, [20], max_live_segment_bytes: @gib)

      assert :ok = Lifecycle.sweep()
      assert reload(server).status == :drain_pending
      assert reload_lifecycle(account).drain_reason == :unused
    end

    test "never drains a keep-warm or Enterprise instance for going unused" do
      keep_warm = account()
      keep_warm_server = unused_instance(keep_warm)
      {:ok, _} = Demand.set_keep_warm(keep_warm.id, @region, true)

      enterprise = account(plan: :enterprise, region: :usa)
      enterprise_server = unused_instance(enterprise)

      assert :ok = Lifecycle.sweep()

      assert reload(keep_warm_server).status == :active
      assert reload(enterprise_server).status == :active
    end

    test "never considers an instance with no lifecycle row" do
      account = account()
      server = active_instance(account, age_days: 8)
      storage_rollups(account, 0..8)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :active
    end

    test "archives a draining never-used instance even when the account asks for its cache mid-drain" do
      account = account()
      server = unused_instance(account)
      assert :ok = Lifecycle.sweep()
      assert reload(server).status == :drain_pending

      elapse_drain(account)
      Demand.record(account.id)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :archived]])

      assert :ok = Lifecycle.reconcile()

      assert reload(server).status == :archived
      assert_received {[:tuist, :kura, :lifecycle, :archived], ^ref, %{count: 1}, %{reason: "unused"}}
    end

    test "does not return an archived never-used instance on the demand it already had" do
      account = account()
      server = archive_unused(account)

      assert :ok = Lifecycle.reconcile()

      assert reload(server).status == :archived
    end

    test "returns an archived never-used instance when the account asks for its cache" do
      account = account()
      server = archive_unused(account)

      Demand.record(account.id)
      assert :ok = Lifecycle.reconcile()

      assert reload(server).status == :provisioning
    end

    defp freeze_clock(now) do
      stub(DateTime, :utc_now, fn -> now end)
      stub(Date, :utc_today, fn -> DateTime.to_date(now) end)
    end

    defp unused_instance(account) do
      server = active_instance(account, age_days: 8)
      with_demand(account, 1)
      storage_rollups(account, 0..8)
      server
    end

    defp archive_unused(account) do
      server = unused_instance(account)
      assert :ok = Lifecycle.sweep()
      elapse_drain(account)
      assert :ok = Lifecycle.reconcile()
      assert reload(server).status == :archived

      account
      |> reload_lifecycle()
      |> Ecto.Changeset.change(%{archived_at: DateTime.truncate(DateTime.add(DateTime.utc_now(), -60, :second), :second)})
      |> Repo.update!()

      server
    end

    defp storage_rollups(account, days_ago, attrs \\ []) do
      for days <- days_ago do
        StorageRollup
        |> struct!(
          Keyword.merge(
            [
              account_id: account.id,
              region: @region,
              date: Date.add(Date.utc_today(), -days),
              snapshot_count: 96 * @replicas,
              max_occupancy_percent: 0,
              max_live_segment_bytes: 0
            ],
            attrs
          )
        )
        |> Repo.insert!()
      end
    end
  end

  describe "placement retirements" do
    setup do
      stub(Provisioner, :destroy, fn _server -> :ok end)
      :ok
    end

    test "the reconciler tick drains a region placement is leaving" do
      # On the reconciler's cadence rather than the archival sweep's: what it
      # waits for is the destination coming up, which happens on that cadence.
      account = account(plan: :enterprise)
      source = active_instance(account)
      _destination = active_instance_in(account, "eu-west")
      with_demand(account, 0)
      {:ok, _held} = PlacerRegions.put_primary(account, @region)
      {:ok, _primary} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _retiring} = PlacerRegions.mark_retiring(account, @region)

      Lifecycle.reconcile()

      assert reload(source).status == :drain_pending
    end

    test "drains a region placement is leaving once somewhere else is serving" do
      account = account(plan: :enterprise)
      source = active_instance(account)
      destination = active_instance_in(account, "eu-west")
      with_demand(account, 0)
      {:ok, _held} = PlacerRegions.put_primary(account, @region)
      {:ok, _primary} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _retiring} = PlacerRegions.mark_retiring(account, @region)

      Lifecycle.reconcile_placement_retirements()

      assert reload(source).status == :drain_pending
      assert reload(destination).status == :active
    end

    test "stable rollout waits for the survivor to advertise before retiring" do
      stub(Environment, :kura_stable_hostname_enabled?, fn -> true end)
      stub(Environment, :kura_stable_hostname_accounts, fn -> [] end)
      account = account(plan: :enterprise)
      source = active_instance(account)
      destination = active_instance_in(account, "eu-west")
      with_demand(account, 0)
      {:ok, _} = PlacerRegions.put_primary(account, @region)
      {:ok, _} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _} = PlacerRegions.mark_retiring(account, @region)

      Lifecycle.reconcile_placement_retirements()
      assert reload(source).status == :active

      host = StableEndpoint.host(account)

      StableEndpoint.observe(destination.region, destination.provisioner_node_ref, %{
        "metadata" => %{"generation" => 1},
        "spec" => %{"stableHost" => host, "stableAdvertise" => true},
        "status" => %{
          "stableEndpoint" => %{
            "host" => host,
            "ready" => true,
            "observedGeneration" => 1,
            "lastCheckedAt" => DateTime.to_iso8601(DateTime.utc_now())
          }
        }
      })

      Lifecycle.reconcile_placement_retirements()
      assert reload(source).status == :drain_pending
      assert reload(destination).status == :active
    end

    test "skips a retiring region the catalog does not name" do
      # The rows can name a region this code has never heard of for the length
      # of a deploy that renames one. The instance there is still serving, and
      # a drain scheduled now would outlive the window that made it look wrong.
      account = account(plan: :enterprise)
      source = active_instance_in(account, "atlantis")
      destination = active_instance_in(account, "eu-west")
      with_demand(account, 0)
      {:ok, _held} = PlacerRegions.put_primary(account, "atlantis")
      {:ok, _primary} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _retiring} = PlacerRegions.mark_retiring(account, "atlantis")

      Lifecycle.reconcile_placement_retirements()

      assert reload(source).status == :active
      assert reload(destination).status == :active
    end

    test "does not count a private runner cache as somewhere else serving" do
      # A runner cache is in-cluster and never CLI-facing. Draining against it
      # would take the account's only developer-facing cache away and leave
      # every machine on the fallback lane.
      account = account(plan: :enterprise)
      source = active_instance(account)
      _runner_cache = active_instance_in(account, "scw-fr-par-runners")
      with_demand(account, 0)
      {:ok, _held} = PlacerRegions.put_primary(account, @region)
      {:ok, _primary} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _retiring} = PlacerRegions.mark_retiring(account, @region)

      Lifecycle.reconcile_placement_retirements()

      assert reload(source).status == :active
    end

    test "carries a retirement through for a region that never had a demand row" do
      # The drain resolution reaches an instance by joining its lifecycle row,
      # so one without a row would go into drain-pending and never be looked at
      # again — holding its volume and its slot forever.
      account = account(plan: :enterprise)
      source = active_instance(account)
      _destination = active_instance_in(account, "eu-west")
      {:ok, _held} = PlacerRegions.put_primary(account, @region)
      {:ok, _primary} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _retiring} = PlacerRegions.mark_retiring(account, @region)

      refute reload_lifecycle(account)

      Lifecycle.reconcile_placement_retirements()

      assert reload(source).status == :drain_pending
      assert reload_lifecycle(account)

      rewind_drain(account, Kura.placement_drain_seconds() + 60)
      Lifecycle.reconcile()

      assert reload_lifecycle(account).teardown_started_at
    end

    test "waits while the account is served from nowhere else" do
      # Taking the only instance would be an outage rather than a move. The
      # destination is provisioned by the ordinary demand path first.
      account = account(plan: :enterprise)
      source = active_instance(account)
      with_demand(account, 0)
      {:ok, _held} = PlacerRegions.put_primary(account, @region)
      {:ok, _primary} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _retiring} = PlacerRegions.mark_retiring(account, @region)

      Lifecycle.reconcile_placement_retirements()

      assert reload(source).status == :active
    end

    test "waits while the destination is still coming up" do
      account = account(plan: :enterprise)
      source = active_instance(account)
      destination = active_instance_in(account, "eu-west")
      {:ok, _provisioning} = Kura.record_observation(destination, %{status: :replicating, current_image_tag: @image_tag})
      with_demand(account, 0)
      {:ok, _held} = PlacerRegions.put_primary(account, @region)
      {:ok, _primary} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _retiring} = PlacerRegions.mark_retiring(account, @region)

      Lifecycle.reconcile_placement_retirements()

      assert reload(source).status == :active
    end

    test "carries an Enterprise retirement through rather than cancelling it" do
      # Enterprise is never archived for inactivity, so the drain resolution
      # cancels any drain it finds on one. A placement retirement is not that
      # drain: it left this region because its traffic no longer earns a slot
      # here, which the inactivity rules get no say in.
      account = account(plan: :enterprise)
      source = active_instance(account)
      _destination = active_instance_in(account, "eu-west")
      with_demand(account, 0)
      {:ok, _held} = PlacerRegions.put_primary(account, @region)
      {:ok, _primary} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _retiring} = PlacerRegions.mark_retiring(account, @region)

      Lifecycle.reconcile_placement_retirements()
      assert reload(source).status == :drain_pending

      Lifecycle.reconcile()

      assert reload(source).status == :drain_pending
      assert reload_lifecycle(account).drain_started_at
    end

    test "keeps a retired instance serving until every cached endpoint answer has expired" do
      # Unpublishing stops new resolutions returning it, but a client that
      # resolved an hour ago still holds it and keeps building against it. A
      # relocation happens while the account is building, so the ordinary
      # margin would tear the instance down under live builds.
      account = account(plan: :enterprise)
      source = active_instance(account)
      _destination = active_instance_in(account, "eu-west")
      with_demand(account, 0)
      {:ok, _held} = PlacerRegions.put_primary(account, @region)
      {:ok, _primary} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _retiring} = PlacerRegions.mark_retiring(account, @region)

      Lifecycle.reconcile_placement_retirements()
      # Past the ordinary drain, still inside the endpoint's freshness.
      rewind_drain(account, Kura.drain_seconds() + 60)

      Lifecycle.reconcile()

      refute reload_lifecycle(account).teardown_started_at
      assert reload(source).status == :drain_pending
    end

    test "tears the retired instance down once its drain window has elapsed" do
      account = account(plan: :enterprise)
      _source = active_instance(account)
      _destination = active_instance_in(account, "eu-west")
      with_demand(account, 0)
      {:ok, _held} = PlacerRegions.put_primary(account, @region)
      {:ok, _primary} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _retiring} = PlacerRegions.mark_retiring(account, @region)

      Lifecycle.reconcile_placement_retirements()
      rewind_drain(account, Kura.placement_drain_seconds() + 60)

      Lifecycle.reconcile()

      assert reload_lifecycle(account).teardown_started_at
    end

    test "drops the placement row once the instance is gone, freeing the region" do
      account = account(plan: :enterprise)
      _destination = active_instance_in(account, "eu-west")
      {:ok, _held} = PlacerRegions.put_primary(account, @region)
      {:ok, _primary} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _retiring} = PlacerRegions.mark_retiring(account, @region)

      Lifecycle.reconcile_placement_retirements()

      assert PlacerRegions.claimed_regions(account) == ["eu-west"]
    end
  end

  describe "provisioning on request" do
    setup do
      stub(Provisioner, :destroy, fn _server -> :ok end)
      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)
      :ok
    end

    defp archived(account) do
      server = active_instance(account)
      start_drain(account, server)
      elapse_drain(account)
      Lifecycle.reconcile()
      assert reload(server).status == :archived
      server
    end

    test "returns the asking account's archived instance without waiting for the demand buffer or the reconciler tick" do
      account = account()
      server = archived(account)
      requested_at = DateTime.utc_now()

      assert {:ok, [%Server{id: id, status: :provisioning}]} = Lifecycle.provision_account(account.id, requested_at)

      assert id == server.id
      lifecycle = reload_lifecycle(account)
      assert lifecycle.last_returned_at
      assert lifecycle.last_cache_demand_at == DateTime.truncate(requested_at, :second)
      assert Repo.exists?(from(d in Deployment, where: d.kura_server_id == ^server.id and d.status == :pending))
    end

    test "provisions an account that has never had an instance" do
      account = account()

      assert {:ok, [%Server{status: :provisioning}]} = Lifecycle.provision_account(account.id, DateTime.utc_now())
    end

    test "hands back an instance that is already coming up, so its activation can be awaited" do
      account = account()
      {:ok, [server]} = Lifecycle.provision_account(account.id, DateTime.utc_now())

      assert {:ok, [%Server{id: id}]} = Lifecycle.provision_account(account.id, DateTime.utc_now())
      assert id == server.id
      assert [_server] = servers_for(account)
    end

    test "leaves every other account to the reconciler tick" do
      other = account()
      other_server = archived(other)
      account = account()
      archived(account)
      Demand.record(other.id)

      assert {:ok, [_server]} = Lifecycle.provision_account(account.id, DateTime.utc_now())

      assert reload(other_server).status == :archived
    end

    test "places a first instance near the request that asked for it, whichever node provisions it" do
      # The request is recorded on the node that served it, and the job that
      # provisions the instance can run on any node, where nothing that node
      # buffered is visible.
      stub(Environment, :kura_available_region_ids, fn -> [@region, "eu-west"] end)
      stub(Environment, :kura_control_plane?, fn -> true end)
      stub(Reconciler, :reconcile_server, fn _server -> :ok end)
      account = account()

      Accounts.get_cache_resolution_for_handle(account.name, :kura, {:ok, "DE"})
      assert [%Oban.Job{args: args}] = all_enqueued(worker: ProvisionOnDemandWorker)
      :ets.delete_all_objects(Tuist.Kura.Origins)
      :ets.delete_all_objects(Demand)

      assert :ok = perform_job(ProvisionOnDemandWorker, args)

      assert [%Server{region: "eu-west", status: :provisioning}] = servers_for(account)
    end

    test "provisions nothing with no runtime image tag configured" do
      stub(Environment, :kura_runtime_image_tag, fn -> nil end)
      account = account()

      assert {:ok, []} = Lifecycle.provision_account(account.id, DateTime.utc_now())
      assert servers_for(account) == []
    end
  end

  describe "provisioning across the regions placement chose" do
    test "provisions every region the account is served from, not just the primary" do
      stub(Environment, :kura_available_region_ids, fn -> [@region, "eu-west"] end)
      stub_region_nodes([{@region, [@node_allocatable_bytes]}, {"eu-west", [@node_allocatable_bytes]}])

      account = account(plan: :enterprise)
      {:ok, _primary} = PlacerRegions.put_primary(account, @region)
      {:ok, _secondary} = PlacerRegions.put_secondary(account, "eu-west")
      with_demand(account, 0)
      {:ok, _} = Demand.upsert(account.id, "eu-west", ago(0))

      Lifecycle.reconcile()

      assert account |> servers_for() |> Enum.map(& &1.region) |> Enum.sort() == ["eu-west", @region]
    end

    test "does not provision a region placement has left" do
      # A retiring region keeps its lifecycle row until the drain finishes, and
      # provisioning from it would rebuild exactly what the retirement removes.
      account = account(plan: :enterprise)
      {:ok, _held} = PlacerRegions.put_primary(account, @region)
      {:ok, _primary} = PlacerRegions.put_primary(account, "eu-west")
      {:ok, _retiring} = PlacerRegions.mark_retiring(account, @region)
      with_demand(account, 0)

      Lifecycle.reconcile()

      assert servers_for(account) == []
    end
  end

  # Rewinds the drain clock by an arbitrary number of seconds, for the windows
  # that are not the ordinary one.
  defp rewind_drain(account, seconds) do
    started_at =
      DateTime.utc_now()
      |> DateTime.add(-seconds, :second)
      |> DateTime.truncate(:second)

    account
    |> reload_lifecycle()
    |> Ecto.Changeset.change(%{drain_started_at: started_at})
    |> Repo.update!()
  end

  defp active_instance_in(account, region) do
    Repo.insert!(%Server{
      account_id: account.id,
      region: region,
      status: :active,
      url: "https://#{account.name}-#{region}-1.kura.tuist.dev",
      current_image_tag: @image_tag,
      provisioner_node_ref: "kura-#{account.id}-#{region}",
      storage_claim_size: "8Gi"
    })
  end

  defp stub_region_nodes(nodes_by_region) do
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
    stub_region_pods([])

    stub(Client, :list_nodes, fn selector ->
      allocatable =
        Enum.find_value(nodes_by_region, [], fn {region_id, allocatable} ->
          {:ok, region} = Regions.fetch(region_id)
          if selector == Regions.node_label_selector(region), do: allocatable
        end)

      {:ok, %{"items" => Enum.map(allocatable, &ready_node/1)}}
    end)
  end

  defp ready_node(allocatable_bytes) do
    %{
      "status" => %{
        "conditions" => [%{"type" => "Ready", "status" => "True"}],
        "allocatable" => %{"ephemeral-storage" => Integer.to_string(allocatable_bytes)}
      }
    }
  end
end
