defmodule TuistWeb.API.Internal.AuthControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @valid_caller_token "test-kura-shared-secret"

  setup :stub_kura_verify_token

  describe "POST /api/internal/auth/verify" do
    test "rejects callers that don't present the shared secret", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/internal/auth/verify", %{token: "x"})

      assert json_response(conn, 401) == %{"error" => "invalid_caller"}
    end

    test "rejects callers that present a wrong shared secret", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer wrong")
        |> post("/api/internal/auth/verify", %{token: "x"})

      assert json_response(conn, 401) == %{"error" => "invalid_caller"}
    end

    test "responds 401 when the verify token is not configured" do
      stub(Environment, :kura_verify_token, fn -> nil end)

      conn =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{@valid_caller_token}")
        |> post("/api/internal/auth/verify", %{token: "x"})

      assert json_response(conn, 503) == %{"error" => "verify_disabled"}
    end

    test "returns 401 when the token doesn't resolve to a subject", %{conn: conn} do
      conn =
        conn
        |> with_kura_caller()
        |> post("/api/internal/auth/verify", %{token: "this-is-not-a-real-token"})

      assert json_response(conn, 401) == %{"error" => "invalid_token"}
    end

    test "returns 400 when the token is missing", %{conn: conn} do
      conn =
        conn
        |> with_kura_caller()
        |> post("/api/internal/auth/verify", %{})

      assert json_response(conn, 400) == %{"error" => "missing_token"}
    end

    test "returns the user's principal with all account handles they belong to", %{conn: conn} do
      user = AccountsFixtures.user_fixture()

      org =
        AccountsFixtures.organization_fixture(creator: user, name: "the-org")
        |> Tuist.Repo.preload(:account)

      {:ok, token, _claims} = Tuist.Authentication.encode_and_sign(user)

      conn =
        conn
        |> with_kura_caller()
        |> post("/api/internal/auth/verify", %{token: token})

      response = json_response(conn, 200)
      assert response["principal"]["id"] == to_string(user.id)
      assert response["principal"]["kind"] == "user"
      assert org.account.name in response["principal"]["account_handles"]
      assert user.account.name in response["principal"]["account_handles"]
    end

    test "returns the project token's principal scoped to the project's account", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      org = AccountsFixtures.organization_fixture(creator: user, name: "the-proj-org") |> Tuist.Repo.preload(:account)
      project = TuistTestSupport.Fixtures.ProjectsFixtures.project_fixture(account_id: org.account.id)

      token = Tuist.Projects.create_project_token(project)

      conn =
        conn
        |> with_kura_caller()
        |> post("/api/internal/auth/verify", %{token: token})

      response = json_response(conn, 200)
      assert response["principal"]["kind"] == "project"
      assert response["principal"]["account_handles"] == [org.account.name]
    end
  end

  defp with_kura_caller(conn) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer #{@valid_caller_token}")
  end

  defp stub_kura_verify_token(_) do
    stub(Environment, :kura_verify_token, fn -> @valid_caller_token end)
    :ok
  end
end
