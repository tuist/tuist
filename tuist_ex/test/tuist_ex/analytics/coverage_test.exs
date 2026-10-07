defmodule TuistEx.Analytics.CoverageTest do
  use ExUnit.Case, async: false
  use Mimic

  alias TuistEx.Analytics.Coverage
  alias TuistEx.Analytics.HTTP

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

  describe "report/4" do
    test "keeps the repository's files, relative to its root, with their blobs and lines" do
      snapshot = [
        %{path: "/repo/app/lib/a.ex", app: "app", test?: false, lines: %{5 => 0, 2 => 3, 3 => 1}},
        %{
          path: "/repo/app/test/support/case.ex",
          app: "app",
          test?: true,
          lines: %{1 => 2, 4 => 0}
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
                 functions: []
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

      assert %{app: "calculator", test?: false, lines: lines} =
               directory |> Coverage.snapshot(app: :calculator) |> Enum.find(&(&1.path == source))

      assert lines == %{3 => 1, 7 => 0, 11 => 0}
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

      Code.prepend_path(Path.join(directory, "ebin"))
      on_exit(fn -> Code.delete_path(Path.join(directory, "ebin")) end)

      # What `Mimic.copy/1` does to a cover-compiled module: the original moves
      # under another name, cover-compiled from its binary, which names no source.
      Mimic.Module.replace!(TuistExCoverFixture.Calculator, [])
      on_exit(fn -> Mimic.Module.clear!(TuistExCoverFixture.Calculator) end)
      3 = apply(Mimic.Module.original(TuistExCoverFixture.Calculator), :add, [1, 2])

      assert %{lines: %{3 => 1, 7 => 0}} =
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

      assert Map.keys(lines) == [3, 7]

      ignored = [
        app: :calculator,
        test_coverage: [
          ignore_modules: [TuistExCoverFixture.Calculator, TuistExCoverFixture.Calculator.Inner]
        ]
      ]

      refute directory |> Coverage.snapshot(ignored) |> Enum.any?(&(&1.path == source))
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
