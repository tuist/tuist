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
  #     child    with a timeout, the pid of `timeout`, which leads another group
  #     output   combined stdout and stderr
  #     status   written once the command ends: its exit code, or `timeout`
  #
  # `mkdir` of the directory is the atomic step that makes starting idempotent
  # on the id. The status file is written before the runner exits, so a reader
  # that sees it knows the output is complete.

  @default_root "/tmp/condukt-processes"
  @default_max_bytes 64 * 1024
  @timeout_exit_code 124

  @doc "The directory name for a process id: any string maps to a safe name."
  def dir_name(id), do: :sha256 |> :crypto.hash(id) |> Base.encode16(case: :lower) |> binary_part(0, 32)

  def start(exec, id, command, opts) do
    dir = dir(id, opts)

    script = """
    mkdir -p #{q(Path.dirname(dir))} || exit 1
    mkdir #{q(dir)} 2>/dev/null || { echo condukt:already_started; exit 0; }
    : > #{q(dir <> "/output")}
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

    # The status comes first: a process that ends after it was taken shows as
    # running, and the next read gets the rest.
    # A runner killed without writing its status may linger as a zombie, as
    # in a pod whose first process reaps nothing, so a zombie counts as gone.
    script = """
    d=#{dir}
    [ -d "$d" ] || { echo condukt:not_found; exit 0; }
    alive() { kill -0 "$1" 2>/dev/null && [ "$(cut -d' ' -f3 "/proc/$1/stat" 2>/dev/null)" != Z ]; }
    if [ -f "$d/status" ]; then s="exited $(cat "$d/status")"
    elif [ ! -f "$d/pid" ] || alive "$(cat "$d/pid")"; then s=running
    elif [ -f "$d/status" ]; then s="exited $(cat "$d/status")"
    else s=lost
    fi
    printf 'condukt:%s %s\\n' "$s" "$(wc -c < "$d/output" | tr -d ' ')"
    tail -c +#{offset + 1} "$d/output" | head -c #{max_bytes}
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

  # Runs as `bash -c runner condukt-process <dir>` in its own session. It leads
  # its process group, so stopping it signals the group; `timeout` leads one of
  # its own, recorded as `child`.
  defp runner(command, opts) do
    cwd = Keyword.get(opts, :cwd)
    timeout = Keyword.get(opts, :timeout)

    {run, after_run} =
      if is_integer(timeout) and timeout > 0 do
        seconds = timeout |> Kernel./(1_000) |> :erlang.float_to_binary(decimals: 3)

        {"timeout --kill-after=5s #{seconds}s bash -c #{q(command)}",
         ~s(echo $! > "$d/child"; wait $!; code=$?; [ "$code" = #{@timeout_exit_code} ] && code=timeout)}
      else
        {"bash -c #{q(command)}", "wait $!; code=$?"}
      end

    cd =
      if cwd,
        do: ~s(cd #{q(cwd)} 2>>"$d/output" || { echo 1 > "$d/status.tmp"; mv "$d/status.tmp" "$d/status"; exit 1; }),
        else: ":"

    """
    d="$1"
    echo $$ > "$d/pid"
    #{exports(Keyword.get(opts, :env, []))}
    #{cd}
    #{run} >> "$d/output" 2>&1 &
    #{after_run}
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
    with [header, output] <- String.split(rest, "\n", parts: 2),
         {:ok, status, size} <- parse_header(header) do
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
