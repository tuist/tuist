defmodule TuistEx.Analytics.Isolated do
  @moduledoc false

  # Runs analytics work in a process of its own. An exception in it, or a
  # server that never answers, ends that process and comes back as an error:
  # it never reaches the `mix test` or `mix compile` being instrumented.

  @doc """
  Returns what `fun` returns, or `{:error, reason}` when it raises, exits or
  takes longer than `timeout` milliseconds.
  """
  def run(fun, timeout) do
    {pid, ref} = spawn_monitor(fn -> exit({:shutdown, {:result, fun.()}}) end)

    receive do
      {:DOWN, ^ref, :process, ^pid, {:shutdown, {:result, result}}} -> result
      {:DOWN, ^ref, :process, ^pid, reason} -> {:error, reason}
    after
      timeout ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> {:error, :timeout}
        end
    end
  end
end
