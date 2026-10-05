defmodule TuistTestSupport.InClusterReads do
  @moduledoc """
  Turns on `Tuist.ClickHouse.ReadRoute` for the calling test process, with an
  in-cluster ClickHouse that cannot answer.

  The test process is registered under `Tuist.ShadowClickHouseRepo`'s name in
  place of its pool, so routing considers the instance running, and a read that
  is routed fails on the repository lookup, as it does when the in-cluster
  server has drifted from the system of record. Other processes keep the
  feature flag's real value, and the registration goes away with the test.
  The name is global, so only `async: false` tests can use this.
  """

  alias Tuist.ShadowClickHouseRepo

  def route_reads_in_cluster do
    Process.register(self(), ShadowClickHouseRepo)
    Mimic.stub(Tuist.Environment, :clickhouse_bare_metal_url, fn -> "http://clickhouse:8123/tuist" end)

    Mimic.stub(FunWithFlags, :enabled?, fn
      :clickhouse_bare_metal_reads -> true
      flag -> Mimic.call_original(FunWithFlags, :enabled?, [flag])
    end)

    :ok
  end
end
