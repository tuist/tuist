defmodule Tuist.Kura.LifecycleTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Lifecycle
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
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
  @pro_resident_gib 30 * @replicas
  # One more instance than fits under the region's pressure line, derived
  # rather than counted out so the fixtures track the real sizing.
  @instances_to_pressure div(trunc(@node_allocatable_bytes * 0.85 / (1024 * 1024 * 1024)), @air_resident_gib) + 1
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
    inserted_at = ago_usec(Keyword.get(opts, :age_days, 120))
    %{claim_size: claim_size} = Regions.storage_profile(AccountPolicies.sizing_plan(account))

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
    test "drains an instance after a complete inactive window and unpublishes its endpoint" do
      account = account()
      server = active_instance(account)
      Repo.insert!(%AccountCacheEndpoint{account_id: account.id, url: server.url, technology: :kura})
      with_demand(account, 91)

      assert :ok = Lifecycle.sweep()

      assert reload(server).status == :drain_pending
      assert Repo.aggregate(from(e in AccountCacheEndpoint, where: e.account_id == ^account.id), :count) == 0
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
      stub_region_nodes([{@region, List.duplicate(@node_allocatable_bytes, 1)}])
      :ok
    end

    test "drains Air at 60 days only while the region is over its pressure line" do
      pressured =
        for _ <- 1..@instances_to_pressure do
          account = account()
          server = active_instance(account)
          with_demand(account, 61)
          {account, server}
        end

      over_pressure_line()

      assert :ok = Lifecycle.sweep()

      drained = Enum.count(pressured, fn {_a, server} -> reload(server).status == :drain_pending end)

      # Only as many as it takes to fit: the region is one instance past its
      # line, so reclaiming one brings it back under.
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

      over_pressure_line()

      assert :ok = Lifecycle.sweep()

      assert reload(coldest_server).status == :drain_pending
      assert reload(recent_server).status == :active
    end

    test "counts what each unconditional archival actually frees" do
      # A Pro instance past the full window is archived regardless, and it frees
      # its own 60Gi rather than an Air instance's 48Gi. The region lands exactly
      # on its line once that room is counted, so no Air instance is pressured.
      # Counted at a uniform per-instance figure it would land 12Gi over and take
      # one.
      pro = account(plan: :pro, region: :usa)
      pro_server = active_instance(pro)
      with_demand(pro, 200)

      air =
        for _ <- 1..3 do
          account = account()
          server = active_instance(account)
          with_demand(account, 61)
          server
        end

      # 730Gi reserved against a 670Gi line: 60Gi over, exactly what the Pro
      # instance holds across its two replicas.
      stub_region_pods(List.duplicate(reserved_pod(10), 73))

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

      over_pressure_line()

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

    test "republishes the cache endpoint the drain unpublished" do
      account = account()
      server = active_instance(account)
      Repo.insert!(%AccountCacheEndpoint{account_id: account.id, url: server.url, technology: :kura})
      start_drain(account, server)

      Demand.record(account.id)
      Lifecycle.reconcile()

      assert [%AccountCacheEndpoint{url: url}] =
               Repo.all(from(e in AccountCacheEndpoint, where: e.account_id == ^account.id))

      assert url == server.url
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
      server = active_instance(account)
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
        region: "eu-central",
        status: :active,
        url: "https://peer.example.com",
        current_image_tag: @image_tag,
        provisioner_node_ref: "kura-#{account.id}-eu-central"
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
  # the region reads as one instance past its pressure line.
  defp over_pressure_line do
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
