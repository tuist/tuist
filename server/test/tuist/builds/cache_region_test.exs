defmodule Tuist.Builds.CacheRegionTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Builds.CacheRegion
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.KuraFixtures

  describe "client_attrs/2" do
    test "expects the account's serving region nearest the origin" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      KuraFixtures.active_server_fixture(account, region: "us-central")
      KuraFixtures.active_server_fixture(account, region: "ap-southeast")

      assert CacheRegion.client_attrs(account, "AU") == %{
               client_origin: "AU",
               cache_expected_region: "ap-southeast"
             }

      assert CacheRegion.client_attrs(account, "US-IL") == %{
               client_origin: "US-IL",
               cache_expected_region: "us-central"
             }
    end

    test "keeps the origin but expects nothing of an account without managed regions" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      assert CacheRegion.client_attrs(account, "AU") == %{client_origin: "AU", cache_expected_region: ""}
    end

    test "records nothing for an unattributed request" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      KuraFixtures.active_server_fixture(account, region: "us-central")

      assert CacheRegion.client_attrs(account, nil) == %{client_origin: "", cache_expected_region: ""}
    end
  end
end
