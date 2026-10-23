defmodule Mix.Tasks.Tuist.TestTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Tuist.Test, as: Task

  test "takes the same command line as mix test, keeping only its own options" do
    assert {[url: "https://tuist.example", retries: 2],
            ["test/a_test.exs:12", "--trace", "--only", "slow"]} =
             Task.split_args([
               "test/a_test.exs:12",
               "--url",
               "https://tuist.example",
               "--trace",
               "--retries=2",
               "--only",
               "slow"
             ])
  end

  test "separates shard preparation, prepared-build and variant options" do
    assert {[prepare_only: true, scheme: "clickhouse-current"], ["--trace"]} =
             Task.split_args(["--prepare-only", "--scheme", "clickhouse-current", "--trace"])

    assert {[no_download: true], ["test/a_test.exs"]} =
             Task.split_args(["--no-download", "test/a_test.exs"])
  end

  test "preparation and prepared-build execution require a shard and cannot be combined" do
    assert :ok = Task.validate_shard_options([], nil)
    assert :ok = Task.validate_shard_options([prepare_only: true], 0)
    assert :ok = Task.validate_shard_options([no_download: true], 0)

    for options <- [[prepare_only: true], [no_download: true]] do
      assert_raise Mix.Error, ~r/require a shard index/, fn ->
        Task.validate_shard_options(options, nil)
      end
    end

    assert_raise Mix.Error, ~r/cannot be combined/, fn ->
      Task.validate_shard_options([prepare_only: true, no_download: true], 0)
    end
  end

  test "still accepts the `--` separator older versions required" do
    assert {[url: "https://tuist.example"], ["--trace"]} =
             Task.split_args(["--url", "https://tuist.example", "--", "--trace"])
  end

  test "parses --project when no forwarded args are given" do
    assert {[project: "acme/widgets"], []} = Task.split_args(["--project", "acme/widgets"])
  end

  test "rejects an own option without a usable value" do
    assert_raise Mix.Error, ~r/--retries expects a number/, fn ->
      Task.split_args(["--retries", "many"])
    end

    assert_raise Mix.Error, ~r/--project expects a value/, fn ->
      Task.split_args(["--project"])
    end
  end

  test "retries are off unless asked for, by flag first and then the environment" do
    assert Task.retries([], fn _ -> nil end) == 0
    assert Task.retries([retries: 2], fn _ -> "5" end) == 2
    assert Task.retries([], fn "TUIST_TEST_RETRIES" -> "3" end) == 3
    assert Task.retries([], fn "TUIST_TEST_RETRIES" -> "nope" end) == 0
  end

  test "adds the analytics formatter to the configured ones, once" do
    formatter = TuistEx.Analytics.ExUnitFormatter

    assert Task.formatters([ExUnit.CLIFormatter]) == [ExUnit.CLIFormatter, formatter]
    assert Task.formatters([ExUnit.CLIFormatter, formatter]) == [ExUnit.CLIFormatter, formatter]
  end

  test "unsigned CI and coverage runs never collect or upload Git history" do
    script = ~S"""
    Mix.start()
    Mix.env(:test)

    # Keep coverage local to the fixture without instrumenting shared build files.
    Mix.Project.in_project(:tuist_ex, File.cwd!(), [test_coverage: [tool: :custom]], fn _ ->
      {:ok, _} = Application.ensure_all_started(:mimic)
      Code.require_file("test/test_helper.exs")
      ExUnit.configure(autorun: false)

      defmodule UnsignedHistoryRegression do
        use ExUnit.Case, async: false

        test "the task skips history work" do
          Mimic.set_mimic_global()
          owner = self()

          Mimic.stub(TuistEx.Auth, :network_publishing?, fn _ -> true end)
          Mimic.stub(TuistEx.Analytics.GitHistory, :enabled?, fn _ -> true end)
          Mimic.stub(TuistEx.Analytics.GitHistory, :collect, fn _, _, _, _ ->
            send(owner, :history_attempted)
            %{history: nil}
          end)

          for function <- [:publish, :upload_listing] do
            Mimic.stub(TuistEx.Analytics.GitHistory, function, fn _, _ ->
              send(owner, :history_attempted)
              []
            end)
          end

          Mimic.stub(TuistEx.Analytics.Args, :run_wrapped, fn "test", Mix.Tasks.Test, _ ->
            send(owner, :tests_ran)
            :ok
          end)

          for args <- [[], ["--cover"], ["--retries", "1"]] do
            Mix.Tasks.Tuist.Test.run(args)
            receive do
              :tests_ran -> :ok
            after
              0 -> raise "the test task did not run"
            end
          end

          receive do
            :history_attempted -> raise "unsigned reporting attempted Git history work"
          after
            0 -> IO.puts("unsigned history isolation verified")
          end
        end
      end

      if ExUnit.run().failures != 0, do: System.halt(1)
    end)
    """

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", script],
        stderr_to_stdout: true,
        env: [{"TUIST_SHARD_INDEX", ""}, {"TUIST_EX_RETRY_RESULTS", ""}]
      )

    assert status == 0, output
    assert output =~ "unsigned history isolation verified"
  end

  test "invalid configuration, raised probes and slow probes never prevent local tests" do
    script = ~S"""
    Mix.start()
    Mix.env(:test)

    Mix.Project.in_project(:tuist_ex, File.cwd!(), [test_coverage: [tool: :custom]], fn _ ->
      {:ok, _} = Application.ensure_all_started(:mimic)
      Code.require_file("test/test_helper.exs")
      ExUnit.configure(autorun: false)

      defmodule ReportingProbeIsolationRegression do
        use ExUnit.Case, async: false

        test "mode detection is isolated and bounded once per invocation" do
          Mimic.set_mimic_global()
          owner = self()
          Mimic.stub(TuistEx.Analytics.GitHistory, :enabled?, fn _ -> false end)
          Mimic.stub(TuistEx.Analytics.Args, :run_wrapped, fn "test", Mix.Tasks.Test, _ ->
            send(owner, :tests_ran)
            :ok
          end)

          for args <- [["--cover"], ["--retries", "1"]] do
            Mix.Tasks.Tuist.Test.run(["--url", "not-a-url"] ++ args)
            assert_received :tests_ran
          end

          for behavior <- [:raise, :timeout] do
            Mimic.stub(TuistEx.Auth, :network_publishing?, fn _ ->
              send(owner, {:probe, behavior})
              case behavior do
                :raise -> raise File.Error, reason: :eacces, action: "read", path: "credentials"
                :timeout -> Process.sleep(:infinity)
              end
            end)

            args = if behavior == :raise, do: ["--cover"], else: ["--retries", "1"]
            Mix.Tasks.Tuist.Test.run(args)
            assert_received {:probe, ^behavior}
            refute_received {:probe, ^behavior}
            assert_received :tests_ran
          end
          IO.puts("reporting probe isolation verified")
        end
      end

      if ExUnit.run().failures != 0, do: System.halt(1)
    end)
    """

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", script],
        stderr_to_stdout: true,
        env: [
          {"TUIST_SHARD_INDEX", ""},
          {"TUIST_EX_RETRY_RESULTS", ""},
          {"CI", "true"},
          {"TUIST_URL", nil}
        ]
      )

    assert status == 0, output
    assert output =~ "reporting probe isolation verified"
  end

  test "does not retry a run whose failed tests all timed out" do
    script = ~S"""
    Mix.start()
    Mix.env(:test)

    Mix.Project.in_project(:tuist_ex, File.cwd!(), [test_coverage: [tool: :custom]], fn _ ->
      {:ok, _} = Application.ensure_all_started(:mimic)
      Code.require_file("test/test_helper.exs")
      Mimic.copy(TuistEx.Analytics.Subprocess)
      ExUnit.configure(autorun: false)

      defmodule TimedOutRetryRegression do
        use ExUnit.Case, async: false

        test "the task retries only failures that did not time out" do
          Mimic.set_mimic_global()
          owner = self()

          Mimic.stub(TuistEx.Auth, :network_publishing?, fn _ -> true end)
          Mimic.stub(TuistEx.Analytics.GitHistory, :enabled?, fn _ -> false end)

          Mimic.stub(TuistEx.Analytics.HTTP, :submit_test_run, fn payload, _opts ->
            send(owner, {:submitted, payload})
            :ok
          end)

          Mimic.stub(TuistEx.Analytics.Subprocess, :run, fn _mix, _args, _env ->
            send(owner, :retried)
            1
          end)

          for {timed_out?, retried?} <- [{true, false}, {false, true}] do
            Mimic.stub(TuistEx.Analytics.Args, :run_wrapped, fn "test", Mix.Tasks.Test, _ ->
              run = %{test_modules: [], status: "failure"}
              payload = if timed_out?, do: Map.put(run, :timed_out, true), else: run
              send(self(), {:deferred_test_run, {payload, [], false}})
              Mix.raise(~s("mix test" failed))
            end)

            output =
              ExUnit.CaptureIO.capture_io(fn ->
                assert_raise Mix.Error, fn -> Mix.Tasks.Tuist.Test.run(["--retries", "1", "--raise"]) end
              end)

            assert output =~ "every one of them timed out" == timed_out?
            assert_received {:submitted, payload}
            refute Map.has_key?(payload, :timed_out)

            if retried?, do: assert_received(:retried), else: refute_received(:retried)
          end

          IO.puts("timed out retry skip verified")
        end
      end

      if ExUnit.run().failures != 0, do: System.halt(1)
    end)
    """

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", script],
        stderr_to_stdout: true,
        env: [{"TUIST_SHARD_INDEX", ""}, {"TUIST_EX_RETRY_RESULTS", ""}]
      )

    assert status == 0, output
    assert output =~ "timed out retry skip verified"
  end

  test "passes a run whose only failures are muted tests, and leaves skipped tests out" do
    script = ~S"""
    Mix.start()
    Mix.env(:test)

    Mix.Project.in_project(:tuist_ex, File.cwd!(), [test_coverage: [tool: :custom]], fn _ ->
      {:ok, _} = Application.ensure_all_started(:mimic)
      Code.require_file("test/test_helper.exs")
      Mimic.copy(TuistEx.Analytics.Subprocess)
      ExUnit.configure(autorun: false)

      defmodule QuarantineRegression do
        use ExUnit.Case, async: false

        test "the task applies the project's quarantine" do
          Mimic.set_mimic_global()
          owner = self()

          Mimic.stub(TuistEx.Auth, :network_publishing?, fn _ -> false end)
          Mimic.stub(TuistEx.Analytics.GitHistory, :enabled?, fn _ -> false end)

          Mimic.stub(TuistEx.Analytics.Quarantine, :fetch, fn _ ->
            {:ok,
             %TuistEx.Analytics.Quarantine{
               muted: MapSet.new([{"CartTest", "", "flakes"}]),
               skipped: MapSet.new([{"CartTest", "add/2", "hangs"}])
             }}
          end)

          Mimic.stub(TuistEx.Analytics.HTTP, :submit_test_run, fn payload, _opts ->
            send(owner, {:submitted, payload})
            :ok
          end)

          Mimic.stub(TuistEx.Analytics.Subprocess, :run, fn _mix, args, env ->
            quarantine = Map.new(env)["TUIST_EX_RETRY_QUARANTINE"]
            send(owner, {:retried, args, :erlang.binary_to_term(File.read!(quarantine))})
            1
          end)

          # A module that failed outside its tests, such as an `on_exit` from
          # `setup_all` raising, fails the run whatever the muted tests did.
          for {failed, module_failed?, passes?} <- [
                {["flakes"], false, true},
                {["flakes", "breaks"], false, false},
                {[], true, false},
                {["flakes"], true, false}
              ] do
            Mimic.stub(TuistEx.Analytics.Args, :run_wrapped, fn "test", Mix.Tasks.Test, args ->
              send(owner, {:args, args})
              cases = Enum.map(failed, &%{name: &1, status: "failure", duration: 1})
              status = if failed == [], do: "success", else: "failure"
              module = %{name: "CartTest", status: status, duration: 2, test_suites: [], test_cases: cases}
              run = %{test_modules: [module], status: status}
              send(self(), {:deferred_test_run, {run, [], module_failed?}})
              Mix.raise(~s("mix test" failed))
            end)

            output =
              ExUnit.CaptureIO.capture_io(fn ->
                if passes? do
                  assert :ok = Mix.Tasks.Tuist.Test.run(["--raise"])
                else
                  assert_raise Mix.Error, fn ->
                    Mix.Tasks.Tuist.Test.run(["--raise", "--retries", "1"])
                  end
                end
              end)

            assert output =~ "CartTest: add/2 hangs"
            assert output =~ "only muted tests failed" == passes?
            # Left out by its module and name, not by a name filter.
            assert_received {:args, args}
            refute "--exclude" in args
            assert TuistEx.Analytics.ExcludeTestIds.installed?()
            assert_received {:submitted, payload}
            # The run's status is its tests'.
            assert payload.status == if(passes? or failed == [], do: "success", else: "failure")
          end

          # ExUnit keeps a failure on record until the test passes, so
          # `--failed` would rerun a test that failed before it was skipped:
          # the retry leaves out what this run did, with the same policy.
          assert_received {:retried, ["tuist.test", "--failed" | retry_args], policy}
          refute "--exclude" in retry_args
          assert MapSet.to_list(policy.skipped) == [{"CartTest", "add/2", "hangs"}]

          Mimic.stub(TuistEx.Analytics.Args, :run_wrapped, fn "test", Mix.Tasks.Test, args ->
            options = Application.get_env(:tuist_ex, :analytics_options)
            send(owner, {:args, args, options[:quarantine_exclusion]})
            :ok
          end)

          retry_quarantine = Path.join(System.tmp_dir!(), "tuist-ex-retry-quarantine-#{System.unique_integer([:positive])}")
          File.write!(retry_quarantine, :erlang.term_to_binary(policy))
          System.put_env([{"TUIST_EX_RETRY_RESULTS", retry_quarantine <> ".results"}, {"TUIST_EX_RETRY_QUARANTINE", retry_quarantine}])
          TuistEx.Analytics.ExcludeTestIds.uninstall()
          ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Tuist.Test.run(["--failed"]) end)
          System.put_env([{"TUIST_EX_RETRY_RESULTS", ""}, {"TUIST_EX_RETRY_QUARANTINE", nil}])
          File.rm!(retry_quarantine)
          assert_received {:args, ["--failed"], :test_ids}
          assert TuistEx.Analytics.ExcludeTestIds.installed?()

          # Where ExUnit cannot be patched, the run falls back to a filter on
          # the skipped test's full name.
          TuistEx.Analytics.ExcludeTestIds.uninstall()
          Mimic.stub(TuistEx.Analytics.ExcludeTestIds, :install, fn _ids -> {:error, :unsupported} end)
          ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Tuist.Test.run([]) end)
          assert_received {:args, args, :names}
          assert ["--exclude", "test:test add/2 hangs"] -- args == []

          Mimic.stub(TuistEx.Analytics.Args, :run_wrapped, fn "test", Mix.Tasks.Test, args ->
            send(owner, {:args, args})
            :ok
          end)

          ExUnit.CaptureIO.capture_io(fn -> Mix.Tasks.Tuist.Test.run(["--no-quarantine"]) end)
          assert_received {:args, []}

          IO.puts("quarantine verified")
        end
      end

      if ExUnit.run().failures != 0, do: System.halt(1)
    end)
    """

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", script],
        stderr_to_stdout: true,
        env: [{"TUIST_SHARD_INDEX", ""}, {"TUIST_EX_RETRY_RESULTS", ""}]
      )

    assert status == 0, output
    assert output =~ "quarantine verified"
  end

  test "declares :test as the preferred CLI env" do
    # The attribute prevents `mix tuist.test` from picking up whatever env
    # the invoker happened to be in (usually :dev), which otherwise breaks
    # `mix test` before any tests run.
    attrs = Task.__info__(:attributes)
    assert Keyword.get(attrs, :preferred_cli_env) == [:test]
  end
end
