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
    assert String.contains?(result, "match(es)")
  end

  test "reports no matches", %{context: context} do
    {:ok, result} = Glob.call(%{"pattern" => "*.nope"}, context)
    assert result =~ "No files matched"
  end

  test "raises a clear error if context.sandbox is missing", %{tmp_dir: tmp_dir} do
    assert_raise ArgumentError, ~r/requires context\.sandbox/, fn ->
      Glob.call(%{"pattern" => "*"}, %{cwd: tmp_dir, opts: []})
    end
  end
end
