defmodule Runner.Commands.Start do
  @moduledoc """
  Start subcommand for running the GitHub Actions runner service.

  This command establishes a persistent connection to the Tuist server
  and listens for job assignments. When a job is received, it registers
  with GitHub, polls for the job, executes it, and reports the result.
  """

  require Logger

  alias Runner.Runner.Connection

  @default_work_dir "/tmp/tuist-runner"

  def run(args) do
    case parse_args(args) do
      {:ok, params} ->
        start_runner(params)

      {:error, :help} ->
        print_help()
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        print_help()
        {:error, reason}
    end
  end

  defp parse_args(args) do
    {switches, _, _} =
      OptionParser.parse(args,
        switches: [
          server_url: :string,
          token: :string,
          work_dir: :string,
          help: :boolean
        ],
        aliases: [
          s: :server_url,
          t: :token,
          w: :work_dir,
          h: :help
        ]
      )

    if switches[:help] do
      {:error, :help}
    else
      validate_params(switches)
    end
  end

  defp validate_params(switches) do
    required_keys = [:server_url, :token]
    missing_keys = required_keys -- Keyword.keys(switches)

    if missing_keys == [] do
      {:ok,
       %{
         server_url: switches[:server_url],
         token: switches[:token],
         work_dir: switches[:work_dir] || @default_work_dir
       }}
    else
      {:error, "Missing required parameters: #{Enum.join(missing_keys, ", ")}"}
    end
  end

  defp start_runner(params) do
    Logger.info("Starting Tuist Runner")
    Logger.info("Server URL: #{params.server_url}")
    Logger.info("Work directory: #{params.work_dir}")

    # Ensure work directory exists
    File.mkdir_p!(params.work_dir)

    # Trap exits for graceful shutdown
    Process.flag(:trap_exit, true)

    case Connection.start_link(
           server_url: params.server_url,
           token: params.token,
           base_work_dir: params.work_dir
         ) do
      {:ok, pid} ->
        Logger.info("Runner connected and waiting for jobs")
        wait_for_shutdown(pid)

      {:error, reason} ->
        Logger.error("Failed to start runner: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp wait_for_shutdown(pid) do
    receive do
      {:EXIT, ^pid, :normal} ->
        Logger.info("Runner stopped normally")
        :ok

      {:EXIT, ^pid, reason} ->
        Logger.error("Runner stopped unexpectedly: #{inspect(reason)}")
        {:error, reason}

      :shutdown ->
        Logger.info("Received shutdown signal")
        Process.exit(pid, :shutdown)
        wait_for_shutdown(pid)
    end
  end

  defp print_help do
    IO.puts("""
    Start Command - Run the GitHub Actions runner service

    Usage:
      runner start [options]

    Required Options:
      --server-url, -s <url>    Tuist server URL
      --token, -t <token>       Runner authentication token

    Optional:
      --work-dir, -w <path>     Base directory for job working directories
                                (default: /tmp/tuist-runner)
      --help, -h                Show this help message

    Description:
      This command starts a persistent connection to the Tuist server and
      waits for GitHub Actions job assignments. When a job is received,
      the runner:

      1. Registers with GitHub using the provided registration token
      2. Creates a session with the GitHub Actions Broker API
      3. Polls for the job details
      4. Executes the job steps
      5. Reports results back to the Tuist server
      6. Cleans up the working directory

      The runner handles one job at a time and automatically reconnects
      if the connection to the server is lost.

    Example:
      runner start --server-url https://cloud.tuist.io --token my-runner-token

      runner start -s https://cloud.tuist.io -t my-token -w /var/runner/work
    """)
  end
end
