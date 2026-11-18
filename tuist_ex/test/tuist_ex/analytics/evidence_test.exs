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

  test "attributes to a test what it ran alone, and nothing to tests that overlapped", %{dir: dir} do
    File.write!(Path.join(dir, "m.erl"), """
    -module(m).
    -export([boot/0, a/0, b/0, setup/0]).
    boot() ->
      ok.
    a() ->
      ok.
    b() ->
      ok.
    setup() ->
      ok.
    """)

    script = ~S"""
    dir = System.fetch_env!("EVIDENCE_DIR")
    :code.set_coverage_mode(:line_counters)
    {:ok, :m, bin} = :compile.file(String.to_charlist(Path.join(dir, "m.erl")), [:binary, :line_coverage])
    {:module, :m} = :code.load_binary(:m, ~c"m.erl", bin)
    # What runs before any test, as the application and the test helper do.
    :m.boot()

    ExUnit.start(autorun: false, formatters: [])
    true = TuistEx.Analytics.Evidence.start([:m])

    defmodule SerialTest do
      use ExUnit.Case
      test "a", do: :m.a()
      test "b", do: :m.b()
    end

    defmodule SetupAllTest do
      use ExUnit.Case

      setup_all do
        :m.setup()
        :ok
      end

      test "inside", do: :m.a()
    end

    # Modules ExUnit runs alongside each other.
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

    ExUnit.run()
    collected = TuistEx.Analytics.Evidence.collect()
    IO.puts("RESULT " <> Base.encode64(:erlang.term_to_binary(collected)))
    """

    {output, 0} = run_child(script, dir)
    [_, encoded] = Regex.run(~r/RESULT (\S+)/, output)
    collected = encoded |> Base.decode64!() |> :erlang.binary_to_term()

    # Line 4 is boot/0's body, 6 a/0's, 8 b/0's and 10 setup/0's.
    assert collected.boot == %{m: [4]}
    assert collected.tests[{SerialTest, :"test a"}] == %{m: [6]}
    assert collected.tests[{SerialTest, :"test b"}] == %{m: [8]}
    assert collected.tests[{SetupAllTest, :"test inside"}] == %{m: [6]}

    assert collected.overlapped ==
             MapSet.new([{AsyncOneTest, :"test x"}, {AsyncTwoTest, :"test y"}])

    refute Map.has_key?(collected.tests, {AsyncOneTest, :"test x"})
    # A module's `setup_all` is part of what every one of its tests depends on.
    assert collected.targets[SetupAllTest] == %{m: [6, 10]}
    assert collected.targets[SerialTest] == %{m: [6, 8]}
    refute collected.failed
  end

  describe "payload/4" do
    test "names scopes by the identities runs report and paths by the repository" do
      collected = %{
        boot: %{App: [1, 2]},
        tests: %{{CartTest, :"test add/2 adds"} => %{Cart: [3, 4, 5, 9], Outside: [1]}},
        targets: %{CartTest => %{Cart: [3, 4, 5, 9, 20]}},
        overlapped: MapSet.new([{AsyncTest, :"test races"}]),
        failed: false
      }

      identities = %{
        {CartTest, :"test add/2 adds"} => {"CartTest", "add/2", "adds"},
        {AsyncTest, :"test races"} => {"AsyncTest", "", "races"}
      }

      sources = %{App: "/repo/lib/app.ex", Cart: "/repo/lib/cart.ex", Outside: "/elsewhere/x.ex"}

      relative =
        &if(String.starts_with?(&1, "/repo/"), do: String.replace_prefix(&1, "/repo/", ""))

      assert Evidence.payload(collected, identities, sources, relative) == %{
               paths: ["lib/app.ex", "lib/cart.ex"],
               scopes: [
                 %{
                   kind: "test",
                   module: "CartTest",
                   suite: "add/2",
                   name: "adds",
                   files: [1],
                   lines: [[3, 5, 9, 9]]
                 },
                 # What ran before any test is part of every module's.
                 %{
                   kind: "target",
                   module: "AsyncTest",
                   suite: "",
                   name: "",
                   files: [0],
                   lines: [[1, 2]]
                 },
                 %{
                   kind: "target",
                   module: "CartTest",
                   suite: "",
                   name: "",
                   files: [0, 1],
                   lines: [[1, 2], [3, 5, 9, 9, 20, 20]]
                 }
               ],
               overlapped_tests: [%{module: "AsyncTest", suite: "", name: "races"}],
               status: "collected"
             }
    end

    test "a run whose hook failed says so" do
      collected = %{boot: %{}, tests: %{}, targets: %{}, overlapped: MapSet.new(), failed: true}
      assert %{status: "failed", scopes: []} = Evidence.payload(collected, %{}, %{}, & &1)
    end
  end

  test "ranges/1 flattens consecutive lines into inclusive ranges" do
    assert Evidence.ranges([]) == []
    assert Evidence.ranges([7]) == [7, 7]
    assert Evidence.ranges([3, 4, 5, 9, 11, 12]) == [3, 5, 9, 9, 11, 12]
  end
end
