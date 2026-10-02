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
  #   * `:defer` keeps the run for the caller, which fetches it with
  #     `take_deferred/0`. `mix tuist.test` uses it when it may retry failed
  #     tests, so the run is sent once, with the retries in it.
  #   * `{:collect, path}` writes the test outcomes to a file and sends
  #     nothing. The process retrying failed tests runs in this mode and the
  #     parent reads the file.
  use GenServer

  alias TuistEx.Analytics.Contract
  alias TuistEx.Analytics.Env
  alias TuistEx.Analytics.HTTP
  alias TuistEx.Analytics.Metadata

  @deferred :deferred_test_run

  def init(opts) do
    opts = Keyword.new(opts)

    # The options the Mix task set apply to the formatter ExUnit starts for
    # the run. A caller that brings its own `:submit` is driving a formatter
    # of its own, typically a test of this module, possibly inside a suite
    # that is itself reported, and gets exactly the options it passed.
    analytics_opts =
      if Keyword.has_key?(opts, :submit),
        do: [],
        else: Application.get_env(:tuist_ex, :analytics_options, [])

    merged = Keyword.merge(analytics_opts, opts)

    {:ok,
     %{
       tests: [],
       aborted?: false,
       monotonic_start_ns: System.monotonic_time(),
       ran_at: DateTime.utc_now(),
       opts: merged,
       shell: Keyword.get(merged, :shell, &default_shell/1)
     }}
  end

  def handle_cast({:suite_started, _opts}, state) do
    {:noreply, %{state | monotonic_start_ns: System.monotonic_time(), ran_at: DateTime.utc_now()}}
  end

  def handle_cast({:test_finished, test}, state) do
    {:noreply, %{state | tests: [record(test) | state.tests]}}
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
        # of its own, so both modes add to what the earlier suites left.
        {:collect, path} ->
          File.write!(path, :erlang.term_to_binary(read_collected(path) ++ tests))

        :defer ->
          payload = build_payload(tests, duration_ms, state.ran_at, state.opts)
          deferred = Application.get_env(:tuist_ex, @deferred, [])

          Application.put_env(
            :tuist_ex,
            @deferred,
            deferred ++ [{payload, state.opts, state.aborted?}]
          )

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

  @doc """
  Sends a test run. A failure is reported through the shell and never raised.
  """
  def submit(payload, opts) do
    submit = Keyword.get(opts, :submit, &HTTP.submit_test_run/2)
    shell = Keyword.get(opts, :shell, &default_shell/1)

    case submit.(payload, opts) do
      :ok -> :ok
      {:error, reason} -> shell.("tuist analytics: failed to submit test run: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Returns the runs kept by `:defer` mode, one `{payload, opts, aborted?}` per
  suite that ran (an umbrella runs one per application), and forgets them.
  `aborted?` says the suite stopped before running every test.
  """
  def take_deferred do
    deferred = Application.get_env(:tuist_ex, @deferred, [])
    Application.delete_env(:tuist_ex, @deferred)
    deferred
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

    payload = %{payload | test_modules: modules, status: aggregate_status(modules)}

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

  defp status_of(cases),
    do: if(Enum.any?(cases, &(&1.status == "failure")), do: "failure", else: "success")

  # Phoenix's HTTP stack (used by the pluggable submit function) sends a few
  # informational messages back to the caller process. Swallow them so tests
  # and real runs don't fill the log with "unexpected message" warnings.
  def handle_info(_message, state), do: {:noreply, state}

  # `Kernel.function_exported?` on private helpers is a formatting convention
  # helper; expose the mapping publicly for tests.
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
  defp status({:excluded, _}), do: "skipped"
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

  defp first_location([]), do: {nil, 0}

  defp first_location([{_module, _fun, _arity, meta} | rest]) do
    case extract_location(meta) do
      nil -> first_location(rest)
      value -> value
    end
  end

  defp first_location([_ | rest]), do: first_location(rest)

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
      id: uuidv4(),
      contract_version: Contract.version(),
      build_system: "mix",
      duration: duration_ms,
      ran_at: DateTime.to_iso8601(ran_at),
      is_ci: Env.ci?(environment),
      status: aggregate_status(modules),
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
      status: aggregate_module_status(tests),
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
        status: aggregate_module_status(described_tests),
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

  # The server schema only allows success/failure for a module: an
  # all-skipped module is reported as success so the run isn't rejected.
  defp aggregate_module_status(tests) do
    if Enum.any?(tests, &(&1.status == "failure")), do: "failure", else: "success"
  end

  defp aggregate_status(modules) do
    cond do
      Enum.any?(modules, &(&1.status == "failure")) -> "failure"
      Enum.all?(modules, &(&1.status == "success")) and modules != [] -> "success"
      true -> "success"
    end
  end

  defp uuidv4 do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c = Bitwise.bor(Bitwise.band(c, 0x0FFF), 0x4000)
    d = Bitwise.bor(Bitwise.band(d, 0x3FFF), 0x8000)

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    |> IO.iodata_to_binary()
  end

  defp default_shell(message) do
    if System.get_env("TUIST_DEBUG") == "1" do
      IO.puts(:stderr, message)
    end

    :ok
  end
end
