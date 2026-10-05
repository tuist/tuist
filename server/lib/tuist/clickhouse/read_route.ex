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

  ## Reads that gate a write

  ClickHouse Cloud stays the system of record until the migration finishes, so
  the in-cluster server is allowed to be behind it, in schema or in data. A read
  that only renders a page can live with that. A read on an ingest path cannot:
  if it fails, the write behind it never happens, and the client gives up after
  its retries. `primary/1` keeps every read made inside it on the system of
  record, so ingest paths wrap their whole unit of work in it rather than
  having to find each read that sits in front of a write.
  """

  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.ShadowClickHouseRepo

  @instance ShadowClickHouseRepo
  @primary {__MODULE__, :primary}

  @doc """
  Runs `fun` against the in-cluster ClickHouse when routing is on, and against
  the system of record otherwise.
  """
  def route(fun) do
    if not primary?() and enabled?() do
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
  Runs `fun` with every read inside it on the system of record, whether or not
  routing is on.
  """
  def primary(fun) do
    previous = Process.put(@primary, true)

    try do
      fun.()
    after
      if previous, do: Process.put(@primary, previous), else: Process.delete(@primary)
    end
  end

  @doc """
  Whether the calling process is inside `primary/1`.
  """
  def primary?, do: Process.get(@primary, false)

  @doc """
  Whether reads are being served by the in-cluster ClickHouse.
  """
  def enabled? do
    configured?() and FunWithFlags.enabled?(:clickhouse_bare_metal_reads)
  end

  # The process lookup comes first because it is the cheaper of the two and it
  # is the one that is false everywhere the migration is not running. This is
  # on the path of every ClickHouse read in the product, so in the environments
  # that will never route anything the whole check should cost one registry
  # lookup rather than building an environment-variable name and reading it.
  defp configured? do
    not is_nil(Process.whereis(@instance)) and not is_nil(Environment.clickhouse_bare_metal_url())
  end
end
