defmodule Tuist.Builds.CacheRegionTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Builds.Build
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

  describe "serving_attrs/1" do
    test "maps the parser's summary" do
      assert CacheRegion.serving_attrs(%{
               "region" => "us-central",
               "node" => "acme-us-central-0",
               "connected_at" => "2026-09-28T09:00:00.000",
               "connected_before_build_seconds" => 120,
               "region_requests" => 90,
               "observed_requests" => 100
             }) == %{
               cache_serving_region: "us-central",
               cache_serving_node: "acme-us-central-0",
               cache_serving_region_requests: 90,
               cache_observed_requests: 100,
               cache_connected_at: ~N[2026-09-28 09:00:00.000],
               cache_connected_before_build_seconds: 120
             }
    end

    test "is empty when no region was recorded" do
      assert CacheRegion.serving_attrs(nil) == %{}
      assert CacheRegion.serving_attrs(%{"region" => ""}) == %{}
    end

    test "tolerates an unparseable connection time" do
      assert %{cache_connected_at: nil, cache_connected_before_build_seconds: nil} =
               CacheRegion.serving_attrs(%{"region" => "eu-west", "connected_at" => "yesterday"})
    end
  end

  describe "verdict/1" do
    test "compares the serving region with the expected one" do
      assert CacheRegion.verdict(build(expected: "ap-southeast", serving: "us-central")) == :mismatch
      assert CacheRegion.verdict(build(expected: "ap-southeast", serving: "ap-southeast")) == :match
    end

    test "is unknown when either side is missing" do
      assert CacheRegion.verdict(build(expected: "", serving: "us-central")) == :unknown
      assert CacheRegion.verdict(build(expected: "us-central", serving: "")) == :unknown
      assert CacheRegion.verdict(%{id: "not a build"}) == :unknown
    end

    test "is unknown for regions a client's resolver cannot pick" do
      # The runner cache is reached by configuration and self-hosted regions are
      # not in the catalog; neither says anything about the client's network.
      assert CacheRegion.verdict(build(expected: "eu-west", serving: "scw-fr-par-runners")) == :unknown
      assert CacheRegion.verdict(build(expected: "eu-west", serving: "office-rack")) == :unknown
    end
  end

  describe "summary/1" do
    test "describes a mismatched build" do
      summary =
        [expected: "ap-southeast", serving: "us-central"]
        |> build()
        |> Map.merge(%{
          client_origin: "AU",
          cache_serving_node: "acme-us-central-0",
          cache_serving_region_requests: 180,
          cache_observed_requests: 200,
          cache_connected_at: ~N[2026-09-28 09:00:00.000],
          cache_connected_before_build_seconds: 600
        })
        |> CacheRegion.summary()

      assert summary == %{
               client_origin: "AU",
               expected_region: "ap-southeast",
               serving_region: "us-central",
               serving_node: "acme-us-central-0",
               serving_region_share: 0.9,
               connected_at: ~U[2026-09-28 09:00:00.000Z],
               connected_before_build_seconds: 600,
               verdict: "mismatch"
             }
    end

    test "is nil for a build that recorded none of it" do
      assert CacheRegion.summary(%Build{}) == nil
    end
  end

  test "region_name/1 prefers the catalog's display name" do
    assert CacheRegion.region_name("ap-southeast") == "Asia Pacific Southeast"
    assert CacheRegion.region_name("office-rack") == "office-rack"
    assert CacheRegion.region_name(nil) == nil
  end

  defp build(expected: expected, serving: serving) do
    %Build{cache_expected_region: expected, cache_serving_region: serving}
  end
end
