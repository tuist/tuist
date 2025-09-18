defmodule Runner do
  @moduledoc """
  Main entry point for the Tuist Runner CLI.

  This module handles subcommand routing for various Tuist automation tasks.
  """

  use Application

  def start(_type, _args) do
    case parse_args() do
      {:ok, command, args} ->
        result = execute_command(command, args)

        case result do
          :ok ->
            System.halt(0)

          {:error, reason} ->
            IO.puts(:stderr, "Runner failed with the following error: #{inspect(reason)}")
            System.halt(1)
        end

      {:error, :help} ->
        print_help()
        System.halt(0)

      {:error, reason} ->
        IO.puts("Error: #{reason}")
        print_help()
        System.halt(1)
    end
  end

  defp parse_args do
    argv = Burrito.Util.Args.get_arguments()

    case argv do
      [] ->
        {:error, :help}

      [command | rest] ->
        case command do
          "qa" -> {:ok, :qa, rest}
          "--help" -> {:error, :help}
          "-h" -> {:error, :help}
          _ -> {:error, "Unknown command: #{command}"}
        end
    end
  end

  defp execute_command(:qa, args) do
    Runner.Commands.QA.run(args)
  end

  defp print_help do
    IO.puts("""
    Tuist Runner CLI

    Usage:
      runner <command> [options]

    Commands:
      qa    Run AI-powered QA tests on iOS app previews

    Options:
      --help, -h    Show this help message

    For command-specific help:
      runner qa --help

    Examples:
      runner qa --preview-url <url> --bundle-identifier <id> --server-url <url> \\
                --run-id <id> --auth-token <token> --account-handle <handle> \\
                --launch-arguments <arguments> --app-description <description> \\
                --project-handle <handle> --prompt "<prompt>" --anthropic-api-key <key>
    """)
  end
end
