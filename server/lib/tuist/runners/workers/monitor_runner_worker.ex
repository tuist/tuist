defmodule Tuist.Runners.Workers.MonitorRunnerWorker do
  @moduledoc """
  Background job for monitoring bare metal runners and triggering cleanup.

  This worker polls the host via SSH to check if the GitHub Actions runner
  process is still running. When the runner exits (or times out), it enqueues cleanup.

  ## Responsibilities

  1. Poll runner process status via SSH (check Runner.Listener process)
  2. Re-enqueue self with delay if still running
  3. When runner exits, trigger cleanup
  4. Enforce max job duration timeout for hanging jobs

  ## Configuration

  - Poll interval: 30 seconds
  - Max job duration: 6 hours (configurable)
  """
  use Oban.Worker, queue: :runners, max_attempts: 3

  alias Tuist.Runners
  alias Tuist.Runners.RunnerJob
  alias Tuist.Runners.Workers.CleanupRunnerWorker
  alias Tuist.SSHClient

  require Logger

  @poll_interval_seconds 30
  @max_job_duration_hours 6
  @ssh_connection_timeout 30_000
  @command_timeout 30_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id} = args}) do
    started_at = Map.get(args, "started_at")

    case Runners.get_runner_job_with_host(job_id) do
      nil ->
        Logger.error("MonitorRunnerWorker: Job #{job_id} not found")
        {:error, :job_not_found}

      %RunnerJob{status: status} when status in [:completed, :failed, :cancelled] ->
        Logger.info("MonitorRunnerWorker: Job #{job_id} already in terminal state: #{status}")
        :ok

      %RunnerJob{status: status} when status not in [:running, :spawning] ->
        Logger.warning("MonitorRunnerWorker: Job #{job_id} in unexpected state: #{status}")
        :ok

      %RunnerJob{host: nil} = job ->
        Logger.warning("MonitorRunnerWorker: Job #{job_id} has no host assigned")
        enqueue_cleanup(job)

      job ->
        monitor_job(job, started_at)
    end
  end

  defp monitor_job(job, started_at) do
    started_at = started_at || DateTime.to_iso8601(DateTime.utc_now())

    if job_timed_out?(started_at) do
      handle_timeout(job)
    else
      check_runner_status(job, started_at)
    end
  end

  defp job_timed_out?(started_at) do
    case DateTime.from_iso8601(started_at) do
      {:ok, start_time, _} ->
        max_duration_seconds = @max_job_duration_hours * 3600
        elapsed = DateTime.diff(DateTime.utc_now(), start_time, :second)
        elapsed >= max_duration_seconds

      _ ->
        false
    end
  end

  defp handle_timeout(job) do
    Logger.warning(
      "MonitorRunnerWorker: Job #{job.id} exceeded max duration of #{@max_job_duration_hours} hours, triggering cleanup"
    )

    case Runners.update_runner_job(job, %{
           error_message: "Job exceeded maximum duration of #{@max_job_duration_hours} hours"
         }) do
      {:ok, updated_job} ->
        enqueue_cleanup(updated_job)

      {:error, _changeset} ->
        enqueue_cleanup(job)
    end
  end

  defp check_runner_status(job, started_at) do
    host = job.host
    runner_name = job.github_runner_name

    Logger.debug("MonitorRunnerWorker: Checking runner process on host #{host.name} for runner #{runner_name}")

    case check_runner_process(host, runner_name) do
      {:ok, :running} ->
        Logger.debug("MonitorRunnerWorker: Runner still active for job #{job.id}, re-enqueueing")
        reschedule_monitor(job.id, started_at)

      {:ok, :not_running} ->
        Logger.info("MonitorRunnerWorker: Runner finished for job #{job.id}, triggering cleanup")
        enqueue_cleanup(job)

      {:error, reason} ->
        Logger.warning("MonitorRunnerWorker: Failed to check runner status for job #{job.id}: #{inspect(reason)}")
        reschedule_monitor(job.id, started_at)
    end
  end

  defp check_runner_process(host, runner_name) do
    ssh_opts = build_ssh_opts(host)

    case SSHClient.connect(String.to_charlist(host.ip), host.ssh_port, ssh_opts) do
      {:ok, connection} ->
        result = run_status_check(connection, runner_name)
        SSHClient.close(connection)
        result

      {:error, reason} ->
        Logger.error("MonitorRunnerWorker: SSH connection failed to #{host.ip}: #{inspect(reason)}")
        {:error, {:ssh_connection_failed, reason}}
    end
  end

  defp run_status_check(connection, runner_name) do
    check_command = build_status_check_command(runner_name)

    case SSHClient.run_command(connection, check_command, @command_timeout) do
      {:ok, output} ->
        parse_status_output(output)

      {:error, reason} ->
        {:error, {:status_check_failed, reason}}
    end
  end

  defp build_status_check_command(runner_name) do
    # Check if the GitHub Actions Runner.Listener process is running for this runner.
    # The runner runs as a dotnet process with Runner.Listener as the entry point.
    # We check for the runner's working directory in the process command line.
    "pgrep -f 'Runner.Listener.*#{runner_name}' > /dev/null && echo 'running' || echo 'not_running'"
  end

  defp parse_status_output(output) do
    case String.trim(output) do
      "running" -> {:ok, :running}
      "not_running" -> {:ok, :not_running}
      other -> {:error, {:unexpected_output, other}}
    end
  end

  defp build_ssh_opts(_host) do
    ssh_user =
      Tuist.Environment.runners_ssh_user()
      |> String.to_charlist()

    # Get SSH private key from secrets
    private_key = Tuist.Environment.runners_ssh_private_key()

    if is_nil(private_key) do
      raise "SSH private key not configured. Please set TUIST_RUNNERS_SSH_PRIVATE_KEY or runners.ssh_private_key in secrets."
    end

    # Write private key to a temporary file for this SSH session
    key_path = write_temp_ssh_key(private_key)

    [
      user: ssh_user,
      silently_accept_hosts: true,
      auth_methods: ~c"publickey",
      user_interaction: false,
      user_dir: String.to_charlist(Path.dirname(key_path)),
      key_cb: {Tuist.Runners.SSHKeyCallback, key_file: String.to_charlist(key_path)},
      connect_timeout: @ssh_connection_timeout
    ]
  end

  defp write_temp_ssh_key(private_key) do
    # Create a temporary directory for SSH keys if it doesn't exist
    temp_dir = System.tmp_dir!() |> Path.join("tuist_runners_ssh")
    File.mkdir_p!(temp_dir)

    # Write the private key to a temporary file
    # Use id_ed25519 since the key is an Ed25519 key in OpenSSH format
    key_path = Path.join(temp_dir, "id_ed25519")
    File.write!(key_path, private_key)
    File.chmod!(key_path, 0o600)

    key_path
  end

  defp reschedule_monitor(job_id, started_at) do
    %{job_id: job_id, started_at: started_at}
    |> __MODULE__.new(schedule_in: @poll_interval_seconds)
    |> Oban.insert()

    :ok
  end

  defp enqueue_cleanup(job) do
    %{job_id: job.id}
    |> CleanupRunnerWorker.new()
    |> Oban.insert()

    :ok
  end
end
