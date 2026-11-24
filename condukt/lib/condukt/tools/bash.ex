defmodule Condukt.Tools.Bash do
  @moduledoc """
  Tool for executing bash commands.

  Routes through the active `Condukt.Sandbox`. With `Sandbox.Local` this
  spawns a real bash subprocess on the host; with `Sandbox.Virtual` it runs
  inside the in-memory bashkit interpreter with no host process spawning; with
  `Sandbox.Microsandbox` it executes inside the guest microVM; with
  `Sandbox.Kubernetes`, inside the session's pod.

  Output that is too long keeps its first and last lines, up to 2000 lines
  or 50KB in all, since a command's start says what it ran and its end how it
  finished.

  ## Parameters

  - `command` - The bash command to execute
  - `cwd` - Directory to run the command in (optional, relative to the sandbox's cwd)
  - `timeout` - Timeout in seconds (optional, default: 120)

  ## Long-running commands

  In a session, on a sandbox that implements `c:Condukt.Sandbox.start_process/4`,
  as `Local`, `Kubernetes`, and `Microsandbox` do, a command runs as a sandbox
  process named by `process_id/2` from the session id and the tool call id,
  apart from the call that started it:

    * Its output streams as it arrives, as
      `{:tool_output, tool_call_id, chunk}` events to stream subscribers and
      the notifier, and into the tool's `output` in the session's view. See
      `Condukt.Tool.output/2`.
    * A command still running after `:park_after` milliseconds (default
      `10_000`) parks the call until it exits, as `Condukt.Park` describes, so
      the call holds no process and the session's tool timeout does not cut
      off a long build. Only the command's own `timeout` does.
    * Aborting the turn kills the command, in the foreground or parked.
      Draining the session for another node (`Condukt.Sessions.stop/2` with
      `drain: true`) leaves it running.
    * A sandbox that implements `c:Condukt.Sandbox.watch_process/3` is asked
      to report the exit itself when the call parks, so the call wakes even
      when the node that ran its watcher restarted.
    * A call that runs again with the same session and tool call ids, such as
      one a restarted session retries, finds the command by its id and
      follows it instead of starting it twice. On `Kubernetes` the command
      runs in the pod, so it survives the BEAM node restarting.

  Options, as `{Condukt.Tools.Bash, park_after: 30_000}`:

    * `:park_after` - milliseconds a command runs in the foreground before the
      call parks
    * `:replay_safe` - `true` declares calls replay-safe (see the Sessions
      and Persistence guide), so a resumed run reruns an interrupted call,
      which then follows the command it started. Set it only on a sandbox
      whose processes outlive the session's node. Defaults to `false`.

  Elsewhere, such as on `Virtual`, or when the tool runs outside a session,
  the call runs the command with `c:Condukt.Sandbox.exec/3` and returns when it
  ends.
  """

  use Condukt.Tool

  alias Condukt.{Sandbox, Secrets}
  alias Condukt.Tools.Bash.{Exited, Watcher}

  @max_lines 2000
  @max_bytes 50 * 1024
  @head_lines 200
  @head_bytes 10 * 1024
  @default_timeout 120_000
  @park_after 10_000
  # How long past its own timeout a parked call waits for the sandbox to
  # report a command it killed, before it wakes and looks itself.
  @timeout_grace 30_000

  @impl true
  def name(opts), do: Keyword.get(opts, :name, "Bash")

  # A rerun follows the command its interrupted call started instead of
  # starting it twice, but only on a sandbox whose processes outlive the
  # node, such as `Kubernetes` or a host's remote sandbox. The host that
  # knows its sandbox opts in with `{Condukt.Tools.Bash, replay_safe: true}`.
  @impl true
  def replay_safe?(opts), do: Keyword.get(opts, :replay_safe, false)

  @impl true
  def description(_opts) do
    """
    Execute a bash command in the current working directory. Returns combined stdout/stderr.
    Long output keeps its first and last lines, up to #{@max_lines} lines or #{div(@max_bytes, 1024)}KB.
    Optionally provide a cwd and timeout in seconds; raise the timeout for long builds and test runs.
    """
    |> String.trim()
  end

  @impl true
  def parameters(_opts) do
    %{
      type: "object",
      properties: %{
        command: %{
          type: "string",
          description: "Bash command to execute"
        },
        cwd: %{
          type: "string",
          description: "Directory to run the command in (relative or absolute)"
        },
        timeout: %{
          type: "number",
          description: "Timeout in seconds (optional, default: #{div(@default_timeout, 1000)})"
        }
      },
      required: ["command"]
    }
  end

  @doc """
  The id of the sandbox process that runs a call's command.

  A host that needs the process after the session is gone, such as to stop
  it, finds it with `Condukt.Sandbox.read_process/4` and
  `Condukt.Sandbox.stop_process/2` under this id.
  """
  def process_id(session_id, tool_call_id) when is_binary(session_id) and is_binary(tool_call_id),
    do: "condukt-bash:" <> session_id <> ":" <> tool_call_id

  @impl true
  def call(%{"command" => command} = args, context) do
    sandbox = fetch_sandbox!(context)
    timeout = trunc((args["timeout"] || div(@default_timeout, 1000)) * 1000)

    exec_opts =
      []
      |> put_if_present(:cwd, args["cwd"])
      |> put_if_present(:env, Secrets.env(context[:secrets]))
      |> Keyword.put(:timeout, timeout)

    if detached?(sandbox, context) do
      start(sandbox, command, exec_opts, timeout, context)
    else
      exec(sandbox, command, exec_opts, timeout)
    end
  end

  @impl true
  def wake(_event, state, context) do
    stop_watcher(state.watcher)
    resume(fetch_sandbox!(context), state, context)
  end

  @impl true
  def cancel(state, context) do
    stop_watcher(state.watcher)
    Sandbox.stop_process(fetch_sandbox!(context), state.id)
  end

  defp detached?(sandbox, context) do
    Sandbox.processes?(sandbox) and is_binary(context[:session_id]) and is_binary(context[:tool_call_id]) and
      is_pid(context[:agent]) and is_reference(context[:turn_ref])
  end

  defp exec(sandbox, command, exec_opts, timeout) do
    case Sandbox.exec(sandbox, command, exec_opts) do
      {:ok, %{output: output, exit_code: exit_code}} ->
        {:ok, format(bound(output, output, byte_size(output)), {:exited, exit_code})}

      {:error, :timeout} ->
        {:error, "Command timed out after #{div(timeout, 1000)} seconds"}

      {:error, reason} ->
        {:error, "Command failed: #{inspect(reason)}"}
    end
  end

  # Starts the command, or finds it when an earlier attempt of this call
  # started it, and follows it in the foreground until it ends or
  # `:park_after` passes, then parks.
  defp start(sandbox, command, exec_opts, timeout, context) do
    id = process_id(context.session_id, context.tool_call_id)
    deadline = System.os_time(:millisecond) + timeout

    # The watcher starts the command, so a call aborted while it starts
    # still has it stopped, once it has started.
    {:ok, watcher} = Watcher.start(sandbox, id, command, exec_opts, context)

    case Watcher.await_start(watcher) do
      started when started in [:ok, {:error, :already_started}] ->
        follow(sandbox, %{id: id, timeout: timeout, deadline: deadline, watcher: watcher, attempt: 1}, context)

      # A wrapper such as `Sandbox.Lazy` whose sandbox runs no processes.
      {:error, :not_supported} ->
        exec(sandbox, command, exec_opts, timeout)

      {:error, reason} ->
        {:error, "Command failed: #{inspect(reason)}"}
    end
  end

  defp follow(sandbox, state, context) do
    watcher = state.watcher
    monitor = Process.monitor(watcher)
    park_after = Keyword.get(context[:opts] || [], :park_after, @park_after)

    receive do
      {Watcher, ^watcher, _status} ->
        Process.demonitor(monitor, [:flush])
        resume(sandbox, state, context)

      {:DOWN, ^monitor, :process, _pid, _reason} ->
        resume(sandbox, state, context)
    after
      park_after ->
        Process.demonitor(monitor, [:flush])
        key = signal_key(context, state.attempt)

        case Watcher.park(watcher, key) do
          :ok -> park(sandbox, state, key, context)
          {:done, _status} -> resume(sandbox, state, context)
        end
    end
  end

  # Whatever reported the command done, the sandbox holds the truth. One
  # still running before its deadline was lost by its watcher, or the call
  # was woken by a signal from elsewhere: follow it again while parked, under
  # a new key, since a wake uses up its keys. So is one the sandbox could not
  # be read for, as while its node restarts: the command goes on there.
  defp resume(sandbox, state, context) do
    before_deadline? = System.os_time(:millisecond) < state.deadline

    case Sandbox.read_process(sandbox, state.id, 0, max_bytes: 0) do
      {:ok, %{status: :running, size: size}} when before_deadline? -> repark(sandbox, state, size, context)
      {:error, reason} when reason != :not_found and before_deadline? -> repark(sandbox, state, nil, context)
      _finished_overdue_or_gone -> finish(sandbox, state.id, state.timeout)
    end
  end

  defp repark(sandbox, state, offset, context) do
    attempt = state.attempt + 1
    key = signal_key(context, attempt)
    {:ok, watcher} = Watcher.start_parked(sandbox, state.id, offset, context, key)
    park(sandbox, %{state | watcher: watcher, attempt: attempt}, key, context)
  end

  # The watcher delivers the exit while this node runs. A sandbox that
  # watches processes itself delivers it too, which wakes the call after a
  # deploy restarted the node; whichever comes second finds the key used.
  defp park(sandbox, state, key, context) do
    _ = Sandbox.watch_process(sandbox, state.id, %{session_id: context.session_id, signal: Exited, key: key})
    {:park, state, signals: [{Exited, key}], until: DateTime.from_unix!(state.deadline + @timeout_grace, :millisecond)}
  end

  defp signal_key(context, 1), do: "bash:" <> context.tool_call_id
  defp signal_key(context, attempt), do: "bash:#{context.tool_call_id}:#{attempt}"

  defp stop_watcher(watcher) when is_pid(watcher), do: Process.exit(watcher, :kill)
  defp stop_watcher(_watcher), do: :ok

  # Reads the result from the sandbox, which holds the truth whatever woke
  # the call, and releases the process. A command still running here is
  # overdue, and stopping it kills it. One that could not be read is left
  # alone: it may still be running, and its own timeout ends it.
  defp finish(sandbox, id, timeout) do
    result =
      with {:ok, %{status: status, size: size}} <- Sandbox.read_process(sandbox, id, 0, max_bytes: 0),
           {:ok, output} <- read_bounded(sandbox, id, size) do
        {status, output}
      end

    if not match?({:error, reason} when reason != :not_found, result), do: Sandbox.stop_process(sandbox, id)

    case result do
      {:error, :not_found} ->
        {:error, "Command was stopped before it finished"}

      {:error, reason} ->
        {:error, "Command failed: #{inspect(reason)}"}

      {status, output} when status in [:running, :timeout] ->
        {:error, join(["Command timed out after #{div(timeout, 1000)} seconds", output])}

      {status, output} ->
        {:ok, format(output, status)}
    end
  end

  defp read_bounded(sandbox, id, size) when size <= @max_bytes do
    with {:ok, output} <- read_range(sandbox, id, 0, size), do: {:ok, bound(output, output, size)}
  end

  defp read_bounded(sandbox, id, size) do
    tail_bytes = @max_bytes - @head_bytes

    with {:ok, head} <- read_range(sandbox, id, 0, @head_bytes),
         {:ok, tail} <- read_range(sandbox, id, size - tail_bytes, tail_bytes) do
      {:ok, bound(head, tail, size)}
    end
  end

  defp read_range(_sandbox, _id, _offset, 0), do: {:ok, ""}

  defp read_range(sandbox, id, offset, bytes) do
    with {:ok, %{output: output}} <- Sandbox.read_process(sandbox, id, offset, max_bytes: bytes), do: {:ok, output}
  end

  defp format(output, {:exited, exit_code}) do
    join([
      output,
      exit_code == nil && "(exit code unknown: the process ended without reporting one)",
      (is_integer(exit_code) and exit_code != 0) && "(exit code: #{exit_code})"
    ])
  end

  defp join(parts), do: parts |> Enum.reject(&(&1 in [false, nil, ""])) |> Enum.join("\n\n")

  defp fetch_sandbox!(%{sandbox: %Sandbox{} = sandbox}), do: sandbox

  defp fetch_sandbox!(_) do
    raise ArgumentError,
          "Condukt.Tools.Bash requires context.sandbox. " <>
            "When invoking the tool outside a Session, build one with " <>
            "Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: \"...\")."
  end

  defp put_if_present(opts, _key, nil), do: opts
  defp put_if_present(opts, key, value), do: Keyword.put(opts, key, value)

  # `head` starts the output and `tail` ends it, and `size` is its length;
  # both are the whole output when it was read in one piece. Output within
  # the limits comes back whole; longer output keeps its first lines and its
  # last, cut at line ends, with what lies between counted.
  defp bound(head, tail, size) do
    if size <= @max_bytes and line_count(head) <= @max_lines do
      head
    else
      head = take_head(head, @head_lines, @head_bytes)
      tail = take_tail(tail, @max_lines - @head_lines, @max_bytes - @head_bytes)
      omitted = size - byte_size(head) - byte_size(tail)

      head <> "\n... (#{omitted} bytes of output truncated) ...\n\n" <> tail
    end
  end

  defp line_count(output), do: length(:binary.matches(output, "\n")) + 1

  defp take_head(output, max_lines, max_bytes) do
    output =
      if byte_size(output) > max_bytes do
        part = binary_part(output, 0, max_bytes)

        case :binary.matches(part, "\n") do
          [] -> trim_partial_char(part)
          matches -> binary_part(part, 0, elem(List.last(matches), 0) + 1)
        end
      else
        output
      end

    case Enum.at(:binary.matches(output, "\n"), max_lines - 1) do
      nil -> output
      {position, 1} -> binary_part(output, 0, position + 1)
    end
  end

  defp take_tail(output, max_lines, max_bytes) do
    output =
      if byte_size(output) > max_bytes do
        part = binary_part(output, byte_size(output) - max_bytes, max_bytes)

        case :binary.match(part, "\n") do
          :nomatch -> drop_continuation_bytes(part)
          {position, 1} -> binary_part(part, position + 1, byte_size(part) - position - 1)
        end
      else
        output
      end

    # The last `max_lines` lines start after the newline before them; a final
    # newline ends the last line rather than starting another.
    newlines = :binary.matches(output, "\n")
    before = if String.ends_with?(output, "\n"), do: max_lines + 1, else: max_lines

    if length(newlines) >= before do
      {position, 1} = Enum.at(newlines, -before)
      binary_part(output, position + 1, byte_size(output) - position - 1)
    else
      output
    end
  end

  # A cut inside a line can split a UTF-8 character; drop its pieces, at most
  # three bytes, and leave output that is not text as it is.
  defp trim_partial_char(binary) do
    Enum.find(0..3, 0, fn drop ->
      drop < byte_size(binary) and String.valid?(binary_part(binary, 0, byte_size(binary) - drop))
    end)
    |> then(&binary_part(binary, 0, byte_size(binary) - &1))
  end

  defp drop_continuation_bytes(<<0b10::2, _::6, rest::binary>>), do: drop_continuation_bytes(rest)
  defp drop_continuation_bytes(binary), do: binary
end
