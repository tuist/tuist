defmodule TuistEx.Analytics.Subprocess do
  @moduledoc false

  # Runs a command that writes straight to this process's standard input,
  # output and error, as if it had been started from the shell. `System.cmd/3`
  # cannot: it reads the command's output through a pipe, in byte chunks that
  # can end in the middle of a UTF-8 character, and writing such a chunk to a
  # unicode device raises. With `:nouse_stdio` the port talks to the command
  # over file descriptors 3 and 4 instead, so the command inherits the
  # terminal, sees it as one (colors), and keeps standard error apart.

  @doc """
  Runs `executable` with `args` and `env` (a list of `{name, value}` string
  pairs added to the environment) and returns its exit status.
  """
  def run(executable, args, env) do
    port =
      Port.open({:spawn_executable, executable}, [
        :nouse_stdio,
        :exit_status,
        args: args,
        env:
          Enum.map(env, fn {name, value} ->
            {String.to_charlist(name), String.to_charlist(value)}
          end)
      ])

    receive do
      {^port, {:exit_status, status}} -> status
    end
  end
end
