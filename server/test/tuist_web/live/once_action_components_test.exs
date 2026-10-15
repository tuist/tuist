defmodule TuistWeb.OnceActionComponentsTest do
  use ExUnit.Case, async: true

  alias TuistWeb.OnceActionComponents

  test "source commitment alignment fails closed without discarding paths" do
    files = ["one", "two", "three", "four"]

    for {statuses, links} <- [
          {nil, [true, true, true, true]},
          {[], [true, true, true, true]},
          {[1, 2, 3, 99], [true, false, false, false]},
          {[1], [false, false, false, false]}
        ] do
      rows = OnceActionComponents.source_rows(%{source_files: files, source_file_statuses: statuses})
      assert Enum.map(rows, & &1.file) == files
      assert Enum.map(rows, & &1.index) == [0, 1, 2, 3]
      assert Enum.map(rows, & &1.link?) == links
    end
  end

  test "large classified source lists have a linear reduction budget" do
    files = Enum.map(1..50_000, &"src/#{&1}.rs")
    statuses = Enum.map(1..50_000, &if(rem(&1, 2) == 0, do: 1, else: 2))
    {:reductions, before} = Process.info(self(), :reductions)
    rows = OnceActionComponents.source_rows(%{source_files: files, source_file_statuses: statuses})
    {:reductions, after_count} = Process.info(self(), :reductions)

    assert after_count - before < 5_000_000
    assert length(rows) == 50_000
    assert hd(rows) == %{file: "src/1.rs", index: 0, link?: false}
    assert List.last(rows) == %{file: "src/50000.rs", index: 49_999, link?: true}
  end

  test "terminal outcomes never show an in-progress badge" do
    for result <- ["failed", "timed_out", "infrastructure_error"] do
      assert OnceActionComponents.status_variant(result) == "error"
    end

    for result <- ["skipped", "cancelled"] do
      assert OnceActionComponents.status_variant(result) == "disabled"
    end
  end
end
