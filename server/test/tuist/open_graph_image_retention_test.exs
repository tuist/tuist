defmodule Tuist.OpenGraphImageRetentionTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.OpenGraphImageRetention
  alias Tuist.Storage

  test "deletes generated images older than the retention window" do
    now = ~U[2026-09-05 12:00:00Z]
    old = DateTime.add(now, -31, :day)
    recent = DateTime.add(now, -29, :day)

    expect(Storage, :list_objects, fn "open-graph-images/", :open_graph_images, opts ->
      assert opts[:max_keys] == 1_000
      assert opts[:continuation_token] == nil

      {:ok,
       %{
         body: %{
           contents: [
             %{key: "open-graph-images/old.jpg", last_modified: old},
             %{key: "open-graph-images/recent.jpg", last_modified: recent}
           ],
           is_truncated: false
         }
       }}
    end)

    expect(Storage, :delete_objects, fn ["open-graph-images/old.jpg"], :open_graph_images -> :ok end)

    assert OpenGraphImageRetention.delete_expired(now: now) == {:ok, nil}
  end

  test "returns the storage continuation token" do
    expect(Storage, :list_objects, fn "open-graph-images/", :open_graph_images, opts ->
      assert opts[:continuation_token] == "previous"

      {:ok,
       %{
         body: %{
           contents: [],
           is_truncated: true,
           next_continuation_token: "next"
         }
       }}
    end)

    assert OpenGraphImageRetention.delete_expired(continuation_token: "previous") == {:ok, "next"}
  end
end
