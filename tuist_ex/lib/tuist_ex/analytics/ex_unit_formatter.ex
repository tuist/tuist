defmodule TuistEx.Analytics.ExUnitFormatter do
  @moduledoc false

  # Custom ExUnit formatter that captures test outcomes and submits a
  # POST /api/projects/:account/:project/tests payload when the suite
  # finishes. Register it via ExUnit.start(formatters: [TuistEx.Analytics.ExUnitFormatter])
  # or by adding it as `formatters` inside ExUnit's application config.
  #
  # The formatter must never change the exit code of `mix test`: a
  # submission failure is logged through Mix.shell/0 (visible with
  # TUIST_DEBUG=1) and swallowed.
  #
  # What happens when the suite finishes depends on the `:mode` option:
  #
  #   * `:submit` (default) sends the run.
  #   * `{:defer, owner}` sends the run to the `owner` process, which collects
  #     it with `take_deferred/0`. `mix tuist.test` uses it when it may retry
  #     failed tests, so the run is sent once, with the retries in it.
  #   * `{:collect, path}` writes the test outcomes to a file and sends
  #     nothing. The process retrying failed tests runs in this mode and the
  #     parent reads the file.
  use GenServer

  alias TuistEx.Analytics.Contract
  alias TuistEx.Analytics.Coverage
  alias TuistEx.Analytics.Enumeration
  alias TuistEx.Analytics.Env
  alias TuistEx.Analytics.HTTP
  alias TuistEx.Analytics.Isolated
  alias TuistEx.Analytics.Metadata
  alias TuistEx.Analytics.Report

  @deferred :deferred_test_run

  def init(opts) do
    merged =
      run_options(Keyword.new(opts), Application.get_env(:tuist_ex, :analytics_options, []))

    {:ok,
     %{
       tests: [],
       enumerated: [],
       filters: {[], []},
       aborted?: false,
       monotonic_start_ns: System.monotonic_time(),
       ran_at: DateTime.utc_now(),
       opts: merged,
       shell: Keyword.get(merged, :shell, &Report.debug/1)
     }}
  end

  @doc """
  The options a formatter runs with, given the ones it was started with and
  the ones the Mix task configured for the run.

  The task's options apply to the formatter ExUnit starts. A caller that
  brings its own `:submit` is driving a formatter of its own, typically a
  test of this module, possibly inside a suite that is itself reported, and
  gets exactly the options it passed.
  """
  def run_options(opts, configured) do
    if Keyword.has_key?(opts, :submit), do: opts, else: Keyword.merge(configured, opts)
  end

  def handle_cast({:suite_started, opts}, state) do
    filters =
      Enumeration.config_filters(
        Keyword.get(opts, :include, []),
        Keyword.get(opts, :exclude, []),
        Keyword.get(state.opts, :cli_filters, {[], []})
      )

    {:noreply,
     %{
       state
       | monotonic_start_ns: System.monotonic_time(),
         ran_at: DateTime.utc_now(),
         filters: filters
     }}
  end

  # A test a filter left out, such as `--only` or `file:line`, was not part
  # of the run: reported as skipped, it would look like it was turned off.
  # It was a candidate, though, which the run's enumerated tests say.
  def handle_cast({:test_finished, %ExUnit.Test{state: {:excluded, _}} = test}, state),
    do: {:noreply, enumerate(state, test)}

  def handle_cast({:test_finished, test}, state) do
    {:noreply, enumerate(%{state | tests: [record(test) | state.tests]}, test)}
  end

  # ExUnit stopped early because of `--max-failures`: tests it never reached
  # are neither passed nor failed, so the run cannot be recovered by retrying
  # the failures it did see.
  def handle_cast(:max_failures_reached, state), do: {:noreply, %{state | aborted?: true}}

  def handle_cast({:suite_finished, times}, state) do
    duration_ms = suite_duration_ms(times, state.monotonic_start_ns)
    tests = Enum.reverse(state.tests)

    try do
      case Keyword.get(state.opts, :mode, :submit) do
        # An umbrella runs one suite per application, each with a formatter
        # of its own, so this adds to what the earlier suites wrote.
        {:collect, path} ->
          File.write!(path, :erlang.term_to_binary(read_collected(path) ++ tests))

        {:defer, owner} ->
          payload =
            tests
            |> build_payload(duration_ms, state.ran_at, state.opts)
            |> put_coverage_snapshot(state.opts)
            |> put_enumeration(state)

          send(owner, {@deferred, {payload, state.opts, state.aborted?}})

        :submit ->
          submit(build_payload(tests, duration_ms, state.ran_at, state.opts), state.opts)
      end
    rescue
      exception ->
        state.shell.(
          "tuist analytics: failed to build test payload: #{Exception.message(exception)}"
        )
    end

    {:noreply, state}
  end

  def handle_cast(_message, state), do: {:noreply, state}

  # Every test has run by now, and `cover` still holds this suite's counters:
  # Mix turns them into its own report, and an umbrella restarts `cover` for
  # its next application, only after the formatters are done. The owner turns
  # the snapshot into the run's coverage before sending it.
  defp put_coverage_snapshot(payload, opts) do
    with true <- Keyword.get(opts, :coverage, false),
         snapshot when is_list(snapshot) <- Coverage.snapshot() do
      Map.put(payload, :coverage_snapshot, snapshot)
    else
      _ -> payload
    end
  end

  defp enumerate(state, test) do
    if Keyword.get(state.opts, :enumerate, false),
      do: %{state | enumerated: [Enumeration.entry(test, state.filters) | state.enumerated]},
      else: state
  end

  # The owner completes the list once ExUnit is done, in case the run left
  # tests unreported. The project is read here for the same reason as the
  # coverage snapshot: in an umbrella, this is the application's own.
  # A run whose test files could not be listed is sent without its
  # enumerated tests rather than not at all.
  defp put_enumeration(payload, state) do
    if Keyword.get(state.opts, :enumerate, false) do
      Map.put(payload, :enumeration, %{
        tests: state.enumerated |> Enum.reverse() |> Enumeration.uniq(),
        project: Enumeration.project(),
        filters: state.filters
      })
    else
      payload
    end
  rescue
    exception ->
      state.shell.(
        "tuist analytics: failed to list the test files: #{Exception.message(exception)}"
      )

      payload
  end

  @doc """
  Sends a test run. A failure is reported through the shell and never raised.
  """
  def submit(payload, opts) do
    submit = Keyword.get(opts, :submit, &HTTP.submit_test_run/2)
    shell = Keyword.get(opts, :shell, &Report.debug/1)

    case Isolated.run(fn -> submit.(payload, opts) end, 60_000) do
      :ok -> :ok
      {:error, reason} -> shell.("tuist analytics: failed to submit test run: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Returns the runs `{:defer, owner}` mode sent to the calling process, one
  `{payload, opts, aborted?}` per suite that ran (an umbrella runs one per
  application). `aborted?` says the suite stopped before running every test.
  Call it once ExUnit is done, when its formatters have stopped.
  """
  def take_deferred do
    receive do
      {@deferred, run} -> [run | take_deferred()]
    after
      0 -> []
    end
  end

  @doc """
  Reads the outcomes a `{:collect, path}` run wrote, as a list of records.
  """
  def read_collected(path) do
    case File.read(path) do
      {:ok, binary} -> :erlang.binary_to_term(binary)
      _ -> []
    end
  rescue
    _ -> []
  end

  @doc """
  Folds retry attempts into a run. `attempts` is one list of records per
  retry, in order. A test that was retried gets a repetition per attempt, its
  status becomes that of its last attempt, and module, suite and run statuses
  are recomputed, the same shape the other build systems report.
  """
  def merge_retries(payload, []), do: payload

  def merge_retries(payload, attempts) do
    retries =
      attempts
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {records, retry} -> Enum.map(records, &{retry, &1}) end)
      |> Enum.reject(fn {_retry, record} -> record.status == "skipped" end)
      |> Enum.group_by(fn {_retry, record} ->
        {record.module, record.describe || "", record.name}
      end)

    modules =
      Enum.map(payload.test_modules, fn module ->
        cases =
          Enum.map(module.test_cases, fn test_case ->
            key = {module.name, Map.get(test_case, :test_suite_name) || "", test_case.name}
            retry_test_case(test_case, Map.get(retries, key, []))
          end)

        # A retry adds the time it took to its test, and so to the suite and
        # module holding it and to the run.
        %{
          module
          | test_cases: cases,
            status: status_of(cases),
            duration: module.duration + added(module.test_cases, cases),
            test_suites:
              Enum.map(module.test_suites, fn suite ->
                in_suite = &(Map.get(&1, :test_suite_name) == suite.name)
                suite_cases = Enum.filter(cases, in_suite)

                %{
                  suite
                  | status: status_of(suite_cases),
                    duration:
                      suite.duration +
                        added(Enum.filter(module.test_cases, in_suite), suite_cases)
                }
              end)
        }
      end)

    added =
      added(
        Enum.flat_map(payload.test_modules, & &1.test_cases),
        Enum.flat_map(modules, & &1.test_cases)
      )

    payload = %{payload | test_modules: modules, status: status_of(modules)}

    if Map.has_key?(payload, :duration),
      do: Map.update!(payload, :duration, &(&1 + added)),
      else: payload
  end

  defp added(before, merged), do: duration_of(merged) - duration_of(before)
  defp duration_of(cases), do: cases |> Enum.map(&Map.get(&1, :duration, 0)) |> Enum.sum()

  defp retry_test_case(test_case, []), do: test_case

  defp retry_test_case(test_case, retries) do
    first = %{
      repetition_number: 1,
      name: "Run 1",
      status: test_case.status,
      duration: test_case.duration
    }

    repetitions =
      Enum.map(retries, fn {retry, record} ->
        %{
          repetition_number: retry + 1,
          name: "Retry #{retry}",
          status: record.status,
          duration: record.duration_ms
        }
      end)

    {_retry, last} = List.last(retries)

    test_case
    |> Map.put(:status, last.status)
    |> Map.put(:duration, test_case.duration + Enum.sum(Enum.map(repetitions, & &1.duration)))
    |> Map.put(
      :failures,
      Map.get(test_case, :failures, []) ++
        Enum.flat_map(retries, fn {_, record} -> record.failures end)
    )
    |> Map.put(:repetitions, [first | repetitions])
  end

  # The server knows two outcomes for a module, a suite or a run: anything
  # without a failure, an all-skipped module included, is a success.
  defp status_of(records) do
    if Enum.any?(records, &(&1.status == "failure")), do: "failure", else: "success"
  end

  def handle_info(_message, state), do: {:noreply, state}

  @doc false
  def record(%ExUnit.Test{} = test) do
    describe = test.tags[:describe]

    %{
      module: inspect(test.module),
      describe: describe,
      name: display_name(test, describe),
      status: status(test.state),
      duration_ms: microseconds_to_milliseconds(test.time),
      failures: failures(test.state, test.tags[:file]),
      is_quarantined: test.tags[:quarantined] == true
    }
  end

  @doc """
  A test as the server identifies it among the enumerated tests: the same
  module, suite and name its test case runs carry.
  """
  def identity(%ExUnit.Test{} = test) do
    describe = test.tags[:describe]
    %{module: inspect(test.module), suite: describe || "", name: display_name(test, describe)}
  end

  # ExUnit registers a test as "<type> <describe> <name>", for example
  # "test create_order/2 rejects an empty cart". The type says nothing and the
  # describe block is reported as the suite, so only the test's own name is
  # kept.
  defp display_name(test, describe) do
    type = test.tags[:test_type] || :test

    test.name
    |> Atom.to_string()
    |> String.replace_prefix("#{type} ", "")
    |> then(
      &if(describe in [nil, ""], do: &1, else: String.replace_prefix(&1, describe <> " ", ""))
    )
  end

  defp status(nil), do: "success"
  defp status({:failed, _}), do: "failure"
  defp status({:invalid, _}), do: "failure"
  defp status({:skipped, _}), do: "skipped"
  defp status(_), do: "success"

  defp failures({:failed, entries}, test_file),
    do: Enum.map(entries, &format_failure(&1, test_file))

  defp failures({:invalid, module}, _test_file), do: [invalid_failure(module)]
  defp failures(_, _test_file), do: []

  defp format_failure({kind, error, stacktrace}, test_file) do
    {path, line_number} = failure_location(stacktrace, test_file)

    failure(safe_format_banner(kind, error), path, line_number, issue_type(error))
  end

  defp invalid_failure(module),
    do: failure("Setup failed for #{inspect(module)}", nil, 0, "error_thrown")

  # A failure without a source location (a timeout, an exit, a failed
  # `setup_all`) has no path. The key is left out rather than sent as null,
  # which the server rejects along with the whole run.
  defp failure(message, nil, _line_number, issue_type),
    do: %{message: message, line_number: 0, issue_type: issue_type}

  defp failure(message, path, line_number, issue_type),
    do: %{message: message, path: path, line_number: line_number, issue_type: issue_type}

  defp issue_type(%ExUnit.AssertionError{}), do: "assertion_failure"
  defp issue_type(_), do: "error_thrown"

  defp safe_format_banner(kind, error) do
    Exception.format_banner(kind, error)
  rescue
    _ -> "#{kind}: #{inspect(error)}"
  end

  defp failure_location(stacktrace, test_file) do
    stacktrace
    |> Enum.find_value(fn
      {_module, _fun, _arity, meta} = _entry ->
        location = extract_location(meta)

        if location &&
             (test_file == nil or String.ends_with?(elem(location, 0), Path.basename(test_file))),
           do: location

      _ ->
        nil
    end)
    |> case do
      nil -> first_location(stacktrace)
      value -> value
    end
  end

  defp first_location(stacktrace) do
    Enum.find_value(stacktrace, {nil, 0}, fn
      {_module, _fun, _arity, meta} -> extract_location(meta)
      _ -> nil
    end)
  end

  defp extract_location(meta) when is_list(meta) do
    file = meta[:file]
    line = meta[:line]

    cond do
      is_list(file) and is_integer(line) -> {List.to_string(file), line}
      is_binary(file) and is_integer(line) -> {file, line}
      true -> nil
    end
  end

  defp extract_location(_), do: nil

  defp microseconds_to_milliseconds(nil), do: 0
  defp microseconds_to_milliseconds(us) when is_integer(us), do: div(us, 1_000)

  defp suite_duration_ms(times, monotonic_start_ns) do
    case times do
      %{run: run_us} when is_integer(run_us) ->
        div(run_us, 1_000)

      _ ->
        elapsed_ns = System.monotonic_time() - monotonic_start_ns
        System.convert_time_unit(elapsed_ns, :native, :millisecond)
    end
  end

  defp build_payload(tests, duration_ms, ran_at, opts) do
    modules = tests |> Enum.group_by(& &1.module) |> Enum.map(&build_module/1)
    environment = Keyword.get(opts, :environment, &System.get_env/1)

    %{
      id: Report.id(),
      contract_version: Contract.version(),
      build_system: "mix",
      duration: duration_ms,
      ran_at: DateTime.to_iso8601(ran_at),
      is_ci: Env.ci?(environment),
      status: status_of(modules),
      elixir_version: Env.elixir_version(),
      otp_version: Env.otp_version(),
      mix_env: Env.mix_env(),
      git_branch: Env.git_branch(environment),
      git_commit_sha: Env.git_commit_sha(environment),
      git_ref: Env.git_ref(environment),
      git_remote_url_origin: Env.git_remote_url_origin(environment),
      ci_provider: Env.ci_provider(environment),
      ci_run_id: Env.ci_run_id(environment),
      ci_project_handle: Env.ci_project_handle(environment),
      ci_host: Env.ci_host(environment),
      shard_plan_id: Keyword.get(opts, :shard_plan_id),
      shard_index: Keyword.get(opts, :shard_index),
      scheme: Keyword.get(opts, :scheme),
      custom_metadata: Metadata.collect(opts),
      test_modules: modules
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  defp build_module({module_name, tests}) do
    suites = build_suites(tests)
    cases = Enum.map(tests, &to_test_case/1)

    %{
      name: module_name,
      status: status_of(tests),
      duration: Enum.reduce(tests, 0, &(&1.duration_ms + &2)),
      test_suites: suites,
      test_cases: cases
    }
  end

  defp build_suites(tests) do
    tests
    |> Enum.reject(&(&1.describe in [nil, ""]))
    |> Enum.group_by(& &1.describe)
    |> Enum.map(fn {describe, described_tests} ->
      %{
        name: describe,
        status: status_of(described_tests),
        duration: Enum.reduce(described_tests, 0, &(&1.duration_ms + &2))
      }
    end)
  end

  defp to_test_case(record) do
    %{
      name: record.name,
      test_suite_name: record.describe,
      status: record.status,
      duration: record.duration_ms,
      is_quarantined: record.is_quarantined,
      failures: record.failures
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end
end
