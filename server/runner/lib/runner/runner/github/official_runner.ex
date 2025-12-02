defmodule Runner.Runner.GitHub.OfficialRunner do
  @moduledoc """
  Manages the official GitHub Actions runner binary.

  This module handles downloading, extracting, and executing the official
  GitHub Actions runner binary. Instead of reimplementing the entire runner
  protocol, we use the official binary which handles all actions, environment
  setup, and job execution natively.

  The runner is started with `--jitconfig` which passes the JIT configuration
  obtained from the GitHub API registration endpoint.
  """

  require Logger

  # Note: Check https://github.com/actions/runner/releases for latest version
  # GitHub deprecates old runner versions, so this may need updating periodically
  @runner_version "2.330.0"
  @download_base_url "https://github.com/actions/runner/releases/download"

  @doc """
  Ensures the runner binary is available, downloading if necessary.

  Returns the path to the runner directory.
  """
  @spec ensure_runner_available(String.t()) :: {:ok, String.t()} | {:error, term()}
  def ensure_runner_available(base_dir) do
    runner_dir = Path.join(base_dir, "actions-runner-#{@runner_version}")
    run_script = Path.join(runner_dir, "run.sh")

    if File.exists?(run_script) do
      Logger.info("Runner binary already available at #{runner_dir}")
      {:ok, runner_dir}
    else
      download_and_extract(runner_dir)
    end
  end

  @doc """
  Runs a job using the official runner binary with JIT configuration.

  The JIT config is the base64-encoded configuration returned by GitHub's
  `generate-jitconfig` API endpoint.
  """
  @spec run_with_jitconfig(String.t(), String.t(), String.t()) ::
          {:ok, integer()} | {:error, term()}
  def run_with_jitconfig(runner_dir, encoded_jit_config, work_dir) do
    run_script = Path.join(runner_dir, "run.sh")

    unless File.exists?(run_script) do
      {:error, :runner_not_found}
    else
      # Ensure work directory exists
      File.mkdir_p!(work_dir)

      Logger.info("Starting official runner with JIT config")
      Logger.debug("Runner dir: #{runner_dir}")
      Logger.debug("Work dir: #{work_dir}")

      # The runner needs to be executed from its own directory
      # and will use the work directory for job execution
      args = ["--jitconfig", encoded_jit_config]

      # Set up environment for the runner
      # Port.open expects env as list of {'VAR', 'value'} charlists
      env = [
        {~c"RUNNER_WORK_FOLDER", String.to_charlist(work_dir)},
        {~c"RUNNER_TEMP", String.to_charlist(Path.join(work_dir, "_temp"))},
        {~c"RUNNER_TOOL_CACHE", String.to_charlist(Path.join(work_dir, "_tool"))}
      ]

      Logger.info("Executing: #{run_script} #{Enum.join(args, " ")}")

      # Use Port for better control over the process
      port = Port.open(
        {:spawn_executable, run_script},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:args, args},
          {:cd, String.to_charlist(runner_dir)},
          {:env, env}
        ]
      )

      collect_output(port, [])
    end
  end

  # Private functions

  defp download_and_extract(runner_dir) do
    {os, arch} = detect_platform()
    filename = "actions-runner-#{os}-#{arch}-#{@runner_version}.tar.gz"
    url = "#{@download_base_url}/v#{@runner_version}/#{filename}"

    Logger.info("Downloading runner from #{url}")

    # Create parent directory
    File.mkdir_p!(Path.dirname(runner_dir))

    # Download to temp file
    temp_file = Path.join(System.tmp_dir!(), filename)

    case download_file(url, temp_file) do
      :ok ->
        Logger.info("Extracting runner to #{runner_dir}")
        File.mkdir_p!(runner_dir)

        case System.cmd("tar", ["-xzf", temp_file, "-C", runner_dir], stderr_to_stdout: true) do
          {_, 0} ->
            # Clean up temp file
            File.rm(temp_file)

            # Make run.sh executable
            run_script = Path.join(runner_dir, "run.sh")
            File.chmod(run_script, 0o755)

            Logger.info("Runner extracted successfully")
            {:ok, runner_dir}

          {output, code} ->
            Logger.error("Failed to extract runner (#{code}): #{output}")
            {:error, {:extract_failed, code, output}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp download_file(url, dest) do
    Logger.info("Downloading #{url} to #{dest}")

    case Req.get(url, into: File.stream!(dest), receive_timeout: 300_000) do
      {:ok, %Req.Response{status: 200}} ->
        Logger.info("Download complete")
        :ok

      {:ok, %Req.Response{status: status}} ->
        Logger.error("Download failed with status #{status}")
        {:error, {:download_failed, status}}

      {:error, reason} ->
        Logger.error("Download failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp detect_platform do
    os = case :os.type() do
      {:unix, :darwin} -> "osx"
      {:unix, :linux} -> "linux"
      {:win32, _} -> "win"
      _ -> "linux"
    end

    arch = case :erlang.system_info(:system_architecture) |> to_string() do
      "aarch64" <> _ -> "arm64"
      "arm64" <> _ -> "arm64"
      "x86_64" <> _ -> "x64"
      "amd64" <> _ -> "x64"
      _ -> "x64"
    end

    {os, arch}
  end

  defp collect_output(port, acc) do
    receive do
      {^port, {:data, data}} ->
        # Log output in real-time
        String.split(data, "\n", trim: true)
        |> Enum.each(&Logger.info("Runner: #{&1}"))

        collect_output(port, [data | acc])

      {^port, {:exit_status, status}} ->
        _output = acc |> Enum.reverse() |> Enum.join()
        Logger.info("Runner exited with status #{status}")
        {:ok, status}

    after
      # 1 hour timeout for job execution
      3_600_000 ->
        Port.close(port)
        {:error, :timeout}
    end
  end
end
