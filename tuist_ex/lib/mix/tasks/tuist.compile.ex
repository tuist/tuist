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

  alias TuistEx.Analytics.Args
  alias TuistEx.Analytics.CompileProfile
  alias TuistEx.Analytics.CompileReporter
  alias TuistEx.Analytics.Isolated

  def run(args) do
    {options, compile_args} = split_args(args)

    # When `mix tuist.test` triggers this compile, its `--url` and `--project`
    # apply here too. Its options are read, never replaced: they also carry
    # how the test run is to be reported.
    inherited =
      Keyword.take(Application.get_env(:tuist_ex, :analytics_options, []), [:url, :project])

    options = Keyword.merge(inherited, options)
    {:ok, reporter} = CompileReporter.start(options)

    # The per-file compiling/waiting split only exists in the compiler's
    # profile output, so turn it on. The lines stay hidden unless the user
    # asked for them.
    user_profile? = "--profile" in compile_args
    compile_args = if user_profile?, do: compile_args, else: compile_args ++ ["--profile", "time"]
    profile = CompileProfile.new()
    installation = CompileProfile.install(profile, user_profile?)
    code_path = :code.get_path()

    try do
      for compiler <- Enum.uniq(Mix.Task.Compiler.compilers() ++ [:elixir, :app]) do
        Mix.Task.Compiler.after_compiler(compiler, fn result ->
          CompileProfile.compiler_finished(profile, compiler)
          # Every compiler: when an earlier one fails (Erlang sources, a custom
          # compiler), the later ones never run, and theirs would be the only
          # record that the build failed.
          CompileReporter.record(reporter, compiler, result)
          result
        end)
      end

      result = Args.run_wrapped("compile", Mix.Tasks.Compile, compile_args)

      # An umbrella's apps compile as projects of their own, where the hooks
      # above are not registered. The root returns what they did, merged, but
      # says `:ok` even when none of them compiled anything: whether one did
      # is left to the files the compiler profiled.
      if Mix.Project.umbrella?(), do: record_umbrella(reporter, result)

      result
    catch
      # A failed compile raises. Without this an umbrella's would go
      # unreported, since its apps' compilers never reached the hooks. An
      # umbrella app that fails also leaves the code paths it pruned out,
      # this package's and the ones it reports with among them.
      kind, reason ->
        Code.prepend_paths(code_path -- :code.get_path())
        CompileReporter.record(reporter, :compile, {:error, []})
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      CompileProfile.uninstall(installation)
      {files, steps} = profile_results(profile)
      CompileProfile.delete(profile)
      CompileReporter.finish(reporter, files, steps)
    end
  end

  defp record_umbrella(reporter, {status, diagnostics}) do
    status = if status == :error, do: :error, else: :noop
    CompileReporter.record(reporter, :compile, {status, diagnostics})
  end

  # `:noop` when compile had already run in this invocation.
  defp record_umbrella(_reporter, _result), do: :ok

  # Reading the profile is analytics work like any other: if it fails, the
  # build is still reported, only without its per-file detail.
  defp profile_results(profile) do
    case Isolated.run(
           fn -> {CompileProfile.files(profile), CompileProfile.steps(profile)} end,
           30_000
         ) do
      {files, steps} when is_list(files) and is_list(steps) -> {files, steps}
      _ -> {[], []}
    end
  end

  @doc """
  Splits the task's own options from the arguments meant for `mix compile`.
  A `--` separator is accepted for compatibility and dropped.
  """
  def split_args(args), do: Args.split(args, url: :string, project: :string)
end
