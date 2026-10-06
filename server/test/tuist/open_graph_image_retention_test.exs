defmodule Tuist.OpenGraphImageRetentionTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.OpenGraphImageRetention
  alias Tuist.Storage

  test "deletes only project images older than the retention window" do
    now = ~U[2026-09-05 12:00:00Z]
    old = DateTime.add(now, -31, :day)
    recent = DateTime.add(now, -29, :day)
    boundary = DateTime.add(now, -30, :day)

    expect(Storage, :list_objects, fn "open-graph-images/projects/", :open_graph_images, opts ->
      assert opts[:max_keys] == 1_000
      assert opts[:continuation_token] == nil

      {:ok,
       %{
         body: %{
           contents: [
             %{key: "open-graph-images/projects/old.jpg", last_modified: old},
             %{key: "open-graph-images/projects/old-string.jpg", last_modified: DateTime.to_iso8601(old)},
             %{key: "open-graph-images/projects/recent.jpg", last_modified: recent},
             %{key: "open-graph-images/projects/boundary.jpg", last_modified: boundary},
             %{key: "open-graph-images/projects/unknown-date.jpg", last_modified: "invalid"}
           ],
           is_truncated: false
         }
       }}
    end)

    expect(Storage, :delete_objects, fn
      ["open-graph-images/projects/old.jpg", "open-graph-images/projects/old-string.jpg"], :open_graph_images -> :ok
    end)

    assert OpenGraphImageRetention.delete_expired(now: now) == {:ok, nil}
  end

  test "returns the storage continuation token" do
    expect(Storage, :list_objects, fn "open-graph-images/projects/", :open_graph_images, opts ->
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
