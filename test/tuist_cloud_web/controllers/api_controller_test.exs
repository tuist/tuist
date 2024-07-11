defmodule TuistCloudWeb.APIControllerTest do
  use TuistCloudWeb.ConnCase, async: true
  alias TuistCloud.AccountsFixtures
  use Mimic

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(email: "tuist@tuist.io")
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
      data_configuration = attrs["data-configuration"] |> Jason.decode!()
      assert data_configuration["spec"] == %{"url" => "/api/spec"}
      assert data_configuration["theme"] == "purple"
      assert data_configuration["authentication"]["http"]["basic"] == %{}
      assert data_configuration["authentication"]["http"]["bearer"]["token"] != nil
      assert data_configuration["authentication"]["preferredSecurityScheme"] == "authorization"
      assert attrs = ~p"/api/spec"
      assert html =~ "<title>API Documentation · Tuist</title>"
    end

    test "includes the right scalar configuration when the user is not authenticated", %{
      conn: conn,
      user: user
    } do
      # When
      conn = conn |> get("/api/docs")

      # Then
      html = html_response(conn, 200)
      {:ok, document} = Floki.parse_document(html)
      [{"script", attrs, _}] = Floki.find(document, "#api-reference")
      attrs = Map.new(attrs)
      assert attrs["data-url"] == "/api/spec"
      data_configuration = attrs["data-configuration"] |> Jason.decode!()
      assert data_configuration["spec"] == %{"url" => "/api/spec"}
      assert data_configuration["theme"] == "purple"
      assert data_configuration["authentication"]["http"]["basic"] == %{}
      assert data_configuration["authentication"]["http"]["bearer"]["token"] == ""
      assert data_configuration["authentication"]["preferredSecurityScheme"] == "authorization"
      assert attrs = ~p"/api/spec"
      assert html =~ "<title>API Documentation · Tuist</title>"
    end
  end
end
