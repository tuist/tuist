defmodule Condukt.Tools.GrepTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox
  alias Condukt.Tools.Grep

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: tmp_dir)
    %{context: %{sandbox: sandbox, opts: []}}
  end

  test "formats matches as path:line: text", %{tmp_dir: tmp_dir, context: context} do
    File.write!(Path.join(tmp_dir, "a.ex"), "alpha\nneedle\ngamma")

    {:ok, result} = Grep.call(%{"pattern" => "needle"}, context)
    assert result == "a.ex:2: needle"
  end

  test "filters by glob", %{tmp_dir: tmp_dir, context: context} do
    File.write!(Path.join(tmp_dir, "keep.ex"), "needle")
    File.write!(Path.join(tmp_dir, "skip.txt"), "needle")

    {:ok, result} = Grep.call(%{"pattern" => "needle", "glob" => "*.ex"}, context)
    assert result =~ "keep.ex"
    refute result =~ "skip.txt"
  end

  test "reports no matches", %{context: context} do
    {:ok, result} = Grep.call(%{"pattern" => "nothing"}, context)
    assert result =~ "No matches"
  end

  test "surfaces invalid regex errors", %{context: context} do
    {:error, error} = Grep.call(%{"pattern" => "["}, context)
    assert error =~ "Invalid regex"
  end
end
