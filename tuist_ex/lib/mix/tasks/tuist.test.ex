defmodule Mix.Tasks.Tuist.Test do
  @shortdoc "Run mix test with Tuist analytics enabled"

  @moduledoc """
  Runs `mix test` with the Tuist analytics ExUnit formatter installed, then
  submits the test run to your Tuist dashboard.

      mix tuist.test [--url URL] [--project ACCOUNT/PROJECT] [--retries N] [--no-quarantine] [ARGS...]

  Every other argument is forwarded to `mix test` as is, so the task can stand
  in for it. Alias it in your `mix.exs` and `mix test` reports to Tuist without
  anyone having to remember a different command:

      def project do
        [aliases: [test: "tuist.test"]]
      end

  The project handle is read from, in order:

    * `TUIST_PROJECT` (env)
    * `--project account/project`
    * `Mix.Project.config()[:tuist][:project]`

  Authentication reuses the credentials `mix tuist.login` stored, or the
  `TUIST_TOKEN` environment variable if set. A submission failure never
  changes the exit code of `mix test`.

  ## Running one shard

  After `mix tuist.test.build` planned the shards, set `TUIST_SHARD_INDEX` (or
  pass `--shard-index`) on each machine. The task then runs only that shard's
  tests, using the uploaded build instead of compiling when there is one, and
  reports them as part of a single test run.

  Use `--prepare-only` to download a shard's build without starting the
  application or running tests. This lets database setup run in a separate
  process. Then use `--no-download` to run the shard against that prepared
  build. Both options require a shard index. `--no-download` explicitly opts
  out of the project's test preparation alias: run that preparation separately
  with compilation disabled. Ordinary runs, including a shard that downloads
  and runs in one command, preserve the project's alias behavior.

  On a shard that uses Mix's coverage tool (see "Coverage"), the tool exports
  the coverage (`--export-coverage shard-<index>`, unless one is given)
  instead of holding the shard to the project's threshold.

  `--scheme LABEL` names an execution variant in analytics, such as a database
  version. Variants with different labels are not compared as flaky reruns.

  ## Coverage

  With `--cover`, the run's line coverage is reported with it. The task
  compiles the project, recompiles the modules a compile wrote since the last
  run with the runtime's native line counters (a build
  `mix tuist.test.build --cover` made needs none), switches the counters on
  and counts with them. Mix's coverage tool, which would compile every module
  for `cover` again, is left out, also for the modules Mimic copies. Its
  summary and threshold are kept: the task prints each
  module's coverage once the suite finishes and fails the run (exit status 3)
  below `test_coverage: [summary: [threshold: N]]`, 90 unless set
  (`summary: false` turns both off). A shard is never held to the threshold.
  No HTML report is written, and setting `:output` warns. An umbrella's root, a project
  that sets its own `test_coverage` tool, such as excoveralls, and a runtime
  without the JIT, which cannot count natively, use Mix's coverage tool.

  ## Coverage-based test selection

  A project that opts in runs only the tests whose code a change touched:

      def project do
        [tuist: [selective_testing: [strategy: :coverage]]]
      end

  With `--cover`, the task asks Tuist for the closest earlier run of the same
  application that recorded which lines each test executed, sends the files
  that changed since then, and leaves out the test modules and tests the
  server says the change cannot reach. Until such a run exists, or when a
  tracked file such as `mix.exs` or `mix.lock` changed, every test runs. A
  request that fails also runs every test, with a warning. Shards planned by
  `mix tuist.test.build` run only what was selected. `--no-selective-testing`
  runs every test and still records evidence for later runs. Umbrella roots
  are not selected.

  ## Quarantined tests

  Before the run, the task reads the tests the project quarantines in Tuist.
  Skipped tests are left out of the run with an `--exclude test:NAME` filter
  per test, and a complete run whose only failures are muted tests passes.
  `--no-quarantine` runs every test and counts every failure. A run that
  cannot read the quarantined tests runs every test.

  ## Retrying failed tests

  ExUnit runs every test once, so a test that fails intermittently looks the
  same as one that is broken. With retries enabled, the tests that failed are
  run again with `mix test --failed`, up to the given number of times. A test
  that passes on a retry is reported to Tuist as flaky, and the task succeeds
  if every failed test eventually passes. A run whose failed tests all timed
  out is not retried.

  Retries are off unless set, in order, by:

    * `--retries N`
    * `TUIST_TEST_RETRIES` (env)
    * `Mix.Project.config()[:tuist][:test_retries]`
  """

  use Mix.Task

  alias TuistEx.Analytics.Args
  alias TuistEx.Analytics.Config
  alias TuistEx.Analytics.Coverage
  alias TuistEx.Analytics.CoverageSummary
  alias TuistEx.Analytics.Evidence
  alias TuistEx.Analytics.ExUnitFormatter
  alias TuistEx.Analytics.GitHistory
  alias TuistEx.Analytics.Isolated
  alias TuistEx.Analytics.Quarantine
  alias TuistEx.Analytics.Report
  alias TuistEx.Analytics.SelectionFilter
  alias TuistEx.Analytics.Shards
  alias TuistEx.Analytics.Subprocess
  alias TuistEx.Analytics.TempDir
  alias TuistEx.Analytics.TestSelection
  alias TuistEx.Auth
  alias TuistEx.Git
  alias TuistEx.HTTP.JSONFile

  @formatter ExUnitFormatter
  @preferred_cli_env :test
  @retry_results "TUIST_EX_RETRY_RESULTS"
  @prepared_build "TUIST_EX_PREPARED_BUILD"
  @retry_mix_path "TUIST_EX_RETRY_MIX_PATH"
  @retry_selection "TUIST_EX_RETRY_SELECTION"
  @suite_failed "\"mix test\" failed"
  # The server's limit on a report's (inflated) body, less room for the
  # request's own framing.
  @report_limit 50_000_000 - 1_000_000

  def run(args) do
    case Args.ensure_env(:test, "tuist.test", args) do
      :ok -> run_in_test_env(args)
      {:reexecuted, 0} -> :ok
      {:reexecuted, status} -> exit({:shutdown, status})
    end
  end

  defp run_in_test_env(args) do
    {options, test_args} = split_args(args)
    validate_shard_options(options, Shards.index(options))
    warn_if_formatter_override(test_args)

    case System.get_env(@retry_results, "") do
      "" ->
        # Decided on the run's own arguments: those a shard adds below are
        # its share of the suite, not a filter.
        options =
          Keyword.merge(options,
            coverage: Coverage.requested?(test_args),
            coverage_partial: Coverage.partial?(test_args),
            coverage_narrowed: Coverage.narrowed?(test_args),
            coverage_excluded_tags: Coverage.excluded_tags(test_args)
          )

        case shard(options, test_args) do
          {options, test_args} ->
            {options, test_args} = native_coverage(options, test_args)

            if options[:prepare_only] do
              :ok
            else
              options = options |> quarantine(test_args) |> select_tests()

              case retries_for(options, test_args) do
                0 ->
                  cond do
                    options[:mute] ->
                      run_with_retries(options, test_args, 0)

                    options[:coverage] or GitHistory.enabled?(false) ->
                      run_deferred(options, test_args)

                    true ->
                      configure(options)
                      run_test(test_args, options)
                  end

                retries ->
                  run_with_retries(options, test_args, retries)
              end
            end

          :nothing_to_run ->
            :ok
        end

      # This process is a retry started by `run_with_retries/3`, rerunning
      # what its parent selected: record what the tests did for the parent,
      # which reports the whole run.
      path ->
        options = Keyword.put(options, :no_download, System.get_env(@prepared_build) == "true")

        if prepared?(options) do
          # Task discovery is done; do not leak its path into the tests' subprocesses.
          System.put_env([{"MIX_PATH", System.get_env(@retry_mix_path)}, {@retry_mix_path, nil}])
        end

        options = retry_selection(options)
        configure(Keyword.put(options, :mode, {:collect, path}))
        run_test(test_args, options)
    end
  end

  # On a shard, run only its share of the tests, against the build the plan
  # carries when there is one. A shard that cannot learn what to run fails:
  # running everything, or nothing, would both be silently wrong.
  defp shard(options, test_args) do
    case Shards.index(options) do
      nil ->
        {options, test_args}

      index ->
        if Mix.Project.umbrella?(),
          do:
            Mix.raise(
              "Tuist does not shard from an umbrella's root yet. Run the shard inside one of its applications."
            )

        reference = shard_unwrap(Shards.reference(options))

        Application.put_env(
          :tuist_ex,
          :analytics_options,
          Keyword.take(options, [:url, :project])
        )

        shard = shard_unwrap(Shards.fetch(reference, index, options))
        assigned = shard["modules"] || []
        files = Shards.files(assigned, Shards.test_units())

        if assigned != [] and files == [],
          do:
            Mix.raise(
              "None of the tests of shard #{index} of #{reference} exist in this checkout."
            )

        # Forwarded arguments are kept as given, in order: repeated options
        # such as `--include a --include b` mean something.
        {test_args, files} = Shards.restrict(test_args, files)
        test_args = Coverage.with_shard_export(test_args, index)

        if files == [] and options[:prepare_only] != true do
          Mix.shell().info("Tuist: shard #{index} of #{reference} has no tests to run.")
          :nothing_to_run
        else
          prebuilt =
            if options[:no_download] do
              app = Mix.Project.config()[:app]

              app_file =
                Path.join([Mix.Project.build_path(), "lib", to_string(app), "ebin", "#{app}.app"])

              if !File.regular?(app_file),
                do: Mix.raise("No prepared build found. Run mix tuist.test --prepare-only first.")

              warn_skipped_preparation()
              ["--no-compile", "--no-deps-check"]
            else
              download_build_args(shard, index)
            end

          if options[:prepare_only] == true and prebuilt == [],
            do: Mix.raise("Shard #{index} has no uploaded build to prepare.")

          Mix.shell().info(
            "Tuist: shard #{index} of #{reference}, #{Shards.count(length(files), "test file")}" <>
              if(prebuilt == [], do: "", else: ", using the uploaded build")
          )

          options =
            options
            |> Keyword.merge(shard_plan_id: shard["shard_plan_id"], shard_index: index)
            |> shard_selection(shard)

          {options, Enum.reject(prebuilt, &(&1 in test_args)) ++ test_args ++ files}
        end
    end
  end

  # A run with coverage counts with the runtime's native line counters,
  # without Mix's coverage tool, which would compile every module for `cover`
  # again. The project is compiled first, as `mix test` would, and what the
  # compile wrote is instrumented: a build `mix tuist.test.build --cover`
  # instrumented needs nothing. An umbrella's root, whose children each run
  # their own suite, a project that sets its own coverage tool, such as
  # excoveralls, which reads `cover`, and a runtime that cannot count
  # natively keep Mix's tool.
  defp native_coverage(options, test_args) do
    cond do
      options[:coverage] != true or options[:prepare_only] == true or Mix.Project.umbrella?() ->
        {options, test_args}

      get_in(Mix.Project.config(), [:test_coverage, :tool]) not in [nil, Mix.Tasks.Test.Coverage] ->
        {options, test_args}

      not :code.coverage_support() ->
        Mix.shell().info(
          "warning: this runtime cannot count coverage natively (it needs the JIT). " <>
            "Mix's coverage tool runs instead."
        )

        {options, test_args}

      true ->
        if "--no-compile" not in test_args do
          Application.put_env(
            :tuist_ex,
            :analytics_options,
            Keyword.take(options, [:url, :project])
          )

          Mix.Task.run("compile", test_args -- ["--warnings-as-errors"])
        end

        compile_path = Mix.Project.compile_path()
        Coverage.instrument([compile_path, Mix.Project.consolidation_path()])

        if Coverage.enable_native(compile_path) do
          warn_if_coverage_output()

          options =
            Keyword.merge(options,
              coverage_native: true,
              coverage_summary: CoverageSummary.options(options[:shard_index])
            )

          evidence? = TestSelection.configured?() and evidence_supported?()
          test_args = Coverage.without_cover(test_args)

          {Keyword.put(options, :coverage_evidence, evidence?),
           if(evidence?, do: one_at_a_time(test_args), else: test_args)}
        else
          {options, test_args}
        end
    end
  end

  # Before Elixir 1.19 nothing tells a test's process apart, so the run
  # records no evidence and keeps its concurrency.
  defp evidence_supported? do
    supported? = Evidence.supported?()

    if not supported? do
      Mix.shell().info(
        "warning: Tuist: recording which lines each test executes needs Elixir 1.19 or later, " <>
          "so this run records none for coverage-based test selection"
      )
    end

    supported?
  end

  # What a test executed is the change in the line counters while it ran, so
  # a run that records evidence runs one module at a time: `--max-cases`
  # given last wins, over the test helper's too. Sharding parallelizes it.
  defp one_at_a_time(test_args) do
    Mix.shell().info(
      "Tuist: running test modules one at a time to record which lines each test executes; " <>
        "shard the run with mix tuist.test.build to run in parallel"
    )

    test_args ++ ["--max-cases", "1"]
  end

  # Mix's coverage tool writes an HTML report to `:output`; counting natively
  # writes none.
  defp warn_if_coverage_output do
    if Keyword.has_key?(Mix.Project.config()[:test_coverage] || [], :output) do
      Mix.shell().info(
        "warning: counting coverage natively writes no HTML report, so :output is not used. " <>
          "Run with --export-coverage and then mix test.coverage for one."
      )
    end
  end

  # A plan without a build is fine: the shard compiles as usual.
  defp download_build_args(shard, index) do
    case Shards.download_build(shard["download_url"], Mix.Project.build_path()) do
      :ok ->
        ["--no-compile", "--no-deps-check"]

      {:error, :no_build} ->
        []

      {:error, reason} ->
        Mix.raise("Could not download the build for shard #{index}: #{inspect(reason)}")
    end
  end

  # A plan for an impact run that selected tests hands each shard the run's
  # whole skip list, and the run, which it reports its tests with.
  defp shard_selection(options, shard) do
    case shard do
      %{"test_impact_run_id" => run_id, "skipped_tests" => skipped}
      when is_binary(run_id) and is_list(skipped) ->
        skipped =
          for %{"module" => module} = entry <- skipped,
              do: %{module: module, suite: entry["suite"] || "", name: entry["name"]}

        apply_selection(options, {:selected, %{run_id: run_id, skipped_tests: skipped}})

      %{"test_impact_run_id" => run_id} when is_binary(run_id) ->
        Keyword.put(options, :test_impact_run_id, run_id)

      _shard ->
        options
    end
  end

  # Coverage-based test selection, for a project that opts into it and a run
  # that measures coverage, which keeps the evidence fresh. The run's Git
  # history goes up first, so the server's graph has the checkout's commit,
  # and the run reuses it. Shards apply what the plan job decided. A VM
  # whose ExUnit can't take the skip list doesn't ask: nothing could be
  # left out.
  defp select_tests(options) do
    if is_nil(options[:shard_index]) and selects?(options) and filter_installed?() do
      network_publishing? = network_publishing?(options)
      history = collect_history(options, network_publishing?)
      upload_history(history, &GitHistory.publish/2, network_publishing?)
      index = TestSelection.index(TestSelection.test_files())

      outcome =
        case Isolated.run(
               fn ->
                 TestSelection.decide(index, Keyword.take(options, [:url, :project, :scheme]))
               end,
               600_000
             ) do
          {:error, reason} -> {:failed, reason}
          outcome -> outcome
        end

      TestSelection.report(outcome)
      options |> Keyword.put(:history, history) |> apply_selection(outcome)
    else
      options
    end
  end

  @doc false
  def selects?(options, config \\ Mix.Project.config()) do
    TestSelection.configured?(config) and options[:coverage] == true and
      options[:no_selective_testing] != true and options[:prepare_only] != true and
      not Mix.Project.umbrella?()
  end

  # A selection leaves its skip list out of the run and its retries, and
  # makes the run's coverage partial when it skips anything; it is not
  # among what the run's own arguments left out, as quarantine is not. Like
  # a shard's, a partial run's total says nothing of the suite, so it skips
  # the coverage summary and its threshold. A run with a reason runs
  # everything and only reports its impact run.
  defp apply_selection(options, {:selected, selection}) do
    if SelectionFilter.apply(selection.skipped_tests) == :ok do
      skips? = selection.skipped_tests != []

      Keyword.merge(options,
        test_impact_run_id: selection.run_id,
        selection_skipped: selection.skipped_tests,
        coverage_partial: options[:coverage_partial] == true or skips?,
        coverage_summary: if(skips?, do: false, else: options[:coverage_summary])
      )
    else
      warn_unfiltered()
      options
    end
  end

  defp apply_selection(options, {:fallback, %{run_id: run_id}}),
    do: Keyword.put(options, :test_impact_run_id, run_id)

  defp apply_selection(options, _outcome), do: options

  defp filter_installed? do
    case SelectionFilter.install() do
      :ok ->
        true

      :error ->
        warn_unfiltered()
        false
    end
  end

  defp warn_unfiltered do
    Mix.shell().info(
      "warning: Tuist coverage-based test selection can't leave tests out with this version of ExUnit, so every test runs."
    )
  end

  # A retry leaves out what its parent's selection did, which the parent
  # wrote to a file: a skip list can be longer than an argument list.
  defp retry_selection(options) do
    with path when is_binary(path) and path != "" <- System.get_env(@retry_selection),
         {:ok, binary} <- File.read(path),
         [_ | _] = skipped <- :erlang.binary_to_term(binary) do
      if SelectionFilter.apply(skipped) == :ok do
        Keyword.put(options, :selection_skipped, skipped)
      else
        warn_unfiltered()
        options
      end
    else
      _ -> options
    end
  end

  defp shard_unwrap({:ok, value}), do: value
  defp shard_unwrap({:error, reason}) when is_binary(reason), do: Mix.raise(reason)
  defp shard_unwrap({:error, reason}), do: Mix.raise("Tuist sharding failed: #{inspect(reason)}")

  defp prepared?(options), do: options[:no_download] == true

  # Reads the tests Tuist quarantines for the project. Without a project or
  # credentials there is nothing to read, and a run that cannot read them
  # runs every test and counts every failure: the policy is never applied in
  # part, and a server that cannot answer never stops the tests.
  defp quarantine(options, test_args) do
    analytics_options = Keyword.take(options, [:url, :project])

    if options[:no_quarantine] == true do
      options
    else
      case Quarantine.fetch(analytics_options) do
        {:ok, policy} ->
          if Quarantine.empty?(policy),
            do: options,
            else: apply_quarantine(options, test_args, policy)

        {:error, reason} when is_binary(reason) ->
          Report.debug("tuist analytics: quarantine not applied: " <> reason)
          options

        {:error, reason} ->
          Mix.shell().info(
            "warning: Tuist could not read the project's quarantined tests (#{inspect(reason)}), " <>
              "so every test runs and every failure counts."
          )

          options
      end
    end
  end

  defp apply_quarantine(options, test_args, policy) do
    skipped = MapSet.size(policy.skipped)
    muted = MapSet.size(policy.muted)

    if skipped > 0 do
      Mix.shell().info(
        "Tuist: skipping #{Shards.count(skipped, "quarantined test")}:\n" <>
          Enum.map_join(Enum.sort(policy.skipped), "\n", &("  " <> Quarantine.describe(&1)))
      )
    end

    # Telling a muted failure apart needs the run to raise when it fails, as
    # retrying does, and the same runs cannot.
    mute? =
      muted > 0 and
        cond do
          warnings_as_errors?(test_args) ->
            Mix.shell().info(
              "warning: Tuist does not apply muted tests when `--warnings-as-errors` is given; " <>
                "their failures fail the run."
            )

            false

          Mix.Project.umbrella?() ->
            Mix.shell().info(
              "warning: Tuist does not apply muted tests from an umbrella's root yet; " <>
                "their failures fail the run. Run the tests inside one of its applications."
            )

            false

          true ->
            Mix.shell().info(
              "Tuist: #{Shards.count(muted, "muted test")} run, and their failures do not fail the run."
            )

            true
        end

    Keyword.merge(options, quarantine: policy, mute: mute?)
  end

  defp run_test(args, options) do
    args =
      args ++ Quarantine.exclude_args(options[:quarantine])

    if prepared?(options),
      do: Mix.Tasks.Test.run(args),
      else: Args.run_wrapped("test", Mix.Tasks.Test, args)
  end

  defp warn_skipped_preparation do
    preparation? =
      Mix.Project.config()[:aliases][:test]
      |> List.wrap()
      |> Enum.any?(&(&1 not in ["test", "tuist.test"]))

    if preparation? do
      Mix.shell().info(
        "Tuist: --no-download skips the project's test preparation alias; " <>
          "run its setup separately with compilation disabled."
      )
    end
  end

  # Coverage is read when each suite finishes and sent with its run, and the
  # Git history goes with the run too, so the runs wait for the suite to end;
  # the Git history is read before the tests can change the checkout.
  defp run_deferred(options, test_args) do
    network_publishing? = network_publishing?(options)

    {history, options} =
      Keyword.pop_lazy(options, :history, fn -> collect_history(options, network_publishing?) end)

    configure(Keyword.put(options, :mode, {:defer, self()}))

    try do
      run_test(test_args, options)
    after
      submit_runs(
        summarize_coverage(ExUnitFormatter.take_deferred()),
        options,
        history,
        network_publishing?
      )
    end
  end

  defp run_with_retries(options, test_args, retries) do
    network_publishing? = network_publishing?(options)

    {history, options} =
      Keyword.pop_lazy(options, :history, fn -> collect_history(options, network_publishing?) end)

    configure(Keyword.put(options, :mode, {:defer, self()}))
    suite = run_suite(test_args, options)
    # One per suite that ran: an umbrella runs one for each application. The
    # first run's coverage is the run's: retries never carry `--cover`.
    {timed_out?, deferred} = pop_timed_out(summarize_coverage(ExUnitFormatter.take_deferred()))

    # A suite cut short by `--max-failures` left tests unrun. Retrying the
    # failures it did reach could pass and hide the ones it never got to, so
    # such a run is reported as it is and stays failed. So does one that
    # failed outside its tests, which no retry reruns and no muted test
    # accounts for.
    recoverable? =
      deferred != [] and
        not Enum.any?(deferred, fn {_payload, _opts, unrecoverable?} -> unrecoverable? end)

    {suite, attempts} =
      cond do
        suite != :failed or not recoverable? or retries == 0 ->
          {suite, []}

        # Tests that all ran out of time point at what they wait on, such as
        # an unreachable service, and every retry would wait out each
        # timeout again.
        timed_out? ->
          Mix.shell().info(
            "warning: Tuist does not retry failed tests when every one of them timed out."
          )

          {suite, []}

        true ->
          retry(test_args, retries, options)
      end

    deferred =
      Enum.map(deferred, fn {payload, opts, unrecoverable?} ->
        {ExUnitFormatter.merge_retries(payload, attempts), opts, unrecoverable?}
      end)

    {suite, deferred} = unmute(suite, recoverable?, deferred, options)
    submit_runs(deferred, options, history, network_publishing?)

    if suite == :failed, do: fail(test_args)
    :ok
  end

  # A recoverable run whose only failures are muted tests passes, and is
  # reported as passing; each muted test keeps its own failure.
  defp unmute(:failed, true, deferred, options) do
    if options[:mute] == true and
         Enum.all?(deferred, fn {payload, _opts, _unrecoverable?} ->
           payload.status == "success" or
             Quarantine.only_muted_failed?(payload, options[:quarantine])
         end) do
      Mix.shell().info("Tuist: only muted tests failed, so the run passes.")

      {:passed,
       Enum.map(deferred, fn {payload, opts, unrecoverable?} ->
         {%{payload | status: "success"}, opts, unrecoverable?}
       end)}
    else
      {:failed, deferred}
    end
  end

  defp unmute(suite, _recoverable?, deferred, _options), do: {suite, deferred}

  # A run counting natively leaves Mix's coverage tool out, so its summary
  # and threshold are printed and checked here, from the counts the formatter
  # read when the suite finished.
  defp summarize_coverage(deferred) do
    Enum.map(deferred, fn {payload, opts, unrecoverable?} ->
      {lines, payload} = Map.pop(payload, :coverage_lines)
      if lines, do: CoverageSummary.report(lines, opts[:coverage_summary])
      {payload, opts, unrecoverable?}
    end)
  end

  defp pop_timed_out(deferred) do
    deferred =
      Enum.map(deferred, fn {payload, opts, unrecoverable?} ->
        {timed_out, payload} = Map.pop(payload, :timed_out, false)
        {timed_out, {payload, opts, unrecoverable?}}
      end)

    {deferred != [] and Enum.all?(deferred, &elem(&1, 0)), Enum.map(deferred, &elem(&1, 1))}
  end

  # The commits and branch heads go up before the runs, whose ingestion reads
  # which commits the default branch reached; the commit's listing once the
  # runs exist.
  defp submit_runs(deferred, options, history, network_publishing?) do
    upload_history(history, &GitHistory.publish/2, network_publishing?)

    for {payload, opts, _unrecoverable?} <- deferred do
      payload
      |> with_coverage(options, opts, history, network_publishing?)
      |> ExUnitFormatter.submit(opts)

      if dir = get_in(payload, [:evidence_snapshot, :collected, :dir]), do: File.rm_rf(dir)
    end

    upload_history(history, &GitHistory.upload_listing/2, network_publishing?)
    :ok
  end

  defp upload_history(nil, _upload, _network_publishing?), do: :ok

  defp upload_history(history, upload, network_publishing?) do
    analytics_options = Application.get_env(:tuist_ex, :analytics_options, [])

    if not network_publishing? do
      case Isolated.run(fn -> upload.(history, analytics_options) end, 300_000) do
        problems when is_list(problems) ->
          Enum.each(problems, &Report.debug("tuist analytics: " <> &1))

        {:error, reason} ->
          Report.debug("tuist analytics: the Git history upload failed: #{inspect(reason)}")
      end
    end
  end

  # Both read the run's own options, as `configure/1` will store them: they
  # run before it, a selection's before the task even knows how it runs.
  defp network_publishing?(options) do
    analytics_options = analytics_options(options)
    Isolated.run(fn -> Auth.network_publishing?(analytics_options) end, 2_000) == true
  end

  # On authenticated CI, or with coverage, unless `TUIST_GIT_UPLOAD_ENABLED=false`.
  defp collect_history(options, network_publishing?) do
    coverage? = options[:coverage] == true
    analytics_options = analytics_options(options)

    with true <-
           not network_publishing? and GitHistory.enabled?(coverage?),
         %{} = history <-
           Isolated.run(
             fn ->
               GitHistory.collect(File.cwd!(), analytics_options, &System.get_env/1, coverage?)
             end,
             300_000
           ) do
      history
    else
      false ->
        nil

      {:error, reason} ->
        Report.debug("tuist analytics: the Git history could not be read: #{inspect(reason)}")
        nil
    end
  end

  defp with_coverage(payload, options, opts, history, network_publishing?) do
    {snapshot, payload} = Map.pop(payload, :coverage_snapshot)
    {evidence, payload} = Map.pop(payload, :evidence_snapshot)

    if network_publishing? do
      payload
    else
      payload
      |> do_with_coverage(snapshot, options, opts, history)
      |> with_evidence(evidence)
    end
  end

  # Which lines each test ran, by repository-relative path, as the run's
  # coverage names its files, written to a file the request reads as it's
  # sent. Evidence that would take the report past the server's limit is
  # written again without lines, which selection doesn't need, and left out
  # when even that doesn't fit.
  defp with_evidence(payload, nil), do: payload

  defp with_evidence(payload, %{collected: collected, identities: identities, sources: sources}) do
    case Git.toplevel(File.cwd!()) do
      {:ok, root} ->
        root = Path.expand(root)

        relative = fn path ->
          if String.starts_with?(path, root <> "/"), do: Path.relative_to(path, root)
        end

        out = Path.join(collected.dir, "coverage_evidence.json")
        write = &Evidence.write(collected, identities, sources, relative, out, lines: &1)
        budget = @report_limit - IO.iodata_length(JSON.encode_to_iodata!(payload))
        :ok = write.(true)

        cond do
          File.stat!(out).size <= budget ->
            Map.put(payload, :coverage_evidence, %JSONFile{path: out})

          (
            size = File.stat!(out).size
            :ok = write.(false)
            File.stat!(out).size <= budget
          ) ->
            Mix.shell().info(
              "warning: Tuist: the run's coverage evidence (#{megabytes(size)}) is too large " <>
                "to send with lines, so carried coverage can't use it; " <>
                "shard the run with mix tuist.test.build to keep them"
            )

            Map.put(payload, :coverage_evidence, %JSONFile{path: out})

          true ->
            Mix.shell().info(
              "warning: Tuist: the run's coverage evidence is too large to send, so it's left out; " <>
                "shard the run with mix tuist.test.build"
            )

            payload
        end

      :error ->
        payload
    end
  rescue
    exception ->
      Report.debug(
        "tuist analytics: the run's coverage evidence could not be sent: #{Exception.message(exception)}"
      )

      payload
  end

  defp megabytes(bytes), do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  defp do_with_coverage(payload, snapshot, options, opts, history) do
    payload = if history, do: Map.merge(payload, GitHistory.payload(history)), else: payload

    # A test sharing a quarantined test's name was left out although the
    # run's own arguments did not ask for it.
    partial? =
      options[:coverage_partial] == true or Map.has_key?(payload, :skip_test_identifiers)

    with snapshot when is_list(snapshot) <- snapshot,
         {:ok, coverage} <- Coverage.build(snapshot, File.cwd!(), partial?),
         {:ok, payload} <-
           Isolated.run(fn -> Coverage.attach(payload, coverage, opts) end, 600_000) do
      payload
    else
      nil ->
        payload

      problem ->
        Report.debug("tuist analytics: the run's coverage could not be sent: #{inspect(problem)}")
        payload
    end
  end

  # With `--raise`, a failing suite raises instead of registering an exit
  # hook that cannot be withdrawn, which is what lets a successful retry turn
  # the run green. Anything else `mix test` raises is not ours to handle.
  defp run_suite(test_args, options) do
    run_test(if("--raise" in test_args, do: test_args, else: test_args ++ ["--raise"]), options)
    :passed
  rescue
    error in Mix.Error ->
      if error.message == @suite_failed, do: :failed, else: reraise(error, __STACKTRACE__)
  end

  defp retry(test_args, retries, options) do
    # The retries run in new processes that start the application again. This
    # one is done with it, and leaving it running would keep hold of whatever
    # it owns exclusively, such as a port a web server listens on.
    for app <- Enum.reverse(project_apps()), do: Application.stop(app)

    Enum.reduce_while(1..retries, {:failed, []}, fn attempt, {_suite, attempts} ->
      Mix.shell().info("\nRetrying the failed tests (attempt #{attempt} of #{retries})\n")

      case retry_once(test_args, options) do
        {:ok, status, records} ->
          attempts = attempts ++ [records]
          if status == 0, do: {:halt, {:passed, attempts}}, else: {:cont, {:failed, attempts}}

        :error ->
          {:halt, {:failed, attempts}}
      end
    end)
  end

  # An umbrella root is no application itself: its children are.
  defp project_apps do
    if Mix.Project.umbrella?(),
      do: Map.keys(Mix.Project.apps_paths()),
      else: List.wrap(Mix.Project.config()[:app])
  end

  # `--failed` picks what to rerun, so the options that pick tests by other
  # means, and that Mix refuses next to it, are left out. So is coverage: the
  # first run already wrote it for the whole suite, and the reruns alone
  # would overwrite it and fall under its threshold.
  @not_for_retries ["--raise", "--failed", "--stale", "--cover"]

  defp retry_args(["--export-coverage", _name | rest]), do: retry_args(rest)
  defp retry_args(["--export-coverage=" <> _name | rest]), do: retry_args(rest)
  defp retry_args([arg | rest]) when arg in @not_for_retries, do: retry_args(rest)
  defp retry_args([arg | rest]), do: [arg | retry_args(rest)]
  defp retry_args([]), do: []

  # A fresh process, like running `mix test --failed` by hand: the test
  # helper, the application and every module start clean, which rerunning in
  # this process cannot guarantee.
  defp retry_once(test_args, options) do
    TempDir.with_dir("tuist-ex-retry", &retry_once(test_args, Path.join(&1, "results"), options))
  end

  defp retry_once(test_args, path, options) do
    case System.find_executable("mix") do
      mix when is_binary(mix) ->
        # `--failed` also reruns tests that failed before they were skipped:
        # ExUnit keeps a failure on record until the test passes.
        args =
          ["tuist.test", "--failed" | retry_args(test_args)] ++
            Quarantine.exclude_args(options[:quarantine])

        env = retry_env(path, options)

        env =
          case options[:selection_skipped] do
            [_ | _] = selection ->
              file = Path.join(Path.dirname(path), "selection")
              File.write!(file, :erlang.term_to_binary(selection))
              [{@retry_selection, file} | env]

            _ ->
              env
          end

        status = Subprocess.run(mix, args, env)
        {:ok, status, ExUnitFormatter.read_collected(path)}

      _ ->
        :error
    end
  end

  defp retry_env(path, options) do
    env = [
      {@retry_results, path},
      {@prepared_build, to_string(prepared?(options))},
      {"MIX_ENV", "test"}
    ]

    if prepared?(options) do
      original_path = System.get_env("MIX_PATH")
      separator = if match?({:win32, _}, :os.type()), do: ";", else: ":"

      mix_path =
        Enum.join([Application.app_dir(:tuist_ex, "ebin") | List.wrap(original_path)], separator)

      [{"MIX_PATH", mix_path}, {@retry_mix_path, original_path} | env]
    else
      env
    end
  end

  # What `mix test` does for a failing suite, deferred until the retries are in.
  defp fail(test_args) do
    if "--raise" in test_args do
      Mix.raise(@suite_failed)
    else
      status = exit_status(test_args)
      System.at_exit(fn _ -> exit({:shutdown, status}) end)
    end
  end

  defp exit_status(test_args) do
    {opts, _rest, _invalid} = OptionParser.parse(test_args, switches: [exit_status: :integer])
    Keyword.get(opts, :exit_status, 2)
  end

  # Read the way `mix test` reads it, so `--warnings-as-errors=true` counts.
  defp warnings_as_errors?(test_args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(test_args, switches: [warnings_as_errors: :boolean])

    Keyword.get(opts, :warnings_as_errors, false)
  end

  # Retrying needs the first run to raise when it fails. `mix test` then
  # raises before it gets to `--warnings-as-errors`, so the retries would
  # pass and the warnings would never fail the run. In an umbrella it raises
  # in the first application that fails, and the ones after it never run.
  defp retries_for(options, test_args) do
    count = retries(options)

    cond do
      count == 0 ->
        0

      warnings_as_errors?(test_args) ->
        Mix.shell().info(
          "warning: Tuist does not retry failed tests when `--warnings-as-errors` is given."
        )

        0

      Mix.Project.umbrella?() ->
        Mix.shell().info(
          "warning: Tuist does not retry failed tests from an umbrella's root yet. " <>
            "Run them inside one of its applications to retry them."
        )

        0

      true ->
        count
    end
  end

  @doc false
  def retries(options, environment \\ &System.get_env/1) do
    configured =
      Keyword.get(options, :retries) || environment.("TUIST_TEST_RETRIES") ||
        Keyword.get(Mix.Project.config()[:tuist] || [], :test_retries)

    case configured do
      count when is_integer(count) and count > 0 ->
        count

      count when is_binary(count) ->
        case Integer.parse(count) do
          {count, ""} when count > 0 -> count
          _ -> 0
        end

      _ ->
        0
    end
  end

  defp warn_if_formatter_override(test_args) do
    if "--formatter" in test_args do
      Mix.shell().info(
        "warning: `--formatter` was forwarded to `mix test`; Mix replaces the formatter list, " <>
          "so Tuist analytics will not be submitted for this run."
      )
    end

    :ok
  end

  @doc false
  def configure(options) do
    # Loading an application resets its settings to their defaults. On a
    # checkout that has not been built yet, ExUnit is not loaded at this
    # point, and the formatter registered below would be wiped when it is.
    Application.load(:ex_unit)
    existing = Application.get_env(:ex_unit, :formatters, [ExUnit.CLIFormatter])
    Application.put_env(:ex_unit, :formatters, formatters(existing))
    # Read here, in the project `mix test` was started from: the formatter
    # runs inside each child of an umbrella, which has its own config.
    Application.put_env(:tuist_ex, :analytics_options, analytics_options(options))
    :ok
  end

  defp analytics_options(options),
    do: Keyword.put_new_lazy(options, :project_config, &Config.project_tuist_config/0)

  @own_switches [
    url: :string,
    project: :string,
    scheme: :string,
    retries: :integer,
    shard_index: :integer,
    shard_reference: :string
  ]

  @doc """
  Splits the task's own options from the arguments meant for `mix test`.
  A `--` separator is accepted for compatibility and dropped.
  """
  def split_args(args) do
    {options, forwarded} = Args.split(args, @own_switches)

    Enum.reduce(
      [
        prepare_only: "--prepare-only",
        no_download: "--no-download",
        no_quarantine: "--no-quarantine",
        no_selective_testing: "--no-selective-testing"
      ],
      {options, forwarded},
      fn
        {key, flag}, {options, forwarded} ->
          if flag in forwarded,
            do: {Keyword.put(options, key, true), Enum.reject(forwarded, &(&1 == flag))},
            else: {options, forwarded}
      end
    )
  end

  @doc false
  def validate_shard_options(options, index) do
    if (options[:prepare_only] == true or options[:no_download] == true) and is_nil(index),
      do: Mix.raise("--prepare-only and --no-download require a shard index.")

    if options[:prepare_only] == true and options[:no_download] == true,
      do: Mix.raise("--prepare-only and --no-download cannot be combined.")

    :ok
  end

  @doc """
  The formatters to run with: the ones already configured, and Tuist's.
  """
  def formatters(existing) do
    if @formatter in existing, do: existing, else: existing ++ [@formatter]
  end
end
