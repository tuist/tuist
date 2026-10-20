defmodule Tuist.IngestRepo.MigrationTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.IngestRepo
  alias Tuist.IngestRepo.Migration

  # The newest ingest migration from before engines went through
  # `Migration.engine/1`. Every migration after it has to use it.
  @enforced_after 20_260_914_120_000

  describe "for_database/2" do
    test "gives a Replicated database the replicated variant of each MergeTree engine" do
      assert Migration.for_database("MergeTree", "Replicated") == "ReplicatedMergeTree"

      assert Migration.for_database("ReplacingMergeTree(inserted_at)", "Replicated") ==
               "ReplicatedReplacingMergeTree(inserted_at)"

      assert Migration.for_database("AggregatingMergeTree", "Replicated") == "ReplicatedAggregatingMergeTree"
      assert Migration.for_database("SummingMergeTree", "Replicated") == "ReplicatedSummingMergeTree"
    end

    test "leaves an engine that is already replicated alone" do
      assert Migration.for_database("ReplicatedMergeTree", "Replicated") == "ReplicatedMergeTree"
    end

    test "leaves the engine as written on a database that is not replicated" do
      assert Migration.for_database("ReplacingMergeTree(inserted_at)", "Atomic") == "ReplacingMergeTree(inserted_at)"
    end

    test "refuses an engine a Replicated database cannot hold" do
      assert_raise ArgumentError, ~r/Memory/, fn -> Migration.for_database("Memory", "Replicated") end
    end
  end

  describe "engine/1" do
    setup do
      # Without the sandbox's transaction, which `system.databases` does not
      # support. A migration runs without one as well.
      owner = Sandbox.start_owner!(IngestRepo, sandbox: false)
      on_exit(fn -> Sandbox.stop_owner(owner) end)
    end

    test "asks the migrated database which engine it needs" do
      # The test database is not replicated, so the engine comes back as written.
      assert Migration.engine("ReplacingMergeTree(inserted_at)") == "ReplacingMergeTree(inserted_at)"
    end
  end

  describe "ingest migrations" do
    test "declare MergeTree engines through Migration.engine/1" do
      offending =
        :tuist
        |> Application.app_dir("priv/ingest_repo/migrations/*.exs")
        |> Path.wildcard()
        |> Enum.filter(&(version(&1) > @enforced_after and literal_engine?(File.read!(&1))))
        |> Enum.map(&Path.basename/1)

      assert offending == [],
             "Declare the table engines in these migrations through Tuist.IngestRepo.Migration.engine/1: #{inspect(offending)}"
    end

    test "tell an engine written directly from one written through the helper" do
      assert literal_engine?(~s|ENGINE = ReplacingMergeTree(inserted_at) ORDER BY id|)
      assert literal_engine?(~s|engine: "MergeTree",|)
      refute literal_engine?(~s|ENGINE = \#{Migration.engine("MergeTree")} ORDER BY id|)
      refute literal_engine?(~s|engine: Migration.engine("ReplacingMergeTree(inserted_at)"),|)
    end
  end

  defp version(path), do: path |> Path.basename() |> String.split("_", parts: 2) |> hd() |> String.to_integer()

  defp literal_engine?(source), do: Regex.match?(~r/engine\s*=\s*\w*MergeTree|engine:\s*"\w*MergeTree/i, source)
end
