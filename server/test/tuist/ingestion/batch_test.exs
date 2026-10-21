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

  @timestamp ~N[2026-10-01 12:00:00.123456]

  test "fact identities are stable UUIDv7s within a report and distinct across reports" do
    first = Batch.run({"plan", 0, 1}, @timestamp, fn -> Batch.uuid(:case) end)
    assert Tuist.UUIDv7.valid?(first)
    assert first == Batch.run({"plan", 0, 1}, @timestamp, fn -> Batch.uuid(:case) end)
    refute first == Batch.run({"plan", 1, 1}, @timestamp, fn -> Batch.uuid(:case) end)
    refute first == Batch.run({"plan", 0, 2}, @timestamp, fn -> Batch.uuid(:case) end)
    refute first == Batch.run({"plan", 0, 1}, @timestamp, fn -> Batch.uuid(:module) end)
    refute first == Batch.run({"plan", 0, 1}, NaiveDateTime.add(@timestamp, 1), fn -> Batch.uuid(:case) end)

    assert first |> String.replace("-", "") |> String.slice(0, 12) |> String.to_integer(16) ==
             NaiveDateTime.diff(@timestamp, ~N[1970-01-01 00:00:00], :millisecond)
  end

  test "exceptions clear request-local staging and identity" do
    assert_raise RuntimeError, "stopped", fn ->
      Batch.run(:report, @timestamp, fn -> raise "stopped" end)
    end

    assert String.at(Batch.uuid(:case), 14) == "7"
    assert :ok == Batch.run(:next, @timestamp, fn -> :ok end)
  end

  test "nested batches do not erase the outer batch" do
    Batch.run(:outer, @timestamp, fn ->
      expected = Batch.uuid(:case)
      assert_raise ArgumentError, fn -> Batch.run(:inner, @timestamp, fn -> :ok end) end
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

    assert {10, nil} == Batch.run(:bounded, @timestamp, fn -> Batch.insert_all(Fact, List.duplicate(row, 10)) end)
  end
end
