defmodule Tuist.ClickHouse.ReadRoute do
  @moduledoc """
  Sends `Tuist.ClickHouseRepo`'s reads to the in-cluster ClickHouse instead of
  to ClickHouse Cloud, for as long as a flag says to (spec #73).

  This is the last step of the migration and the only one a customer can see,
  so it is the one that has to be reversible in seconds rather than in a
  deploy. It is therefore a `FunWithFlags` toggle, flipped from `/ops/flags`.

  It is deliberately global rather than per actor. Routing is decided at the
  repository boundary, where there is no request and therefore no organization
  to decide for; threading one through every read path is the coupling this
  module exists to avoid. So the rollout is all reads or none, and the safety
  it trades that against is how quickly it reverses.

  ## Why a dynamic repository

  The alternative is for every read path to choose between two repository
  modules, which would mean the retry, telemetry and sandbox behaviour of
  `Tuist.ClickHouseRepo` being reimplemented on the second one, or quietly
  lost. Naming `Tuist.ShadowClickHouseRepo` as the dynamic repository instead
  changes only which connection pool this process talks to, once, at the
  repository boundary. It is the same mechanism the test environment already
  uses to point reads at the sandboxed ingest repository.

  The pool is only in the supervision tree while a destination is configured,
  so the flag alone cannot route reads at a server that is not there: both
  conditions are required.
  """

  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.ShadowClickHouseRepo

  @instance ShadowClickHouseRepo

  @doc """
  Runs `fun` against the in-cluster ClickHouse when routing is on, and against
  the system of record otherwise.
  """
  def route(fun) do
    if enabled?() do
      previous = ClickHouseRepo.get_dynamic_repo()
      ClickHouseRepo.put_dynamic_repo(@instance)

      try do
        fun.()
      after
        ClickHouseRepo.put_dynamic_repo(previous)
      end
    else
      fun.()
    end
  end

  @doc """
  Whether reads are being served by the in-cluster ClickHouse.
  """
  def enabled? do
    configured?() and FunWithFlags.enabled?(:clickhouse_bare_metal_reads)
  end

  # Cheap and local: the instance is only registered when the URL was set at
  # boot, so this asks whether the pool exists rather than reading config on
  # every query.
  defp configured? do
    not is_nil(Environment.clickhouse_bare_metal_url()) and not is_nil(Process.whereis(@instance))
  end
end
