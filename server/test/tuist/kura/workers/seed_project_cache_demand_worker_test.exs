defmodule Tuist.Kura.Workers.SeedProjectCacheDemandWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Lifecycle
  alias Tuist.Kura.PlacerRegion
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.Telemetry
  alias Tuist.Kura.Workers.SeedProjectCacheDemandWorker
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  @region "us-east"
  @node_allocatable_bytes 847_551_469_804
  @image_tag "0.5.2"

  # Same shape as the lifecycle tests: drive the region catalog to the real
  # managed `us-east` rather than the dev-only local controller, so seeding
  # resolves through the service regions production resolves through.
  setup do
    stub(Environment, :env, fn -> :prod end)
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :kura_available_region_ids, fn -> [@region] end)
    stub(Environment, :kura_runtime_image_tag, fn -> @image_tag end)
    stub_region_nodes([])
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

  defp seed(account) do
    perform_job(SeedProjectCacheDemandWorker, %{"account_id" => account.id})
  end

  defp servers_for(account) do
    Repo.all(from(s in Server, where: s.account_id == ^account.id))
  end

  defp ago(days), do: DateTime.truncate(ago_usec(days), :second)
  defp ago_usec(days), do: DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

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

  describe "seeding demand" do
    test "records demand for an account with no instance, and the reconciler provisions it" do
      account = account()

      assert :ok = seed(account)

      assert %{service_region: @region} = Demand.get(account.id, @region)

      assert :ok = Lifecycle.reconcile()
      assert [%Server{status: :provisioning, region: @region}] = servers_for(account)
    end

    test "records demand for a paid account in the region it resolves to" do
      account = account(plan: :pro, region: :usa)

      assert :ok = seed(account)

      {:ok, %{service_region: region}} = AccountPolicies.resolve(account)
      assert %{} = Demand.get(account.id, region)
    end

    test "does nothing for an account that already has a live instance" do
      account = account()
      {:ok, _} = Demand.upsert(account.id, @region, ago(30))
      assert :ok = Lifecycle.reconcile()
      assert [%Server{}] = servers_for(account)

      before = Demand.get(account.id, @region)

      assert :ok = seed(account)

      assert Demand.get(account.id, @region).last_cache_demand_at == before.last_cache_demand_at
    end

    test "does nothing for an account whose plan resolves to no service region" do
      account = account(plan: :open_source)

      assert :ok = seed(account)

      assert Repo.aggregate(from(l in Tuist.Kura.AccountRegionLifecycle, where: l.account_id == ^account.id), :count) ==
               0
    end

    test "does nothing for an account that no longer exists" do
      assert :ok = perform_job(SeedProjectCacheDemandWorker, %{"account_id" => 0})
    end
  end

  describe "capacity" do
    test "declines to seed into a region over its pressure line, and records the refusal" do
      stub_region_nodes([{@region, [@node_allocatable_bytes]}])
      stub_region_pods(List.duplicate(reserved_pod(50), 100))

      account = account()

      handler = attach_seed_declined_handler()

      assert :ok = seed(account)

      assert Demand.get(account.id, @region) == nil
      assert_receive {^handler, %{count: 1}, %{region: @region, reason: "capacity_pressure"}}
    end

    test "creates the project anyway when the region it resolves to has no room" do
      stub_region_nodes([{@region, [@node_allocatable_bytes]}])
      stub_region_pods(List.duplicate(reserved_pod(50), 100))

      account = account()

      assert {:ok, _project} = Projects.create_project(%{name: "demo", account: %{id: account.id}})

      assert :ok = seed(account)
      assert Demand.get(account.id, @region) == nil
    end

    test "seeds while the region is under its pressure line" do
      stub_region_nodes([{@region, [@node_allocatable_bytes]}])
      stub_region_pods([reserved_pod(50)])

      account = account()

      assert :ok = seed(account)

      assert %{} = Demand.get(account.id, @region)
    end
  end

  describe "what the seeded instance must not trigger" do
    test "is not archived while it is younger than a full inactive window" do
      account = account()
      assert :ok = seed(account)
      assert :ok = Lifecycle.reconcile()

      [server] = servers_for(account)
      # Well past any probation-length window, and past the demand-tracking
      # grace period, but nowhere near the inactive window the identity rule
      # measures. An instance seeded here has moved no bytes by construction,
      # so a rule keyed on that would take it here.
      age_to(server, Demand.get(account.id, @region), 20)

      assert :ok = Lifecycle.sweep()

      assert [%Server{status: :active}] = servers_for(account)
    end

    test "is archived once it has gone a full inactive window without demand" do
      account = account()
      assert :ok = seed(account)
      assert :ok = Lifecycle.reconcile()

      [server] = servers_for(account)
      age_to(server, Demand.get(account.id, @region), Environment.kura_inactive_days() + 10)

      assert :ok = Lifecycle.sweep()

      assert [%Server{status: :drain_pending}] = servers_for(account)
    end

    test "leaves placement undecided so the first-placement guess stays correctable" do
      account = account()

      assert :ok = seed(account)
      assert :ok = Lifecycle.reconcile()

      assert Repo.all(from(p in PlacerRegion, where: p.account_id == ^account.id)) == []
    end
  end

  defp age_to(server, lifecycle, days) do
    server
    |> Ecto.Changeset.change(%{status: :active, inserted_at: ago_usec(days), updated_at: ago_usec(days)})
    |> Repo.update!()

    lifecycle
    |> Ecto.Changeset.change(%{inserted_at: ago(days), updated_at: ago(days), last_cache_demand_at: ago(days)})
    |> Repo.update!()
  end

  defp attach_seed_declined_handler do
    handler = make_ref()
    test = self()

    :telemetry.attach(
      handler,
      Telemetry.event_name_seed_declined(),
      fn _event, measurements, metadata, _config ->
        send(test, {handler, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    handler
  end
end
