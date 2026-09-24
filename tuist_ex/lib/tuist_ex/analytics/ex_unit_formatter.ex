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
  use GenServer

  alias TuistEx.Analytics.Contract
  alias TuistEx.Analytics.Env
  alias TuistEx.Analytics.HTTP

  def init(opts) do
    analytics_opts = Application.get_env(:tuist_ex, :analytics_options, [])
    merged = Keyword.merge(analytics_opts, Keyword.new(opts))

    {:ok,
     %{
       tests: [],
       monotonic_start_ns: System.monotonic_time(),
       ran_at: DateTime.utc_now(),
       opts: merged,
       submit: Keyword.get(merged, :submit, &HTTP.submit_test_run/2),
       shell: Keyword.get(merged, :shell, &default_shell/1)
     }}
  end

  def handle_cast({:suite_started, _opts}, state) do
    {:noreply, %{state | monotonic_start_ns: System.monotonic_time(), ran_at: DateTime.utc_now()}}
  end

  def handle_cast({:test_finished, test}, state) do
    {:noreply, %{state | tests: [record(test) | state.tests]}}
  end

  def handle_cast({:suite_finished, times}, state) do
    duration_ms = suite_duration_ms(times, state.monotonic_start_ns)

    try do
      payload = build_payload(Enum.reverse(state.tests), duration_ms, state.ran_at)

      case state.submit.(payload, state.opts) do
        :ok ->
          :ok

        {:error, reason} ->
          state.shell.("tuist analytics: failed to submit test run: #{inspect(reason)}")
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
      name: Atom.to_string(test.name),
      status: status(test.state),
      duration_ms: microseconds_to_milliseconds(test.time),
      failures: failures(test.state, test.tags[:file]),
      is_quarantined: test.tags[:quarantined] == true
    }
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

    %{
      message: safe_format_banner(kind, error),
      path: path,
      line_number: line_number,
      issue_type: issue_type(error)
    }
  end

  defp invalid_failure(module) do
    %{
      message: "Setup failed for #{inspect(module)}",
      path: nil,
      line_number: 0,
      issue_type: "error_thrown"
    }
  end

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

  defp build_payload(tests, duration_ms, ran_at) do
    modules = tests |> Enum.group_by(& &1.module) |> Enum.map(&build_module/1)

    %{
      id: uuidv4(),
      contract_version: Contract.version(),
      build_system: "mix",
      duration: duration_ms,
      ran_at: DateTime.to_iso8601(ran_at),
      is_ci: Env.ci?(),
      status: aggregate_status(modules),
      elixir_version: Env.elixir_version(),
      otp_version: Env.otp_version(),
      mix_env: Env.mix_env(),
      git_branch: Env.git_branch(),
      git_commit_sha: Env.git_commit_sha(),
      git_ref: Env.git_ref(),
      git_remote_url_origin: Env.git_remote_url_origin(),
      ci_provider: Env.ci_provider(),
      ci_run_id: Env.ci_run_id(),
      ci_project_handle: Env.ci_project_handle(),
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
