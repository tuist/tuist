defmodule Tuist.Ingestion.BatchTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Ingestion.Batch
  alias Tuist.IngestRepo

  defmodule Fact do
    @moduledoc false
    use Ecto.Schema
    use Tuist.Ingestion.Bufferable

    @primary_key {:id, Ecto.UUID, autogenerate: false}
    schema "batch_test_facts" do
      field :payload, :string
    end
  end

  test "fact identities are stable within a report and distinct across reports" do
    first = Batch.run({"plan", 0, 1}, fn -> Batch.uuid(:case) end)
    assert first == Batch.run({"plan", 0, 1}, fn -> Batch.uuid(:case) end)
    refute first == Batch.run({"plan", 1, 1}, fn -> Batch.uuid(:case) end)
    refute first == Batch.run({"plan", 0, 2}, fn -> Batch.uuid(:case) end)
    refute first == Batch.run({"plan", 0, 1}, fn -> Batch.uuid(:module) end)
  end

  test "exceptions clear request-local staging and identity" do
    assert_raise RuntimeError, "stopped", fn ->
      Batch.run(:report, fn -> raise "stopped" end)
    end

    assert String.at(Batch.uuid(:case), 14) == "7"
    assert :ok == Batch.run(:next, fn -> :ok end)
  end

  test "nested batches do not erase the outer batch" do
    Batch.run(:outer, fn ->
      expected = Batch.uuid(:case)
      assert_raise ArgumentError, fn -> Batch.run(:inner, fn -> :ok end) end
      assert Batch.uuid(:case) == expected
    end)
  end

  test "encoded staging is bounded by the per-table limit plus one oversized row" do
    payload = String.duplicate("x", 1024 * 1024)
    row = %{id: Ecto.UUID.generate(), payload: payload}

    expect(IngestRepo, :query, 2, fn sql, [header | chunks], opts ->
      assert sql =~ "batch_test_facts"
      assert opts[:encode] == false
      assert IO.iodata_length(chunks) <= 9 * 1024 * 1024
      assert byte_size(header) > 0
      {:ok, %{}}
    end)

    assert {10, nil} == Batch.run(:bounded, fn -> Batch.insert_all(Fact, List.duplicate(row, 10)) end)
  end
end
