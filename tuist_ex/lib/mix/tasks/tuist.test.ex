defmodule Mix.Tasks.Tuist.Test do
  @shortdoc "Run mix test with Tuist analytics enabled"

  @moduledoc """
  Runs `mix test` with the Tuist analytics ExUnit formatter installed, then
  submits the test run to your Tuist dashboard.

      mix tuist.test [--url URL] [--project ACCOUNT/PROJECT] [--retries N] [ARGS...]

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

  ## Retrying failed tests

  ExUnit runs every test once, so a test that fails intermittently looks the
  same as one that is broken. With retries enabled, the tests that failed are
  run again with `mix test --failed`, up to the given number of times. A test
  that passes on a retry is reported to Tuist as flaky, and the task succeeds
  if every failed test eventually passes.

  Retries are off unless set, in order, by:

    * `--retries N`
    * `TUIST_TEST_RETRIES` (env)
    * `Mix.Project.config()[:tuist][:test_retries]`
  """

  use Mix.Task

  alias TuistEx.Analytics.Args
  alias TuistEx.Analytics.ExUnitFormatter
  alias TuistEx.Analytics.Shards
  alias TuistEx.Analytics.TempDir

  @formatter ExUnitFormatter
  @preferred_cli_env :test
  @retry_results "TUIST_EX_RETRY_RESULTS"
  @suite_failed "\"mix test\" failed"

  def run(args) do
    case Args.ensure_env(:test, "tuist.test", args) do
      :ok -> run_in_test_env(args)
      {:reexecuted, 0} -> :ok
      {:reexecuted, status} -> exit({:shutdown, status})
    end
  end

  defp run_in_test_env(args) do
    {options, test_args} = split_args(args)
    warn_if_formatter_override(test_args)
    retrying? = System.get_env(@retry_results) not in [nil, ""]

    # A retry reruns what its parent already selected for the shard.
    selection = if retrying?, do: {options, test_args}, else: shard(options, test_args)

    case {selection, System.get_env(@retry_results), retries(options)} do
      {:nothing_to_run, _path, _retries} ->
        :ok

      {{options, test_args}, path, _retries} when is_binary(path) and path != "" ->
        # This process is a retry started by the branch below: record what
        # the tests did for the parent, which reports the whole run.
        configure(Keyword.put(options, :mode, {:collect, path}))
        run_test(test_args)

      {{options, test_args}, _path, 0} ->
        configure(options)
        run_test(test_args)

      {{options, test_args}, _path, retries} ->
        run_with_retries(options, test_args, retries)
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

        if files == [] do
          Mix.shell().info("Tuist: shard #{index} of #{reference} has no tests to run.")
          :nothing_to_run
        else
          prebuilt = download_build_args(shard, index)

          Mix.shell().info(
            "Tuist: shard #{index} of #{reference}, #{Shards.count(length(files), "test file")}" <>
              if(prebuilt == [], do: "", else: ", using the uploaded build")
          )

          options =
            Keyword.merge(options, shard_plan_id: shard["shard_plan_id"], shard_index: index)

          {options, Enum.reject(prebuilt, &(&1 in test_args)) ++ test_args ++ files}
        end
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

  defp shard_unwrap({:ok, value}), do: value
  defp shard_unwrap({:error, reason}) when is_binary(reason), do: Mix.raise(reason)
  defp shard_unwrap({:error, reason}), do: Mix.raise("Tuist sharding failed: #{inspect(reason)}")

  defp run_test(args), do: Args.run_wrapped("test", Mix.Tasks.Test, args)

  defp run_with_retries(options, test_args, retries) do
    configure(Keyword.put(options, :mode, {:defer, self()}))
    suite = run_suite(test_args)
    # One per suite that ran: an umbrella runs one for each application.
    deferred = ExUnitFormatter.take_deferred()

    # A suite cut short by `--max-failures` left tests unrun. Retrying the
    # failures it did reach could pass and hide the ones it never got to, so
    # such a run is reported as it is and stays failed.
    complete? =
      deferred != [] and not Enum.any?(deferred, fn {_payload, _opts, aborted?} -> aborted? end)

    {suite, attempts} =
      if suite == :failed and complete?, do: retry(test_args, retries), else: {suite, []}

    for {payload, opts, _aborted?} <- deferred do
      ExUnitFormatter.submit(ExUnitFormatter.merge_retries(payload, attempts), opts)
    end

    if suite == :failed, do: fail(test_args)
    :ok
  end

  # With `--raise`, a failing suite raises instead of registering an exit
  # hook that cannot be withdrawn, which is what lets a successful retry turn
  # the run green. Anything else `mix test` raises is not ours to handle.
  defp run_suite(test_args) do
    run_test(if("--raise" in test_args, do: test_args, else: test_args ++ ["--raise"]))
    :passed
  rescue
    error in Mix.Error ->
      if error.message == @suite_failed, do: :failed, else: reraise(error, __STACKTRACE__)
  end

  defp retry(test_args, retries) do
    # The retries run in new processes that start the application again. This
    # one is done with it, and leaving it running would keep hold of whatever
    # it owns exclusively, such as a port a web server listens on.
    for app <- Enum.reverse(project_apps()), do: Application.stop(app)

    Enum.reduce_while(1..retries, {:failed, []}, fn attempt, {_suite, attempts} ->
      Mix.shell().info("\nRetrying the failed tests (attempt #{attempt} of #{retries})\n")

      case retry_once(test_args) do
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
  # means, and that Mix refuses next to it, are left out.
  @not_for_retries ["--raise", "--failed", "--stale"]

  # A fresh process, like running `mix test --failed` by hand: the test
  # helper, the application and every module start clean, which rerunning in
  # this process cannot guarantee.
  defp retry_once(test_args) do
    TempDir.with_dir("tuist-ex-retry", &retry_once(test_args, Path.join(&1, "results")))
  end

  defp retry_once(test_args, path) do
    case System.find_executable("mix") do
      mix when is_binary(mix) ->
        color = if IO.ANSI.enabled?(), do: ["--color"], else: []

        args =
          ["tuist.test", "--failed"] ++ color ++ Enum.reject(test_args, &(&1 in @not_for_retries))

        {_output, status} =
          System.cmd(mix, args,
            env: [{@retry_results, path}, {"MIX_ENV", "test"}],
            into: IO.stream(:stdio, :line),
            stderr_to_stdout: true
          )

        {:ok, status, ExUnitFormatter.read_collected(path)}

      _ ->
        :error
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
    Application.put_env(:tuist_ex, :analytics_options, options)
    :ok
  end

  @own_switches [
    url: :string,
    project: :string,
    retries: :integer,
    shard_index: :integer,
    shard_reference: :string
  ]

  @doc """
  Splits the task's own options from the arguments meant for `mix test`.
  A `--` separator is accepted for compatibility and dropped.
  """
  def split_args(args), do: Args.split(args, @own_switches)

  @doc """
  The formatters to run with: the ones already configured, and Tuist's.
  """
  def formatters(existing) do
    if @formatter in existing, do: existing, else: existing ++ [@formatter]
  end
end
