defmodule Mix.Tasks.Tuist.Test do
  @shortdoc "Run mix test with Tuist analytics enabled"

  @moduledoc """
  Runs `mix test` with the Tuist analytics ExUnit formatter installed, then
  submits the test run to your Tuist dashboard.

      mix tuist.test [--url URL] [--project ACCOUNT/PROJECT] [-- ARGS...]

  All arguments after `--` are forwarded to `mix test`. The project handle is
  read from, in order:

    * `TUIST_PROJECT` (env)
    * `--project account/project`
    * `Mix.Project.config()[:tuist][:project]`

  Authentication reuses the credentials `mix tuist.login` stored, or the
  `TUIST_TOKEN` environment variable if set. A submission failure never
  changes the exit code of `mix test`.
  """

  use Mix.Task

  @formatter TuistEx.Analytics.ExUnitFormatter
  @preferred_cli_env :test

  def run(args) do
    ensure_test_env!()
    {options, test_args} = split_args(args)
    warn_if_formatter_override(test_args)
    configure(options)
    Mix.Task.run("test", test_args)
  end

  defp ensure_test_env! do
    if Mix.env() != :test do
      Mix.env(:test)
      Mix.Task.run("loadconfig")
    end

    :ok
  end

  defp warn_if_formatter_override(test_args) do
    if "--formatter" in test_args do
      Mix.shell().info(
        "warning: `--formatter` was forwarded to `mix test`; Mix replaces the formatter list, " <>
          "so Tuist analytics will not be submitted for this run."
      )
    end

    :ok
  end

  @doc false
  def configure(options) do
    Application.put_env(:ex_unit, :formatters, formatters(options))
    Application.put_env(:tuist_ex, :analytics_options, options)
    :ok
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
      Mix.raise("Usage: mix tuist.test [--url URL] [--project ACCOUNT/PROJECT] [-- ARGS...]")
    end

    opts
  end

  defp formatters(_options) do
    existing = Application.get_env(:ex_unit, :formatters, [ExUnit.CLIFormatter])

    if @formatter in existing do
      existing
    else
      existing ++ [@formatter]
    end
  end
end
