defmodule TuistWeb.OperatorGrantPlugsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Plug.Conn

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.OperatorGrant

  describe "redirect_to_ops_if_operator/2" do
    setup do
      stub(Tuist.Environment, :ops_reason_form_url, fn -> "https://ops.tuist.dev/grants/new" end)
      :ok
    end

    test "redirects a non-member operator with no grant to the reason form", %{conn: conn} do
      project = ProjectsFixtures.project_fixture(preload: [:account])
      operator = operator_user()

      conn =
        conn
        |> with_handles(project.account.name, project.name)
        |> assign(:current_user, operator)
        |> OperatorGrant.redirect_to_ops_if_operator([])

      assert conn.halted
      [location] = get_resp_header(conn, "location")
      assert location =~ "https://ops.tuist.dev/grants/new"
      assert location =~ "account=#{project.account.name}"
    end

    test "does not redirect a non-operator (regular customer)", %{conn: conn} do
      project = ProjectsFixtures.project_fixture(preload: [:account])
      user = AccountsFixtures.user_fixture(preload: [:account])

      conn =
        conn
        |> with_handles(project.account.name, project.name)
        |> assign(:current_user, user)
        |> OperatorGrant.redirect_to_ops_if_operator([])

      refute conn.halted
    end

    test "does not redirect an operator who already holds a grant", %{conn: conn} do
      project = ProjectsFixtures.project_fixture(preload: [:account])
      now = System.system_time(:second)

      operator = %{
        operator_user()
        | operator_grant: %{tier: :read, account_id: project.account_id, exp: now + 600}
      }

      conn =
        conn
        |> with_handles(project.account.name, project.name)
        |> assign(:current_user, operator)
        |> OperatorGrant.redirect_to_ops_if_operator([])

      refute conn.halted
    end

    test "does not redirect an unauthenticated request", %{conn: conn} do
      project = ProjectsFixtures.project_fixture(preload: [:account])

      conn =
        conn
        |> with_handles(project.account.name, project.name)
        |> assign(:current_user, nil)
        |> OperatorGrant.redirect_to_ops_if_operator([])

      refute conn.halted
    end
  end

  describe "accept_operator_grant/2" do
    setup do
      jwk = JOSE.JWK.generate_key({:okp, :Ed25519})
      pub_pem = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem() |> unwrap()

      stub(Tuist.Environment, :operator_grant_public_key, fn -> pub_pem end)
      stub(Tuist.Environment, :operator_grant_audience, fn -> "tuist-server" end)
      stub(Tuist.Environment, :operator_grant_max_ttl_seconds, fn -> 3600 end)

      {:ok, signer: jwk}
    end

    test "stores a valid grant in the session and strips the param", %{signer: signer} do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      token = mint(signer, claims(account.name))

      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/#{account.name}?operator_grant=#{token}")
        |> Plug.Test.init_test_session(%{})
        |> OperatorGrant.accept_operator_grant([])

      assert conn.halted
      assert [location] = get_resp_header(conn, "location")
      refute location =~ "operator_grant"
      assert location == "/#{account.name}"

      grant = get_session(conn, "operator_grants")[account.name]
      assert grant.tier == :read
      assert grant.account_id == account.id
    end

    test "ignores and strips an invalid token", %{signer: _signer} do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/#{account.name}?operator_grant=not-a-token")
        |> Plug.Test.init_test_session(%{})
        |> OperatorGrant.accept_operator_grant([])

      assert conn.halted
      assert get_session(conn, "operator_grants") == nil
    end
  end

  defp operator_user do
    AccountsFixtures.user_fixture(
      email: "operator-#{System.unique_integer([:positive])}@tuist.dev",
      preload: [:account]
    )
  end

  defp with_handles(conn, account_handle, project_handle) do
    conn =
      conn
      |> Plug.Conn.put_private(:phoenix_endpoint, TuistWeb.Endpoint)
      |> Plug.Test.init_test_session(%{auth_method: :google})

    %{conn | params: %{"account_handle" => account_handle, "project_handle" => project_handle}}
  end

  defp claims(account_handle) do
    now = System.system_time(:second)

    %{
      "iss" => "ops.tuist.dev",
      "aud" => "tuist-server",
      "sub" => "operator@tuist.dev",
      "account_handle" => account_handle,
      "tier" => "read",
      "reason" => "investigating",
      "jti" => "1",
      "iat" => now,
      "exp" => now + 600
    }
  end

  defp mint(signer, claims) do
    {_meta, token} = signer |> JOSE.JWT.sign(%{"alg" => "EdDSA"}, claims) |> JOSE.JWS.compact()
    token
  end

  defp unwrap({_kty, pem}), do: pem
  defp unwrap(pem) when is_binary(pem), do: pem
end
