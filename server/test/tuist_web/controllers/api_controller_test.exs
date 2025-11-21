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
      data_configuration = Jason.decode!(attrs["data-configuration"])
      assert data_configuration["spec"] == %{"url" => "/api/spec"}
      assert data_configuration["theme"] == "purple"
      assert data_configuration["authentication"]["http"]["basic"] == %{}
      assert data_configuration["authentication"]["http"]["bearer"]["token"]
      assert data_configuration["authentication"]["preferredSecurityScheme"] == "authorization"
      assert html =~ "<title>API Documentation · Tuist</title>"
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
      data_configuration = Jason.decode!(attrs["data-configuration"])
      assert data_configuration["spec"] == %{"url" => "/api/spec"}
      assert data_configuration["theme"] == "purple"
      assert data_configuration["authentication"]["http"]["basic"] == %{}
      assert data_configuration["authentication"]["http"]["bearer"]["token"] == ""
      assert data_configuration["authentication"]["preferredSecurityScheme"] == "authorization"
      assert html =~ "<title>API Documentation · Tuist</title>"
    end
  end
end
