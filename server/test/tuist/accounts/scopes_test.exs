defmodule Tuist.Accounts.ScopesTest do
  use ExUnit.Case, async: true

  alias Tuist.Accounts.Scopes

  describe "all_scopes/0" do
    test "returns all valid scopes" do
      scopes = Scopes.all_scopes()

      assert "account:members:read" in scopes
      assert "account:members:write" in scopes
      assert "account:registry:read" in scopes
      assert "account:registry:write" in scopes
      assert "project:previews:read" in scopes
      assert "project:previews:write" in scopes
      assert "project:admin:read" in scopes
      assert "project:admin:write" in scopes
      assert "project:cache:read" in scopes
      assert "project:cache:write" in scopes
      assert "project:bundles:read" in scopes
      assert "project:bundles:write" in scopes
      assert "project:tests:read" in scopes
      assert "project:tests:write" in scopes
      assert "project:builds:read" in scopes
      assert "project:builds:write" in scopes
    end
  end

  describe "account_scopes/0" do
    test "returns only account-level scopes" do
      scopes = Scopes.account_scopes()

      assert length(scopes) == 4
      assert "account:members:read" in scopes
      assert "account:members:write" in scopes
      assert "account:registry:read" in scopes
      assert "account:registry:write" in scopes
    end
  end

  describe "project_scopes/0" do
    test "returns only project-level scopes" do
      scopes = Scopes.project_scopes()

      assert length(scopes) == 12

      Enum.each(scopes, fn scope ->
        assert String.starts_with?(scope, "project:")
      end)
    end
  end

  describe "valid?/1" do
    test "returns true for valid scopes" do
      assert Scopes.valid?("project:cache:read")
      assert Scopes.valid?("project:cache:write")
      assert Scopes.valid?("account:members:read")
    end

    test "returns false for invalid scopes" do
      refute Scopes.valid?("invalid:scope")
      refute Scopes.valid?("project:cache:delete")
      refute Scopes.valid?("project:cache")
    end
  end

  describe "validate/1" do
    test "returns :ok when all scopes are valid" do
      assert :ok == Scopes.validate(["project:cache:read", "account:registry:write"])
    end

    test "returns :ok for empty list" do
      assert :ok == Scopes.validate([])
    end

    test "returns error with invalid scopes" do
      assert {:error, ["invalid:scope"]} == Scopes.validate(["project:cache:read", "invalid:scope"])
    end

    test "returns all invalid scopes in error" do
      result = Scopes.validate(["invalid:one", "project:cache:read", "invalid:two"])
      assert {:error, invalid} = result
      assert "invalid:one" in invalid
      assert "invalid:two" in invalid
      refute "project:cache:read" in invalid
    end
  end

  describe "parse/1" do
    test "parses valid scope into components" do
      assert {:ok, %{entity_type: "project", object: "cache", access_level: "read"}} ==
               Scopes.parse("project:cache:read")
    end

    test "parses account scope into components" do
      assert {:ok, %{entity_type: "account", object: "members", access_level: "write"}} ==
               Scopes.parse("account:members:write")
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} == Scopes.parse("invalid")
      assert {:error, :invalid_format} == Scopes.parse("project:cache")
      assert {:error, :invalid_format} == Scopes.parse("a:b:c:d")
    end
  end

  describe "account_scope?/1" do
    test "returns true for account scopes" do
      assert Scopes.account_scope?("account:members:read")
      assert Scopes.account_scope?("account:registry:write")
    end

    test "returns false for project scopes" do
      refute Scopes.account_scope?("project:cache:read")
    end
  end

  describe "project_scope?/1" do
    test "returns true for project scopes" do
      assert Scopes.project_scope?("project:cache:read")
      assert Scopes.project_scope?("project:builds:write")
    end

    test "returns false for account scopes" do
      refute Scopes.project_scope?("account:members:read")
    end
  end
end
