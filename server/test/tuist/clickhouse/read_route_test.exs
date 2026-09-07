defmodule Tuist.ClickHouse.ReadRouteTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.ClickHouse.ReadRoute

  describe "enabled?/0" do
    test "is off when no in-cluster ClickHouse is configured" do
      # Which is every environment that is not mid-migration. The flag alone
      # must not be able to route reads at a server that is not there.
      stub(Tuist.Environment, :clickhouse_bare_metal_url, fn -> nil end)

      refute ReadRoute.enabled?()
    end

    test "is off when the URL is set but the instance is not running" do
      # The pool is started at boot from the same setting, so this is the
      # window during a rollout when configuration and process disagree.
      stub(Tuist.Environment, :clickhouse_bare_metal_url, fn -> "http://clickhouse:8123/tuist" end)

      refute ReadRoute.enabled?()
    end
  end

  describe "route/1" do
    test "leaves the read where it already went while routing is off" do
      stub(Tuist.Environment, :clickhouse_bare_metal_url, fn -> nil end)

      assert ReadRoute.route(fn -> Tuist.ClickHouseRepo.get_dynamic_repo() end) ==
               Tuist.ClickHouseRepo.get_dynamic_repo()
    end

    test "returns the read's value" do
      stub(Tuist.Environment, :clickhouse_bare_metal_url, fn -> nil end)

      assert ReadRoute.route(fn -> :result end) == :result
    end
  end
end
