defmodule LuftServer.Threads.RunnerSandbox do
  @moduledoc """
  A `Condukt.Sandbox` on the thread owner's own machine, through its runner
  (`LuftServer.Threads.Runners`). Read, Write, Edit and Bash become runner
  operations; the runner itself confines them to the folders its owner shared
  and refuses commands when terminal access is off, so this module does not
  decide what is allowed, it only resolves paths against the working folder.

  Options: `:runner_id`, `:run` (required) and `:cwd`, an absolute folder on the
  runner (its new project folder unless the thread chose another).
  """
  @behaviour Condukt.Sandbox

  alias LuftServer.Threads.Runners

  @file_timeout_ms 30_000
  @exec_timeout_ms 120_000
  @max_exec_timeout_ms 30 * 60 * 1000

  @impl true
  def init(opts) do
    with {:ok, runner_id} <- Keyword.fetch(opts, :runner_id),
         {:ok, %{id: _, thread_id: _, attempt: _} = run} <- Keyword.fetch(opts, :run),
         cwd when is_binary(cwd) <- Keyword.get(opts, :cwd) do
      {:ok, %{runner_id: runner_id, run: run, cwd: cwd}}
    else
      _ -> {:error, :invalid_runner_sandbox}
    end
  end

  @impl true
  def shutdown(_state), do: :ok

  @impl true
  def cwd(state), do: state.cwd

  @impl true
  def read_file(state, path) do
    case call(state, "read_file", %{"path" => resolve(state, path)}, @file_timeout_ms) do
      {:ok, %{"text" => text}} ->
        {:ok, text}

      {:ok, %{"base64" => data}} ->
        with :error <- Base.decode64(data), do: {:error, :invalid_response}

      {:ok, _} ->
        {:error, :invalid_response}

      error ->
        error
    end
  end

  @impl true
  def list_dir(state, path) do
    case call(state, "list_dir", %{"path" => resolve(state, path)}, @file_timeout_ms) do
      {:ok, %{"entries" => entries}} when is_list(entries) ->
        {:ok,
         Enum.map(entries, fn entry ->
           %{
             name: entry["name"],
             type: if(entry["kind"] == "directory", do: :directory, else: :file)
           }
         end)}

      {:ok, _} ->
        {:error, :invalid_response}

      error ->
        error
    end
  end

  @impl true
  def write_file(state, path, content) do
    # Text with NUL goes as base64: requests are stored as `jsonb`, which can't hold `\u0000`.
    payload =
      if String.valid?(content) and not String.contains?(content, <<0>>),
        do: %{"path" => resolve(state, path), "text" => content},
        else: %{"path" => resolve(state, path), "base64" => Base.encode64(content)}

    case call(state, "write_file", payload, @file_timeout_ms) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @impl true
  def edit_file(state, path, old_text, new_text) do
    with {:ok, content} <- read_file(state, path) do
      case occurrences(content, old_text) do
        1 ->
          updated = String.replace(content, old_text, new_text, global: false)

          with :ok <- write_file(state, path, updated),
               do: {:ok, %{occurrences: 1, content: updated}}

        count ->
          {:ok, %{occurrences: count, content: content}}
      end
    end
  end

  @impl true
  def exec(state, command, opts) do
    timeout = opts |> Keyword.get(:timeout, @exec_timeout_ms) |> min(@max_exec_timeout_ms)
    cwd = resolve(state, Keyword.get(opts, :cwd, state.cwd))
    command = with_env(command, Keyword.get(opts, :env, []))

    # The runner kills the command at its own timeout; wait a little longer for its answer.
    case call(
           state,
           "exec",
           %{"command" => command, "cwd" => cwd, "timeout_ms" => timeout},
           timeout + 15_000
         ) do
      {:ok, %{"timed_out" => true}} ->
        {:error, :timeout}

      {:ok, result} ->
        output = (result["stdout"] || "") <> (result["stderr"] || "")
        {:ok, %{output: output, exit_code: result["exit_code"] || -1}}

      error ->
        error
    end
  end

  @doc "Runs a display operation (screenshot, click, …) on the runner."
  def display(runner_id, run, op, payload),
    do: call(%{runner_id: runner_id, run: run}, op, payload, @file_timeout_ms)

  defp call(state, op, payload, timeout) do
    case Runners.call(state.runner_id, state.run, op, payload, timeout) do
      {:error, :timeout} -> {:error, "The runner did not answer. Check that it is on and online."}
      other -> other
    end
  end

  defp resolve(_state, "/" <> _ = path), do: path
  defp resolve(_state, "~" <> _ = path), do: path
  defp resolve(state, path), do: Path.join(state.cwd, path)

  defp occurrences(_content, ""), do: 0
  defp occurrences(content, text), do: length(:binary.matches(content, text))

  # The runner's shell starts with the person's own environment; layer the
  # tool's variables on top with a POSIX `export` prefix.
  defp with_env(command, []), do: command

  defp with_env(command, env) do
    exports =
      env
      |> Enum.filter(fn {key, _value} -> to_string(key) =~ ~r/\A[A-Za-z_][A-Za-z0-9_]*\z/ end)
      |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{shell_quote(value)}" end)

    if exports == "", do: command, else: "export #{exports}; #{command}"
  end

  defp shell_quote(value), do: "'" <> String.replace(to_string(value), "'", "'\\''") <> "'"
end
