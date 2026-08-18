defmodule Tuist.Kura.LifecycleTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Lifecycle
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  @region "us-east"
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
    stub(Environment, :kura_available_region_ids, fn -> [@region] end)
    stub(Environment, :kura_runtime_image_tag, fn -> @image_tag end)
    stub(Environment, :kura_region_machines, fn _ -> nil end)
    stub(FunWithFlags, :enabled?, fn :kura_archival, [for: _account] -> true end)

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

  defp active_instance(account, opts \\ []) do
    inserted_at = ago_usec(Keyword.get(opts, :age_days, 120))

    %Server{
      account_id: account.id,
      region: @region,
      status: :active,
      url: "https://#{account.name}-us-east-1.kura.tuist.dev",
      current_image_tag: @image_tag,
      provisioner_node_ref: "kura-#{account.id}-us-east"
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

    test "leaves an account on authoritative object storage when the region has no safe slot" do
      stub(Environment, :kura_region_machines, fn @region -> 1 end)

      # Fill the single machine's usable filesystem with Air instances.
      for _ <- 1..47, do: active_instance(account())

      account = account()
      Demand.record(account.id)

      assert :ok = Lifecycle.reconcile()

      assert servers_for(account) == []
    end

    test "emits a capacity event when provisioning is refused" do
      stub(Environment, :kura_region_machines, fn @region -> 1 end)
      for _ <- 1..47, do: active_instance(account())

      account = account()
      Demand.record(account.id)

      ref = :telemetry_test.attach_event_handlers(self(), [[:tuist, :kura, :lifecycle, :capacity_refused]])

      Lifecycle.reconcile()

      assert_received {[:tuist, :kura, :lifecycle, :capacity_refused], ^ref, measurements, metadata}
      assert measurements.forecast_gib > measurements.installed_gib
      assert metadata.region == @region
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

    test "does not archive when the flag is off for the account" do
      stub(FunWithFlags, :enabled?, fn :kura_archival, [for: _account] -> false end)

      account = account()
      server = active_instance(account)
      with_demand(account, 200)

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

    test "keeps provisioning while archival is disabled" do
      stub(FunWithFlags, :enabled?, fn :kura_archival, [for: _account] -> false end)

      account = account()
      Demand.record(account.id)

      assert :ok = Lifecycle.reconcile()

      assert [%Server{status: :provisioning}] = servers_for(account)
    end
  end

  describe "Air capacity pressure" do
    setup do
      stub(Environment, :kura_region_machines, fn @region -> 1 end)
      :ok
    end

    test "drains Air at 60 days only while the region is over capacity" do
      # 47 Air instances is 1128 GiB against 1105 GiB installed.
      pressured =
        for _ <- 1..47 do
          account = account()
          server = active_instance(account)
          with_demand(account, 61)
          {account, server}
        end

      assert :ok = Lifecycle.sweep()

      drained = Enum.count(pressured, fn {_a, server} -> reload(server).status == :drain_pending end)

      # Only as many as it takes to fit: one 24 GiB Air instance brings 1128
      # back under 1105.
      assert drained == 1
    end

    test "preserves the 90-day target when there is room" do
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

      for _ <- 1..45 do
        filler = account()
        active_instance(filler)
        with_demand(filler, 10)
      end

      assert :ok = Lifecycle.sweep()

      assert reload(coldest_server).status == :drain_pending
      assert reload(recent_server).status == :active
    end

    test "never pressures a paid plan below its 90-day window" do
      for _ <- 1..47 do
        account = account()
        active_instance(account)
        with_demand(account, 10)
      end

      pro = account(plan: :pro, region: :usa)
      server = active_instance(pro)
      with_demand(pro, 61)

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

    test "returns a draining instance to service when archival is disabled mid-drain" do
      account = account()
      server = active_instance(account)
      start_drain(account, server)

      # The incident rollback has to reach a drain already in flight: the sweep
      # selected this instance minutes before teardown is due.
      stub(FunWithFlags, :enabled?, fn :kura_archival, [for: _account] -> false end)

      assert :ok = Lifecycle.reconcile()

      assert reload(server).status == :active
      assert reload_lifecycle(account).drain_started_at == nil
      reject(&Provisioner.destroy/1)
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
      assert lifecycle.last_reclaimed_bytes == 24 * @gib
      assert lifecycle.last_drain_duration_ms >= Kura.drain_seconds() * 1000
    end

    test "records the paid plan's larger reclaimed quota" do
      stub(Provisioner, :current_image_tag, fn _server -> {:error, :not_found} end)

      account = account(plan: :pro, region: :usa)
      server = active_instance(account)
      start_drain(account, server)
      elapse_drain(account)

      Lifecycle.reconcile()

      assert reload_lifecycle(account).last_reclaimed_bytes == 50 * @gib
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
      assert measurements.reclaimed_bytes == 24 * @gib
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
end
