defmodule TuistEx.Analytics.Args do
  @moduledoc false

  alias TuistEx.Analytics.Relay

  # Separates a Tuist task's own options from the arguments it forwards to the
  # Mix task it wraps. Everything it does not recognise is forwarded untouched
  # and in order, so `mix tuist.test` takes the same command line as
  # `mix test` and can be aliased in its place.

  @doc """
  Returns `{options, forwarded}`. `switches` maps each own option to
  `:string` or `:integer`; both `--name value` and `--name=value` are
  accepted. A `--` separator, which older versions required before the
  forwarded arguments, is dropped.
  """
  def split(args, switches) do
    names =
      Map.new(switches, fn {name, type} ->
        {"--" <> String.replace(Atom.to_string(name), "_", "-"), {name, type}}
      end)

    split(args, names, [], [])
  end

  @doc """
  Runs the Mix task a Tuist task wraps.

  When the project aliases that task to the Tuist one (`test: "tuist.test"`)
  and the Tuist task is invoked by its own name, `Mix.Task.run/2` follows the
  alias back to the task already running and does nothing. The wrapped task
  is then called directly.
  """
  def run_wrapped(task, module, args) do
    case Mix.Task.run(task, args) do
      :noop -> if Mix.Task.alias?(task), do: module.run(args), else: :noop
      result -> result
    end
  end

  @doc """
  Makes sure a task that needs the test environment runs in it.

  Mix picks the environment before it runs a task, from `MIX_ENV`, the
  project's `preferred_envs`, or the name typed on the command line (which is
  why `mix test`, and a `test` alias, need nothing). A Tuist task typed by its
  own name starts in `dev`, with `dev`'s dependencies loaded, and switching
  environment from inside the task does not undo that. So it starts over in a
  new process instead.

  Returns `:ok` when already in the environment, or `{:reexecuted, status}`
  with the exit status of the process that did the work.
  """
  def ensure_env(env, task, args) do
    if Mix.env() == env do
      :ok
    else
      mix =
        System.find_executable("mix") ||
          Mix.raise("Could not find the mix executable to run #{task}.")

      {_output, status} =
        System.cmd(mix, [task | args],
          env: [{"MIX_ENV", Atom.to_string(env)}],
          into: Relay.new(),
          stderr_to_stdout: true
        )

      {:reexecuted, status}
    end
  end

  defp split([], _names, options, forwarded), do: {Enum.reverse(options), Enum.reverse(forwarded)}

  defp split(["--" | rest], names, options, forwarded), do: split(rest, names, options, forwarded)

  defp split([arg | rest], names, options, forwarded) do
    case String.split(arg, "=", parts: 2) do
      [flag, value] when is_map_key(names, flag) ->
        split(rest, names, [option(names, flag, value) | options], forwarded)

      [flag] when is_map_key(names, flag) ->
        case rest do
          [value | rest] -> split(rest, names, [option(names, flag, value) | options], forwarded)
          [] -> Mix.raise("#{flag} expects a value")
        end

      _ ->
        split(rest, names, options, [arg | forwarded])
    end
  end

  defp option(names, flag, value) do
    case Map.fetch!(names, flag) do
      {name, :string} ->
        {name, value}

      {name, :integer} ->
        case Integer.parse(value) do
          {integer, ""} -> {name, integer}
          _ -> Mix.raise("#{flag} expects a number, got: #{value}")
        end
    end
  end
end
