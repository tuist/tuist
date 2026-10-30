defmodule TuistWeb.BrowserTelemetry.DeduplicationTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.BrowserTelemetry.Receipts
  alias TuistWeb.BrowserTelemetry.Deduplication

  defp measurement(lcp \\ 7524) do
    %{
      "type" => "web-vitals",
      "values" => %{"lcp" => lcp},
      "context" => %{"id" => "measurement-1", "navigation_entry_id" => "navigation-1", "rum_ray_id" => "first"}
    }
  end

  defp meta, do: %{"session" => %{"id" => "session-1"}}

  test "replays keep their identity across collectors, while updates and navigations remain distinct" do
    key = Deduplication.key(measurement(), meta())
    assert byte_size(key) == 32
    assert key == Deduplication.key(put_in(measurement(), ["context", "rum_ray_id"], "second"), meta())
    assert key == Deduplication.key(measurement(7524.0), meta())
    refute key == Deduplication.key(measurement(8000), meta())
    refute key == Deduplication.key(put_in(measurement(), ["context", "navigation_entry_id"], "navigation-2"), meta())
    refute key == Deduplication.key(measurement(), %{"session" => %{"id" => "session-2"}})
  end

  test "missing and placeholder identifiers cannot collapse unrelated observations" do
    for value <- [nil, "", "unknown", "  ", String.duplicate("a", 257)] do
      assert is_nil(Deduplication.key(put_in(measurement(), ["context", "navigation_entry_id"], value), meta()))
      assert is_nil(Deduplication.key(put_in(measurement(), ["context", "id"], value), meta()))
      assert is_nil(Deduplication.key(measurement(), %{"session" => %{"id" => value}}))
    end

    assert is_nil(Deduplication.key(measurement(-1), meta()))
    assert is_nil(Deduplication.key(measurement(), %{"session" => "malformed"}))
    assert byte_size(Deduplication.key(measurement(Integer.pow(10, 400)), meta())) == 32
    assert is_nil(Deduplication.key(%{"type" => "custom", "context" => %{}}, meta()))
  end

  test "marks repeats within and across batches, preserves raw values and other collections" do
    first = measurement()
    updated = measurement(8000)
    untracked = put_in(first, ["context", "navigation_entry_id"], "unknown")

    payload = %{
      "meta" => meta(),
      "measurements" => [first, first, updated, updated, untracked],
      "events" => [%{"name" => "navigation"}]
    }

    expect(Receipts, :deliver, fn keys, forward ->
      assert length(keys) == 4
      forward.(MapSet.new([Deduplication.key(first, meta())]))
    end)

    assert {:ok, :accepted} =
             Deduplication.deliver(payload, fn forwarded ->
               assert Enum.map(forwarded["measurements"], & &1["context"]["rum_deduplication"]) ==
                        ["duplicate", "duplicate", "unique", "duplicate", "untracked"]

               assert Enum.map(forwarded["measurements"], & &1["values"]) ==
                        Enum.map(payload["measurements"], & &1["values"])

               assert forwarded["events"] == payload["events"]
               {:ok, :accepted}
             end)
  end
end
