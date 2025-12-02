defmodule Runner.Runner.JobExecutor do
  @moduledoc """
  Orchestrates the execution of GitHub Actions jobs using the official runner.

  This module is responsible for:
  1. Registering with GitHub to get JIT configuration
  2. Ensuring the official runner binary is available
  3. Running the official runner with --jitconfig
  4. Cleaning up resources after job completion

  The official runner binary handles all the complex protocol details:
  session management, job polling, action execution, etc.
  """

  require Logger

  alias Runner.Runner.GitHub.{OfficialRunner, Registration}

  @runner_cache_dir "/tmp/github-actions-runner"

  @type job_config :: %{
          job_id: String.t(),
          github_org: String.t(),
          github_repo: String.t() | nil,
          labels: [String.t()],
          registration_token: String.t(),
          timeout_ms: integer() | nil
        }

  @type job_result :: %{
          result: :succeeded | :failed | :cancelled | :error,
          exit_code: integer(),
          error: term() | nil,
          duration_ms: integer()
        }

  @doc """
  Executes a job with full lifecycle management.

  Registers with GitHub, downloads the official runner if needed,
  and runs the job. Returns the job result.
  """
  @spec execute(job_config(), keyword()) :: {:ok, job_result()} | {:error, term()}
  def execute(job_config, opts \\ []) do
    base_work_dir = Keyword.get(opts, :base_work_dir, "/tmp/tuist-runner")
    work_dir = create_working_directory(base_work_dir, job_config.job_id)
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting job execution: #{job_config.job_id}")
    Logger.info("Working directory: #{work_dir}")

    try do
      result = do_execute(job_config, work_dir, opts)
      duration_ms = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, exit_code} ->
          {:ok,
           %{
             result: if(exit_code == 0, do: :succeeded, else: :failed),
             exit_code: exit_code,
             error: nil,
             duration_ms: duration_ms
           }}

        {:error, reason} ->
          {:ok,
           %{
             result: :error,
             exit_code: 1,
             error: reason,
             duration_ms: duration_ms
           }}
      end
    after
      cleanup_working_directory(work_dir)
    end
  end

  # Private functions

  defp do_execute(job_config, work_dir, _opts) do
    runner_name = generate_runner_name(job_config.job_id)

    # Step 1: Register with GitHub to get JIT configuration
    Logger.info("Registering runner with GitHub...")

    with {:ok, registration} <- register_runner(job_config, runner_name),
         encoded_jit_config <- registration.encoded_jit_config,
         true <- is_binary(encoded_jit_config) || {:error, :missing_jit_config},
         # Step 2: Ensure official runner binary is available
         {:ok, runner_dir} <- OfficialRunner.ensure_runner_available(@runner_cache_dir),
         # Step 3: Run the official runner with JIT config
         {:ok, exit_code} <- OfficialRunner.run_with_jitconfig(runner_dir, encoded_jit_config, work_dir) do
      {:ok, exit_code}
    end
  end

  defp register_runner(job_config, runner_name) do
    params = %{
      github_org: job_config.github_org,
      github_repo: job_config.github_repo,
      labels: job_config.labels,
      runner_name: runner_name
    }

    case Registration.register(job_config.registration_token, params) do
      {:ok, registration} ->
        Logger.info("Runner registered: #{registration.runner_id}")
        {:ok, registration}

      {:error, reason} ->
        Logger.error("Failed to register runner: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp generate_runner_name(job_id) do
    short_id = job_id |> String.slice(0, 8)
    "tuist-runner-#{short_id}-#{:rand.uniform(9999)}"
  end

  defp create_working_directory(base_dir, job_id) do
    work_dir = Path.join(base_dir, job_id)
    File.mkdir_p!(work_dir)
    Logger.info("Created working directory: #{work_dir}")
    work_dir
  end

  defp cleanup_working_directory(work_dir) do
    Logger.info("Cleaning up working directory: #{work_dir}")

    case File.rm_rf(work_dir) do
      {:ok, _} ->
        Logger.info("Working directory cleaned up")

      {:error, reason, file} ->
        Logger.warning("Failed to clean up #{file}: #{inspect(reason)}")
    end
  end
end
