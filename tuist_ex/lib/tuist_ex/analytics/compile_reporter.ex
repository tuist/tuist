defmodule TuistEx.Analytics.CompileReporter do
  @moduledoc false

  # Captures Mix compiler diagnostics for the current `mix compile` run and
  # submits a mix-builds payload when the run finishes. Diagnostics are
  # collected via the `after_compiler` hook of `Mix.Task.Compiler`; the
  # reporter is a GenServer only so the hook has a durable inbox even when
  # multiple compilers run.

  use GenServer

  alias TuistEx.Analytics.Contract
  alias TuistEx.Analytics.Env
  alias TuistEx.Analytics.HTTP
  alias TuistEx.Analytics.MachineMetrics
  alias TuistEx.Analytics.Metadata

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @doc "Records diagnostics returned by a Mix compiler."
  def record(compiler, {status, diagnostics}) do
    GenServer.cast(__MODULE__, {:record, compiler, status, diagnostics})
  end

  @doc "Marks the compile as finished and submits the build payload."
  def finish do
    GenServer.call(__MODULE__, :finish, 60_000)
  end

  @impl true
  def init(opts) do
    parent = self()
    sampler_opts = Keyword.get(opts, :sampler_opts, [])

    sampler_pid =
      case Keyword.get(opts, :sampler, :auto) do
        :auto ->
          case MachineMetrics.start_link(
                 Keyword.merge([sink: {parent, :machine_metric}], sampler_opts)
               ) do
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
       started_at: DateTime.utc_now(),
       monotonic_start_ns: System.monotonic_time(),
       sampler_pid: sampler_pid,
       opts: opts,
       submit: Keyword.get(opts, :submit, &HTTP.submit_mix_build/2),
       shell: Keyword.get(opts, :shell, &default_shell/1)
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
  def handle_call(:finish, _from, state) do
    if state.sampler_pid, do: MachineMetrics.stop(state.sampler_pid)

    duration_ms =
      System.convert_time_unit(
        System.monotonic_time() - state.monotonic_start_ns,
        :native,
        :millisecond
      )

    payload = build_payload(state, duration_ms)

    case state.submit.(payload, state.opts) do
      :ok ->
        :ok

      {:error, reason} ->
        state.shell.("tuist analytics: failed to submit compile run: #{inspect(reason)}")
    end

    {:reply, :ok, %{state | sampler_pid: nil}}
  end

  @impl true
  def handle_info({:machine_metric, sample}, state) do
    {:noreply, %{state | machine_metrics: [sample | state.machine_metrics]}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp normalize_diagnostic(%{__struct__: _} = diagnostic, compiler) do
    %{
      severity: severity(diagnostic),
      file: string(diagnostic, :file),
      module: module_name(diagnostic),
      message: string(diagnostic, :message),
      line: integer(diagnostic, [:position, :line]),
      column: integer(diagnostic, [:position, :column]),
      compiler: Atom.to_string(compiler)
    }
  end

  defp normalize_diagnostic(diagnostic, compiler) when is_map(diagnostic) do
    %{
      severity: severity(diagnostic),
      file: string(diagnostic, :file),
      module: module_name(diagnostic),
      message: string(diagnostic, :message),
      line: integer(diagnostic, [:position, :line]),
      column: integer(diagnostic, [:position, :column]),
      compiler: Atom.to_string(compiler)
    }
  end

  defp severity(diagnostic) do
    case Map.get(diagnostic, :severity) do
      :error -> "error"
      "error" -> "error"
      _ -> "warning"
    end
  end

  defp string(diagnostic, key) do
    case Map.get(diagnostic, key) do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp module_name(diagnostic) do
    case Map.get(diagnostic, :source) do
      value when is_atom(value) and not is_nil(value) -> inspect(value)
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp integer(diagnostic, [key]) do
    case Map.get(diagnostic, key) do
      n when is_integer(n) and n >= 0 -> n
      {line, _} when is_integer(line) and line >= 0 -> line
      _ -> nil
    end
  end

  defp integer(diagnostic, [:position, :line]) do
    case Map.get(diagnostic, :position) do
      n when is_integer(n) and n >= 0 -> n
      {line, _} when is_integer(line) and line >= 0 -> line
      _ -> nil
    end
  end

  defp integer(diagnostic, [:position, :column]) do
    case Map.get(diagnostic, :position) do
      {_, column} when is_integer(column) and column >= 0 -> column
      _ -> nil
    end
  end

  defp build_payload(state, duration_ms) do
    environment = Keyword.get(state.opts, :environment, &System.get_env/1)
    status =
      cond do
        Enum.any?(state.statuses, &(&1 == :error)) -> "failure"
        Enum.any?(state.diagnostics, &(&1.severity == "error")) -> "failure"
        true -> "success"
      end

    %{
      id: uuidv4(),
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
      machine_metrics: Enum.reverse(state.machine_metrics),
      diagnostics: state.diagnostics
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  defp uuidv4 do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c = Bitwise.bor(Bitwise.band(c, 0x0FFF), 0x4000)
    d = Bitwise.bor(Bitwise.band(d, 0x3FFF), 0x8000)

    "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b"
    |> :io_lib.format([a, b, c, d, e])
    |> IO.iodata_to_binary()
  end

  defp default_shell(message) do
    if System.get_env("TUIST_DEBUG") == "1" do
      IO.puts(:stderr, message)
    end

    :ok
  end
end
