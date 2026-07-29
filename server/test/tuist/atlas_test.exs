defmodule Tuist.AtlasTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Atlas
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "customer_context/1" do
    test "returns the Atlas customer context by account handle" do
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        current_month_remote_cache_hits_count: 42
      )

      assert {:ok, %{current_month_remote_cache_hits: 42}} = Atlas.customer_context("tuist-org")
    end

    test "returns not_found when the account handle does not exist" do
      assert {:error, :not_found} = Atlas.customer_context("missing")
    end
  end
end
