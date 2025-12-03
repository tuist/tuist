defmodule Tuist.Runners.Workers.CleanupRunnerWorker do
  @moduledoc """
  Background job for cleaning up runners after job completion.

  This worker handles cleanup when a bare metal runner job finishes.

  ## Responsibilities

  1. Execute cleanup script on host via SSH (remove runner, clean workspace)
  2. Transition job status through cleanup → completed/failed
  3. Log cleanup metrics for monitoring

  ## Error Handling

  - Retries cleanup on SSH failure (up to 5 attempts)
  - Marks job as failed after max retries with error message
  - Logs errors for alerting on persistent failures
  """
  use Oban.Worker, queue: :runners, max_attempts: 5

  alias Tuist.Runners
  alias Tuist.Runners.RunnerJob
  alias Tuist.SSHClient

  require Logger

  @cleanup_timeout 120_000
  @ssh_connection_timeout 30_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}, attempt: attempt, max_attempts: max_attempts}) do
    start_time = System.monotonic_time(:millisecond)

    case Runners.get_runner_job_with_host(job_id) do
      nil ->
        Logger.error("CleanupRunnerWorker: Job #{job_id} not found")
        {:error, :job_not_found}

      %RunnerJob{status: status} when status in [:completed, :failed, :cancelled] ->
        Logger.info("CleanupRunnerWorker: Job #{job_id} already in terminal state: #{status}")
        :ok

      %RunnerJob{host: nil} = job ->
        Logger.warning("CleanupRunnerWorker: Job #{job_id} has no host assigned, marking as completed")
        mark_job_completed_no_cleanup(job, start_time)

      job ->
        perform_cleanup(job, attempt, max_attempts, start_time)
    end
  end

  defp perform_cleanup(job, attempt, max_attempts, start_time) do
    job_id = job.id

    with {:ok, job} <- transition_to_cleanup(job),
         :ok <- execute_cleanup_script(job) do
      mark_job_completed(job, start_time)
    else
      {:error, :already_in_cleanup} ->
        case execute_cleanup_script(job) do
          :ok -> mark_job_completed(job, start_time)
          {:error, reason} -> handle_cleanup_failure(job, reason, attempt, max_attempts, start_time)
        end

      {:error, :invalid_transition} ->
        Logger.warning("CleanupRunnerWorker: Job #{job_id} cannot transition to cleanup from #{job.status}")
        :ok

      {:error, reason} ->
        handle_cleanup_failure(job, reason, attempt, max_attempts, start_time)
    end
  end

  defp transition_to_cleanup(%RunnerJob{status: :cleanup}), do: {:error, :already_in_cleanup}

  defp transition_to_cleanup(job) do
    case Runners.update_runner_job(job, %{status: :cleanup}) do
      {:ok, updated_job} ->
        Logger.info("CleanupRunnerWorker: Job #{job.id} transitioned to cleanup state")
        {:ok, updated_job}

      {:error, changeset} ->
        Logger.error("CleanupRunnerWorker: Failed to transition job #{job.id} to cleanup: #{inspect(changeset.errors)}")

        {:error, :invalid_transition}
    end
  end

  defp execute_cleanup_script(job) do
    host = job.host
    runner_name = job.github_runner_name

    Logger.info("CleanupRunnerWorker: Executing cleanup for runner #{runner_name} on host #{host.name} (#{host.ip})")

    ssh_opts = build_ssh_opts()

    case SSHClient.connect(String.to_charlist(host.ip), host.ssh_port, ssh_opts) do
      {:ok, connection} ->
        result = run_cleanup_command(connection, runner_name, job.id)
        SSHClient.close(connection)
        result

      {:error, reason} ->
        Logger.error("CleanupRunnerWorker: SSH connection failed to #{host.ip}: #{inspect(reason)}")
        {:error, {:ssh_connection_failed, reason}}
    end
  end

  defp run_cleanup_command(connection, runner_name, job_id) do
    cleanup_command = build_cleanup_command(runner_name)

    case SSHClient.run_command(connection, cleanup_command, @cleanup_timeout) do
      {:ok, output} ->
        Logger.info("CleanupRunnerWorker: Cleanup completed for job #{job_id}, output: #{String.slice(output, 0, 500)}")
        :ok

      {:error, reason} ->
        Logger.error("CleanupRunnerWorker: Cleanup command failed for job #{job_id}: #{inspect(reason)}")
        {:error, {:cleanup_command_failed, reason}}
    end
  end

  defp build_cleanup_command(runner_name) do
    # Remove the runner directory and clean up any leftover processes.
    # The runner is installed in ~/actions-runner-{runner_name}
    """
    pkill -f 'actions-runner-#{runner_name}' 2>/dev/null || true; \
    rm -rf ~/actions-runner-#{runner_name} 2>/dev/null || true
    """
  end

  defp build_ssh_opts do
    ssh_user =
      Tuist.Environment.runners_ssh_user()
      |> String.to_charlist()

    # Get SSH private key from secrets
    private_key = Tuist.Environment.runners_ssh_private_key()

    if is_nil(private_key) do
      raise "SSH private key not configured. Please set TUIST_RUNNERS_SSH_PRIVATE_KEY or runners.ssh_private_key in secrets."
    end

    # Write private key to a temporary directory for this SSH session
    {user_dir, _key_path} = write_temp_ssh_key(private_key)

    [
      user: ssh_user,
      silently_accept_hosts: true,
      auth_methods: ~c"publickey",
      user_interaction: false,
      user_dir: String.to_charlist(user_dir),
      connect_timeout: @ssh_connection_timeout
    ]
  end

  defp write_temp_ssh_key(private_key) do
    # Create a unique temporary directory for this SSH session
    # This ensures each connection has its own isolated key
    session_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    temp_dir = Path.join([System.tmp_dir!(), "tuist_runners_ssh", session_id])
    File.mkdir_p!(temp_dir)

    # Write the private key to a temporary file
    # Use id_ed25519 since the key is an Ed25519 key in OpenSSH format
    key_path = Path.join(temp_dir, "id_ed25519")
    File.write!(key_path, private_key)
    File.chmod!(key_path, 0o600)

    {temp_dir, key_path}
  end

  defp mark_job_completed(job, start_time) do
    duration_ms = System.monotonic_time(:millisecond) - start_time

    case Runners.update_runner_job(job, %{status: :completed, completed_at: DateTime.utc_now()}) do
      {:ok, _updated_job} ->
        log_cleanup_metrics(job.id, :success, duration_ms)
        Logger.info("CleanupRunnerWorker: Job #{job.id} marked as completed (#{duration_ms}ms)")
        :ok

      {:error, changeset} ->
        Logger.error("CleanupRunnerWorker: Failed to mark job #{job.id} as completed: #{inspect(changeset.errors)}")

        {:error, :status_update_failed}
    end
  end

  defp handle_cleanup_failure(job, reason, attempt, max_attempts, start_time) do
    duration_ms = System.monotonic_time(:millisecond) - start_time
    error_message = format_error_message(reason)

    if attempt >= max_attempts do
      Logger.error("CleanupRunnerWorker: Max retries reached for job #{job.id}, marking as failed: #{error_message}")

      case Runners.update_runner_job(job, %{
             status: :failed,
             completed_at: DateTime.utc_now(),
             error_message: "Cleanup failed after #{max_attempts} attempts: #{error_message}"
           }) do
        {:ok, _} ->
          log_cleanup_metrics(job.id, :failed, duration_ms)
          :ok

        {:error, changeset} ->
          Logger.error("CleanupRunnerWorker: Failed to mark job #{job.id} as failed: #{inspect(changeset.errors)}")

          :ok
      end
    else
      log_cleanup_metrics(job.id, :retry, duration_ms)

      Logger.warning(
        "CleanupRunnerWorker: Cleanup failed for job #{job.id} (attempt #{attempt}/#{max_attempts}): #{error_message}"
      )

      {:error, reason}
    end
  end

  defp format_error_message({:ssh_connection_failed, reason}), do: "SSH connection failed: #{inspect(reason)}"
  defp format_error_message({:cleanup_command_failed, reason}), do: "Cleanup command failed: #{inspect(reason)}"
  defp format_error_message(reason), do: inspect(reason)

  defp log_cleanup_metrics(job_id, status, duration_ms) do
    Logger.info("CleanupRunnerWorker: metrics job_id=#{job_id} status=#{status} duration_ms=#{duration_ms}")
  end

  defp mark_job_completed_no_cleanup(job, start_time) do
    duration_ms = System.monotonic_time(:millisecond) - start_time

    with {:ok, job} <- Runners.update_runner_job(job, %{status: :cleanup}),
         {:ok, _updated_job} <- Runners.update_runner_job(job, %{status: :completed, completed_at: DateTime.utc_now()}) do
      log_cleanup_metrics(job.id, :success, duration_ms)
      Logger.info("CleanupRunnerWorker: Job #{job.id} marked as completed (no cleanup needed, #{duration_ms}ms)")
      :ok
    else
      {:error, changeset} ->
        Logger.error("CleanupRunnerWorker: Failed to mark job #{job.id} as completed: #{inspect(changeset.errors)}")

        {:error, :status_update_failed}
    end
  end
end
