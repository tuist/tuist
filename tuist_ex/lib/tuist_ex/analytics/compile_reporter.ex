defmodule TuistEx.Analytics.CompileReporter do
  @moduledoc false

  # Captures Mix compiler diagnostics for the current `mix compile` run and
  # submits a mix-builds payload when the run finishes. Diagnostics are
  # collected via the `after_compiler` hook of `Mix.Task.Compiler`; the
  # reporter is a process so the hooks and the machine sampler have somewhere
  # to send what they see while the compilers run.

  use GenServer

  alias TuistEx.Analytics.Contract
  alias TuistEx.Analytics.Env
  alias TuistEx.Analytics.HTTP
  alias TuistEx.Analytics.Isolated
  alias TuistEx.Analytics.MachineMetrics
  alias TuistEx.Analytics.Metadata
  alias TuistEx.Analytics.Report

  # Long enough for the stored login to be refreshed under its lock and the
  # report sent.
  @submit_timeout 60_000

  @doc """
  Starts a reporter for one build. It is not registered under a name: the
  caller holds on to it and passes it to `record/3` and `finish/3`, so any
  number of builds, or tests, can each have their own.
  """
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)

  @doc """
  Starts a reporter that is not linked to the caller, so nothing that goes
  wrong while reporting can take the build down with it. It stops when the
  caller does.
  """
  def start(opts \\ []), do: GenServer.start(__MODULE__, Keyword.put(opts, :owner, self()))

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  @doc "Records what a Mix compiler returned."
  def record(reporter, compiler, {status, diagnostics}) do
    GenServer.cast(reporter, {:record, compiler, status, diagnostics})
  end

  @doc "Marks the build as finished, submits it, and stops the reporter."
  def finish(reporter, files \\ [], steps \\ []) do
    request = :gen_server.send_request(reporter, {:finish, files, steps})

    # Waits a little longer than the submission may take. A reporter that
    # stopped, or never answers, costs the report, never the build.
    case :gen_server.receive_response(request, @submit_timeout + 5_000) do
      {:reply, :ok} ->
        :ok

      _ ->
        Process.unlink(reporter)
        Process.exit(reporter, :kill)
        :ok
    end
  end

  @impl true
  def init(opts) do
    parent = self()
    if owner = Keyword.get(opts, :owner), do: Process.monitor(owner)
    sampler_opts = Keyword.get(opts, :sampler_opts, [])

    sampler_pid =
      case Keyword.get(opts, :sampler, :auto) do
        :auto ->
          case MachineMetrics.start_link(Keyword.merge([sink: parent], sampler_opts)) do
            {:ok, pid} -> pid
            _ -> nil
          end

        nil ->
          nil

        pid when is_pid(pid) ->
          pid
      end

    {:ok,
     %{
       diagnostics: [],
       statuses: [],
       machine_metrics: [],
       files: [],
       steps: [],
       started_at: DateTime.utc_now(),
       monotonic_start_ns: System.monotonic_time(),
       sampler_pid: sampler_pid,
       opts: opts,
       submit: Keyword.get(opts, :submit, &HTTP.submit_mix_build/2),
       shell: Keyword.get(opts, :shell, &Report.debug/1)
     }}
  end

  @impl true
  def handle_cast({:record, compiler, status, diagnostics}, state) do
    normalized =
      diagnostics
      |> List.wrap()
      |> Enum.map(&normalize_diagnostic(&1, compiler))

    {:noreply,
     %{
       state
       | statuses: [status | state.statuses],
         diagnostics: state.diagnostics ++ normalized
     }}
  end

  @impl true
  def handle_call({:finish, files, steps}, _from, state) do
    if state.sampler_pid, do: MachineMetrics.stop(state.sampler_pid)

    duration_ms =
      System.convert_time_unit(
        System.monotonic_time() - state.monotonic_start_ns,
        :native,
        :millisecond
      )

    if nothing_compiled?(state, files) do
      :ok
    else
      state = %{state | files: files, steps: steps}

      submission =
        Isolated.run(
          fn -> state.submit.(build_payload(state, duration_ms), state.opts) end,
          @submit_timeout
        )

      case submission do
        :ok ->
          :ok

        {:error, reason} ->
          state.shell.("tuist analytics: failed to submit compile run: #{inspect(reason)}")
      end
    end

    # One reporter per build: staying around would carry this build's
    # diagnostics, clock and options into the next compile in this process.
    {:stop, :normal, :ok, %{state | sampler_pid: nil}}
  end

  # What the server accepts in one build. A report over these is refused
  # whole, so an oversized build is trimmed to its most expensive parts
  # instead of being lost.
  @max_files 20_000
  @max_steps 50_000
  @max_diagnostics 5_000
  @max_machine_metrics 20_000
  @max_nested 5_000
  @max_name 1_024
  @max_message 10_000

  # The server refuses a body over 50 MB. The limits above bound each field,
  # not their sum, so a build that hits several of them is also trimmed as a
  # whole.
  @max_payload_bytes 40_000_000

  defp fit_files(files) do
    files = Enum.filter(files, &(String.length(&1.path) <= @max_name))

    # Only an oversized build is reordered: what is dropped is its fastest files.
    files =
      if length(files) > @max_files,
        do: files |> Enum.sort_by(&(-&1.compile_duration_ms)) |> Enum.take(@max_files),
        else: files

    Enum.map(files, fn file ->
      Enum.reduce([:modules, :waits, :dependencies], file, fn key, file ->
        if is_list(file[key]), do: Map.update!(file, key, &Enum.take(&1, @max_nested)), else: file
      end)
    end)
  end

  defp fit_steps(steps) when length(steps) <= @max_steps, do: steps
  defp fit_steps(steps), do: steps |> Enum.sort_by(&(-&1.duration_ms)) |> Enum.take(@max_steps)

  defp fit_diagnostic(diagnostic) do
    diagnostic
    |> Map.update(:message, "", &String.slice(&1, 0, @max_message))
    |> Map.update(:file, "", &String.slice(&1, 0, @max_name))
    |> Map.update(:module, "", &String.slice(&1, 0, @max_name))
  end

  # Keeps every nth sample, so a very long build still covers its whole span.
  defp thin(samples, max) when length(samples) <= max, do: samples
  defp thin(samples, max), do: Enum.take_every(samples, ceil(length(samples) / max))

  # Some compilers return :ok even when no files changed. The profile, not
  # those statuses, tells us whether an aliased compile did real work.
  # Failures still need reporting even when compilation produced no files.
  defp nothing_compiled?(state, files) do
    files == [] and :error not in state.statuses and
      not Enum.any?(state.diagnostics, &(&1.severity == "error"))
  end

  @impl true
  def handle_info({:machine_metric, sample}, state) do
    {:noreply, %{state | machine_metrics: [sample | state.machine_metrics]}}
  end

  # The build that started this reporter is gone without finishing it.
  def handle_info({:DOWN, _ref, :process, _owner, _reason}, state) do
    if state.sampler_pid, do: MachineMetrics.stop(state.sampler_pid)
    {:stop, :normal, %{state | sampler_pid: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp normalize_diagnostic(diagnostic, compiler) when is_map(diagnostic) do
    {line, column} = position(diagnostic)

    %{
      severity: severity(diagnostic),
      file: file(diagnostic),
      module: module_name(diagnostic),
      message: message(diagnostic),
      line: line,
      column: column,
      compiler: compiler_name(diagnostic, compiler)
    }
  end

  # Diagnostics an umbrella returns carry the compiler that produced them.
  defp compiler_name(%{compiler_name: name}, _compiler) when is_binary(name),
    do: String.downcase(name)

  defp compiler_name(_diagnostic, compiler), do: Atom.to_string(compiler)

  defp severity(diagnostic) do
    case Map.get(diagnostic, :severity) do
      :error -> "error"
      "error" -> "error"
      _ -> "warning"
    end
  end

  # Relative, like the compiled files: an absolute path says where the
  # checkout is, which is nobody's business.
  defp file(%{file: file}) when is_binary(file), do: Path.relative_to_cwd(file)
  defp file(_diagnostic), do: ""

  defp message(%{message: message}) when is_binary(message) or is_list(message),
    do: IO.chardata_to_string(message)

  defp message(_diagnostic), do: ""

  # The module the diagnostic was raised in, when its stacktrace says.
  defp module_name(%{stacktrace: [{module, _function, _arity, _location} | _]})
       when is_atom(module), do: inspect(module)

  defp module_name(_diagnostic), do: ""

  defp position(%{position: {line, column}})
       when is_integer(line) and line >= 0 and is_integer(column) and column >= 0,
       do: {line, column}

  defp position(%{position: line}) when is_integer(line) and line >= 0, do: {line, nil}
  defp position(_diagnostic), do: {nil, nil}

  defp build_payload(state, duration_ms) do
    environment = Keyword.get(state.opts, :environment, &System.get_env/1)

    status =
      cond do
        Enum.any?(state.statuses, &(&1 == :error)) -> "failure"
        Enum.any?(state.diagnostics, &(&1.severity == "error")) -> "failure"
        true -> "success"
      end

    %{
      id: Report.id(),
      contract_version: Contract.version(),
      duration_ms: duration_ms,
      status: status,
      is_ci: Env.ci?(environment),
      started_at: DateTime.to_iso8601(state.started_at),
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
      custom_metadata: Metadata.collect(state.opts),
      machine_metrics: state.machine_metrics |> Enum.reverse() |> thin(@max_machine_metrics),
      diagnostics:
        state.diagnostics |> Enum.take(@max_diagnostics) |> Enum.map(&fit_diagnostic/1),
      files: fit_files(state.files),
      steps: fit_steps(state.steps)
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
    |> fit_payload(Keyword.get(state.opts, :max_payload_bytes, @max_payload_bytes))
  end

  @trimmable [:files, :steps, :machine_metrics, :diagnostics]

  # Halves the longest list until the report fits, keeping the slowest files.
  defp fit_payload(payload, max_bytes) do
    largest = Enum.max_by(@trimmable, &length(Map.get(payload, &1, [])))
    entries = Map.get(payload, largest, [])

    if entries == [] or byte_size(JSON.encode!(payload)) <= max_bytes do
      payload
    else
      entries =
        if largest == :files, do: Enum.sort_by(entries, &(-&1.compile_duration_ms)), else: entries

      fit_payload(
        Map.put(payload, largest, Enum.take(entries, div(length(entries), 2))),
        max_bytes
      )
    end
  end
end
