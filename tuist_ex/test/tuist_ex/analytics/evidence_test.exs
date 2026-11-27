defmodule TuistEx.Analytics.EvidenceTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.Evidence

  setup do
    dir = Path.join(System.tmp_dir!(), "tuist-ex-evidence-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  # Runs `script` in a VM of its own: collecting replaces ExUnit's handler
  # and switches the runtime's coverage mode, which this suite must not see.
  defp run_child(script, dir) do
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    System.cmd(System.find_executable("elixir"), paths ++ ["-e", script],
      stderr_to_stdout: true,
      env: [{"EVIDENCE_DIR", dir}]
    )
  end

  # The child's `coverage_evidence`, with scopes keyed by kind, module and
  # name and their files resolved to `{path, lines}`.
  defp run_suite(dir, max_cases, lines?) do
    File.write!(Path.join(dir, "m.erl"), """
    -module(m).
    -export([boot/0, a/0, b/0, setup/0, teardown/0]).
    boot() ->
      ok.
    a() ->
      ok.
    b() ->
      ok.
    setup() ->
      ok.
    teardown() ->
      ok.
    """)

    # A module with a dependency's code and a template compiled into it,
    # which only `TemplateTest` runs: from each `-file` attribute, its line 1,
    # the lines are the dependency's, which count for nothing, then the
    # template's.
    File.write!(Path.join(dir, "n.erl"), """
    -module(n).
    -export([own/0, dep/0, render/1]).
    own() ->
      ok.
    -file("deps/dep/lib/dep.ex", 1).
    dep() ->
      ok.
    -file("n.html.heex", 1).
    render(X) ->
      case X of
        a -> one;
        _ -> other
      end.
    """)

    # A module whose only code from another file is a dependency's.
    File.write!(Path.join(dir, "o.erl"), """
    -module(o).
    -export([own/0, dep/0]).
    own() ->
      ok.
    -file("deps/dep/lib/dep.ex", 1).
    dep() ->
      ok.
    """)

    script = """
    dir = System.fetch_env!("EVIDENCE_DIR")
    :code.set_coverage_mode(:line_counters)
    {:ok, :m, bin} = :compile.file(String.to_charlist(Path.join(dir, "m.erl")), [:binary, :line_coverage])
    {:module, :m} = :code.load_binary(:m, ~c"m.erl", bin)
    ebin = Path.join(dir, "ebin")
    File.mkdir_p!(ebin)
    for module <- ["n", "o"] do
      {:ok, _} = :compile.file(String.to_charlist(Path.join(dir, module <> ".erl")), [:debug_info, outdir: String.to_charlist(ebin)])
    end
    {2, []} = TuistEx.Analytics.Coverage.instrument(ebin, dir, [])
    {:module, :n} = :code.load_abs(String.to_charlist(Path.join(ebin, "n")))
    {:module, :o} = :code.load_abs(String.to_charlist(Path.join(ebin, "o")))
    # What runs before any test, as the application and the test helper do.
    :m.boot()

    ExUnit.start(autorun: false, formatters: [], max_cases: #{max_cases})
    true = TuistEx.Analytics.Evidence.start([:m, :n, :o])

    defmodule SerialTest do
      use ExUnit.Case
      test "a", do: :m.a()
      test "b", do: :m.b()
    end

    defmodule SetupAllTest do
      use ExUnit.Case

      setup_all do
        :m.setup()
        on_exit(fn -> :m.teardown() end)
        :ok
      end

      test "inside", do: :m.a()
    end

    # Modules ExUnit runs alongside each other, unless one at a time.
    defmodule AsyncOneTest do
      use ExUnit.Case, async: true

      test "x" do
        Process.sleep(200)
        :m.a()
      end
    end

    defmodule AsyncTwoTest do
      use ExUnit.Case, async: true

      test "y" do
        Process.sleep(200)
        :m.b()
      end
    end

    defmodule TemplateTest do
      use ExUnit.Case
      test "render", do: :n.dep() && :n.render(:a)
    end

    defmodule DepTest do
      use ExUnit.Case
      test "dep", do: :o.own() && :o.dep()
    end

    ExUnit.run()
    collected = TuistEx.Analytics.Evidence.collect()

    identities =
      for {module, name, suite} <- [
            {SerialTest, "a", ""}, {SerialTest, "b", ""}, {SetupAllTest, "inside", ""},
            {AsyncOneTest, "x", ""}, {AsyncTwoTest, "y", ""}, {TemplateTest, "render", ""},
            {DepTest, "dep", ""}
          ],
          into: %{},
          do: {{module, :"test \#{name}"}, {inspect(module), suite, name}}

    out = Path.join(dir, "evidence.json")
    sources = %{
      m: %{files: %{0 => Path.join(dir, "m.erl")}, resources: []},
      n: %{files: %{0 => Path.join(dir, "n.erl"), 2 => Path.join(dir, "n.html.heex")}, resources: [Path.join(dir, "n.po")]},
      o: %{files: %{0 => Path.join(dir, "o.erl")}, resources: []}
    }
    {:ok, _} = TuistEx.Analytics.Evidence.write(collected, identities, sources, &Path.basename/1, out, lines: #{lines?})
    File.rm_rf!(collected.dir)
    IO.puts("RESULT " <> Base.encode64(File.read!(out)))
    """

    {output, 0} = run_child(script, dir)
    [_, encoded] = Regex.run(~r/RESULT (\S+)/, output)
    evidence = encoded |> Base.decode64!() |> JSON.decode!()

    scopes =
      Map.new(evidence["scopes"], fn scope ->
        files = Enum.map(scope["files"], &Enum.at(evidence["paths"], &1))
        lines = scope["lines"] || Enum.map(files, fn _ -> nil end)
        {{scope["kind"], scope["module"], scope["name"]}, Enum.zip(files, lines)}
      end)

    {evidence, scopes}
  end

  test "attributes to a test the lines it ran alone, and nothing to tests that overlapped",
       %{dir: dir} do
    {evidence, scopes} = run_suite(dir, 4, true)

    # Line 4 is boot/0's body, 6 a/0's, 8 b/0's, 10 setup/0's, 12 teardown/0's.
    assert scopes[{"test", "SerialTest", "a"}] == [{"m.erl", [6, 6]}]
    assert scopes[{"test", "SerialTest", "b"}] == [{"m.erl", [8, 8]}]
    assert scopes[{"test", "SetupAllTest", "inside"}] == [{"m.erl", [6, 6]}]

    assert Enum.sort(evidence["overlapped_tests"]) == [
             %{"module" => "AsyncOneTest", "name" => "x", "suite" => ""},
             %{"module" => "AsyncTwoTest", "name" => "y", "suite" => ""}
           ]

    refute Map.has_key?(scopes, {"test", "AsyncOneTest", "x"})

    # A module's `setup_all`, its tests and its `setup_all`'s `on_exit` are
    # part of what every one of its tests depends on, as is the boot.
    assert scopes[{"target", "SetupAllTest", ""}] == [{"m.erl", [4, 4, 6, 6, 10, 10, 12, 12]}]
    assert scopes[{"target", "SerialTest", ""}] == [{"m.erl", [4, 4, 6, 6, 8, 8]}]
    # Overlapped tests' modules still depend on the boot.
    assert scopes[{"target", "AsyncOneTest", ""}] == [{"m.erl", [4, 4]}]
    assert evidence["status"] == "collected"
  end

  test "attributes a template's lines to the template, and a module's resources to what ran it",
       %{dir: dir} do
    {_evidence, scopes} = run_suite(dir, 1, true)

    # The template's lines 3 and 4 are the `case` and its first clause; the
    # resource holds no lines.
    assert Enum.sort(scopes[{"test", "TemplateTest", "render"}]) ==
             [{"n.html.heex", [3, 4]}, {"n.po", []}]

    # A module that didn't run brings no resources.
    assert scopes[{"test", "SerialTest", "a"}] == [{"m.erl", [6, 6]}]

    # A dependency's code counts in no file: line 4 is own/0's body.
    assert scopes[{"test", "DepTest", "dep"}] == [{"o.erl", [4, 4]}]
  end

  test "one module at a time, async tests get their own lines", %{dir: dir} do
    {evidence, scopes} = run_suite(dir, 1, true)

    assert evidence["overlapped_tests"] == []
    assert scopes[{"test", "AsyncOneTest", "x"}] == [{"m.erl", [6, 6]}]
    assert scopes[{"test", "AsyncTwoTest", "y"}] == [{"m.erl", [8, 8]}]
    assert scopes[{"target", "AsyncTwoTest", ""}] == [{"m.erl", [4, 4, 8, 8]}]
    # A test doesn't pick up the previous module's teardown.
    assert scopes[{"test", "SetupAllTest", "inside"}] == [{"m.erl", [6, 6]}]
  end

  test "without lines, scopes name their files only", %{dir: dir} do
    {_evidence, scopes} = run_suite(dir, 1, false)

    assert scopes[{"test", "SerialTest", "a"}] == [{"m.erl", nil}]
    assert scopes[{"target", "SetupAllTest", ""}] == [{"m.erl", nil}]
  end

  test "executed/2 compares counters by position, as a line can hold several" do
    # A `def` with default arguments has a counter per generated clause.
    before = [{Cart, [{474, 3}, {474, 0}, {476, 3}]}, {Other, [{1, 2}]}]
    now = [{Cart, [{474, 3}, {474, 0}, {476, 4}]}, {Other, [{1, 2}]}, {Loaded, [{7, 1}, {8, 0}]}]

    assert Evidence.executed(now, before) == %{Cart => [476], Loaded => [7]}
    # A module whose counters changed shape counts every line that ran.
    assert Evidence.executed([{Cart, [{474, 3}]}], before) == %{Cart => [474]}
  end

  test "ranges/1 flattens consecutive lines into inclusive ranges" do
    assert Evidence.ranges([]) == []
    assert Evidence.ranges([7]) == [7, 7]
    assert Evidence.ranges([3, 4, 5, 9, 11, 12]) == [3, 5, 9, 9, 11, 12]
  end
end
