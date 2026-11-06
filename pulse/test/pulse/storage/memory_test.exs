defmodule Pulse.Storage.MemoryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Record.Log
  alias Pulse.Storage
  alias Pulse.Storage.Memory

  setup do
    Memory.reset()
    :ok
  end

  defp record(ts, opts \\ []) do
    %Log{
      timestamp_ns: ts,
      severity_text: Keyword.get(opts, :severity_text),
      service: Keyword.get(opts, :service),
      body: Keyword.get(opts, :body)
    }
  end

  test "append then query returns the records for the tenant" do
    :ok = Storage.append(:logs, "t1", [record(10), record(20)])
    assert {:ok, records} = Storage.query(:logs, "t1")
    assert Enum.map(records, & &1.timestamp_ns) == [20, 10]
  end

  test "records for one tenant are invisible to another" do
    :ok = Storage.append(:logs, "t1", [record(1)])
    :ok = Storage.append(:logs, "t2", [record(2)])

    assert {:ok, [%Log{timestamp_ns: 1}]} = Storage.query(:logs, "t1")
    assert {:ok, [%Log{timestamp_ns: 2}]} = Storage.query(:logs, "t2")
  end

  test "filters by time range and service" do
    :ok =
      Storage.append(:logs, "t", [
        record(10, service: "api"),
        record(20, service: "web"),
        record(30, service: "api"),
        record(40, service: "api")
      ])

    assert {:ok, records} = Storage.query(:logs, "t", start_ts: 15, end_ts: 35, service: "api")
    assert Enum.map(records, & &1.timestamp_ns) == [30]
  end

  test "applies limit" do
    :ok = Storage.append(:logs, "t", [record(1), record(2), record(3), record(4)])
    assert {:ok, records} = Storage.query(:logs, "t", limit: 2)
    assert length(records) == 2
    assert Enum.map(records, & &1.timestamp_ns) == [4, 3]
  end

  test "nil-timestamp records do not leak through time-bounded queries" do
    # Guards a subtle Elixir term-ordering trap: nil >= 5 returns true
    # because atoms sort above integers. Without an explicit is_integer
    # guard in filter_by_time, nil-ts records would slip past every
    # start_ts filter.
    :ok = Storage.append(:logs, "t", [%Log{timestamp_ns: nil}, record(100)])

    assert {:ok, [%Log{timestamp_ns: 100}]} = Storage.query(:logs, "t", start_ts: 50)
    assert {:ok, [%Log{timestamp_ns: 100}]} = Storage.query(:logs, "t", end_ts: 200)

    # But an unbounded query still returns them.
    assert {:ok, records} = Storage.query(:logs, "t")
    assert Enum.any?(records, &is_nil(&1.timestamp_ns))
  end

  test "stores records verbatim without wall-clock backfill" do
    # Prior versions injected `now` when a timestamp was nil. That was
    # dropped because injecting a fresh timestamp per call breaks the
    # retry-idempotency story in the S3 adapter — the second PUT under
    # the same idempotency key would overwrite the first with a later
    # timestamp. Memory is the test-only adapter and mirrors the same
    # contract for consistency.
    :ok = Storage.append(:logs, "t", [%Log{timestamp_ns: nil, observed_timestamp_ns: nil}])
    assert {:ok, [%Log{timestamp_ns: nil, observed_timestamp_ns: nil}]} = Storage.query(:logs, "t")
  end

  test "equal timestamps are broken by observed_timestamp_ns then trace_id" do
    # Guard against a limit response depending on adapter-internal insertion
    # order. Two adapters must sort ties the same way; both delegate to
    # Pulse.Storage.SortOrder.
    a = %Log{timestamp_ns: 10, observed_timestamp_ns: 100, trace_id: "aaa"}
    b = %Log{timestamp_ns: 10, observed_timestamp_ns: 300, trace_id: "aaa"}
    c = %Log{timestamp_ns: 10, observed_timestamp_ns: 200, trace_id: "bbb"}

    :ok = Storage.append(:logs, "t", [a, b, c])
    assert {:ok, sorted} = Storage.query(:logs, "t")
    assert Enum.map(sorted, & &1.observed_timestamp_ns) == [300, 200, 100]
  end
end
