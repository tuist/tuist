defmodule Tuist.Sandboxes.AmpReconcilerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client
  alias Tuist.Repo
  alias Tuist.Sandboxes.AmpIntegration
  alias Tuist.Sandboxes.AmpIntegrations
  alias Tuist.Sandboxes.AmpReconciler
  alias Tuist.Sandboxes.AmpRuntime
  alias Tuist.Sandboxes.Nodes
  alias TuistTestSupport.Fixtures.SandboxesFixtures

  setup do
    user = user_fixture()
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> true end)
    {:ok, integration} = AmpIntegrations.connect(user.account.id, user, "aop_live_#{Ecto.UUID.generate()}")

    %{
      integration: integration,
      user: user,
      config: %{namespace: "amp", image: "image:1", url: "https://tuist.example", node_selector: %{}}
    }
  end

  test "reconciliation can be repeated and records only observed readiness", %{integration: integration, config: config} do
    stub(Client, :get, fn path, _ ->
      if String.contains?(path, "serviceaccounts?") do
        {:ok, %{"items" => []}}
      else
        {:ok, %{"metadata" => %{"generation" => 3}, "status" => %{"observedGeneration" => 3, "readyReplicas" => 1}}}
      end
    end)

    expect(Client, :apply, 6, fn _ -> {:ok, %{}} end)
    assert :ok = AmpReconciler.reconcile(integration.account_id, config)
    assert :ok = AmpReconciler.reconcile(integration.account_id, config)
    assert %{status: :running, last_checked_at: %DateTime{}} = Repo.get!(AmpIntegration, integration.id)
  end

  test "a partial Kubernetes write remains retryable without exposing diagnostics", %{
    integration: integration,
    config: config
  } do
    stub(Client, :get, fn _, _ -> {:ok, %{"items" => []}} end)
    expect(Client, :apply, fn %{"kind" => "ServiceAccount"} -> {:ok, %{}} end)
    expect(Client, :apply, fn %{"kind" => "Secret"} -> {:error, "private provider diagnostic"} end)
    assert :ok = AmpReconciler.reconcile(integration.account_id, config)
    assert %{status: :error, enabled: true} = Repo.get!(AmpIntegration, integration.id)
    refute inspect(AmpIntegrations.public_status(Repo.get!(AmpIntegration, integration.id))) =~ "private"
  end

  test "rotation removes the old workload before provisioning its successor", %{
    integration: first,
    user: user,
    config: config
  } do
    {:ok, current} = AmpIntegrations.connect(user.account.id, user, "aop_live_new_revision")
    old_name = AmpRuntime.name(first)

    stub(Client, :get, fn path, _ ->
      if String.contains?(path, "serviceaccounts?") do
        {:ok, %{"items" => [%{"metadata" => %{"name" => old_name}}]}}
      else
        {:ok, %{"items" => []}}
      end
    end)

    expect(Client, :delete, 3, fn path ->
      assert String.ends_with?(path, old_name)
      :ok
    end)

    expect(Client, :apply, 3, fn manifest ->
      assert manifest["metadata"]["name"] == AmpRuntime.name(current)
      {:ok, %{}}
    end)

    assert :ok = AmpReconciler.reconcile(first.account_id, config)
    assert Repo.get!(AmpIntegration, first.id).status == :pending
  end

  test "disconnect never provisions and tolerates already removed resources", %{
    integration: integration,
    user: user,
    config: config
  } do
    {:ok, _} = AmpIntegrations.disconnect(user.account.id, user)

    stub(Client, :get, fn path, _ ->
      if String.contains?(path, "serviceaccounts?") do
        {:ok, %{"items" => [%{"metadata" => %{"name" => AmpRuntime.name(integration)}}]}}
      else
        {:ok, %{"items" => []}}
      end
    end)

    expect(Client, :delete, 3, fn _ -> {:error, :not_found} end)
    reject(&Client.apply/1)
    assert :ok = AmpReconciler.reconcile(integration.account_id, config)
    assert %{status: :disconnected, provider_token: nil} = Repo.get!(AmpIntegration, integration.id)
  end

  test "disconnect preserves residency until the node confirms pause", %{
    integration: integration,
    user: user,
    config: config
  } do
    sandbox =
      SandboxesFixtures.sandbox_fixture(
        account: user.account,
        amp_orb_id: "live-orb",
        amp_integration_id: integration.id,
        node_name: "node-a",
        residency_work_id: "amp:live-orb"
      )

    {:ok, _} = AmpIntegrations.disconnect(user.account.id, user)
    stub(Client, :get, fn _, _ -> {:ok, %{"items" => []}} end)
    expect(Nodes, :call, fn "node-a", "pause", _, _ -> {:error, :timeout} end)
    assert :ok = AmpReconciler.reconcile(user.account.id, config)
    assert Repo.reload!(sandbox).residency_work_id == "amp:live-orb"
    assert Repo.reload!(integration).status == :error

    expect(Nodes, :call, fn "node-a", "pause", _, _ -> {:ok, %{}} end)
    assert :ok = AmpReconciler.reconcile(user.account.id, config)
    assert %{state: :paused, residency_work_id: nil} = Repo.reload!(sandbox)
    assert Repo.reload!(integration).status == :disconnected
  end

  test "rotation waits for old pods to terminate before starting a new consumer", %{
    integration: integration,
    user: user,
    config: config
  } do
    {:ok, _} = AmpIntegrations.connect(user.account.id, user, "aop_live_new_consumer")

    stub(Client, :get, fn path, _ ->
      if String.contains?(path, "serviceaccounts?") do
        {:ok, %{"items" => [%{"metadata" => %{"name" => AmpRuntime.name(integration)}}]}}
      else
        {:ok, %{"items" => [%{"metadata" => %{"name" => "old-pod"}}]}}
      end
    end)

    expect(Client, :delete, fn path ->
      assert String.contains?(path, "/deployments/")
      :ok
    end)

    reject(&Client.apply/1)
    assert :ok = AmpReconciler.reconcile(user.account.id, config)
    assert Repo.reload!(integration).status == :error
  end
end
