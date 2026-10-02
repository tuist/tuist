defmodule Mix.Tasks.Tuist.Compile do
  @shortdoc "Run mix compile with Tuist analytics enabled"

  @moduledoc """
  Runs `mix compile` with the Tuist analytics compile reporter attached and
  submits the resulting build to your Tuist dashboard.

      mix tuist.compile [--url URL] [--project ACCOUNT/PROJECT] [ARGS...]

  Every other argument is forwarded to `mix compile` as is, so the task can
  stand in for it. Alias it in your `mix.exs` and every compile reports to
  Tuist, including the ones `mix test` or `mix phx.server` trigger:

      def project do
        [aliases: [compile: "tuist.compile"]]
      end

  The project handle, URL, and authentication follow the same precedence as
  `mix tuist.test` and `mix tuist.login`.

  A submission failure never changes the exit code of `mix compile`; set
  `TUIST_DEBUG=1` to surface the reason on standard error.
  """

  use Mix.Task

  alias TuistEx.Analytics.CompileProfile
  alias TuistEx.Analytics.CompileReporter

  def run(args) do
    {options, compile_args} = split_args(args)

    # When `mix tuist.test` triggers this compile, its `--url` and `--project`
    # apply here too. Its options are read, never replaced: they also carry
    # how the test run is to be reported.
    inherited =
      Keyword.take(Application.get_env(:tuist_ex, :analytics_options, []), [:url, :project])

    options = Keyword.merge(inherited, options)
    {:ok, _pid} = ensure_reporter_started(options)

    # The per-file compiling/waiting split only exists in the compiler's
    # profile output, so turn it on. The lines stay hidden unless the user
    # asked for them.
    user_profile? = "--profile" in compile_args
    compile_args = if user_profile?, do: compile_args, else: compile_args ++ ["--profile", "time"]
    profile = CompileProfile.start(user_profile?)

    try do
      for compiler <- Enum.uniq(Mix.Task.Compiler.compilers() ++ [:elixir, :app]) do
        Mix.Task.Compiler.after_compiler(compiler, fn result ->
          CompileProfile.compiler_finished(compiler)
          # Every compiler: when an earlier one fails (Erlang sources, a custom
          # compiler), the later ones never run, and theirs would be the only
          # record that the build failed.
          CompileReporter.record(compiler, result)
          result
        end)
      end

      TuistEx.Analytics.Args.run_wrapped("compile", Mix.Tasks.Compile, compile_args)
    after
      steps = CompileProfile.steps()
      CompileReporter.finish(CompileProfile.stop(profile), steps)
    end
  end

  @doc """
  Splits the task's own options from the arguments meant for `mix compile`.
  A `--` separator is accepted for compatibility and dropped.
  """
  def split_args(args), do: TuistEx.Analytics.Args.split(args, url: :string, project: :string)

  defp ensure_reporter_started(options) do
    case CompileReporter.start_link(options) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end
end
