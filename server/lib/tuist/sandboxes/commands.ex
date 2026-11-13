defmodule Tuist.Sandboxes.Commands do
  @moduledoc """
  Commands that outlive one request, in the shape other sandbox providers
  use: start returns an ID at once, then the caller streams or polls the
  output, writes to stdin, lists, waits for and cancels its commands.

  The command runs detached in the guest, in a session of its own (`setsid`
  through perl, present on both guest images), so the node's exec fence does
  not kill it when the starting exec returns. Its output, stdin, pid and exit
  code live in a directory under the guest's `$HOME`; a `sandbox_commands`
  row records what was started and how it ended (never its environment).

  While any command runs, the sandbox holds the shared `commands` residency
  (and, on macOS, the host hold of the same name), so idle pauses, capacity
  reclaim and host idle eviction leave it alone. Commands share it, so a
  sandbox runs several at once; an agent turn holding the sandbox refuses
  them with `:busy`. The residency ends when the last command does, except
  on macOS: there it is the session's lease and lasts until the sandbox has
  been idle for ten minutes (`end_lease/1`), with the host hold
  set to expire a little later in case the server never ends it. An agent
  thinks between commands for longer than the host's idle eviction, and a
  checkpointed VM can only come back on its own Mac, so without the lease
  most commands waited for that Mac to leave CI. The lease holds the VM's
  CI slot and the account's quota; `Sandboxes.pause/1` gives both back at
  once. A sandbox the account API creates or resumes takes it too (`keep/1`).
  `Tuist.Sandboxes.Workers.CommandWatchWorker` enforces each timeout and
  records commands nobody reads again.
  """

  import Bitwise
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxCommand
  alias Tuist.Sandboxes.Workers.CommandWatchWorker
  alias Tuist.Sandboxes.Workers.EndLeaseWorker

  @residency "commands"
  @lease_seconds 600
  @host_hold_slack_seconds 120
  @host_wait_ms 25_000
  @host_poll_ms 1_000
  @default_timeout_ms to_timeout(hour: 1)
  @max_timeout_ms to_timeout(hour: 6)
  @max_wait_seconds 50
  @chunk_bytes 512 * 1024
  @max_stdin_bytes 256 * 1024
  # Linux caps each environment string at 128 KiB (MAX_ARG_STRLEN), so the
  # base64 of a stdin write travels in parts of at most this many bytes.
  @stdin_env_part_bytes 64 * 1024
  @missing_exit_code 44
  @stdin_closed_exit_code 45
  @stdin_offset_exit_code 47
  @invalid_cwd_exit_code 46
  @list_limit 100
  @finished_retention_days 7
  @env_name ~r/\A[A-Za-z_][A-Za-z0-9_]*\z/

  @dir ~S|d="$HOME/.cache/tuist/commands/$TUIST_COMMAND_ID"|

  # The feeder copies what `write_stdin/4` appends to `stdin` into the
  # command, and ends its stdin once `stdin_closed` exists and everything is
  # copied (at once when stdin is not attached). The script waits for the
  # pid file, which the detached shell writes after setsid: until then the
  # command is still in the starting exec's process group.
  #
  # The script enters the command's working directory itself: the guest
  # agent refuses to start any process in a missing directory, which would
  # otherwise surface as a node failure instead of the caller's mistake.
  @start_script @dir <>
                  """

                  if [ -n "${TUIST_CWD-}" ]; then cd -- "$TUIST_CWD" 2> /dev/null || exit #{@invalid_cwd_exit_code}; fi
                  """ <>
                  ~S"""
                  set -eu
                  mkdir -p "$d"
                  printf '%s' "$TUIST_COMMAND" > "$d/command"
                  : > "$d/stdout"
                  : > "$d/stderr"
                  : > "$d/stdin"
                  [ "$TUIST_STDIN" = 1 ] || : > "$d/stdin_closed"
                  cat > "$d/feed.pl" <<'FEED'
                  $SIG{PIPE} = 'IGNORE';
                  my $d = shift;
                  open(my $in, '<', "$d/stdin") or exit 0;
                  binmode $in; binmode STDOUT;
                  sub drain { while (my $n = sysread($in, my $buf, 65536)) { defined(syswrite(STDOUT, $buf)) or exit 0 } }
                  while (1) {
                    drain();
                    if (-e "$d/stdin_closed" || -e "$d/exit_code") { drain(); exit 0 }
                    select(undef, undef, undef, 0.1);
                  }
                  FEED
                  unset TUIST_COMMAND TUIST_STDIN TUIST_CWD
                  perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' \
                    /bin/bash -c 'echo $$ > "$1/pid"; perl "$1/feed.pl" "$1" | /bin/bash -l "$1/command" > "$1/stdout" 2> "$1/stderr"; echo $? > "$1/exit_code.tmp"; mv "$1/exit_code.tmp" "$1/exit_code"' _ "$d" \
                    < /dev/null > /dev/null 2>&1 &
                  i=0
                  while [ ! -s "$d/pid" ]; do
                    i=$((i + 1))
                    [ "$i" -le 200 ] || { echo "the command did not start" >&2; exit 1; }
                    sleep 0.05
                  done
                  """

  # Prints `<state> <exit code or -> <stdout size> <stderr size> <reason or ->`
  # on the first line, then the stdout chunk; the stderr chunk goes to stderr.
  # The exit code is checked before the sizes are taken, so a finished
  # command's last read holds all of its output.
  @read_script @dir <>
                 """

                 [ -d "$d" ] || exit #{@missing_exit_code}
                 """ <>
                 ~S"""
                 end=$(( $(date +%s) + TUIST_WAIT ))
                 while :; do
                   state=running
                   if [ -e "$d/exit_code" ]; then
                     state=exited
                   elif ! kill -0 "$(cat "$d/pid" 2> /dev/null)" 2> /dev/null; then
                     [ -e "$d/exit_code" ] && state=exited || state=lost
                   fi
                   so=$(( $(wc -c < "$d/stdout") ))
                   se=$(( $(wc -c < "$d/stderr") ))
                   [ "$state" != running ] && break
                   [ "$so" -gt "$TUIST_STDOUT_OFFSET" ] || [ "$se" -gt "$TUIST_STDERR_OFFSET" ] && break
                   [ "$(date +%s)" -ge "$end" ] && break
                   sleep 0.5
                 done
                 # Killing the session also kills the shell that writes exit_code.
                 [ "$state" = lost ] && [ -s "$d/killed" ] && state=exited
                 code=-
                 [ -e "$d/exit_code" ] && code=$(cat "$d/exit_code")
                 reason=-
                 [ -s "$d/killed" ] && reason=$(cat "$d/killed")
                 echo "$state $code $so $se $reason"
                 n=$(( so - TUIST_STDOUT_OFFSET )); [ "$n" -gt "$TUIST_CHUNK" ] && n=$TUIST_CHUNK
                 [ "$n" -gt 0 ] && tail -c +$((TUIST_STDOUT_OFFSET + 1)) "$d/stdout" | head -c "$n"
                 n=$(( se - TUIST_STDERR_OFFSET )); [ "$n" -gt "$TUIST_CHUNK" ] && n=$TUIST_CHUNK
                 [ "$n" -gt 0 ] && tail -c +$((TUIST_STDERR_OFFSET + 1)) "$d/stderr" | head -c "$n" >&2
                 exit 0
                 """

  # With TUIST_STDIN_OFFSET, the bytes stdin had before this write, a write
  # sent again lands once: one whose bytes are already there succeeds without
  # appending them, and one that does not continue stdin fails. The lock
  # covers a second attempt arriving while the first still runs.
  @stdin_script @dir <>
                  """

                  [ -d "$d" ] || exit #{@missing_exit_code}
                  closed_code=#{@stdin_closed_exit_code}
                  offset_code=#{@stdin_offset_exit_code}
                  """ <>
                  ~S"""
                  perl -MMIME::Base64 -MFcntl=:flock -e '
                    my ($stdin, $closed, $exited, $closed_code, $offset_code) = @ARGV;
                    open(my $f, ">>", $stdin) or die "$!\n"; binmode $f; flock($f, LOCK_EX) or die "$!\n";
                    my $data = decode_base64(join "", map { $ENV{"TUIST_STDIN_DATA_$_"} } 0 .. $ENV{TUIST_STDIN_PARTS} - 1);
                    my $offset = $ENV{TUIST_STDIN_OFFSET} // "";
                    my $size = (stat $f)[7];
                    exit 0 if $offset ne "" && $size == $offset + length $data;
                    exit $closed_code if -e $closed || ($offset ne "" && -e $exited);
                    exit $offset_code if $offset ne "" && $size != $offset;
                    print $f $data; close $f or die "$!\n"' \
                    "$d/stdin" "$d/stdin_closed" "$d/exit_code" "$closed_code" "$offset_code" || exit $?
                  [ "$TUIST_STDIN_CLOSE" = 1 ] && : > "$d/stdin_closed"
                  exit 0
                  """

  # Signals the command's session (its pid is the group id), then kills
  # what is left after five seconds. The first reason recorded wins.
  @kill_script @dir <>
                 """

                 [ -d "$d" ] || exit #{@missing_exit_code}
                 """ <>
                 ~S"""
                 [ -e "$d/exit_code" ] && exit 0
                 [ -s "$d/killed" ] || printf '%s' "$TUIST_REASON" > "$d/killed"
                 : > "$d/stdin_closed"
                 pid=$(cat "$d/pid")
                 kill -TERM -- -"$pid" 2> /dev/null || exit 0
                 i=0
                 while kill -0 -- -"$pid" 2> /dev/null && [ "$i" -lt 50 ]; do i=$((i + 1)); sleep 0.1; done
                 kill -KILL -- -"$pid" 2> /dev/null || true
                 exit 0
                 """

  def residency, do: @residency
  def max_stdin_bytes, do: @max_stdin_bytes

  @doc """
  Starts a command in the sandbox, resuming it first, and answers at once.

  Params: `:command` (a shell command, or the program when `:args` is given),
  `:args` (run `command` with these arguments and no shell interpretation),
  `:env`, `:cwd` (default the workspace), `:timeout_ms` (default one hour, at
  most six), `:stdin` (`true` to keep stdin open for `write_stdin/5`;
  otherwise the command reads an empty stdin) and `:id` (a UUID the client
  chose, so that sending the request again answers the command it started
  instead of starting another).

  While CI holds the sandbox's host, admission refuses the resume of a
  paused sandbox; a running one needs no grant. The start then tries again every second for up to
  #{div(@host_wait_ms, 1000)} seconds before it answers the refusal, so the
  command starts as soon as the host frees instead of after the client's
  next retry.
  """
  def start(%Sandbox{} = sandbox, params) do
    with {:ok, script} <- script(params),
         {:ok, env} <- validate_env(Map.get(params, :env) || %{}),
         {:ok, id} <- command_id(Map.get(params, :id)) do
      # A request sent again with the same `id`, such as after a gateway
      # error hid the answer, gets the command the first one started.
      case id && get(sandbox, id) do
        {:ok, command} ->
          {:ok, serialize(command)}

        _ ->
          deadline = System.monotonic_time(:millisecond) + @host_wait_ms
          start_admitted(sandbox, id || Ecto.UUID.generate(), params, script, env, deadline)
      end
    end
  end

  defp command_id(nil), do: {:ok, nil}

  defp command_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_command}
    end
  end

  defp start_admitted(sandbox, id, params, script, env, deadline) do
    case start_new(sandbox, id, params, script, env) do
      {:error, reason} = error ->
        if host_busy?(reason) and System.monotonic_time(:millisecond) + @host_poll_ms < deadline do
          Process.sleep(@host_poll_ms)

          case Sandboxes.get_sandbox_by_id(sandbox.id) do
            %Sandbox{} = fresh -> start_admitted(fresh, id, params, script, env, deadline)
            nil -> {:error, :not_found}
          end
        else
          error
        end

      result ->
        result
    end
  end

  # `{:host_busy, why}` is a resume its own Mac refused; a replaced Mac
  # never takes it back.
  defp host_busy?(:no_capacity), do: true
  defp host_busy?({:host_busy, why}), do: why != :replaced
  defp host_busy?(_reason), do: false

  defp start_new(sandbox, id, params, script, env) do
    with {:ok, running} <- Sandboxes.ensure_running(sandbox) do
      timeout_ms = params |> Map.get(:timeout_ms, @default_timeout_ms) |> max(1) |> min(@max_timeout_ms)
      prune_finished(running)

      case start_on(running, id, params, script, env, timeout_ms) do
        {:error, reason} = error ->
          if Sandboxes.interrupted_by_pause?(reason),
            do: start_after_pause(running, id, params, script, env, timeout_ms),
            else: error

        result ->
          result
      end
    end
  end

  # An idle sandbox's pause can reach the node before the row says paused, or
  # the pause's caller can die before recording it. Like `Sandboxes.exec/3`,
  # wait for it and start on the resumed sandbox.
  defp start_after_pause(running, id, params, script, env, timeout_ms) do
    with {:ok, resumed} <- Sandboxes.await_pause(running),
         do: start_on(resumed, id, params, script, env, timeout_ms)
  end

  defp start_on(sandbox, id, params, script, env, timeout_ms) do
    # The row exists before the sandbox is held, so a command finishing
    # concurrently sees it and keeps the residency.
    command =
      Repo.insert!(%SandboxCommand{
        id: id,
        sandbox_id: sandbox.id,
        account_id: sandbox.account_id,
        command: script,
        cwd: Map.get(params, :cwd),
        stdin: Map.get(params, :stdin) == true,
        deadline_at: DateTime.add(DateTime.utc_now(:second), div(timeout_ms, 1000) + 1)
      })

    case hold_and_launch(sandbox, command, env) do
      {:ok, held} ->
        {:ok, _job} =
          %{
            sandbox_id: held.id,
            command_id: command.id,
            deadline_ms: DateTime.to_unix(command.deadline_at, :millisecond)
          }
          |> CommandWatchWorker.new(schedule_in: 15)
          |> Oban.insert()

        {:ok, serialize(command)}

      {:error, reason} ->
        Repo.delete!(command)
        # A start that failed does not begin a session, but it leaves one
        # that was already leased alone.
        release_if_idle(sandbox, lease: sandbox.residency_work_id == @residency)
        {:error, reason}
    end
  end

  defp hold_and_launch(sandbox, command, env) do
    with {:ok, held} <- Sandboxes.begin_shared_residency(sandbox, @residency),
         :ok <- Sandboxes.hold_host_residency(held, @residency),
         :ok <- launch(held, command, env) do
      {:ok, held}
    end
  end

  defp launch(sandbox, command, env) do
    exec_opts = [
      env:
        Map.merge(env, %{
          "TUIST_COMMAND_ID" => command.id,
          "TUIST_COMMAND" => command.command,
          "TUIST_CWD" => command.cwd || "",
          "TUIST_STDIN" => if(command.stdin, do: "1", else: "0")
        }),
      timeout_ms: 30_000
    ]

    case Sandboxes.exec_running(sandbox, ["/bin/bash", "-c", @start_script], exec_opts) do
      {:ok, %{exit_code: 0}} -> :ok
      {:ok, %{exit_code: @invalid_cwd_exit_code}} -> {:error, {:invalid_cwd, command.cwd}}
      {:ok, %{stderr: stderr}} -> {:error, String.trim("could not start the command: " <> stderr)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp script(%{command: command} = params) when is_binary(command) and command != "" do
    case Map.get(params, :args) do
      nil ->
        {:ok, command}

      args when is_list(args) ->
        if(Enum.all?(args, &is_binary/1),
          do: {:ok, "exec " <> Enum.map_join([command | args], " ", &shell_quote/1)},
          else: {:error, :invalid_command}
        )

      _ ->
        {:error, :invalid_command}
    end
  end

  defp script(_params), do: {:error, :invalid_command}

  defp shell_quote(value), do: "'" <> String.replace(value, "'", ~S('\'')) <> "'"

  defp validate_env(env) when is_map(env) do
    if Enum.all?(env, fn {key, value} -> is_binary(key) and is_binary(value) and Regex.match?(@env_name, key) end),
      do: {:ok, env},
      else: {:error, :invalid_command}
  end

  defp validate_env(_env), do: {:error, :invalid_command}

  @doc """
  The sandbox's commands, newest first.
  """
  def list(%Sandbox{id: sandbox_id}) do
    from(c in SandboxCommand, where: c.sandbox_id == ^sandbox_id, order_by: [desc: c.inserted_at], limit: @list_limit)
    |> Repo.all()
    |> Enum.map(&serialize/1)
  end

  @doc """
  Reads the command's state and the output past the given byte offsets,
  waiting up to `:wait_seconds` (default 0, at most #{@max_wait_seconds}) for
  new output or the exit. Each stream returns at most #{@chunk_bytes} bytes,
  cut at a UTF-8 boundary; `*_offset` in the answer is where the next read
  starts. The first read that sees the command gone records how it ended.
  """
  def read(%Sandbox{} = sandbox, id, opts \\ []) do
    wait = opts |> Keyword.get(:wait_seconds, 0) |> max(0) |> min(@max_wait_seconds)
    stdout_offset = max(Keyword.get(opts, :stdout_offset, 0), 0)
    stderr_offset = max(Keyword.get(opts, :stderr_offset, 0), 0)

    env = %{
      "TUIST_COMMAND_ID" => id,
      "TUIST_WAIT" => Integer.to_string(wait),
      "TUIST_STDOUT_OFFSET" => Integer.to_string(stdout_offset),
      "TUIST_STDERR_OFFSET" => Integer.to_string(stderr_offset),
      "TUIST_CHUNK" => Integer.to_string(@chunk_bytes)
    }

    with {:ok, command} <- get(sandbox, id) do
      exec_opts = [env: env, timeout_ms: wait * 1000 + 30_000, raw_output: true]

      case Sandboxes.exec(sandbox, ["/bin/bash", "-c", @read_script], exec_opts) do
        {:ok, result} ->
          case parse(result, stdout_offset, stderr_offset) do
            {:ok, read} ->
              command = record(sandbox, command, read.status, read.exit_code)
              {:ok, Map.merge(serialize(command), Map.drop(read, [:status, :exit_code]))}

            {:error, :not_found} ->
              # The guest lost the directory, such as a sandbox created again.
              command = record(sandbox, command, :lost, nil)
              {:ok, Map.merge(serialize(command), empty_read(stdout_offset, stderr_offset))}

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Offsets past any output make `read/3` wait for the exit alone.
  @past_end 1 <<< 62

  @doc """
  The command's state, waiting up to `wait_seconds` (at most #{@max_wait_seconds})
  for it to end.
  """
  def wait(%Sandbox{} = sandbox, id, wait_seconds) do
    with {:ok, read} <- read(sandbox, id, wait_seconds: wait_seconds, stdout_offset: @past_end, stderr_offset: @past_end) do
      {:ok, Map.take(read, [:id, :command, :cwd, :stdin, :status, :exit_code, :deadline_at, :finished_at, :started_at])}
    end
  end

  defp empty_read(stdout_offset, stderr_offset),
    do: %{stdout: "", stderr: "", stdout_offset: stdout_offset, stderr_offset: stderr_offset, complete: true}

  @doc """
  Appends `data` to the command's stdin and, with `close`, ends it. With
  `offset`, the number of bytes written to stdin before this write, sending
  the same write again appends it only once.
  """
  def write_stdin(%Sandbox{} = sandbox, id, data, close?, offset \\ nil) when is_binary(data) do
    with {:ok, command} <- get(sandbox, id),
         :ok <- writable(command, data, offset) do
      env = stdin_env(command, data, close?, offset)

      case Sandboxes.exec(sandbox, ["/bin/bash", "-c", @stdin_script], env: env, timeout_ms: 30_000) do
        {:ok, %{exit_code: 0}} -> {:ok, serialize(command)}
        {:ok, %{exit_code: @missing_exit_code}} -> {:error, :not_found}
        {:ok, %{exit_code: @stdin_closed_exit_code}} -> {:error, :stdin_closed}
        {:ok, %{exit_code: @stdin_offset_exit_code}} -> {:error, :stdin_offset_mismatch}
        {:ok, %{stderr: stderr}} -> {:error, "could not write to stdin: " <> String.trim(stderr)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp stdin_env(command, data, close?, offset) do
    encoded = Base.encode64(data)

    parts =
      for at <- 0..(byte_size(encoded) - 1)//@stdin_env_part_bytes do
        binary_part(encoded, at, min(@stdin_env_part_bytes, byte_size(encoded) - at))
      end

    parts
    |> Enum.with_index(fn part, index -> {"TUIST_STDIN_DATA_#{index}", part} end)
    |> Map.new()
    |> Map.merge(%{
      "TUIST_COMMAND_ID" => command.id,
      "TUIST_STDIN_PARTS" => Integer.to_string(length(parts)),
      "TUIST_STDIN_CLOSE" => if(close?, do: "1", else: "0"),
      "TUIST_STDIN_OFFSET" => if(offset, do: Integer.to_string(offset), else: "")
    })
  end

  defp writable(%SandboxCommand{stdin: false}, _data, _offset), do: {:error, :stdin_not_attached}
  # A write with an offset may be one that reached the command before it
  # ended, so the guest, which knows what stdin holds, answers it.
  defp writable(%SandboxCommand{status: status}, _data, nil) when status != :running, do: {:error, :stdin_closed}
  defp writable(_command, data, _offset) when byte_size(data) > @max_stdin_bytes, do: {:error, :invalid_command}
  defp writable(_command, _data, _offset), do: :ok

  @doc """
  Stops the command (SIGTERM to its session, SIGKILL after five seconds) and
  answers its state.
  """
  def cancel(%Sandbox{} = sandbox, id) do
    with {:ok, command} <- get(sandbox, id) do
      case kill(sandbox, command.id, "cancelled", &Sandboxes.exec/3) do
        result when result in [:ok, {:error, :not_found}] -> wait(sandbox, command.id, 0)
        error -> error
      end
    end
  end

  @doc false
  def kill(sandbox, id, reason, exec \\ &Sandboxes.exec_running/3) do
    env = %{"TUIST_COMMAND_ID" => id, "TUIST_REASON" => reason}

    case exec.(sandbox, ["/bin/bash", "-c", @kill_script], env: env, timeout_ms: 30_000) do
      {:ok, %{exit_code: 0}} -> :ok
      {:ok, %{exit_code: @missing_exit_code}} -> {:error, :not_found}
      {:ok, %{stderr: stderr}} -> {:error, "could not stop the command: " <> String.trim(stderr)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  # The guest's view of a command without waking the sandbox, for the watcher.
  def probe(sandbox, id) do
    env = %{
      "TUIST_COMMAND_ID" => id,
      "TUIST_WAIT" => "0",
      "TUIST_STDOUT_OFFSET" => "0",
      "TUIST_STDERR_OFFSET" => "0",
      "TUIST_CHUNK" => "0"
    }

    with {:ok, result} <-
           Sandboxes.exec_running(sandbox, ["/bin/bash", "-c", @read_script],
             env: env,
             timeout_ms: 30_000,
             raw_output: true
           ),
         {:ok, read} <- parse(result, 0, 0) do
      {:ok, read.status, read.exit_code}
    end
  end

  @doc """
  Records how a running command ended (a finished one keeps its outcome) and
  gives the sandbox back once no command runs.
  """
  def record(sandbox, %SandboxCommand{status: :running} = command, status, exit_code) when status != :running do
    {:ok, updated} =
      command
      |> Ecto.Changeset.change(status: status, exit_code: exit_code, finished_at: DateTime.utc_now(:second))
      |> Repo.update()

    release_if_idle(sandbox)
    updated
  end

  def record(_sandbox, command, _status, _exit_code), do: command

  @doc """
  Ends the shared residency, and releases the macOS host hold, once none of
  the sandbox's commands runs; on macOS it leases the sandbox to the
  session instead (`lease: false` ends it there too). The check and the
  release happen under the sandbox row's lock. `start/2` inserts its
  running row before it holds the sandbox, so a release either sees that
  row and keeps the residency, or ends it first and the start takes it
  again.
  """
  def release_if_idle(%Sandbox{id: sandbox_id}, opts \\ []) do
    lease? = Keyword.get(opts, :lease, true)

    sandbox_id
    |> when_idle(fn
      %Sandbox{platform: :darwin} = sandbox when lease? -> {:lease, sandbox}
      sandbox -> end_commands_residency(sandbox)
    end)
    |> after_idle()
  end

  @doc """
  Leases a macOS sandbox the account API just created or resumed to the
  session, as its commands do, so the agent's first command after it does
  not wait to resume it. Linux sandboxes are answered as they are.
  """
  def keep(%Sandbox{platform: :darwin} = sandbox) do
    with {:ok, held} <- Sandboxes.prepare_shared_residency(sandbox, @residency) do
      lease(held)
      {:ok, held}
    end
  end

  def keep(%Sandbox{} = sandbox), do: {:ok, sandbox}

  @doc """
  Ends the session's lease once the sandbox has been idle for its length,
  which lets the sandbox pause. A command running, newer activity or
  another residency keeps it; activity moves the check to when the lease
  would end after it.
  """
  def end_lease(sandbox_id) do
    sandbox_id
    |> when_idle(fn sandbox ->
      if DateTime.after?(lease_ends_at(sandbox), DateTime.utc_now()),
        do: {:later, sandbox},
        else: end_commands_residency(sandbox)
    end)
    |> after_idle()
  end

  # Runs `fun` under the sandbox row's lock when the commands residency
  # holds the sandbox and none of its commands runs.
  defp when_idle(sandbox_id, fun) do
    {:ok, outcome} =
      Repo.transaction(fn ->
        sandbox = Repo.one(from(s in Sandbox, where: s.id == ^sandbox_id, lock: "FOR UPDATE"))
        running = Repo.exists?(from(c in SandboxCommand, where: c.sandbox_id == ^sandbox_id and c.status == :running))
        if match?(%Sandbox{residency_work_id: @residency}, sandbox) and not running, do: fun.(sandbox)
      end)

    outcome
  end

  defp end_commands_residency(%Sandbox{} = sandbox) do
    {:ok, _} = ensure_ended(Sandboxes.end_residency(sandbox.id, @residency))
    {:released, sandbox}
  end

  defp after_idle({:lease, sandbox}), do: lease(sandbox)
  defp after_idle({:later, sandbox}), do: schedule_lease_end(sandbox, lease_ends_at(sandbox))

  defp after_idle({:released, %Sandbox{node_name: node} = sandbox}) when is_binary(node) do
    _ = Sandboxes.release_host_residency(sandbox, @residency)
    :ok
  end

  defp after_idle(_outcome), do: :ok

  # The host hold runs a little past the lease, so it only ends on its own
  # when the server never ended the lease.
  defp lease(%Sandbox{} = sandbox) do
    _ = Sandboxes.hold_host_residency(sandbox, @residency, (@lease_seconds + @host_hold_slack_seconds) * 1000)
    schedule_lease_end(sandbox, DateTime.add(DateTime.utc_now(), @lease_seconds))
  end

  defp lease_ends_at(%Sandbox{last_active_at: %DateTime{} = at}), do: DateTime.add(at, @lease_seconds)
  defp lease_ends_at(%Sandbox{}), do: DateTime.utc_now()

  defp schedule_lease_end(%Sandbox{id: id}, at) do
    {:ok, _job} =
      %{sandbox_id: id}
      |> EndLeaseWorker.new(scheduled_at: at, replace: [scheduled: [:scheduled_at], available: [:scheduled_at]])
      |> Oban.insert()

    :ok
  end

  defp ensure_ended({:ok, sandbox}), do: {:ok, sandbox}
  defp ensure_ended(:ok), do: {:ok, nil}

  defp get(%Sandbox{id: sandbox_id}, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %SandboxCommand{} = command <- Repo.get_by(SandboxCommand, id: uuid, sandbox_id: sandbox_id) do
      {:ok, command}
    else
      _ -> {:error, :not_found}
    end
  end

  defp prune_finished(%Sandbox{id: sandbox_id}) do
    cutoff = DateTime.add(DateTime.utc_now(), -@finished_retention_days, :day)

    Repo.delete_all(
      from(c in SandboxCommand,
        where: c.sandbox_id == ^sandbox_id and c.status != :running and c.finished_at < ^cutoff
      )
    )
  end

  def serialize(%SandboxCommand{} = command) do
    command
    |> Map.take([:id, :command, :cwd, :stdin, :status, :exit_code, :deadline_at, :finished_at, :inserted_at])
    |> Map.update!(:status, &Atom.to_string/1)
    |> Map.put(:started_at, command.inserted_at)
    |> Map.delete(:inserted_at)
  end

  defp parse(%{exit_code: @missing_exit_code}, _so, _se), do: {:error, :not_found}

  defp parse(%{exit_code: 0, stdout: stdout, stderr: stderr}, stdout_offset, stderr_offset) do
    with [header, out] <- String.split(stdout, "\n", parts: 2),
         [state, code, stdout_size, stderr_size, reason] <- String.split(header, " "),
         {stdout_size, ""} <- Integer.parse(stdout_size),
         {stderr_size, ""} <- Integer.parse(stderr_size) do
      {out, out_bytes} = utf8_prefix(out)
      {err, err_bytes} = utf8_prefix(stderr)

      {:ok,
       %{
         status: status(state, reason),
         exit_code: exit_code(code),
         stdout: out,
         stderr: err,
         stdout_offset: stdout_offset + out_bytes,
         stderr_offset: stderr_offset + err_bytes,
         complete:
           state != "running" and stdout_offset + out_bytes >= stdout_size and
             stderr_offset + err_bytes >= stderr_size
       }}
    else
      _ -> {:error, "unexpected command state from the guest"}
    end
  end

  defp parse(%{stderr: stderr}, _so, _se), do: {:error, "could not read the command: " <> String.trim(stderr)}

  defp status("running", _reason), do: :running
  defp status("lost", _reason), do: :lost
  defp status("exited", "timeout"), do: :timed_out
  defp status("exited", "cancelled"), do: :cancelled
  defp status("exited", _reason), do: :exited

  defp exit_code("-"), do: nil

  defp exit_code(code) do
    case Integer.parse(code) do
      {value, _rest} -> value
      :error -> nil
    end
  end

  # A chunk can end inside a multi-byte character. Keep the longest valid
  # prefix that drops at most three trailing bytes, so the next read starts
  # on the character; output that is not UTF-8 at all is returned with
  # replacements and consumed whole.
  defp utf8_prefix(chunk) do
    size = byte_size(chunk)

    0..min(3, size)
    |> Enum.find_value(fn drop ->
      prefix = binary_part(chunk, 0, size - drop)
      if String.valid?(prefix), do: {prefix, size - drop}
    end)
    |> case do
      nil -> {String.replace_invalid(chunk), size}
      found -> found
    end
  end
end
