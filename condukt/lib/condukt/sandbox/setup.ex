defmodule Condukt.Sandbox.Setup do
  @moduledoc """
  Prepares a sandbox before a session's first turn, and again when the
  session comes back on a sandbox that was paused.

  `prepare/3` runs a repository's setup script as a sandbox process, streams
  its output to `:on_output`, and, when the script succeeds and the sandbox
  implements `c:Condukt.Sandbox.snapshot/2`, saves a snapshot. A later
  sandbox started with that snapshot (its `init/1` takes `:snapshot`) skips
  the setup. `resume/3` runs a resume script, such as one that starts what a
  pause stopped, the same way, without a snapshot.

      {:ok, %{snapshot: snapshot_id}} =
        Condukt.Sandbox.Setup.prepare(sandbox, File.read!(".agents/setup"),
          on_output: &IO.write/1,
          snapshot: [key: "repo@" <> sha]
        )

  Which snapshot to boot from, and when to refresh it, is the host's policy:
  Condukt only runs the script and asks the sandbox to save.
  """

  alias Condukt.Sandbox

  @default_timeout to_timeout(hour: 1)
  @wait 2_000
  @retry 1_000

  @doc """
  Runs `script` and saves a snapshot when it succeeds. Options:

    * `:on_output` — a function given each chunk of output
    * `:snapshot` — options for `c:Condukt.Sandbox.snapshot/2`, or `false`
      to skip saving
    * `:timeout`, `:cwd`, `:env` — as `c:Condukt.Sandbox.start_process/4`

  Returns `{:ok, %{snapshot: id_or_nil}}`, or `{:error, {:setup_failed,
  status, tail}}` with the end of the output.
  """
  def prepare(%Sandbox{} = sandbox, script, opts \\ []) do
    with :ok <- run(sandbox, "condukt-setup", script, opts) do
      snapshot(sandbox, Keyword.get(opts, :snapshot, []))
    end
  end

  defp snapshot(_sandbox, false), do: {:ok, %{snapshot: nil}}

  defp snapshot(sandbox, opts) do
    case Sandbox.snapshot(sandbox, opts) do
      {:ok, id} -> {:ok, %{snapshot: id}}
      {:error, :not_supported} -> {:ok, %{snapshot: nil}}
      {:error, reason} -> {:error, {:snapshot_failed, reason}}
    end
  end

  @doc "Runs a resume script. Takes `prepare/3`'s options but `:snapshot`."
  def resume(%Sandbox{} = sandbox, script, opts \\ []) do
    run(sandbox, "condukt-resume", script, opts)
  end

  defp run(sandbox, kind, script, opts) do
    # Random, not a node counter: a sandbox that outlives the node may still
    # hold an earlier run's process, which a reused id would find instead.
    id = "#{kind}:#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
    timeout = opts[:timeout] || @default_timeout
    process_opts = [timeout: timeout, cwd: opts[:cwd], env: opts[:env] || []]
    # Reads that fail, as while the sandbox's node restarts, are retried
    # until the script's own timeout has passed: the script goes on anyway.
    deadline = System.monotonic_time(:millisecond) + timeout + @wait

    with :ok <- Sandbox.start_process(sandbox, id, script, process_opts) do
      try do
        follow(sandbox, id, 0, "", Keyword.get(opts, :on_output, fn _ -> :ok end), deadline)
      after
        Sandbox.stop_process(sandbox, id)
      end
    end
  end

  defp follow(sandbox, id, offset, tail, on_output, deadline) do
    case Sandbox.read_process(sandbox, id, offset, wait: @wait) do
      {:ok, %{output: output, offset: next, size: size, status: status}} ->
        if output != "", do: on_output.(output)
        tail = binary_slice(tail <> output, -min(byte_size(tail <> output), 4096)..-1//1)

        cond do
          status == :running or next < size -> follow(sandbox, id, next, tail, on_output, deadline)
          status == {:exited, 0} -> :ok
          true -> {:error, {:setup_failed, status, tail}}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        retry(reason, deadline, fn -> follow(sandbox, id, offset, tail, on_output, deadline) end)
    end
  end

  defp retry(reason, deadline, fun) do
    if System.monotonic_time(:millisecond) < deadline do
      Process.sleep(@retry)
      fun.()
    else
      {:error, reason}
    end
  end
end
