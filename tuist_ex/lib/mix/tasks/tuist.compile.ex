defmodule Mix.Tasks.Tuist.Compile do
  @shortdoc "Run mix compile with Tuist analytics enabled"

  @moduledoc """
  Runs `mix compile` with the Tuist analytics compile reporter attached and
  submits the resulting build to your Tuist dashboard.

      mix tuist.compile [--url URL] [--project ACCOUNT/PROJECT] [-- ARGS...]

  Everything after `--` is forwarded to `mix compile`. The project handle,
  URL, and authentication follow the same precedence as `mix tuist.test` and
  `mix tuist.login`.

  A submission failure never changes the exit code of `mix compile`; set
  `TUIST_DEBUG=1` to surface the reason on standard error.
  """

  use Mix.Task

  alias TuistEx.Analytics.CompileReporter

  def run(args) do
    {options, compile_args} = split_args(args)

    Application.put_env(:tuist_ex, :analytics_options, options)
    {:ok, _pid} = ensure_reporter_started(options)

    try do
      Mix.Task.Compiler.after_compiler(:elixir, fn result ->
        CompileReporter.record(:elixir, result)
        result
      end)

      Mix.Task.Compiler.after_compiler(:app, fn result ->
        CompileReporter.record(:app, result)
        result
      end)

      Mix.Task.run("compile", compile_args)
    after
      CompileReporter.finish()
    end
  end

  @doc false
  def split_args(args) do
    case Enum.split_while(args, &(&1 != "--")) do
      {left, []} -> {parse_options(left), []}
      {left, ["--" | right]} -> {parse_options(left), right}
    end
  end

  defp parse_options(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [url: :string, project: :string])

    if rest != [] or invalid != [] do
      Mix.raise("Usage: mix tuist.compile [--url URL] [--project ACCOUNT/PROJECT] [-- ARGS...]")
    end

    opts
  end

  defp ensure_reporter_started(options) do
    case CompileReporter.start_link(options) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end
end
