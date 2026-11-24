defmodule TuistWeb.Internal.AtlasKuraRolloutsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.AtlasWorkloadIdentity
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Rollout
  alias Tuist.Kura.Rollouts
  alias Tuist.Kura.Usage
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.RateLimit

  @path "/api/internal/atlas/kura/rollout"

  setup do
    stub(RateLimit.Atlas, :hit, fn _conn -> {:allow, 1} end)
    stub(AtlasWorkloadIdentity, :verify, fn "valid-token" -> {:ok, %{namespace: "atlas-production", name: "atlas"}} end)
    stub(Rollouts.Notifier, :notify, fn _event, _rollout, _metadata -> :ok end)
    stub(Usage, :recent_request_counts_by_account, fn _account_ids, _days -> %{} end)
    stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "0.6.0" end)
    stub(Tuist.Environment, :kura_available_region_ids, fn -> ["local-controller"] end)
    stub(Tuist.Environment, :kura_canary_account_handles, fn -> [] end)
    stub(Tuist.Environment, :kura_rollout_expedite_tag, fn -> nil end)
    stub(Tuist.Environment, :kura_rollout_pacing, fn -> nil end)

    stub(Provisioner, :rollout_health, fn _server ->
      {:ok,
       %{
         ready: true,
         serving: true,
         ring_consistent: true,
         backfilling_peers: 0,
         backfill_degraded: false,
         backfill_budget_exhausted_peers: 0,
         fd_timeout_count: 0,
         peer_connection_failures: 0,
         memory_pressure_state: 0,
         sampled_pods: 1,
         expected_pods: 1,
         sampled_at: DateTime.utc_now()
       }}
    end)

    :ok
  end

  test "rejects unauthenticated callers", %{conn: conn} do
    assert conn |> get(@path) |> json_response(401)
  end

  test "reports not found when there is no rollout", %{conn: conn} do
    assert %{"error" => "resource_not_found"} = conn |> authed() |> get(@path) |> json_response(404)
    assert conn |> authed() |> get(@path, %{"id" => "not-a-uuid"}) |> json_response(404)
  end

  test "names the server that held a wave open past its deadline", %{conn: conn} do
    stuck = create_active_server()
    converged = create_active_server()

    assert :ok = Rollouts.sync()
    rollout = Rollouts.active_rollout()
    {:ok, _} = Kura.activate_server(Repo.get!(Kura.Server, converged.server.id), "0.6.0")

    Rollout
    |> where([r], r.id == ^rollout.id)
    |> Repo.update_all(set: [wave_started_at: DateTime.add(DateTime.utc_now(), -61 * 60, :second)])

    assert :ok = Rollouts.sync()

    response = conn |> authed() |> get(@path) |> json_response(200)

    assert %{"id" => id, "status" => "paused", "pause_reason" => "wave_deadline_exceeded", "image_tag" => "0.6.0"} =
             response["rollout"]

    assert id == rollout.id
    assert response["unconverged_server_count"] == 1
    assert [server] = response["unconverged_servers"]
    assert server["server_id"] == stuck.server.id
    assert server["account_handle"] == stuck.account.name
    assert server["observed_image_tag"] == "0.5.2"
    assert server["deployment"]["image_tag"] == "0.6.0"
    assert response["waves"] |> Enum.map(& &1["servers"]) |> Enum.sum() == 2
    assert response["waves"] |> Enum.map(& &1["converged"]) |> Enum.sum() == 1
    assert %{"action" => "paused", "actor" => "gate"} = hd(response["events"])

    assert conn |> authed() |> get(@path, %{"id" => rollout.id}) |> json_response(200) == response
  end

  defp create_active_server do
    account = Accounts.get_account_from_user(AccountsFixtures.user_fixture())
    {:ok, server} = Kura.create_server(%{account_id: account.id, region: "local-controller", image_tag: "0.5.2"})

    Deployment
    |> where([d], d.kura_server_id == ^server.id and d.status in [:pending, :running])
    |> Repo.all()
    |> Enum.each(fn deployment ->
      {:ok, deployment} = if deployment.status == :pending, do: Kura.mark_running(deployment), else: {:ok, deployment}
      {:ok, _} = Kura.mark_succeeded(deployment)
    end)

    {:ok, server} = Kura.activate_server(server, "0.5.2")
    %{account: account, server: server}
  end

  defp authed(conn), do: put_req_header(conn, "authorization", "Bearer valid-token")
end
