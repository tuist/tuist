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

    test "does not redirect when the ops reason-form url is unconfigured", %{conn: conn} do
      stub(Tuist.Environment, :ops_reason_form_url, fn -> nil end)
      project = ProjectsFixtures.project_fixture(preload: [:account])
      operator = operator_user()

      conn =
        conn
        |> with_handles(project.account.name, project.name)
        |> assign(:current_user, operator)
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

    test "stores a valid grant in the session for its operator subject", %{signer: signer} do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      operator = operator_user()
      token = mint(signer, claims(account.name, operator.email))

      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/#{account.name}?operator_grant=#{token}")
        |> Plug.Test.init_test_session(%{auth_method: :google})
        |> assign(:current_user, operator)
        |> OperatorGrant.accept_operator_grant([])

      assert conn.halted
      assert [location] = get_resp_header(conn, "location")
      refute location =~ "operator_grant"
      assert location == "/#{account.name}"

      grant = get_session(conn, "operator_grants")[account.name]
      assert grant.tier == :read
      assert grant.account_id == account.id
    end

    test "rejects a grant when the session is not Google-authenticated", %{signer: signer} do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      operator = operator_user()
      token = mint(signer, claims(account.name, operator.email))

      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/#{account.name}?operator_grant=#{token}")
        |> Plug.Test.init_test_session(%{})
        |> assign(:current_user, operator)
        |> OperatorGrant.accept_operator_grant([])

      assert conn.halted
      assert get_session(conn, "operator_grants") == nil
    end

    test "rejects a valid grant presented by a non-operator session", %{signer: signer} do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      # Token minted for an operator, but the session belongs to a regular
      # customer user: a leaked redirect-back URL must not attach the grant.
      token = mint(signer, claims(account.name, "operator@tuist.dev"))
      customer = AccountsFixtures.user_fixture(preload: [:account])

      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/#{account.name}?operator_grant=#{token}")
        |> Plug.Test.init_test_session(%{auth_method: :google})
        |> assign(:current_user, customer)
        |> OperatorGrant.accept_operator_grant([])

      assert conn.halted
      assert [location] = get_resp_header(conn, "location")
      refute location =~ "operator_grant"
      assert get_session(conn, "operator_grants") == nil
    end

    test "rejects a grant presented by a different operator", %{signer: signer} do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      subject = operator_user()
      other_operator = operator_user()
      token = mint(signer, claims(account.name, subject.email))

      conn =
        :get
        |> Phoenix.ConnTest.build_conn("/#{account.name}?operator_grant=#{token}")
        |> Plug.Test.init_test_session(%{auth_method: :google})
        |> assign(:current_user, other_operator)
        |> OperatorGrant.accept_operator_grant([])

      assert conn.halted
      assert get_session(conn, "operator_grants") == nil
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

  describe "load_operator_grant/2" do
    test "stamps the grant jti + sub onto logger metadata" do
      operator = operator_user()
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      now = System.system_time(:second)

      claims = %{
        tier: :read,
        account_id: account.id,
        account_handle: account.name,
        sub: operator.email,
        jti: "grant-42",
        exp: now + 600
      }

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{"operator_grants" => %{account.name => claims}})
        |> assign(:current_user, operator)
        |> Map.put(:params, %{"account_handle" => account.name})
        |> OperatorGrant.load_operator_grant([])

      assert Logger.metadata()[:operator_grant_jti] == "grant-42"
      assert Logger.metadata()[:operator_grant_sub] == operator.email
      assert conn.assigns.current_user.operator_grant.jti == "grant-42"
    end

    test "loads the grant despite case drift between the session key and the URL handle" do
      operator = operator_user()
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      now = System.system_time(:second)

      claims = %{
        tier: :read,
        account_id: account.id,
        account_handle: "acme",
        sub: operator.email,
        jti: "g1",
        exp: now + 600
      }

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{"operator_grants" => %{"acme" => claims}})
        |> assign(:current_user, operator)
        |> Map.put(:params, %{"account_handle" => "ACME"})
        |> OperatorGrant.load_operator_grant([])

      assert conn.assigns.current_user.operator_grant.jti == "g1"
    end
  end

  describe "active_grant?/2 (SSO bypass binding)" do
    test "true for the operator the grant was minted for (case-insensitive handle)" do
      operator = operator_user()
      conn = assign(Phoenix.ConnTest.build_conn(), :current_user, %{operator | operator_grant: grant_for(operator)})
      assert OperatorGrant.active_grant?(conn, "acme")
      assert OperatorGrant.active_grant?(conn, "ACME")
    end

    test "false when the grant is for a different account than the request" do
      operator = operator_user()
      conn = assign(Phoenix.ConnTest.build_conn(), :current_user, %{operator | operator_grant: grant_for(operator)})
      refute OperatorGrant.active_grant?(conn, "other-account")
    end

    test "false when the holder is a different operator" do
      grant = grant_for(operator_user())
      other = operator_user()
      conn = assign(Phoenix.ConnTest.build_conn(), :current_user, %{other | operator_grant: grant})
      refute OperatorGrant.active_grant?(conn, "acme")
    end

    test "false when the holder is not a Tuist operator" do
      customer = AccountsFixtures.user_fixture(preload: [:account])
      conn = assign(Phoenix.ConnTest.build_conn(), :current_user, %{customer | operator_grant: grant_for(customer)})
      refute OperatorGrant.active_grant?(conn, "acme")
    end

    test "false when the grant is expired" do
      operator = operator_user()
      grant = grant_for(operator, exp: System.system_time(:second) - 1)
      conn = assign(Phoenix.ConnTest.build_conn(), :current_user, %{operator | operator_grant: grant})
      refute OperatorGrant.active_grant?(conn, "acme")
    end

    test "false without a grant" do
      conn = assign(Phoenix.ConnTest.build_conn(), :current_user, operator_user())
      refute OperatorGrant.active_grant?(conn, "acme")
    end
  end

  defp grant_for(user, opts \\ []) do
    now = System.system_time(:second)

    %{
      tier: :read,
      account_id: 1,
      account_handle: "acme",
      sub: user.email,
      exp: Keyword.get(opts, :exp, now + 600)
    }
  end

  defp operator_user do
    user =
      AccountsFixtures.user_fixture(
        email: "operator-#{System.unique_integer([:positive])}@tuist.dev",
        preload: [:account]
      )

    AccountsFixtures.oauth2_identity_fixture(user: user, provider: :google)
    user
  end

  defp with_handles(conn, account_handle, project_handle) do
    conn =
      conn
      |> Plug.Conn.put_private(:phoenix_endpoint, TuistWeb.Endpoint)
      |> Plug.Test.init_test_session(%{auth_method: :google})

    %{conn | params: %{"account_handle" => account_handle, "project_handle" => project_handle}}
  end

  defp claims(account_handle, sub) do
    now = System.system_time(:second)

    %{
      "iss" => "ops.tuist.dev",
      "aud" => "tuist-server",
      "sub" => sub,
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
