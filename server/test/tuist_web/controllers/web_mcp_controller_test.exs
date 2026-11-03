defmodule TuistWeb.WebMCPControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.MCP.Search
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.RateLimit

  @docs_tools ["list_tuist_files", "read_tuist_file", "search_tuist", "search_tuist_code"]

  setup do
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Environment, :codebase_search_enabled?, fn -> true end)
    stub(RateLimit.MCP, :hit, fn _conn -> {:allow, 1} end)
    :ok
  end

  describe "POST /api/webmcp" do
    test "lists only read-only tools", %{conn: conn} do
      tools = conn |> browser_session(AccountsFixtures.user_fixture()) |> list_tools("/api/webmcp")

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
        |> call_tool("/api/webmcp", "get_project", %{
          "account_handle" => user.account.name,
          "project_handle" => project.name
        })

      refute result["isError"]
      assert result["structuredContent"]["full_handle"] == "#{user.account.name}/#{project.name}"
    end

    test "refuses a private project the user cannot read", %{conn: conn} do
      other = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: other.account.id)

      result =
        conn
        |> browser_session(AccountsFixtures.user_fixture())
        |> call_tool("/api/webmcp", "get_project", %{
          "account_handle" => other.account.name,
          "project_handle" => project.name
        })

      assert result["isError"]
      assert [%{"text" => "You do not have access to project:" <> _}] = result["content"]
    end

    test "lets an organization member read the organization's projects", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(preload: [:account])
      :ok = Accounts.add_user_to_organization(user, organization, role: :user)
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      result =
        conn
        |> browser_session(user)
        |> call_tool("/api/webmcp", "get_project", %{
          "account_handle" => organization.account.name,
          "project_handle" => project.name
        })

      refute result["isError"]
    end

    test "refuses write tools", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])

      response =
        conn
        |> browser_session(user)
        |> post_rpc("/api/webmcp", "tools/call", %{
          "name" => "create_project",
          "arguments" => %{"account_handle" => user.account.name, "project_handle" => "from-webmcp"}
        })
        |> json_response(200)

      assert response["error"]["message"] == "Tool not found: create_project"
      assert Projects.get_project_by_account_and_project_handles(user.account.name, "from-webmcp") == nil
    end

    test "answers only tool listings and calls", %{conn: conn} do
      response =
        conn
        |> browser_session(AccountsFixtures.user_fixture())
        |> post_rpc("/api/webmcp", "prompts/list", %{})
        |> json_response(400)

      assert response["error"]["code"] == -32_600

      notification =
        build_conn()
        |> browser_session(AccountsFixtures.user_fixture())
        |> put_req_header("content-type", "application/json")
        |> post("/api/webmcp", JSON.encode!(%{"jsonrpc" => "2.0", "method" => "tools/list"}))

      assert json_response(notification, 400)["error"]["code"] == -32_600
    end

    test "requires a signed-in session", %{conn: conn} do
      conn = conn |> browser_session(nil) |> post_rpc("/api/webmcp", "tools/list", %{})

      assert json_response(conn, 401)
    end

    test "does not accept a bearer token instead of a session", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      conn =
        conn
        |> browser_session(nil)
        |> put_req_header("authorization", "Bearer #{user.token}")
        |> post_rpc("/api/webmcp", "tools/list", %{})

      assert json_response(conn, 401)
    end

    test "requires the session's CSRF token", %{conn: conn} do
      conn = conn |> browser_session(AccountsFixtures.user_fixture()) |> delete_req_header("x-csrf-token")

      assert_error_sent 403, fn -> post_rpc(conn, "/api/webmcp", "tools/list", %{}) end
    end

    test "requires the sign-in method every SSO-enforcing organization of the user requires", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      enforce_sso(user, :google)

      assert conn |> browser_session(user, auth_method: :password) |> list_tools_status() == 403
      assert build_conn() |> browser_session(user, auth_method: nil) |> list_tools_status() == 403
      assert build_conn() |> browser_session(user, auth_method: :google) |> list_tools_status() == 200

      enforce_sso(user, :okta)

      assert build_conn() |> browser_session(user, auth_method: :google) |> list_tools_status() == 403
    end

    test "uses its own rate limit bucket", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      test_process = self()
      stub(RateLimit.MCP, :hit, &Mimic.call_original(RateLimit.MCP, :hit, [&1]))

      stub(RateLimit, :hit, fn key, _opts ->
        send(test_process, {:rate_limit_key, key})
        {:allow, 1}
      end)

      conn |> browser_session(user) |> post_rpc("/api/webmcp", "tools/list", %{})

      assert_received {:rate_limit_key, key}
      assert key == "webmcp:auth:user:#{user.id}"
    end

    test "dashboard pages advertise it only to signed-in users", %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])

      refute conn |> get("/users/log_in") |> html_response(200) =~ "webmcp-endpoint"

      assert build_conn() |> log_in_user(user) |> get("/#{user.account.name}/projects") |> html_response(200) =~
               ~s(<meta name="webmcp-endpoint" content="/api/webmcp">)
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

    test "does not act on the signed-in user's behalf", %{conn: conn} do
      response =
        conn
        |> log_in_user(AccountsFixtures.user_fixture())
        |> post_rpc("/api/webmcp/public", "tools/call", %{"name" => "list_accounts", "arguments" => %{}})
        |> json_response(200)

      assert response["error"]["message"] == "Tool not found: list_accounts"
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

  defp enforce_sso(user, provider) do
    organization =
      AccountsFixtures.organization_fixture(
        creator: user,
        sso_provider: provider,
        sso_organization_id: "#{TuistTestSupport.Utilities.unique_integer()}.example.com",
        oauth2_client_id: "client-id",
        oauth2_client_secret: "client-secret"
      )

    # Enabling enforcement through `Accounts` also requires a verified login
    # email domain, which is not what these tests are about.
    organization |> Ecto.Changeset.change(sso_enforced: true) |> Tuist.Repo.update!()
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

  defp list_tools_status(conn), do: conn |> post_rpc("/api/webmcp", "tools/list", %{}) |> Map.fetch!(:status)

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
