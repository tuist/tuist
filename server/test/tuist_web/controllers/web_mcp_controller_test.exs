defmodule TuistWeb.WebMCPControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.MCP.Search
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.RateLimit

  @docs_tools ["list_tuist_files", "read_tuist_file", "search_tuist", "search_tuist_code"]

  setup do
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :codebase_search_enabled?, fn -> true end)
    stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)
    :ok
  end

  describe "POST /api/webmcp/accounts/:account_handle" do
    test "lists only read-only tools", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      tools = conn |> browser_session(user) |> list_tools(account_path(user.account))

      names = Enum.map(tools, & &1["name"])
      assert "list_projects" in names
      assert "search_tuist" in names
      refute "create_project" in names
      refute "add_organization_member" in names
      refute "report_feedback" in names
      assert Enum.all?(tools, &(&1["annotations"]["readOnlyHint"] == true))
    end

    test "calls tools as the user signed in to the browser session", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      result =
        conn
        |> browser_session(user)
        |> call_tool(account_path(user.account), "get_project", project_arguments(project))

      refute result["isError"]
      assert result["structuredContent"]["full_handle"] == "#{user.account.name}/#{project.name}"
    end

    test "lets an organization member read the organization's projects", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      organization = organization_with_member(user)
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      result =
        conn
        |> browser_session(user)
        |> call_tool(account_path(organization.account), "get_project", project_arguments(project))

      refute result["isError"]
    end

    test "refuses another account's data, even one the user can read", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = organization_with_member(user)
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      result =
        conn
        |> browser_session(user)
        |> call_tool(account_path(user.account), "get_project", project_arguments(project))

      assert result["isError"]
      assert [%{"text" => "You do not have access to project:" <> _}] = result["content"]
    end

    test "refuses another account's records addressed by ID or dashboard URL", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = organization_with_member(user)
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
      preview = AppBuildsFixtures.preview_fixture(project: project)
      url = Environment.app_url(path: "/#{organization.account.name}/#{project.name}/previews/#{preview.id}")
      conn = browser_session(conn, user)

      refute call_tool(conn, account_path(organization), "get_preview", %{"preview_id" => preview.id})["isError"]
      assert call_tool(conn, account_path(user.account), "get_preview", %{"preview_id" => preview.id})["isError"]
      assert call_tool(conn, account_path(user.account), "get_preview", %{"preview_id" => url})["isError"]
    end

    test "lists only the account's projects and the account itself", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      organization = organization_with_member(user)
      own = ProjectsFixtures.project_fixture(account_id: user.account.id)
      ProjectsFixtures.project_fixture(account_id: organization.account.id)
      conn = browser_session(conn, user)

      projects = call_tool(conn, account_path(user.account), "list_projects", %{})
      accounts = call_tool(conn, account_path(user.account), "list_accounts", %{})

      assert Enum.map(projects["structuredContent"]["projects"], & &1["name"]) == [own.name]
      assert Enum.map(accounts["structuredContent"]["accounts"], & &1["handle"]) == [user.account.name]
    end

    test "answers 404 for an unknown account", %{conn: conn} do
      conn =
        conn
        |> browser_session(AccountsFixtures.user_fixture())
        |> post_rpc("/api/webmcp/accounts/does-not-exist", "tools/list", %{})

      assert json_response(conn, 404)["message"] == "Account not found: does-not-exist"
    end

    test "answers only tool listings and calls", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])

      response =
        conn
        |> browser_session(user)
        |> post_rpc(account_path(user.account), "prompts/list", %{})
        |> json_response(400)

      assert response["error"]["code"] == -32_600

      notification =
        build_conn()
        |> browser_session(user)
        |> put_req_header("content-type", "application/json")
        |> post(account_path(user.account), JSON.encode!(%{"jsonrpc" => "2.0", "method" => "tools/list"}))

      assert json_response(notification, 400)["error"]["code"] == -32_600

      nameless_call =
        build_conn()
        |> browser_session(user)
        |> post_rpc(account_path(user.account), "tools/call", %{"arguments" => %{}})

      assert json_response(nameless_call, 400)["error"]["code"] == -32_600
    end

    test "requires a signed-in session", %{conn: conn} do
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      conn = conn |> browser_session(nil) |> post_rpc(account_path(account), "tools/list", %{})

      assert json_response(conn, 401)
    end

    test "does not accept a bearer token instead of a session", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])

      conn =
        conn
        |> browser_session(nil)
        |> put_req_header("authorization", "Bearer #{user.token}")
        |> post_rpc(account_path(user.account), "tools/list", %{})

      assert json_response(conn, 401)
    end

    test "requires the session's CSRF token", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      conn = conn |> browser_session(user) |> delete_req_header("x-csrf-token")

      assert_error_sent 403, fn -> post_rpc(conn, account_path(user.account), "tools/list", %{}) end
    end

    test "requires the sign-in method the account's organization enforces, as its dashboard does", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      google = enforce_sso(organization_with_member(user), :google)
      okta = enforce_sso(organization_with_member(user), :okta)

      assert conn |> browser_session(user, auth_method: :password) |> list_tools_status(google) == 403
      assert build_conn() |> browser_session(user, auth_method: nil) |> list_tools_status(google) == 403
      assert build_conn() |> browser_session(user, auth_method: :google) |> list_tools_status(google) == 200

      # Other accounts keep their own requirements.
      assert build_conn() |> browser_session(user, auth_method: :google) |> list_tools_status(okta) == 403
      assert build_conn() |> browser_session(user, auth_method: :password) |> list_tools_status(user) == 200
    end

    test "uses its own rate limit bucket", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      test_process = self()
      stub(RateLimit.MCP, :hit, &Mimic.call_original(RateLimit.MCP, :hit, [&1]))

      stub(RateLimit, :hit, fn key, _opts ->
        send(test_process, {:rate_limit_key, key})
        {:allow, 1}
      end)

      conn |> browser_session(user) |> post_rpc(account_path(user.account), "tools/list", %{})

      assert_received {:rate_limit_key, key}
      assert key == "webmcp:auth:user:#{user.id}"
    end

    test "account pages advertise it to signed-in users, other pages the public tools", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])

      assert conn |> get("/users/log_in") |> html_response(200) =~
               ~s(<meta name="webmcp-endpoint" content="/api/webmcp/public">)

      assert build_conn() |> log_in_user(user) |> get("/#{user.account.name}/projects") |> html_response(200) =~
               ~s(data-webmcp-endpoint="/api/webmcp/accounts/#{user.account.name}")

      headerbar = fn assigns ->
        render_component(&TuistWeb.AppLayoutComponents.headerbar/1, Map.merge(headerbar_assigns(user), assigns))
      end

      refute headerbar.(%{current_user: nil}) =~ "data-webmcp-endpoint"
      refute headerbar.(%{webmcp: false}) =~ "data-webmcp-endpoint"
      assert headerbar.(%{}) =~ "data-webmcp-endpoint"
    end
  end

  describe "POST /api/webmcp/public" do
    test "lists only the documentation and source tools", %{conn: conn} do
      names = conn |> list_tools("/api/webmcp/public") |> Enum.map(& &1["name"]) |> Enum.sort()

      assert names == @docs_tools
    end

    test "calls tools without a session or CSRF token", %{conn: conn} do
      stub(Search, :search, fn %{"query" => "cache"} -> {:error, "Tuist search is unavailable: timeout"} end)

      result = call_tool(conn, "/api/webmcp/public", "search_tuist", %{"query" => "cache"})

      assert [%{"text" => "Tuist search is unavailable: timeout"}] = result["content"]
    end

    test "rate limits by client address", %{conn: conn} do
      test_process = self()
      stub(RateLimit.MCP, :hit, &Mimic.call_original(RateLimit.MCP, :hit, [&1]))

      stub(RateLimit, :hit, fn key, _opts ->
        send(test_process, {:rate_limit_key, key})
        {:allow, 1}
      end)

      post_rpc(conn, "/api/webmcp/public", "tools/list", %{})

      assert_received {:rate_limit_key, "webmcp:unauth:" <> _address}
    end

    test "documentation pages advertise it", %{conn: conn} do
      assert conn |> get("/en/docs/guides/install-tuist") |> html_response(200) =~
               ~s(<meta name="webmcp-endpoint" content="/api/webmcp/public">)
    end
  end

  defp organization_with_member(user) do
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    :ok = Accounts.add_user_to_organization(user, organization, role: :user)
    organization
  end

  defp enforce_sso(organization, provider) do
    # Enabling enforcement through `Accounts` also requires a verified login
    # email domain, which is not what these tests are about.
    organization
    |> Ecto.Changeset.change(sso_enforced: true, sso_provider: provider)
    |> Tuist.Repo.update!()
    |> Tuist.Repo.preload(:account)
  end

  defp headerbar_assigns(user) do
    %{breadcrumbs: [], current_user: user, selected_account: user.account, latest_app_release: nil}
  end

  defp account_path(%{account: account}), do: account_path(account)
  defp account_path(account), do: "/api/webmcp/accounts/#{account.name}"

  defp project_arguments(project) do
    project = Tuist.Repo.preload(project, :account)
    %{"account_handle" => project.account.name, "project_handle" => project.name}
  end

  # Sends what the dashboard sends: the session cookie and the session's CSRF
  # token in a header. `ConnTest` skips CSRF protection unless told otherwise.
  defp browser_session(conn, user, opts \\ []) do
    csrf_token = Plug.CSRFProtection.get_csrf_token()
    conn = if user, do: log_in_user(conn, user), else: init_test_session(conn, %{})

    conn
    |> put_session(:auth_method, Keyword.get(opts, :auth_method, :password))
    |> put_session("_csrf_token", Process.get(:plug_unmasked_csrf_token))
    |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))
    |> put_req_header("x-csrf-token", csrf_token)
  end

  defp list_tools(conn, path),
    do: conn |> post_rpc(path, "tools/list", %{}) |> json_response(200) |> get_in(["result", "tools"])

  defp list_tools_status(conn, account),
    do: conn |> post_rpc(account_path(account), "tools/list", %{}) |> Map.fetch!(:status)

  defp call_tool(conn, path, name, arguments) do
    conn
    |> post_rpc(path, "tools/call", %{"name" => name, "arguments" => arguments})
    |> json_response(200)
    |> Map.fetch!("result")
  end

  defp post_rpc(conn, path, method, params) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> post(path, JSON.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}))
  end
end
