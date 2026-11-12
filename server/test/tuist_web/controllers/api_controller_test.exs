defmodule TuistWeb.APIControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.dev")
    %{user: user}
  end

  describe "docs" do
    test "includes the right scalar configuration when the user is authenticated", %{
      conn: conn,
      user: user
    } do
      # When
      conn = conn |> log_in_user(user) |> get("/api/docs")

      # Then
      html = html_response(conn, 200)
      {:ok, document} = Floki.parse_document(html)
      [{"script", attrs, _}] = Floki.find(document, "#api-reference")
      attrs = Map.new(attrs)
      assert attrs["data-url"] == "/api/spec"
      data_configuration = JSON.decode!(attrs["data-configuration"])
      assert data_configuration["spec"] == %{"url" => "/api/spec"}
      assert data_configuration["theme"] == "purple"
      assert data_configuration["authentication"]["http"]["basic"] == %{}
      assert data_configuration["authentication"]["http"]["bearer"]["token"]
      assert data_configuration["authentication"]["preferredSecurityScheme"] == "authorization"
      assert html =~ "<title>API Documentation · Tuist</title>"
    end

    test "does not embed a token for a session that skipped enforced single sign-on", %{user: user} do
      organization = AccountsFixtures.organization_fixture()
      :ok = Tuist.Accounts.add_user_to_organization(user, organization, role: :user)

      organization
      |> Ecto.Changeset.change(sso_enforced: true, sso_provider: :google, sso_organization_id: "api-example.com")
      |> Tuist.Repo.update!()

      token = fn auth ->
        html =
          build_conn()
          |> init_test_session(%{})
          |> put_session(:user_token, Tuist.Accounts.generate_user_session_token(user, auth))
          |> get("/api/docs")
          |> html_response(200)

        {:ok, document} = Floki.parse_document(html)
        [configuration] = Floki.attribute(document, "#api-reference", "data-configuration")
        JSON.decode!(configuration)["authentication"]["http"]["bearer"]["token"]
      end

      assert token.(%{auth_method: :password}) == ""
      assert token.(%{auth_method: :google, provider_organization_id: "api-example.com"}) != ""
    end

    test "includes the designed Open Graph card when hosted", %{conn: conn} do
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)

      conn = get(conn, "/api/docs")

      {:ok, document} = conn |> html_response(200) |> Floki.parse_document()
      [image] = Floki.attribute(document, "meta[property='og:image']", "content")

      assert image == Tuist.Environment.app_url(path: "/images/open-graph/api-docs-card.jpeg")
    end

    test "omits the Open Graph image on-premise, where the image route is not served", %{
      conn: conn
    } do
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)

      conn = get(conn, "/api/docs")

      {:ok, document} = conn |> html_response(200) |> Floki.parse_document()
      assert Floki.find(document, "meta[property='og:image']") == []
    end

    test "includes the right scalar configuration when the user is not authenticated", %{
      conn: conn
    } do
      # When
      conn = get(conn, "/api/docs")

      # Then
      html = html_response(conn, 200)
      {:ok, document} = Floki.parse_document(html)
      [{"script", attrs, _}] = Floki.find(document, "#api-reference")
      attrs = Map.new(attrs)
      assert attrs["data-url"] == "/api/spec"
      data_configuration = JSON.decode!(attrs["data-configuration"])
      assert data_configuration["spec"] == %{"url" => "/api/spec"}
      assert data_configuration["theme"] == "purple"
      assert data_configuration["authentication"]["http"]["basic"] == %{}
      assert data_configuration["authentication"]["http"]["bearer"]["token"] == ""
      assert data_configuration["authentication"]["preferredSecurityScheme"] == "authorization"
      assert html =~ "<title>API Documentation · Tuist</title>"
    end
  end
end
