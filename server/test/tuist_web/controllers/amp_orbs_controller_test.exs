defmodule TuistWeb.AmpOrbsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client
  alias Tuist.Sandboxes.AmpIntegrations
  alias Tuist.Sandboxes.AmpRuntime
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.Sandbox
  alias TuistTestSupport.Fixtures.SandboxesFixtures

  setup do
    user = user_fixture()
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> true end)
    {:ok, integration} = AmpIntegrations.connect(user.account.id, user, "aop_live_#{Ecto.UUID.generate()}")
    %{user: user, integration: integration}
  end

  defp request(conn, attrs \\ %{"operation" => "pause"}) do
    conn |> put_req_header("authorization", "Bearer workload") |> post("/api/internal/amp-orbs/amp-thread", attrs)
  end

  defp identity(integration, namespace \\ "tuist-amp-orbs") do
    stub(Client, :create_amp_provider_token_review, fn "workload" ->
      {:ok, %{namespace: namespace, name: AmpRuntime.name(integration), uid: "sa-id"}}
    end)
  end

  test "a forged account parameter never changes the authenticated account", %{conn: conn, integration: integration} do
    identity(integration)
    other = user_fixture()

    sandbox =
      SandboxesFixtures.sandbox_fixture(
        account: other.account,
        amp_orb_id: "amp-thread",
        state: :paused
      )

    assert response(
             request(conn, %{
               "operation" => "delete",
               "account_id" => other.account.id,
               "account_handle" => other.account.name
             }),
             204
           ) == ""

    assert Tuist.Repo.get!(Sandbox, sandbox.id).state == :paused
  end

  test "reports account resource exhaustion separately from fleet capacity", %{
    conn: conn,
    integration: integration,
    user: user
  } do
    identity(integration)

    {:ok, _} =
      Concurrency.update_limits(user.account, %{sandbox_vcpus_limit: 2, sandbox_memory_gb_limit: 4})

    SandboxesFixtures.sandbox_fixture(account: user.account)

    assert response(request(conn, %{"operation" => "spawn", "orb_token" => "orb-fixture"}), 429) ==
             "Account sandbox CPU or memory limit reached"
  end

  test "requires workload authentication", %{conn: conn} do
    stub(Client, :create_amp_provider_token_review, fn _ -> {:error, :unauthenticated} end)
    assert response(request(conn), 401)
  end

  test "rejects another namespace", %{conn: conn, integration: integration} do
    identity(integration, "another-environment")
    assert response(request(conn), 401)
  end

  test "pause is authorized for the verified provider without an account parameter", %{
    conn: conn,
    integration: integration
  } do
    identity(integration)
    assert response(request(conn), 204) == ""
  end

  test "disconnect and rotation revoke earlier identities", %{conn: conn, integration: integration, user: user} do
    identity(integration)
    assert {:ok, _} = AmpIntegrations.connect(user.account.id, user, "aop_live_rotated")
    assert response(request(conn), 403)
    {:ok, latest} = AmpIntegrations.connect(user.account.id, user, "aop_live_latest")
    identity(latest)
    assert {:ok, _} = AmpIntegrations.disconnect(user.account.id, user)
    assert response(request(Phoenix.ConnTest.build_conn()), 403)
  end

  test "flag denial prevents new work and permits cleanup", %{conn: conn, integration: integration} do
    identity(integration)
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> false end)
    assert response(request(conn, %{"operation" => "spawn", "orb_token" => "orb-fixture"}), 403)
    assert response(request(Phoenix.ConnTest.build_conn()), 204) == ""
  end

  test "rejects missing guest credentials before dispatch", %{conn: conn, integration: integration} do
    identity(integration)
    assert response(request(conn, %{"operation" => "spawn"}), 400)
  end

  test "failed dispatch retains the sandbox identity and recovery state", %{
    conn: conn,
    integration: integration,
    user: user
  } do
    identity(integration)

    expect(Tuist.Sandboxes, :dispatch_amp_orb, fn account, orb_id, attrs ->
      assert account.id == user.account.id

      SandboxesFixtures.sandbox_fixture(
        account: account,
        amp_orb_id: orb_id,
        amp_integration_id: attrs.amp_integration_id,
        state: :error,
        node_name: "node-with-preserved-disk"
      )

      {:error, :orb_bootstrap_failed}
    end)

    assert response(request(conn, %{"operation" => "spawn", "orb_token" => "guest-fixture"}), 503)

    assert %{state: :error, node_name: "node-with-preserved-disk"} =
             Tuist.Repo.get_by!(Sandbox, account_id: user.account.id, amp_orb_id: "amp-thread")
  end

  test "concurrent integration work is retried instead of crossing a rotation", %{conn: conn, integration: integration} do
    identity(integration)
    parent = self()

    task =
      Task.async(fn ->
        AmpIntegrations.with_lock(integration.account_id, fn ->
          send(parent, :integration_locked)

          receive do
            :release -> :ok
          after
            5_000 -> :timeout
          end
        end)
      end)

    try do
      assert_receive :integration_locked
      assert response(request(conn), 409)
    after
      send(task.pid, :release)
      Task.await(task)
    end
  end
end
