defmodule Tuist.IngestRepo.DictionarySourceCredentialsTest do
  @moduledoc """
  A `CLICKHOUSE` dictionary source is resolved inside the ClickHouse server, so
  it authenticates separately from the connection that created it. Naming no
  user makes it fall back to `default` with an empty password, which passes on
  a server with no password set and fails everywhere else with Code 516. Dev,
  test and the managed instance are all passwordless, so no environment we run
  migrations against catches this; only the source text does.
  """
  use ExUnit.Case, async: true

  @migrations_path Path.join([__DIR__, "..", "..", "..", "priv", "ingest_repo", "migrations"])

  test "every dictionary reading a local table names the credentials the repo connects with" do
    anonymous =
      @migrations_path
      |> Path.join("*.exs")
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        path |> File.read!() |> String.contains?("SOURCE(CLICKHOUSE(")
      end)
      |> Enum.map(&Path.basename/1)
      |> Enum.sort()

    assert anonymous == [],
           """
           These migrations build a dictionary whose source names no user, so ClickHouse \
           authenticates it as `default` with an empty password and fails with Code 516 on \
           any instance that sets one:

           #{Enum.map_join(anonymous, "\n", &("  " <> &1))}

           Render the source with `Tuist.ClickHouseDictionarySource.local_table/2` instead.
           """
  end
end
