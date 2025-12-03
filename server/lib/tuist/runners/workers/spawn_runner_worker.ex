defmodule Tuist.Runners.Workers.SpawnRunnerWorker do
  @moduledoc """
  Background job for spawning runners on Mac hosts.

  This worker handles async runner spawning when a GitHub workflow_job
  webhook with action "queued" is received.

  ## Responsibilities

  1. Load job record and find available host
  2. Get GitHub registration token via GitHub.Client
  3. Execute runner setup on host via SSH (configure and start GitHub Actions runner)
  4. Update job status (spawning -> running)
  5. Enqueue MonitorRunnerWorker

  ## Error Handling

  - Retries on transient SSH failures (max 3 attempts)
  - Marks job as failed if no hosts available
  - Cleans up on spawn failure
  """
  use Oban.Worker, queue: :runners, max_attempts: 3

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners
  alias Tuist.Runners.RunnerJob
  alias Tuist.Runners.Workers.MonitorRunnerWorker
  alias Tuist.SSHClient

  require Logger

  @ssh_connection_timeout 30_000
  @spawn_timeout 300_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}, attempt: attempt, max_attempts: max_attempts}) do
    case Runners.get_runner_job(job_id) do
      nil ->
        Logger.error("SpawnRunnerWorker: Job #{job_id} not found")
        {:error, :job_not_found}

      %RunnerJob{status: status} when status in [:completed, :failed, :cancelled] ->
        Logger.info("SpawnRunnerWorker: Job #{job_id} already in terminal state: #{status}")
        :ok

      %RunnerJob{status: status} when status not in [:pending, :spawning] ->
        Logger.warning("SpawnRunnerWorker: Job #{job_id} in unexpected state: #{status}, skipping")
        :ok

      job ->
        spawn_runner(job, attempt, max_attempts)
    end
  end

  defp spawn_runner(job, attempt, max_attempts) do
    Logger.info("SpawnRunnerWorker: Starting spawn for job #{job.id} (attempt #{attempt}/#{max_attempts})")

    case transition_to_spawning(job) do
      {:ok, spawning_job} ->
        do_spawn_runner(spawning_job, attempt, max_attempts)

      {:error, reason} ->
        handle_spawn_failure(job, reason, attempt, max_attempts)
    end
  end

  defp do_spawn_runner(job, attempt, max_attempts) do
    case find_available_host() do
      {:error, :no_hosts_available} ->
        handle_no_hosts(job)

      {:ok, host} ->
        do_spawn_runner_on_host(job, host, attempt, max_attempts)
    end
  end

  defp do_spawn_runner_on_host(job, host, attempt, max_attempts) do
    with {:ok, job} <- assign_host_to_job(job, host),
         {:ok, registration_token} <- get_registration_token(job),
         runner_name = generate_runner_name(job),
         {:ok, job} <- update_runner_name(job, runner_name),
         :ok <- setup_runner_on_host(host, job, registration_token, runner_name) do
      complete_spawn(job)
    else
      {:error, reason} ->
        job_with_host = Runners.get_runner_job(job.id)
        handle_spawn_failure(job_with_host, reason, attempt, max_attempts)
    end
  end

  defp transition_to_spawning(%RunnerJob{status: :spawning} = job), do: {:ok, job}

  defp transition_to_spawning(job) do
    case Runners.update_runner_job(job, %{status: :spawning}) do
      {:ok, updated_job} ->
        Logger.info("SpawnRunnerWorker: Job #{job.id} transitioned to spawning state")
        {:ok, updated_job}

      {:error, changeset} ->
        Logger.error("SpawnRunnerWorker: Failed to transition job #{job.id} to spawning: #{inspect(changeset.errors)}")

        {:error, :transition_failed}
    end
  end

  defp find_available_host do
    case Runners.get_best_available_host() do
      nil ->
        Logger.warning("SpawnRunnerWorker: No available hosts found")
        {:error, :no_hosts_available}

      host ->
        Logger.info("SpawnRunnerWorker: Selected host #{host.name} (#{host.ip})")
        {:ok, host}
    end
  end

  defp assign_host_to_job(job, host) do
    case Runners.update_runner_job(job, %{host_id: host.id}) do
      {:ok, updated_job} ->
        {:ok, %{updated_job | host: host}}

      {:error, changeset} ->
        Logger.error("SpawnRunnerWorker: Failed to assign host to job #{job.id}: #{inspect(changeset.errors)}")
        {:error, :host_assignment_failed}
    end
  end

  defp get_registration_token(job) do
    organization = Runners.get_runner_organization(job.organization_id)

    if organization && organization.github_app_installation_id do
      GitHubClient.get_org_runner_registration_token(%{
        org: job.org,
        installation_id: organization.github_app_installation_id
      })
    else
      Logger.error("SpawnRunnerWorker: No GitHub installation found for job #{job.id}")
      {:error, :no_github_installation}
    end
  end

  defp generate_runner_name(job) do
    short_id = String.slice(job.id, 0, 8)
    "tuist-runner-#{short_id}"
  end

  defp update_runner_name(job, runner_name) do
    case Runners.update_runner_job(job, %{github_runner_name: runner_name}) do
      {:ok, updated_job} -> {:ok, updated_job}
      {:error, _} -> {:error, :runner_name_update_failed}
    end
  end

  defp setup_runner_on_host(host, job, registration_token, runner_name) do
    ssh_opts = build_ssh_opts()

    case SSHClient.connect(String.to_charlist(host.ip), host.ssh_port, ssh_opts) do
      {:ok, connection} ->
        result = execute_runner_setup(connection, job, registration_token, runner_name)
        SSHClient.close(connection)
        result

      {:error, reason} ->
        Logger.error("SpawnRunnerWorker: SSH connection failed to #{host.ip}: #{inspect(reason)}")
        {:error, {:ssh_connection_failed, reason}}
    end
  end

  defp execute_runner_setup(connection, job, registration_token, runner_name) do
    setup_command = build_setup_command(job, registration_token.token, runner_name)

    case SSHClient.run_command(connection, setup_command, @spawn_timeout) do
      {:ok, output} ->
        Logger.info(
          "SpawnRunnerWorker: Runner setup completed for job #{job.id}, output: #{String.slice(output, 0, 500)}"
        )

        :ok

      {:error, reason} ->
        # Log the full error details including any output from the failed command
        Logger.error("SpawnRunnerWorker: Runner setup failed for job #{job.id}")
        Logger.error("SpawnRunnerWorker: Error details: #{inspect(reason)}")
        {:error, {:setup_command_failed, reason}}
    end
  end

  defp build_setup_command(job, token, runner_name) do
    runner_dir = "actions-runner-#{runner_name}"
    # Use organization-level URL for org-level runners
    runner_url = "https://github.com/#{job.org}"

    """
    set -e
    cd ~
    if [ ! -d "#{runner_dir}" ]; then
      mkdir -p #{runner_dir}
      cd #{runner_dir}
      curl -s -o actions-runner-osx-arm64.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-osx-arm64-2.321.0.tar.gz
      tar xzf actions-runner-osx-arm64.tar.gz
      rm actions-runner-osx-arm64.tar.gz
    else
      cd #{runner_dir}
    fi
    ./config.sh --unattended --url #{runner_url} --token #{token} --name #{runner_name} --labels tuist-runners --ephemeral --replace
    nohup ./run.sh > runner.log 2>&1 &
    sleep 2
    if ! pgrep -f 'Runner.Listener.*#{runner_name}' > /dev/null; then
      echo 'Runner failed to start. Last 50 lines of runner.log:'
      tail -n 50 runner.log
      exit 1
    fi
    echo 'Runner started successfully'
    """
  end

  defp build_ssh_opts do
    ssh_user = String.to_charlist(Tuist.Environment.runners_ssh_user())

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
    session_id = 8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    temp_dir = Path.join([System.tmp_dir!(), "tuist_runners_ssh", session_id])
    File.mkdir_p!(temp_dir)

    # Write the private key to a temporary file
    # Use id_ed25519 since the key is an Ed25519 key in OpenSSH format
    key_path = Path.join(temp_dir, "id_ed25519")
    File.write!(key_path, private_key)
    File.chmod!(key_path, 0o600)

    {temp_dir, key_path}
  end

  defp complete_spawn(job) do
    case Runners.update_runner_job(job, %{status: :running, started_at: DateTime.utc_now()}) do
      {:ok, updated_job} ->
        Logger.info("SpawnRunnerWorker: Job #{updated_job.id} is now running")
        enqueue_monitor(updated_job)

      {:error, changeset} ->
        Logger.error("SpawnRunnerWorker: Failed to mark job #{job.id} as running: #{inspect(changeset.errors)}")

        {:error, :status_update_failed}
    end
  end

  defp enqueue_monitor(job) do
    %{job_id: job.id, started_at: DateTime.to_iso8601(DateTime.utc_now())}
    |> MonitorRunnerWorker.new()
    |> Oban.insert()

    :ok
  end

  defp handle_no_hosts(job) do
    Logger.error("SpawnRunnerWorker: No hosts available for job #{job.id}, marking as failed")

    Runners.update_runner_job(job, %{
      status: :failed,
      completed_at: DateTime.utc_now(),
      error_message: "No runner hosts available"
    })

    {:error, :no_hosts_available}
  end

  defp handle_spawn_failure(job, reason, attempt, max_attempts) do
    error_message = format_error_message(reason)
    Logger.error("SpawnRunnerWorker: Spawn failed for job #{job.id}: #{error_message}")

    if attempt >= max_attempts do
      Logger.error("SpawnRunnerWorker: Max attempts reached for job #{job.id}, marking as failed")

      Runners.update_runner_job(job, %{
        status: :failed,
        completed_at: DateTime.utc_now(),
        error_message: "Spawn failed after #{max_attempts} attempts: #{error_message}"
      })

      :ok
    else
      Runners.update_runner_job(job, %{error_message: error_message})
      {:error, reason}
    end
  end

  defp format_error_message({:ssh_connection_failed, reason}), do: "SSH connection failed: #{inspect(reason)}"
  defp format_error_message({:setup_command_failed, reason}), do: "Runner setup failed: #{inspect(reason)}"
  defp format_error_message(:no_github_installation), do: "No GitHub App installation found"
  defp format_error_message(:transition_failed), do: "Failed to transition job state"
  defp format_error_message(:host_assignment_failed), do: "Failed to assign host"
  defp format_error_message(:runner_name_update_failed), do: "Failed to update runner name"
  defp format_error_message(reason), do: inspect(reason)
end
