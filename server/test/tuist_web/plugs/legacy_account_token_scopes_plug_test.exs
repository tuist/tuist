defmodule TuistWeb.Plugs.LegacyAccountTokenScopesPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias TuistWeb.Plugs.LegacyAccountTokenScopesPlug

  describe "call/2" do
    test "transforms legacy registry_read scope to account:registry:read", %{conn: conn} do
      # Given
      conn = %{conn | body_params: %{"scopes" => ["registry_read"]}}

      # When
      result = LegacyAccountTokenScopesPlug.call(conn, [])

      # Then
      assert result.body_params["scopes"] == ["account:registry:read"]
    end

    test "keeps new format scopes unchanged", %{conn: conn} do
      # Given
      conn = %{conn | body_params: %{"scopes" => ["project:cache:read", "account:registry:read"]}}

      # When
      result = LegacyAccountTokenScopesPlug.call(conn, [])

      # Then
      assert result.body_params["scopes"] == ["project:cache:read", "account:registry:read"]
    end

    test "transforms mixed legacy and new scopes", %{conn: conn} do
      # Given
      conn = %{conn | body_params: %{"scopes" => ["registry_read", "project:cache:read"]}}

      # When
      result = LegacyAccountTokenScopesPlug.call(conn, [])

      # Then
      assert result.body_params["scopes"] == ["account:registry:read", "project:cache:read"]
    end

    test "passes through conn when scopes is not present", %{conn: conn} do
      # Given
      conn = %{conn | body_params: %{"name" => "test-token"}}

      # When
      result = LegacyAccountTokenScopesPlug.call(conn, [])

      # Then
      assert result.body_params == %{"name" => "test-token"}
    end

    test "passes through conn when body_params is empty", %{conn: conn} do
      # Given
      conn = %{conn | body_params: %{}}

      # When
      result = LegacyAccountTokenScopesPlug.call(conn, [])

      # Then
      assert result.body_params == %{}
    end
  end
end
