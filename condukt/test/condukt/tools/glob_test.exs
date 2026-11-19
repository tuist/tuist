defmodule Condukt.Tools.GlobTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox
  alias Condukt.Tools.Glob

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: tmp_dir)
    %{context: %{sandbox: sandbox, opts: []}}
  end

  test "lists matching paths", %{tmp_dir: tmp_dir, context: context} do
    File.write!(Path.join(tmp_dir, "a.ex"), "")
    File.write!(Path.join(tmp_dir, "b.ex"), "")

    {:ok, result} = Glob.call(%{"pattern" => "*.ex"}, context)
    assert String.contains?(result, "a.ex")
    assert String.contains?(result, "b.ex")
  end

  test "a pattern without a slash matches names at any depth", %{tmp_dir: tmp_dir, context: context} do
    File.mkdir_p!(Path.join(tmp_dir, "lib/deep"))
    File.write!(Path.join(tmp_dir, "lib/deep/c.ex"), "")
    File.write!(Path.join(tmp_dir, "top.ex"), "")

    assert {:ok, "lib/deep/c.ex\ntop.ex"} = Glob.call(%{"pattern" => "*.ex"}, context)
    assert {:ok, "top.ex"} = Glob.call(%{"pattern" => "./top.ex"}, context)
    assert {:ok, "No files found matching pattern"} = Glob.call(%{"pattern" => "deep/*.ex"}, context)
  end

  test "says when the limit cut results off", %{tmp_dir: tmp_dir, context: context} do
    for name <- ~w(a b c), do: File.write!(Path.join(tmp_dir, name <> ".ex"), "")

    assert {:ok, "a.ex\nb.ex\n\n[2 results limit reached. Use limit=4 for more, or refine pattern]"} =
             Glob.call(%{"pattern" => "*.ex", "limit" => 2}, context)

    assert {:ok, "a.ex\nb.ex\nc.ex"} = Glob.call(%{"pattern" => "*.ex", "limit" => 3}, context)
  end

  test "reports no matches", %{context: context} do
    {:ok, result} = Glob.call(%{"pattern" => "*.nope"}, context)
    assert result == "No files found matching pattern"
  end

  test "raises a clear error if context.sandbox is missing", %{tmp_dir: tmp_dir} do
    assert_raise ArgumentError, ~r/requires context\.sandbox/, fn ->
      Glob.call(%{"pattern" => "*"}, %{cwd: tmp_dir, opts: []})
    end
  end
end
