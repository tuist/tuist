defmodule Pulse.Storage.SortOrderTest do
  # SortOrder is the shared tie-breaker for every storage adapter. A client
  # that swaps adapters must never see the order change when timestamps are
  # equal, so this coverage runs against the pure sort — no adapter needed.

  use Pulse.Test.Case, async: true

  alias Pulse.Record.Log
  alias Pulse.Storage.SortOrder

  defp log(ts, opts \\ []) do
    %Log{
      timestamp_ns: ts,
      observed_timestamp_ns: Keyword.get(opts, :observed),
      trace_id: Keyword.get(opts, :trace_id),
      span_id: Keyword.get(opts, :span_id),
      body: Keyword.get(opts, :body)
    }
  end

  test "primary sort is timestamp_ns descending" do
    result = SortOrder.sort([log(10), log(30), log(20)])
    assert Enum.map(result, & &1.timestamp_ns) == [30, 20, 10]
  end

  test "equal timestamp_ns falls through to observed_timestamp_ns descending" do
    result =
      SortOrder.sort([
        log(10, observed: 100),
        log(10, observed: 300),
        log(10, observed: 200)
      ])

    assert Enum.map(result, & &1.observed_timestamp_ns) == [300, 200, 100]
  end

  test "trace_id and body break further ties deterministically" do
    a = log(10, observed: 5, trace_id: "aaa", body: "one")
    b = log(10, observed: 5, trace_id: "aaa", body: "two")
    c = log(10, observed: 5, trace_id: "bbb", body: "one")

    # The precise order matters less than the fact that repeated sorts of
    # the same input produce the same output.
    assert SortOrder.sort([a, b, c]) == SortOrder.sort([c, b, a])
    assert SortOrder.sort([a, b, c]) == SortOrder.sort([b, a, c])
  end

  test "nil fields sort last within their position" do
    with_trace = log(10, observed: 5, trace_id: "aaa")
    without_trace = log(10, observed: 5, trace_id: nil)

    result = SortOrder.sort([without_trace, with_trace])
    assert Enum.map(result, & &1.trace_id) == ["aaa", nil]
  end

  test "a non-string body sorts without crashing" do
    # OTLP `AnyValue` can produce a body that is not a String — an
    # integer, a boolean, a list. The sort layer must not crash on those;
    # sorting is for stability, not for user-facing order.
    int_body = %Log{timestamp_ns: 10, observed_timestamp_ns: 5, body: 42}
    list_body = %Log{timestamp_ns: 10, observed_timestamp_ns: 5, body: [1, 2, 3]}
    bool_body = %Log{timestamp_ns: 10, observed_timestamp_ns: 5, body: true}
    string_body = %Log{timestamp_ns: 10, observed_timestamp_ns: 5, body: "z"}
    nil_body = %Log{timestamp_ns: 10, observed_timestamp_ns: 5, body: nil}

    assert [_, _, _, _, _] = SortOrder.sort([int_body, list_body, bool_body, string_body, nil_body])
  end

  test "nil and empty string in the same position are distinguishable" do
    # Prior version collapsed `nil` and `""` into the same sort key, so two
    # otherwise-identical records could reorder unpredictably. Now `nil`
    # sorts after every real string, including `""`.
    with_empty = log(10, observed: 5, trace_id: "", body: "z")
    without = log(10, observed: 5, trace_id: nil, body: "z")

    result = SortOrder.sort([without, with_empty])
    assert Enum.map(result, & &1.trace_id) == ["", nil]
  end
end
