defmodule TuistWeb.OpsKuraMetricsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    {:ok, _server} =
      %Server{}
      |> Server.create_changeset(%{
        account_id: account.id,
        region: "us-east",
        provisioner_node_ref: "kura-acme-us-east-1"
      })
      |> Repo.insert()

    %{conn: assign(conn, :current_user, user), user: user}
  end

  describe "GET /api/ops/kura/pods/:pod/metrics" do
    test "returns the pod's exposition to an operator", %{conn: conn} do
      stub(Accounts, :tuist_operator?, fn _ -> true end)

      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: "kura_http_requests_total 7\n"}}
      end)

      conn = get(conn, "/api/ops/kura/pods/kura-acme-us-east-1-1/metrics")

      assert response(conn, 200) == "kura_http_requests_total 7\n"
      assert response_content_type(conn, :text) =~ "text/plain"
    end

    test "refuses a user who is not an operator", %{conn: conn} do
      stub(Accounts, :tuist_operator?, fn _ -> false end)
      reject(&Req.get/2)

      assert_raise TuistWeb.Errors.UnauthorizedError, fn ->
        get(conn, "/api/ops/kura/pods/kura-acme-us-east-1-1/metrics")
      end
    end

    test "refuses an unauthenticated request", %{conn: conn} do
      reject(&Req.get/2)

      conn =
        conn
        |> assign(:current_user, nil)
        |> get("/api/ops/kura/pods/kura-acme-us-east-1-1/metrics")

      assert conn.status in [401, 403]
    end

    test "404s a pod no server owns", %{conn: conn} do
      stub(Accounts, :tuist_operator?, fn _ -> true end)
      reject(&Req.get/2)

      conn = get(conn, "/api/ops/kura/pods/kura-other-us-east-1-0/metrics")

      assert json_response(conn, 404)["error"] =~ "No Kura server is registered"
    end

    test "502s a pod that cannot be reached", %{conn: conn} do
      stub(Accounts, :tuist_operator?, fn _ -> true end)
      expect(Req, :get, fn _url, _opts -> {:error, %Mint.TransportError{reason: :timeout}} end)

      conn = get(conn, "/api/ops/kura/pods/kura-acme-us-east-1-0/metrics")

      assert json_response(conn, 502)["error"] =~ "could not be reached"
    end
  end
end
