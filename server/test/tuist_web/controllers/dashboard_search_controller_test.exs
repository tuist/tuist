defmodule TuistWeb.DashboardSearchControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.KeyValueStore.LoadLimiter
  alias Tuist.Projects
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.RateLimit

  setup context do
    stub(RateLimit.MCP, :hit, fn _ -> {:allow, 1} end)
    stub(RateLimit, :hit, fn _, _ -> {:allow, 1} end)
    %{start: {LoadLimiter, :start_link, [opts]}} = TuistWeb.DashboardSearchController.child_spec([])
    pool = Module.concat(__MODULE__, context.test)
    start_supervised!({LoadLimiter, Keyword.put(opts, :name, pool)})

    stub(LoadLimiter, :run, fn _, key, loader ->
      Mimic.call_original(LoadLimiter, :run, [pool, key, loader, :infinity])
    end)

    user = AccountsFixtures.user_fixture(preload: [:account])
    %{user: user}
  end

  test "suggests authorized projects and validates current and recent destinations", %{conn: conn, user: user} do
    first = ProjectsFixtures.project_fixture(account_id: user.account.id)
    second = ProjectsFixtures.project_fixture(account_id: user.account.id)
    foreign = ProjectsFixtures.project_fixture()
    conn = session(conn, user)

    response = search(conn, user.account)
    assert get_resp_header(response, "cache-control") == ["private, no-store"]
    paths = response |> json_response(200) |> Map.fetch!("results") |> Enum.map(& &1["path"])
    assert "/#{user.account.name}/#{first.name}" in paths
    assert "/#{user.account.name}/#{second.name}" in paths
    refute Enum.any?(paths, &String.ends_with?(&1, foreign.name))

    result =
      conn
      |> search(user.account, %{project: second.name, catalog: true})
      |> json_response(200)

    [%{"path" => path} | _] = result["results"]
    assert path == "/#{user.account.name}/#{second.name}"
    assert result["preferred_project"] == second.name
    assert Enum.map(result["results"], & &1["path"]) == [path]
    assert Enum.sort(Enum.map(result["projects"], & &1["name"])) == Enum.sort([first.name, second.name])

    switched =
      conn |> search(user.account, %{project: second.name, search_query: "project:#{first.name}"}) |> json_response(200)

    assert Enum.map(switched["results"], & &1["path"]) == ["/#{user.account.name}/#{first.name}"]

    assert Enum.all?(
             result["projects"],
             &Enum.any?(&1["pages"], fn page -> page["destination"] == "/tests/test-runs" end)
           )

    assert search(conn, user.account, %{project: foreign.name}).status == 404

    assert conn
           |> search(user.account, %{recent_project: first.name, catalog: true})
           |> json_response(200)
           |> Map.fetch!("preferred_project") == first.name

    assert conn
           |> search(user.account, %{recent_project: foreign.name, catalog: true})
           |> json_response(200)
           |> Map.fetch!("preferred_project") == nil

    scoped = conn |> search(user.account, %{search_query: "project:#{first.name}"}) |> json_response(200)
    assert [%{"path" => scoped_path}] = scoped["results"]
    assert scoped_path == "/#{user.account.name}/#{first.name}"
  end

  test "private accounts cannot be searched by another user", %{conn: conn, user: user} do
    other = AccountsFixtures.user_fixture(preload: [:account])
    ProjectsFixtures.project_fixture(account_id: other.account.id)
    assert conn |> session(user) |> search(other.account) |> json_response(404) == %{"message" => "Not found"}
  end

  test "public accounts expose public projects only", %{conn: conn, user: user} do
    owner = AccountsFixtures.user_fixture(preload: [:account])
    account = owner.account |> Ecto.Changeset.change(visibility: :public) |> Repo.update!()
    public = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)
    private = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :private)

    result = conn |> session(user) |> search(account) |> json_response(200)
    assert [%{"path" => path}] = result["results"]
    assert path == "/#{account.name}/#{public.name}"

    assert conn |> session(user) |> search(account, %{project: private.name}) |> json_response(404) == %{
             "message" => "Not found"
           }
  end

  test "membership removal takes effect on the next search", %{conn: conn, user: user} do
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    :ok = Accounts.add_user_to_organization(user, organization, role: :viewer)
    ProjectsFixtures.project_fixture(account_id: organization.account.id)
    conn = session(conn, user)
    assert search(conn, organization.account).status == 200

    Accounts.remove_user_from_organization(user, organization)
    assert search(conn, organization.account).status == 404
  end

  test "requires the account's SSO session", %{conn: conn, user: user} do
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    :ok = Accounts.add_user_to_organization(user, organization, role: :user)

    organization
    |> Ecto.Changeset.change(sso_enforced: true, sso_provider: :google, sso_organization_id: "search.example")
    |> Repo.update!()

    assert conn |> session(user) |> search(organization.account) |> json_response(403)

    assert build_conn()
           |> session(user, %{auth_method: :google, provider_organization_id: "search.example"})
           |> search(organization.account)
           |> json_response(200)
  end

  test "requires browser authentication and CSRF", %{conn: conn, user: user} do
    assert conn |> session(nil) |> search(user.account) |> json_response(401)
    conn = conn |> session(user) |> delete_req_header("x-csrf-token")
    assert_error_sent 403, fn -> search(conn, user.account) end
  end

  test "rejects malformed and oversized search parameters", %{conn: conn, user: user} do
    conn = session(conn, user)

    for params <- [%{search_query: ["test"]}, %{search_query: String.duplicate("é", 161)}] do
      assert conn |> search(user.account, params) |> json_response(400) == %{"message" => "Invalid search"}
    end

    assert Phoenix.Logger.filter_values(%{"search_query" => "private test name"}) == %{"search_query" => "[FILTERED]"}
  end

  test "search budgets are independent of WebMCP and deny before resource reads", %{conn: conn, user: user} do
    conn = session(conn, user)
    user_key = "dashboard-search:user:#{user.id}"
    account_key = "dashboard-search:account:#{user.account.id}"
    reject(Projects, :list_accessible_projects, 2)

    expect(RateLimit, :hit, fn ^user_key, opts ->
      assert opts == [algorithm: :token_bucket, capacity: 4, refill_rate: 2, fallback: false]
      {:deny, 1_501}
    end)

    denied = search(conn, user.account)
    assert json_response(denied, 429)
    assert get_resp_header(denied, "retry-after") == ["2"]

    expect(RateLimit, :hit, fn ^user_key, _ -> {:allow, 1} end)

    expect(RateLimit, :hit, fn ^account_key, opts ->
      assert opts == [algorithm: :token_bucket, capacity: 10, refill_rate: 5, fallback: false]
      {:deny, 500}
    end)

    assert conn |> search(user.account) |> json_response(429)

    expect(RateLimit, :hit, fn ^user_key, _ -> {:error, :unavailable} end)
    assert conn |> search(user.account) |> json_response(503)
  end

  test "overlapping requests cannot exceed two searches, and capacity recovers", %{conn: conn, user: user} do
    conn = session(conn, user)
    parent = self()

    expect(Projects, :list_accessible_projects, 2, fn account, opts ->
      send(parent, {:search_started, self()})

      receive do
        :continue -> Mimic.call_original(Projects, :list_accessible_projects, [account, opts])
      end
    end)

    first = Task.async(fn -> search(conn, user.account) end)
    assert_receive {:search_started, first_worker}, 2_000
    second = Task.async(fn -> search(conn, user.account) end)
    assert_receive {:search_started, second_worker}, 2_000
    assert conn |> search(user.account) |> json_response(429)
    refute_receive {:search_started, _}

    send(first_worker, :continue)
    send(second_worker, :continue)
    assert first |> Task.await() |> json_response(200)
    assert second |> Task.await() |> json_response(200)

    stub(Projects, :list_accessible_projects, fn account, opts ->
      Mimic.call_original(Projects, :list_accessible_projects, [account, opts])
    end)

    assert conn |> search(user.account) |> json_response(200)
  end

  defp search(conn, account, params \\ %{}) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/dashboard-search/#{account.name}", JSON.encode!(Map.merge(%{search_query: ""}, params)))
  end

  defp session(conn, user, auth \\ %{}) do
    token = Plug.CSRFProtection.get_csrf_token()
    conn = init_test_session(conn, %{})
    conn = if user, do: put_session(conn, :user_token, Accounts.generate_user_session_token(user, auth)), else: conn

    conn
    |> put_session("_csrf_token", Process.get(:plug_unmasked_csrf_token))
    |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))
    |> put_req_header("x-csrf-token", token)
  end
end
