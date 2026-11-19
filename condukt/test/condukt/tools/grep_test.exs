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
    assert result == "No matches found"
  end

  test "surfaces invalid regex errors", %{context: context} do
    {:error, error} = Grep.call(%{"pattern" => "["}, context)
    assert error =~ "Invalid regex"
  end

  test "filters nested files by name when the glob has no slash", %{tmp_dir: tmp_dir, context: context} do
    File.mkdir_p!(Path.join(tmp_dir, "lib"))
    File.write!(Path.join(tmp_dir, "lib/deep.ex"), "needle")

    assert {:ok, "lib/deep.ex:1: needle"} = Grep.call(%{"pattern" => "needle", "glob" => "*.ex"}, context)
  end

  test "shows context lines and marks matches inside them", %{tmp_dir: tmp_dir, context: context} do
    File.write!(Path.join(tmp_dir, "a.txt"), "one\ntwo\nneedle\nfour\nneedle\nsix\nseven\neight")

    assert {:ok, result} = Grep.call(%{"pattern" => "needle", "context" => 1}, context)
    assert result == "a.txt-2- two\na.txt:3: needle\na.txt-4- four\na.txt:5: needle\na.txt-6- six"
  end

  test "literal and ignoreCase", %{tmp_dir: tmp_dir, context: context} do
    File.write!(Path.join(tmp_dir, "a.txt"), "a.b(c)\naxb(c)\nNEEDLE")

    assert {:ok, "a.txt:1: a.b(c)"} = Grep.call(%{"pattern" => "a.b(c)", "literal" => true}, context)
    assert {:ok, "a.txt:3: NEEDLE"} = Grep.call(%{"pattern" => "needle", "ignoreCase" => true}, context)
  end

  test "says when the match limit or line length cut output", %{tmp_dir: tmp_dir, context: context} do
    long = String.duplicate("x", 600)
    File.write!(Path.join(tmp_dir, "a.txt"), "hit #{long}\nhit\nhit")

    assert {:ok, result} = Grep.call(%{"pattern" => "hit", "limit" => 2}, context)
    [first, second, "", notice] = String.split(result, "\n")
    assert first == "a.txt:1: hit " <> String.duplicate("x", 496) <> "... [truncated]"
    assert second == "a.txt:2: hit"

    assert notice ==
             "[2 matches limit reached. Use limit=4 for more, or refine pattern. " <>
               "Some lines truncated to 500 chars. Use read tool to see full lines]"

    assert {:ok, "a.txt:2: hit\na.txt:3: hit"} = Grep.call(%{"pattern" => "^hit$", "limit" => 2}, context)
  end

  # A sandbox that counts lines differently from `\\n` splits, as one that
  # breaks lines at a lone CR does, can report a line past the file's end.
  defmodule CrLines do
    @behaviour Condukt.Sandbox

    @impl true
    def init(opts), do: Sandbox.Local.init(opts)
    @impl true
    def shutdown(_state), do: :ok
    @impl true
    def read_file(state, path), do: Sandbox.Local.read_file(state, path)
    @impl true
    def write_file(state, path, content), do: Sandbox.Local.write_file(state, path, content)
    @impl true
    def edit_file(state, path, old, new), do: Sandbox.Local.edit_file(state, path, old, new)
    @impl true
    def exec(state, command, opts), do: Sandbox.Local.exec(state, command, opts)
    @impl true
    def cwd(state), do: Sandbox.Local.cwd(state)
    @impl true
    def grep(_state, _pattern, _opts), do: {:ok, [%{path: "cr.txt", line_number: 5, line: "needle"}]}
  end

  test "context leaves out lines past the end of the file", %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "cr.txt"), "a\rb\rc\rd\rneedle")
    {:ok, sandbox} = Sandbox.new(CrLines, cwd: tmp_dir)

    assert {:ok, "cr.txt:5: needle"} =
             Grep.call(%{"pattern" => "needle", "context" => 1}, %{sandbox: sandbox, opts: []})
  end
end
