defmodule TuistEx.Analytics.CoverageTest do
  use ExUnit.Case, async: false
  use Mimic

  alias TuistEx.Analytics.Coverage
  alias TuistEx.Analytics.HTTP
  alias TuistEx.Analytics.Shards

  describe "partial?/1" do
    test "is true when the run's own arguments pick tests" do
      for args <- [
            ["--only", "integration"],
            ["--exclude=slow"],
            ["--failed"],
            ["--stale"],
            ["--max-failures", "1"],
            ["test/a_test.exs"],
            ["--cover", "test/a_test.exs:12"]
          ] do
        assert Coverage.partial?(args), "expected #{inspect(args)} to be partial"
      end
    end

    test "is false for the whole suite, whatever else it is told" do
      for args <- [
            [],
            ["--cover"],
            ["--include", "slow", "--seed", "0"],
            ["--cover", "--export-coverage", "shard-1", "--warnings-as-errors"],
            ["--max-cases", "4", "--trace"]
          ] do
        refute Coverage.partial?(args), "expected #{inspect(args)} not to be partial"
      end
    end
  end

  test "excluded_tags/1 names the tags the run's own --exclude options filter on" do
    assert Coverage.excluded_tags(["--exclude", "slow", "--exclude=test:test a b", "--seed", "0"]) ==
             ["slow", "test"]

    assert Coverage.excluded_tags(["--only", "slow", "--cover"]) == []
  end

  test "narrowed?/1 is true only for arguments that pick the tests to run" do
    for args <- [
          ["--only", "integration"],
          ["--failed"],
          ["--stale"],
          ["--name-pattern=foo"],
          ["test/a_test.exs:12"]
        ] do
      assert Coverage.narrowed?(args), "expected #{inspect(args)} to be narrowed"
    end

    for args <- [
          [],
          ["--exclude", "slow"],
          ["--max-failures", "1"],
          ["--include", "slow", "--cover"]
        ] do
      refute Coverage.narrowed?(args), "expected #{inspect(args)} not to be narrowed"
    end
  end

  describe "report/4" do
    test "keeps the repository's files, relative to its root, with their blobs and lines" do
      snapshot = [
        %{
          path: "/repo/app/lib/a.ex",
          app: "app",
          test?: false,
          lines: %{5 => 0, 2 => 3, 3 => 1},
          functions: [%{name: "run/1", line: 1, calls: 3, covered: 2, executable: 3}]
        },
        %{
          path: "/repo/app/test/support/case.ex",
          app: "app",
          test?: true,
          lines: %{1 => 2, 4 => 0},
          functions: [%{name: "setup/1", line: 1, calls: 2, covered: 1, executable: 2}]
        },
        %{path: "/elixir/lib/enum.ex", app: "elixir", test?: false, lines: %{1 => 1}}
      ]

      report = Coverage.report(snapshot, "/repo", %{"app/lib/a.ex" => "blob-a"}, false)

      assert report.tool == "cover"
      assert report.tool_version =~ ~r/^OTP \d+\/Elixir /
      refute report.partial

      assert report.files == [
               %{
                 path: "app/lib/a.ex",
                 git_blob_id: "blob-a",
                 targets: ["app"],
                 is_test: false,
                 covered_lines: 2,
                 executable_lines: 3,
                 line_numbers: [2, 3, 5],
                 execution_counts: [3, 1, 0],
                 functions: [
                   %{
                     name: "run/1",
                     line_number: 1,
                     execution_count: 3,
                     covered_lines: 2,
                     executable_lines: 3
                   }
                 ]
               },
               %{
                 path: "app/test/support/case.ex",
                 targets: ["app"],
                 is_test: true,
                 covered_lines: 1,
                 executable_lines: 2,
                 line_numbers: [],
                 execution_counts: [],
                 functions: []
               }
             ]
    end
  end

  describe "snapshot/2" do
    setup do
      directory =
        Path.join(System.tmp_dir!(), "tuist-ex-cover-#{System.unique_integer([:positive])}")

      File.mkdir_p!(Path.join(directory, "lib"))
      File.mkdir_p!(Path.join(directory, "ebin"))
      on_exit(fn -> File.rm_rf!(directory) end)

      source = Path.join(directory, "lib/calculator.ex")

      File.write!(source, """
      defmodule TuistExCoverFixture.Calculator do
        def add(a, b) do
          a + b
        end

        def unused(x) do
          x * 2
        end

        defmodule Inner do
          def hi, do: :hi
        end

        def kind(0), do: :zero
        def kind(n), do: n
        def greet(name \\\\ "you"), do: name
        def __schema__(:source), do: "calculators"
      end
      """)

      # Cover compiles from the debug info, which the test environment may leave out.
      debug_info = Code.get_compiler_option(:debug_info)
      Code.put_compiler_option(:debug_info, true)
      Code.put_compiler_option(:ignore_module_conflict, true)

      {:ok, modules, _} =
        Kernel.ParallelCompiler.compile_to_path([source], Path.join(directory, "ebin"),
          return_diagnostics: true
        )

      Code.put_compiler_option(:ignore_module_conflict, false)
      Code.put_compiler_option(:debug_info, debug_info)

      # Under `mix test --cover` the cover server is Mix's, and stopping it
      # would end the run.
      cover_running? = Process.whereis(:cover_server) != nil

      on_exit(fn ->
        if !cover_running?, do: :cover.stop()

        for module <- modules do
          :code.purge(module)
          :code.delete(module)
        end
      end)

      # Mix puts the build on the code path, where sources and function
      # clauses are read from.
      Code.prepend_path(Path.join(directory, "ebin"))
      on_exit(fn -> Code.delete_path(Path.join(directory, "ebin")) end)

      %{directory: directory, source: source, cover_running?: cover_running?}
    end

    test "is nil when cover is not running", %{
      directory: directory,
      cover_running?: cover_running?
    } do
      if !cover_running? do
        :cover.stop()
        assert Coverage.snapshot(directory, app: :calculator) == nil
      end
    end

    test "reads each source file's executable lines and counts, in one entry per file", %{
      directory: directory,
      source: source
    } do
      case :cover.start() do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end

      [ok: _, ok: _] =
        :cover.compile_beam_directory(String.to_charlist(Path.join(directory, "ebin")))

      3 = apply(TuistExCoverFixture.Calculator, :add, [1, 2])
      :zero = apply(TuistExCoverFixture.Calculator, :kind, [0])
      5 = apply(TuistExCoverFixture.Calculator, :kind, [5])
      "you" = apply(TuistExCoverFixture.Calculator, :greet, [])
      "calculators" = apply(TuistExCoverFixture.Calculator, :__schema__, [:source])

      assert %{app: "calculator", test?: false, lines: lines, functions: functions} =
               directory |> Coverage.snapshot(app: :calculator) |> Enum.find(&(&1.path == source))

      # A line only a generated function owns, as the `__schema__/1` Ecto's
      # `schema` defines on its own line, counts for the file but belongs to
      # no listed function.
      assert lines == %{3 => 1, 7 => 0, 11 => 0, 14 => 1, 15 => 1, 16 => 2, 17 => 1}

      # Each function with the line it starts at, how many times it was
      # called, and its lines; the generated `__info__/1` is left out.
      # A function with several clauses counts the calls of each. A default
      # argument adds a function on the same line, which owns no line of its
      # own and is left out.
      assert functions == [
               %{name: "add/2", line: 2, calls: 1, covered: 1, executable: 1},
               %{name: "unused/1", line: 6, calls: 0, covered: 0, executable: 1},
               %{name: "hi/0", line: 11, calls: 0, covered: 0, executable: 1},
               %{name: "kind/1", line: 14, calls: 2, covered: 2, executable: 2},
               %{name: "greet/1", line: 16, calls: 1, covered: 1, executable: 1}
             ]
    end

    test "counts a module Mimic copied under its original's source", %{
      directory: directory,
      source: source
    } do
      case :cover.start() do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end

      [ok: _, ok: _] =
        :cover.compile_beam_directory(String.to_charlist(Path.join(directory, "ebin")))

      # What `Mimic.copy/1` does to a cover-compiled module: the original moves
      # under another name, cover-compiled from its binary, which names no source.
      # Calls before the copy stay in the module's own counters.
      3 = apply(TuistExCoverFixture.Calculator, :add, [1, 2])
      3 = apply(TuistExCoverFixture.Calculator, :add, [1, 2])
      3 = apply(TuistExCoverFixture.Calculator, :add, [1, 2])

      {_beam, coverdata} = Mimic.Module.replace!(TuistExCoverFixture.Calculator, [])

      on_exit(fn ->
        Mimic.Module.clear!(TuistExCoverFixture.Calculator)
        File.rm(coverdata)
      end)

      3 = apply(Mimic.Module.original(TuistExCoverFixture.Calculator), :add, [1, 2])

      assert %{lines: %{3 => 3, 7 => 0}, functions: [%{name: "add/2", calls: 3, covered: 1} | _]} =
               directory |> Coverage.snapshot(app: :calculator) |> Enum.find(&(&1.path == source))
    end

    test "leaves out the modules the project's coverage configuration ignores", %{
      directory: directory,
      source: source
    } do
      case :cover.start() do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end

      [ok: _, ok: _] =
        :cover.compile_beam_directory(String.to_charlist(Path.join(directory, "ebin")))

      ignored = [app: :calculator, test_coverage: [ignore_modules: [~r/\.Inner$/]]]

      assert %{lines: lines} =
               directory |> Coverage.snapshot(ignored) |> Enum.find(&(&1.path == source))

      assert Map.keys(lines) == [3, 7, 14, 15, 16, 17]

      ignored = [
        app: :calculator,
        test_coverage: [
          ignore_modules: [TuistExCoverFixture.Calculator, TuistExCoverFixture.Calculator.Inner]
        ]
      ]

      refute directory |> Coverage.snapshot(ignored) |> Enum.any?(&(&1.path == source))
    end
  end

  describe "native coverage" do
    # A build of one module, as `mix tuist.test.build` leaves it, with the
    # debug info the instrumentation recompiles from.
    setup do
      directory =
        Path.join(System.tmp_dir!(), "tuist-ex-native-#{System.unique_integer([:positive])}")

      config = [
        app: :native_fixture,
        build_path: Path.join(directory, "_build"),
        build_per_environment: false
      ]

      ebin = Mix.Project.compile_path(config)
      File.mkdir_p!(ebin)
      File.mkdir_p!(Path.join(directory, "lib"))
      on_exit(fn -> File.rm_rf!(directory) end)

      source = Path.join(directory, "lib/calc.ex")

      File.write!(source, """
      defmodule TuistExNativeFixture.Calc do
        @moduledoc "Adds."

        def add(a, b) do
          a + b
        end

        def unused(x) do
          x * 2
        end

        def __schema__(:source), do: "calcs"
      end
      """)

      # As a project's build has them: the test environment may leave them out.
      previous = Map.take(Code.compiler_options(), [:debug_info, :docs])
      Code.compiler_options(debug_info: true, docs: true)

      {:ok, _modules, _} =
        Kernel.ParallelCompiler.compile_to_path([source], ebin, return_diagnostics: true)

      Code.compiler_options(previous)
      :code.purge(TuistExNativeFixture.Calc)
      :code.delete(TuistExNativeFixture.Calc)

      %{directory: directory, config: config, ebin: ebin, source: source}
    end

    test "instruments only the modules a compile wrote since", %{ebin: ebin} do
      beam = Path.join(ebin, "Elixir.TuistExNativeFixture.Calc.beam")
      original = File.read!(beam)

      assert {1, []} = Coverage.instrument(ebin)
      instrumented = File.read!(beam)
      assert {0, []} = Coverage.instrument(ebin)
      assert File.read!(beam) == instrumented

      {:ok, {_, [compile_info: info]}} =
        :beam_lib.chunks(String.to_charlist(beam), [:compile_info])

      assert :line_coverage in info[:options]

      # Protocol consolidation reads Elixir's own debug info.
      assert {:ok, {_, [debug_info: {:debug_info_v1, :elixir_erl, _}]}} =
               :beam_lib.chunks(String.to_charlist(beam), [:debug_info])

      # Doctests read the docs off the build.
      assert {:docs_v1, _, :elixir, _, %{"en" => "Adds."}, _, _} =
               Code.fetch_docs(beam)

      # A later compile writes the module without the counters.
      File.write!(beam, original)
      assert {1, []} = Coverage.instrument(ebin)
    end

    test "instrumenting a downloaded shard leaves the builder's build unchanged", %{
      directory: directory,
      config: config,
      ebin: ebin
    } do
      beam = Path.join(ebin, "Elixir.TuistExNativeFixture.Calc.beam")
      original = File.read!(beam)
      original_stat = File.stat!(beam)
      archive = Path.join(directory, "build.tar.gz")
      shard_build = Path.join(directory, "shard-build")

      assert :ok = Shards.archive(config[:build_path], archive)
      assert :ok = Shards.extract(archive, shard_build)
      shard_ebin = Path.join(shard_build, Path.relative_to(ebin, config[:build_path]))
      assert {1, []} = Coverage.instrument(shard_ebin)

      assert File.read!(beam) == original
      assert File.stat!(beam).mtime == original_stat.mtime
      refute File.read!(Path.join(shard_ebin, Path.basename(beam))) == original
    end

    # The consolidated protocols are built into a directory of their own.
    test "instruments every directory it is given", %{directory: directory, ebin: ebin} do
      consolidated = Path.join(directory, "consolidated")
      File.mkdir_p!(consolidated)

      File.cp!(
        Path.join(ebin, "Elixir.TuistExNativeFixture.Calc.beam"),
        Path.join(consolidated, "Elixir.TuistExNativeFixture.Calc.beam")
      )

      assert {2, []} = Coverage.instrument([ebin, consolidated])
    end

    # In a runtime started without `+JPcover`, as a user's is.
    test "switches the runtime to native counters and counts lines, without cover", %{
      directory: directory,
      config: config,
      ebin: ebin,
      source: source
    } do
      if :erlang.system_info(:emu_flavor) != :jit, do: flunk("native coverage needs the JIT")

      Coverage.instrument(ebin)
      tuist_ex = :code.lib_dir(:tuist_ex) |> to_string() |> Path.join("ebin")

      script = """
      Mix.start()
      Code.prepend_path(#{inspect(ebin)})
      Code.prepend_path(#{inspect(tuist_ex)})
      true = TuistEx.Analytics.Coverage.enable_native(#{inspect(ebin)})
      3 = TuistExNativeFixture.Calc.add(1, 2)
      snapshot = TuistEx.Analytics.Coverage.snapshot(#{inspect(directory)}, #{inspect(config)})
      IO.write(snapshot |> :erlang.term_to_binary() |> Base.encode64())
      """

      {output, 0} =
        System.cmd(
          System.find_executable("elixir"),
          ["-e", script],
          env: [{"MIX_ENV", "test"}]
        )

      assert [%{path: ^source, lines: lines, functions: functions}] =
               output
               |> String.split("\n")
               |> List.last()
               |> Base.decode64!()
               |> :erlang.binary_to_term()

      # `__schema__/1` is not listed, but its line counts for the file, as cover counts it.
      assert lines == %{5 => 1, 9 => 0, 12 => 0}

      assert [
               %{name: "add/2", line: 4, covered: 1, executable: 1},
               %{name: "unused/1", line: 8, covered: 0, executable: 1}
             ] = functions
    end

    # In a runtime of its own, started without `+JPcover` as a user's is: the
    # swaps outlive the test, and Mimic swaps the modules back after the suite
    # from a build the test removes.
    test "swaps every module Mimic copies before a test runs and counts them natively", %{
      directory: directory,
      config: config,
      ebin: ebin,
      source: source
    } do
      if :erlang.system_info(:emu_flavor) != :jit, do: flunk("native coverage needs the JIT")

      doubler = Path.join(directory, "lib/doubler.ex")

      File.write!(doubler, """
      defmodule TuistExNativeFixture.Doubler do
        def double(x) do
          x * 2
        end
      end
      """)

      previous = Map.take(Code.compiler_options(), [:debug_info])
      Code.compiler_options(debug_info: true)

      {:ok, _modules, _} =
        Kernel.ParallelCompiler.compile_to_path([doubler], ebin, return_diagnostics: true)

      Code.compiler_options(previous)
      :code.purge(TuistExNativeFixture.Doubler)
      :code.delete(TuistExNativeFixture.Doubler)
      Coverage.instrument(ebin)

      paths =
        Enum.map(
          [:tuist_ex, :mimic, :ham],
          &(&1 |> :code.lib_dir() |> to_string() |> Path.join("ebin"))
        )

      script = """
      Mix.start()
      Enum.each(#{inspect([ebin | paths])}, &Code.prepend_path/1)
      true = TuistEx.Analytics.Coverage.enable_native(#{inspect(ebin)})
      :ok = Application.load(:ex_unit)
      {:ok, _} = Application.ensure_all_started(:mimic)
      Mimic.copy(TuistExNativeFixture.Calc)
      Mimic.copy(TuistExNativeFixture.Doubler)
      # As the application does while it starts, before the swap.
      3 = TuistExNativeFixture.Calc.add(1, 2)
      TuistEx.Analytics.Coverage.prepare_native(#{inspect(config)})
      true = Mimic.Module.copied?(TuistExNativeFixture.Calc)
      true = Mimic.Module.copied?(TuistExNativeFixture.Doubler)
      [] = :cover.modules()
      3 = TuistExNativeFixture.Calc.add(1, 2)
      4 = TuistExNativeFixture.Doubler.double(2)
      snapshot = TuistEx.Analytics.Coverage.snapshot(#{inspect(directory)}, #{inspect(config)})
      IO.write(snapshot |> :erlang.term_to_binary() |> Base.encode64())
      """

      {output, 0} =
        System.cmd(System.find_executable("elixir"), ["-e", script],
          cd: directory,
          env: [{"MIX_ENV", "test"}]
        )

      snapshot =
        output
        |> String.split("\n")
        |> List.last()
        |> Base.decode64!()
        |> :erlang.binary_to_term()
        |> Map.new(&{&1.path, &1.lines})

      assert snapshot == %{source => %{5 => 2, 9 => 0, 12 => 0}, doubler => %{3 => 1}}
    end
  end

  describe "with_shard_export/2" do
    test "exports a measured shard's coverage instead of holding it to Mix's threshold" do
      assert Coverage.with_shard_export(["--cover", "--trace"], 2) ==
               ["--cover", "--trace", "--export-coverage", "shard-2"]
    end

    test "keeps an export the run names, and adds none without coverage" do
      for args <- [
            ["--cover", "--export-coverage", "mine"],
            ["--cover", "--export-coverage=mine"],
            ["--trace"]
          ] do
        assert Coverage.with_shard_export(args, 0) == args
      end
    end
  end

  describe "without_cover/1" do
    test "leaves Mix's coverage tool out and keeps everything else" do
      assert Coverage.without_cover([
               "--cover",
               "--export-coverage",
               "shard",
               "--warnings-as-errors",
               "--export-coverage=other",
               "test/a_test.exs"
             ]) == ["--warnings-as-errors", "test/a_test.exs"]
    end
  end

  describe "attach/3" do
    @coverage %{
      tool: "cover",
      tool_version: "OTP 28/Elixir 1.19.5",
      partial: false,
      files: [%{path: "lib/a.ex", line_numbers: [1], execution_counts: [1]}]
    }

    test "sends the coverage inline within the server's threshold" do
      stub(HTTP, :project_request, fn :get, "/tests/coverage/settings", nil, _ ->
        {:ok, %{"inline_threshold_bytes" => 5_000_000}}
      end)

      assert {:ok, %{coverage: @coverage}} = Coverage.attach(%{id: "run"}, @coverage, [])
    end

    test "uploads the coverage past the threshold and names the upload" do
      test_pid = self()

      stub(HTTP, :project_request, fn
        :get, "/tests/coverage/settings", nil, _ ->
          {:ok, %{"inline_threshold_bytes" => 1}}

        :post, "/tests/coverage/uploads", %{test_run_id: "run"}, _ ->
          {:ok, %{"storage_key" => "key", "upload_url" => "https://upload"}}
      end)

      stub(TuistEx.HTTP, :put_binary, fn "https://upload", compressed ->
        send(test_pid, {:uploaded, compressed})
        {:ok, "etag"}
      end)

      assert {:ok, %{coverage: coverage}} = Coverage.attach(%{id: "run"}, @coverage, [])

      assert coverage == %{
               tool: "cover",
               tool_version: "OTP 28/Elixir 1.19.5",
               partial: false,
               storage_key: "key"
             }

      assert_received {:uploaded, compressed}

      assert compressed |> :zlib.unzip() |> JSON.decode!() == %{
               "path" => "lib/a.ex",
               "line_numbers" => [1],
               "execution_counts" => [1]
             }
    end

    test "reports a failed upload" do
      stub(HTTP, :project_request, fn
        :get, "/tests/coverage/settings", nil, _ -> {:ok, %{"inline_threshold_bytes" => 1}}
        :post, "/tests/coverage/uploads", _, _ -> {:error, {:http, 404, %{}}}
      end)

      assert {:error, {:http, 404, %{}}} = Coverage.attach(%{id: "run"}, @coverage, [])
    end
  end
end
