defmodule Condukt.Sandbox.Processes do
  @moduledoc false

  # Detached processes for sandboxes that reach their machine through a shell,
  # such as a Kubernetes pod or a microVM guest. Each sandbox passes a function
  # that runs one bash script there and returns `exec/3`'s result.
  #
  # A process named `id` lives in `<root>/<dir_name(id)>`, on the sandbox's
  # machine rather than in the BEAM, so it survives the node that started it:
  #
  #     pid      the runner's pid, which leads its own session and process group
  #     child    the command's pid, which leads a session and group of its own,
  #              so stopping it or its timeout reaches everything it started
  #     timed_out  exists once the timeout fired, so the status says `timeout`
  #              whatever exit code the killed command left
  #     output   combined stdout and stderr
  #     status   written once the command ends: its exit code, or `timeout`
  #     stdin    what `write/5` appended, which a feeder copies into the command
  #     stdin_closed  exists once stdin ended, at once without `stdin: true`
  #
  # `mkdir` of the directory is the atomic step that makes starting idempotent
  # on the id. The status file is written before the runner exits, so a reader
  # that sees it knows the output is complete.

  @default_root "/tmp/condukt-processes"
  @default_max_bytes 64 * 1024
  # How long a command has to stop after the TERM its timeout sends.
  @kill_after_seconds 5
  # One exec answers within the remote sandboxes' 30 s exec timeout.
  @max_wait 25_000

  # Copies what `write/5` appends to `$1/stdin` into its stdout, the
  # command's stdin, and ends once `stdin_closed` exists and everything is
  # copied, the command has ended (`status` or `ended` exists), or the
  # process was stopped and its directory removed. `stdin_closed` is checked
  # before the size is taken: a writer appends its last bytes before it
  # creates that file, so seeing it first means the size includes them.
  @feeder ~S"""
  condukt_feed() {
    o=0
    while :; do
      [ -d "$1" ] || return 0
      c=; [ -e "$1/stdin_closed" ] && c=1
      s=$(wc -c < "$1/stdin" 2>/dev/null | tr -d ' ')
      [ -n "$s" ] || return 0
      if [ "$s" -gt "$o" ]; then
        tail -c +$((o + 1)) "$1/stdin" | head -c $((s - o)) || return 0
        o=$s
      elif [ -n "$c" ] || [ -e "$1/status" ] || [ -e "$1/ended" ]; then
        return 0
      else
        sleep 0.05
      fi
    done
  }
  """

  @doc false
  def feeder, do: @feeder

  @doc false
  # Shell that runs the command, already started in the background as `$c`
  # under its own session, to its end: kills its group `seconds` after it
  # started, recording `timed_out` in `$d`, and leaves its exit code, or
  # `timeout`, in `$code`. The watchdog waits with `read -t`, a builtin, so
  # killing it leaves no `sleep` behind.
  def await_child(timeout) do
    if is_integer(timeout) and timeout > 0 do
      seconds = timeout |> Kernel./(1_000) |> :erlang.float_to_binary(decimals: 3)

      """
      ( read -t #{seconds} <> <(:)
        : > "$d/timed_out"
        kill -TERM -- -$c 2>/dev/null
        read -t #{@kill_after_seconds} <> <(:)
        kill -KILL -- -$c 2>/dev/null ) >/dev/null 2>&1 &
      w=$!
      wait $c; code=$?
      kill $w 2>/dev/null
      [ -e "$d/timed_out" ] && code=timeout
      """
    else
      "wait $c; code=$?\n"
    end
  end

  @doc """
  The command a process runs: on a pseudo-terminal through util-linux
  `script` when `:pty` is set, so a shell behaves as it does for a person.
  """
  def command(command, opts) do
    if Keyword.get(opts, :pty), do: "script -qfec #{q(command)} /dev/null", else: command
  end

  @doc "The directory name for a process id: any string maps to a safe name."
  def dir_name(id), do: :sha256 |> :crypto.hash(id) |> Base.encode16(case: :lower) |> binary_part(0, 32)

  def start(exec, id, command, opts) do
    dir = dir(id, opts)

    script = """
    mkdir -p #{q(Path.dirname(dir))} || exit 1
    mkdir #{q(dir)} 2>/dev/null || { echo condukt:already_started; exit 0; }
    : > #{q(dir <> "/output")}
    : > #{q(dir <> "/stdin")}
    #{if Keyword.get(opts, :stdin), do: ":", else: ": > " <> q(dir <> "/stdin_closed")}
    setsid -f bash -c #{q(runner(command, opts))} condukt-process #{q(dir)} </dev/null >/dev/null 2>&1 || exit 1
    echo condukt:started
    """

    case exec.(script) do
      {:ok, %{output: output, exit_code: 0}} -> started(output)
      {:ok, %{output: output}} -> {:error, {:start_failed, String.trim(output)}}
      {:error, reason} -> {:error, reason}
    end
  end

  def read(exec, id, offset, opts) when is_integer(offset) and offset >= 0 do
    dir = q(dir(id, opts))
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    # Tenths of a second to wait for output past `offset` or the end.
    wait = opts |> Keyword.get(:wait, 0) |> min(@max_wait) |> div(100)

    # The status comes first: a process that ends after it was taken shows as
    # running, and the next read gets the rest.
    # A runner killed without writing its status may linger as a zombie, as
    # in a pod whose first process reaps nothing, so a zombie counts as gone.
    script = """
    d=#{dir}
    [ -d "$d" ] || { echo condukt:not_found; exit 0; }
    alive() { kill -0 "$1" 2>/dev/null && [ "$(cut -d' ' -f3 "/proc/$1/stat" 2>/dev/null)" != Z ]; }
    i=0
    while :; do
      if [ -f "$d/status" ]; then s="exited $(cat "$d/status")"
      elif [ ! -f "$d/pid" ] || alive "$(cat "$d/pid")"; then s=running
      elif [ -f "$d/status" ]; then s="exited $(cat "$d/status")"
      else s=lost
      fi
      [ "$s" = running ] && [ "$(wc -c < "$d/output")" -le #{offset} ] && [ $i -lt #{wait} ] || break
      i=$((i + 1)); sleep 0.1
    done
    printf 'condukt:%s %s\\n' "$s" "$(wc -c < "$d/output" | tr -d ' ')"
    tail -c +#{offset + 1} "$d/output" | head -c #{max_bytes} | base64 | tr -d '\\n'
    """

    case exec.(script) do
      {:ok, %{output: output, exit_code: 0}} -> parse_read(output, offset)
      {:ok, %{output: output}} -> {:error, {:read_failed, String.trim(output)}}
      {:error, reason} -> {:error, reason}
    end
  end

  def stop(exec, id, opts) do
    script = """
    d=#{q(dir(id, opts))}
    [ -d "$d" ] || exit 0
    i=0; while [ ! -f "$d/pid" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done
    if [ ! -f "$d/status" ]; then
      groups=""
      for f in pid child; do [ -f "$d/$f" ] && groups="$groups -$(cat "$d/$f")"; done
      if [ -n "$groups" ]; then
        kill -TERM -- $groups 2>/dev/null
        i=0; while kill -0 -- $groups 2>/dev/null && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done
        kill -KILL -- $groups 2>/dev/null
      fi
    fi
    rm -rf -- "$d"
    """

    case exec.(script) do
      {:ok, %{exit_code: 0}} -> :ok
      {:ok, %{output: output}} -> {:error, {:stop_failed, String.trim(output)}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Appends `data` to a process's stdin. See `c:Condukt.Sandbox.write_process/4`.
  """
  def write(exec, id, data, opts) do
    offset = Keyword.get(opts, :offset)
    # A write sent again closes too, so a close is not lost to a retry.
    close = if Keyword.get(opts, :close), do: ~s(: > "$d/stdin_closed"), else: ":"

    script = """
    d=#{q(dir(id, opts))}
    [ -d "$d" ] || { echo condukt:not_found; exit 0; }
    size=$(wc -c < "$d/stdin" | tr -d ' ')
    #{if offset, do: "[ \"$size\" = #{offset + byte_size(data)} ] && { #{close}; echo condukt:ok; exit 0; }", else: ":"}
    [ -e "$d/stdin_closed" ] && { echo condukt:stdin_closed; exit 0; }
    #{if offset, do: "[ \"$size\" = #{offset} ] || { echo condukt:offset_mismatch; exit 0; }", else: ":"}
    printf '%s' #{q(Base.encode64(data))} | base64 -d >> "$d/stdin" || exit 1
    #{close}
    echo condukt:ok
    """

    case exec.(script) do
      {:ok, %{output: output, exit_code: 0}} -> written(output)
      {:ok, %{output: output}} -> {:error, {:write_failed, String.trim(output)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp written(output) do
    cond do
      output =~ "condukt:ok" -> :ok
      output =~ "condukt:not_found" -> {:error, :not_found}
      output =~ "condukt:stdin_closed" -> {:error, :stdin_closed}
      output =~ "condukt:offset_mismatch" -> {:error, :offset_mismatch}
      true -> {:error, {:write_failed, String.trim(output)}}
    end
  end

  # Runs as `bash -c runner condukt-process <dir>` in its own session. The
  # command runs under `setsid` in a session and group of its own, recorded
  # as `child`, so stopping it, or its timeout, signals everything it
  # started; the runner's group holds the feeder and the timeout's watchdog.
  defp runner(command, opts) do
    cwd = Keyword.get(opts, :cwd)
    command = command(command, opts)
    feed = if Keyword.get(opts, :stdin), do: ~s(condukt_feed "$d" | ), else: ""

    cd =
      if cwd,
        do: ~s(cd #{q(cwd)} 2>>"$d/output" || { echo 1 > "$d/status.tmp"; mv "$d/status.tmp" "$d/status"; exit 1; }),
        else: ":"

    """
    d="$1"
    echo $$ > "$d/pid"
    #{@feeder}
    #{exports(Keyword.get(opts, :env, []))}
    #{cd}
    #{feed}setsid bash -c #{q(command)} >> "$d/output" 2>&1 &
    c=$!
    echo $c > "$d/child"
    #{await_child(Keyword.get(opts, :timeout))}
    echo "$code" > "$d/status.tmp" && mv "$d/status.tmp" "$d/status"
    """
  end

  defp exports(env) do
    env
    |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)
    |> Enum.filter(fn {key, _value} -> Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, key) end)
    |> Enum.map_join("\n", fn {key, value} -> "export #{key}=#{q(value)}" end)
  end

  defp started(output) do
    cond do
      output =~ "condukt:already_started" -> {:error, :already_started}
      output =~ "condukt:started" -> :ok
      true -> {:error, {:start_failed, String.trim(output)}}
    end
  end

  defp parse_read("condukt:not_found" <> _rest, _offset), do: {:error, :not_found}

  defp parse_read("condukt:" <> rest, offset) do
    # The slice is cut at byte offsets, so it travels base64-encoded: an exec
    # that answers text only would drop one that splits a character.
    with [header, encoded] <- String.split(rest, "\n", parts: 2),
         {:ok, status, size} <- parse_header(header),
         {:ok, output} <- Base.decode64(encoded, ignore: :whitespace) do
      {:ok, %{output: output, offset: offset + byte_size(output), size: size, status: status}}
    else
      _other -> {:error, {:read_failed, rest}}
    end
  end

  defp parse_read(output, _offset), do: {:error, {:read_failed, output}}

  defp parse_header(header) do
    case String.split(header, " ") do
      ["running", size] -> {:ok, :running, String.to_integer(size)}
      ["lost", size] -> {:ok, {:exited, nil}, String.to_integer(size)}
      ["exited", "timeout", size] -> {:ok, :timeout, String.to_integer(size)}
      ["exited", code, size] -> {:ok, {:exited, String.to_integer(code)}, String.to_integer(size)}
      _other -> :error
    end
  end

  defp dir(id, opts), do: Path.join(Keyword.get(opts, :root, @default_root), dir_name(id))

  defp q(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
end
