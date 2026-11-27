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

  # A template compiled into a module, as Phoenix compiles a LiveView's
  # `.html.heex`, and a file the module reads at compile time, as a Gettext
  # backend reads its `.po` files.
  describe "templates and external resources" do
    setup do
      directory =
        Path.join(System.tmp_dir!(), "tuist-ex-template-#{System.unique_integer([:positive])}")

      File.mkdir_p!(Path.join(directory, "lib"))
      File.mkdir_p!(Path.join(directory, "priv"))
      on_exit(fn -> File.rm_rf!(directory) end)

      File.write!(Path.join(directory, "mix.exs"), """
      defmodule TuistExTemplateFixture.MixProject do
        use Mix.Project
        def project, do: [app: :tuist_ex_template_fixture, version: "0.1.0"]
      end
      """)

      source = Path.join(directory, "lib/page.ex")

      File.write!(source, """
      defmodule TuistExTemplateFixture.Page do
        require EEx

        @external_resource "priv/greeting.txt"
        @external_resource "linked/greeting.txt"
        @greeting File.read!("priv/greeting.txt")

        def greeting, do: @greeting

        EEx.function_from_file(:def, :render, "lib/page.html.eex", [:name])

        def unused(x) do
          x * 2
        end
      end
      """)

      template = Path.join(directory, "lib/page.html.eex")

      File.write!(template, """
      Hello <%= name %>
      <%= if name == "nobody" do %>
        <%= String.upcase(name) %>
      <% end %>
      <%= if name == "boom", do: raise("boom") %>
      """)

      File.write!(Path.join(directory, "priv/greeting.txt"), "hi")
      # The module names its resource a second time through a link, as a
      # module reading `Application.app_dir/2` names `priv` through the
      # build's link to it.
      File.ln_s!("priv", Path.join(directory, "linked"))

      {output, status} =
        System.cmd(System.find_executable("mix"), ["compile"],
          cd: directory,
          stderr_to_stdout: true,
          env: [{"MIX_ENV", "test"}, {"MIX_BUILD_PATH", nil}, {"MIX_DEPS_PATH", nil}]
        )

      assert status == 0, output

      config = [
        app: :tuist_ex_template_fixture,
        build_path: Path.join(directory, "_build"),
        build_per_environment: true
      ]

      %{directory: directory, config: config, source: source, template: template}
    end

    test "counts a template's lines in its own file and a module's resources as files it ran",
         %{directory: directory, config: config, source: source, template: template} do
      if :erlang.system_info(:emu_flavor) != :jit, do: flunk("native coverage needs the JIT")

      ebin = Path.join(directory, "_build/test/lib/tuist_ex_template_fixture/ebin")
      assert {1, []} = Coverage.instrument(ebin, directory, config)
      # The module says it carries the counters, so it isn't instrumented again.
      assert {0, []} = Coverage.instrument(ebin, directory, config)
      tuist_ex = :code.lib_dir(:tuist_ex) |> to_string() |> Path.join("ebin")

      script = """
      Mix.start()
      Code.prepend_path(#{inspect(ebin)})
      Code.prepend_path(#{inspect(tuist_ex)})
      true = TuistEx.Analytics.Coverage.enable_native(#{inspect(ebin)})
      "hi" = TuistExTemplateFixture.Page.greeting()
      TuistExTemplateFixture.Page.render("x")

      frame =
        try do
          TuistExTemplateFixture.Page.render("boom")
        rescue
          _ -> Enum.find(__STACKTRACE__, &(elem(&1, 0) == TuistExTemplateFixture.Page))
        end

      result = %{
        snapshot: TuistEx.Analytics.Coverage.snapshot(#{inspect(directory)}, #{inspect(config)}),
        sources: TuistEx.Analytics.Coverage.sources([TuistExTemplateFixture.Page], #{inspect(directory)}, #{inspect(config)}),
        module_lines: TuistEx.Analytics.Coverage.module_lines(#{inspect(config)}),
        frame: frame
      }

      IO.write(result |> :erlang.term_to_binary() |> Base.encode64())
      """

      {output, 0} =
        System.cmd(System.find_executable("elixir"), ["-e", script],
          cd: directory,
          env: [{"MIX_ENV", "test"}]
        )

      result =
        output
        |> String.split("\n")
        |> List.last()
        |> Base.decode64!()
        |> :erlang.binary_to_term()

      resource = Path.join(directory, "priv/greeting.txt")
      snapshot = Map.new(result.snapshot, &{&1.path, &1})

      # The template's lines aren't the module's: line 2 is the `if`, line 5
      # the `raise` both calls reached.
      assert snapshot[source].lines == %{8 => 1, 13 => 0}
      assert snapshot[template].lines == %{2 => 2, 5 => 2}
      assert Enum.map(snapshot[source].functions, & &1.name) == ["greeting/0", "unused/1"]
      assert snapshot[template].functions == []
      assert snapshot[resource].lines == %{}

      assert %{
               TuistExTemplateFixture.Page => %{
                 files: %{0 => ^source, 1 => ^template},
                 ids: ids,
                 resources: [^resource]
               }
             } = result.sources

      # Each counter's ID says its file and line: the template's are the
      # template's own.
      assert {1, 5} in Tuple.to_list(ids)
      assert {0, 13} in Tuple.to_list(ids)

      # Mix's summary and threshold count no template line, as Mix's tool doesn't.
      assert result.module_lines == %{TuistExTemplateFixture.Page => %{8 => true, 13 => false}}

      # Stack traces still name the template and its line.
      assert {TuistExTemplateFixture.Page, :render, 1, location} = result.frame
      assert {location[:file], location[:line]} == {~c"lib/page.html.eex", 5}
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

  describe "attach/4" do
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

      assert {:ok, %{coverage: @coverage}} =
               Coverage.attach(%{id: "run"}, @coverage, 1_000_000, [])
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

      assert {:ok, %{coverage: coverage}} =
               Coverage.attach(%{id: "run"}, @coverage, 1_000_000, [])

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

    test "uploads coverage that compresses under the threshold but inflates past it" do
      # Inline, the server would inflate the run's body past the limit the
      # threshold is meant to stay under.
      files =
        for n <- 1..2000,
            do: %{path: "lib/file_#{n}.ex", line_numbers: [1, 2, 3], execution_counts: [1, 0, 1]}

      coverage = %{@coverage | files: files}
      ndjson = Enum.map_join(files, "\n", &JSON.encode!/1)
      threshold = div(byte_size(ndjson), 2)
      test_pid = self()

      stub(HTTP, :project_request, fn
        :get, "/tests/coverage/settings", nil, _ ->
          {:ok, %{"inline_threshold_bytes" => threshold}}

        :post, "/tests/coverage/uploads", %{test_run_id: "run"}, _ ->
          {:ok, %{"storage_key" => "key", "upload_url" => "https://upload"}}
      end)

      stub(TuistEx.HTTP, :put_binary, fn "https://upload", compressed ->
        send(test_pid, {:uploaded, compressed})
        {:ok, "etag"}
      end)

      assert {:ok, %{coverage: %{storage_key: "key"} = attached}} =
               Coverage.attach(%{id: "run"}, coverage, 1_000_000, [])

      refute Map.has_key?(attached, :files)
      assert_received {:uploaded, compressed}
      assert byte_size(compressed) < threshold
      assert :zlib.unzip(compressed) == ndjson
    end

    test "uploads coverage within the threshold that the rest of the report leaves no room for" do
      stub(HTTP, :project_request, fn
        :get, "/tests/coverage/settings", nil, _ ->
          {:ok, %{"inline_threshold_bytes" => 5_000_000}}

        :post, "/tests/coverage/uploads", %{test_run_id: "run"}, _ ->
          {:ok, %{"storage_key" => "key", "upload_url" => "https://upload"}}
      end)

      stub(TuistEx.HTTP, :put_binary, fn "https://upload", _compressed -> {:ok, "etag"} end)
      size = byte_size(Enum.map_join(@coverage.files, "\n", &JSON.encode!/1))

      assert {:ok, %{coverage: @coverage}} = Coverage.attach(%{id: "run"}, @coverage, size, [])

      assert {:ok, %{coverage: %{storage_key: "key"}}} =
               Coverage.attach(%{id: "run"}, @coverage, size - 1, [])
    end

    test "reports a failed upload" do
      stub(HTTP, :project_request, fn
        :get, "/tests/coverage/settings", nil, _ -> {:ok, %{"inline_threshold_bytes" => 1}}
        :post, "/tests/coverage/uploads", _, _ -> {:error, {:http, 404, %{}}}
      end)

      assert {:error, {:http, 404, %{}}} = Coverage.attach(%{id: "run"}, @coverage, 1_000_000, [])
    end
  end

  describe "attach_evidence/5" do
    @rest %{overlapped_tests: [], status: "collected"}

    setup do
      dir =
        Path.join(System.tmp_dir!(), "tuist-ex-evidence-#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      ndjson = Path.join(dir, "coverage_evidence.ndjson")

      File.write!(ndjson, [
        ~s({"kind":"test","module":"ATest","suite":"","name":"a","files":["lib/a.ex"],"lines":[[3,5]]}\n),
        ~s({"kind":"target","module":"ATest","suite":"","name":"","files":["lib/a.ex"],"lines":[[1,5]]}\n)
      ])

      %{ndjson: ndjson}
    end

    test "uploads evidence within the threshold that the rest of the report leaves no room for",
         %{ndjson: ndjson} do
      stub(HTTP, :project_request, fn
        :get, "/tests/coverage/settings", nil, _ ->
          {:ok, %{"inline_threshold_bytes" => 5_000_000}}

        :post, "/tests/coverage/uploads", _, _ ->
          {:ok, %{"evidence_storage_key" => "evidence-key", "evidence_upload_url" => "https://u"}}
      end)

      stub(TuistEx.HTTP, :put_binary, fn "https://u", _ -> {:ok, "etag"} end)

      assert {:ok, %{coverage_evidence: %{storage_key: "evidence-key"}}} =
               Coverage.attach_evidence(%{id: "run"}, ndjson, @rest, 10, [])
    end

    test "uploads evidence that compresses under the threshold but is past it uncompressed",
         %{ndjson: ndjson} do
      line =
        ~s({"kind":"test","module":"ATest","suite":"","name":"a","files":["lib/a.ex"],"lines":[[3,5]]}\n)

      File.write!(ndjson, List.duplicate(line, 500))
      threshold = div(File.stat!(ndjson).size, 2)

      stub(HTTP, :project_request, fn
        :get, "/tests/coverage/settings", nil, _ ->
          {:ok, %{"inline_threshold_bytes" => threshold}}

        :post, "/tests/coverage/uploads", _, _ ->
          {:ok, %{"evidence_storage_key" => "evidence-key", "evidence_upload_url" => "https://u"}}
      end)

      test_pid = self()

      stub(TuistEx.HTTP, :put_binary, fn "https://u", compressed ->
        send(test_pid, {:uploaded, byte_size(compressed)})
        {:ok, "etag"}
      end)

      assert {:ok, %{coverage_evidence: %{storage_key: "evidence-key"}}} =
               Coverage.attach_evidence(%{id: "run"}, ndjson, @rest, 50_000_000, [])

      assert_received {:uploaded, compressed_size}
      assert compressed_size < threshold
    end

    test "uploads the evidence past the threshold and names the upload", %{ndjson: ndjson} do
      test_pid = self()

      stub(HTTP, :project_request, fn
        :get, "/tests/coverage/settings", nil, _ ->
          {:ok, %{"inline_threshold_bytes" => 1}}

        :post, "/tests/coverage/uploads", %{test_run_id: "run"}, _ ->
          {:ok,
           %{
             "storage_key" => "key",
             "upload_url" => "https://upload",
             "evidence_storage_key" => "evidence-key",
             "evidence_upload_url" => "https://evidence-upload"
           }}
      end)

      stub(TuistEx.HTTP, :put_binary, fn "https://evidence-upload", compressed ->
        send(test_pid, {:uploaded, compressed})
        {:ok, "etag"}
      end)

      assert {:ok, %{coverage_evidence: evidence}} =
               Coverage.attach_evidence(%{id: "run"}, ndjson, @rest, 50_000_000, [])

      assert evidence == Map.put(@rest, :storage_key, "evidence-key")
      assert_received {:uploaded, compressed}
      assert :zlib.unzip(compressed) == File.read!(ndjson)
    end

    test "is inline within the threshold, or when the server takes no evidence uploads",
         %{ndjson: ndjson} do
      stub(HTTP, :project_request, fn :get, "/tests/coverage/settings", nil, _ ->
        {:ok, %{"inline_threshold_bytes" => 5_000_000}}
      end)

      assert :inline = Coverage.attach_evidence(%{id: "run"}, ndjson, @rest, 50_000_000, [])

      stub(HTTP, :project_request, fn
        :get, "/tests/coverage/settings", nil, _ ->
          {:ok, %{"inline_threshold_bytes" => 1}}

        :post, "/tests/coverage/uploads", _, _ ->
          {:ok, %{"storage_key" => "key", "upload_url" => "https://upload"}}
      end)

      reject(&TuistEx.HTTP.put_binary/2)
      assert :inline = Coverage.attach_evidence(%{id: "run"}, ndjson, @rest, 50_000_000, [])
    end

    test "reports a failed upload", %{ndjson: ndjson} do
      stub(HTTP, :project_request, fn
        :get, "/tests/coverage/settings", nil, _ ->
          {:ok, %{"inline_threshold_bytes" => 1}}

        :post, "/tests/coverage/uploads", _, _ ->
          {:ok, %{"evidence_storage_key" => "k", "evidence_upload_url" => "https://u"}}
      end)

      stub(TuistEx.HTTP, :put_binary, fn _, _ -> {:error, {:http, 403}} end)

      assert {:error, {:http, 403}} =
               Coverage.attach_evidence(%{id: "run"}, ndjson, @rest, 50_000_000, [])
    end
  end
end
