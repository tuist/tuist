defmodule TuistWeb.Internal.KuraActivationControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Cache
  alias Tuist.Environment
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Workers.ProvisionOnDemandWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.KuraFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup :set_mimic_from_context

  setup do
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :env, fn -> :prod end)
    stub(Demand, :instance_expected?, fn _ -> true end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    {:ok, token, _claims} = Cache.issue_cache_token(project)
    %{user: user, account: user.account, project: project, token: token}
  end

  defp activate(conn, host, token) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> post("/_internal/kura/activate", %{host: host})
  end

  test "the first cache request queues provisioning immediately", %{conn: conn, account: account, token: token} do
    conn = activate(conn, "#{account.name}.cache.tuist.dev", token)
    assert json_response(conn, 202) == %{"status" => "provisioning"}
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert_enqueued(worker: ProvisionOnDemandWorker, args: %{account_id: account.id})
  end

  test "an archived account wakes without retaining a cache pod", %{conn: conn, account: account, token: token} do
    server = KuraFixtures.active_server_fixture(account)
    server |> Ecto.Changeset.change(status: :archived, url: nil) |> Repo.update!()
    assert conn |> activate("#{account.name}.cache.tuist.dev", token) |> json_response(202)
    assert_enqueued(worker: ProvisionOnDemandWorker, args: %{account_id: account.id})
  end

  test "serving accounts return a regional URL, never the stable hostname", %{conn: conn, account: account, token: token} do
    server = KuraFixtures.active_server_fixture(account)
    assert conn |> activate("#{account.name}.cache.tuist.dev", token) |> json_response(200) == %{"endpoint" => server.url}
    refute_enqueued(worker: ProvisionOnDemandWorker)
  end

  test "ordinary credentials and exchanged cache credentials both work", %{conn: conn, account: account, user: user} do
    server = KuraFixtures.active_server_fixture(account)
    {:ok, token, _} = Tuist.Authentication.encode_and_sign(user)
    assert conn |> activate("#{account.name}.cache.tuist.dev", token) |> json_response(200) == %{"endpoint" => server.url}
  end

  test "foreign, invalid and expired credentials cannot start capacity", %{conn: conn, account: account, project: project} do
    other = ProjectsFixtures.project_fixture()
    {:ok, foreign, _} = Cache.issue_cache_token(other)
    {:ok, expired, _} = Cache.issue_cache_token(project, ttl: -60)
    reject(Demand, :record, 1)

    for token <- [foreign, expired, "invalid"] do
      assert conn |> activate("#{account.name}.cache.tuist.dev", token) |> json_response(403)
    end

    refute_enqueued(worker: ProvisionOnDemandWorker)
  end

  test "raw account tokens must carry a cache scope", %{conn: conn, account: account, project: project} do
    {:ok, {_record, token}} =
      Accounts.create_account_token(%{
        account: account,
        name: "cache-reader",
        scopes: ["project:cache:read"],
        project_ids: [project.id]
      })

    assert conn |> activate("#{account.name}.cache.tuist.dev", token) |> json_response(202)
    assert_enqueued(worker: ProvisionOnDemandWorker, args: %{account_id: account.id})

    subject = %Tuist.Accounts.AuthenticatedAccount{account: account, scopes: [], all_projects: true}
    {:ok, empty_token, _} = Cache.issue_cache_token(subject)
    reject(Demand, :record, 1)
    assert conn |> activate("#{account.name}.cache.tuist.dev", empty_token) |> json_response(403)
  end

  test "missing authorization cannot start capacity", %{conn: conn, account: account} do
    assert conn |> post("/_internal/kura/activate", %{host: "#{account.name}.cache.tuist.dev"}) |> json_response(401)
    refute_enqueued(worker: ProvisionOnDemandWorker)
  end

  test "environment suffixes cannot activate a different environment", %{conn: conn, account: account, token: token} do
    for host <- [
          "#{account.name}-canary.cache.tuist.dev",
          "#{account.name}-staging.cache.tuist.dev",
          "#{account.name}.cache.tuist.dev.evil"
        ] do
      assert conn |> activate(host, token) |> json_response(403)
    end

    refute_enqueued(worker: ProvisionOnDemandWorker)
    stub(Environment, :env, fn -> :stag end)
    assert conn |> activate("#{account.name}-staging.cache.tuist.dev", token) |> json_response(202)
  end

  test "retained client aliases resolve but expired aliases do not", %{conn: conn, account: account, user: user} do
    {:ok, renamed} = Accounts.update_account(account, %{name: "renamed-#{account.id}"})
    user = Repo.preload(user, :account, force: true)
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    {:ok, token, _} = Cache.issue_cache_token(project)
    server = KuraFixtures.active_server_fixture(renamed)
    assert conn |> activate("#{account.name}.cache.tuist.dev", token) |> json_response(200) == %{"endpoint" => server.url}
    stub(Tuist.Kura.Identity, :client_handles, fn _ -> [user.account.name] end)
    assert conn |> activate("#{account.name}.cache.tuist.dev", token) |> json_response(403)
  end

  test "billing blocks provisioning even with an earlier valid token", %{conn: conn, account: account, token: token} do
    stub(Tuist.Billing, :cache_access_blocked?, fn _ -> true end)
    assert conn |> activate("#{account.name}.cache.tuist.dev", token) |> json_response(402)
    refute_enqueued(worker: ProvisionOnDemandWorker)
  end

  test "self-hosted server does not provision managed capacity", %{conn: conn, account: account, token: token} do
    stub(Environment, :tuist_hosted?, fn -> false end)
    assert conn |> activate("#{account.name}.cache.tuist.dev", token) |> json_response(403)
    refute_enqueued(worker: ProvisionOnDemandWorker)
  end
end
