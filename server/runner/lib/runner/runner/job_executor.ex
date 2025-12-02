defmodule Runner.Runner.JobExecutor do
  @moduledoc """
  Orchestrates the execution of GitHub Actions jobs.

  This module is responsible for:
  1. Creating a working directory for the job
  2. Registering the runner with GitHub
  3. Creating a session and starting the message listener
  4. Waiting for and executing jobs
  5. Cleaning up resources after job completion
  """

  require Logger

  alias Runner.Runner.GitHub.{Auth, JobRunner, MessageListener, Registration, Session}

  @default_timeout_ms 3_600_000

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

  Creates a working directory, registers with GitHub, polls for the job,
  executes it, and cleans up. Returns the job result.
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
        {:ok, job_result} ->
          {:ok, Map.put(job_result, :duration_ms, duration_ms)}

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

    with {:ok, registration} <- register_runner(job_config, runner_name),
         {:ok, credentials} <- initialize_credentials(registration),
         {:ok, session} <- create_session(registration, credentials, runner_name),
         {:ok, job_result} <-
           run_job_loop(registration, credentials, session, work_dir, job_config) do
      # Clean up session
      cleanup_session(registration, credentials, session)
      {:ok, job_result}
    end
  end

  defp register_runner(job_config, runner_name) do
    Logger.info("Registering runner with GitHub...")

    Registration.register(job_config.registration_token, %{
      github_org: job_config.github_org,
      github_repo: job_config.github_repo,
      labels: job_config.labels,
      runner_name: runner_name
    })
  end

  defp initialize_credentials(registration) do
    Logger.info("Initializing credentials...")

    # Use the credentials from registration which already has client_id
    Auth.refresh_token(registration.credentials)
  end

  defp create_session(registration, credentials, runner_name) do
    Logger.info("Creating session with Broker API...")

    # Use server_url (v1 API) which includes the pool/session context
    # The v2 API (broker.actions.githubusercontent.com) seems to require additional context
    server_url = registration.server_url || registration.server_url_v2

    Session.create_session(server_url, credentials, %{
      runner_id: registration.runner_id,
      agent_id: registration.agent_id,
      pool_id: registration.pool_id,
      runner_name: runner_name
    })
  end

  defp run_job_loop(registration, credentials, session, work_dir, job_config) do
    Logger.info("Starting message listener...")

    # Start the message listener
    {:ok, listener_pid} =
      MessageListener.start_link(
        server_url_v2: registration.server_url_v2,
        credentials: credentials,
        session_id: session.session_id,
        runner_info: %{
          runner_id: registration.runner_id,
          runner_name: session.owner_name
        },
        notify_pid: self()
      )

    try do
      timeout = job_config.timeout_ms || @default_timeout_ms
      wait_for_job(listener_pid, credentials, work_dir, timeout)
    after
      MessageListener.stop(listener_pid)
    end
  end

  defp wait_for_job(listener_pid, credentials, work_dir, timeout) do
    Logger.info("Waiting for job message...")

    receive do
      {:job_message, message} ->
        Logger.info("Received job message: #{message.message_type}")

        # Pause the listener while we execute
        MessageListener.pause(listener_pid)

        # Execute the job
        execute_job_from_message(message, credentials, work_dir)

      {:job_completed, result} ->
        {:ok, result}

      {:job_failed, reason} ->
        {:error, reason}
    after
      timeout ->
        Logger.warning("Timed out waiting for job")
        {:error, :timeout}
    end
  end

  defp execute_job_from_message(%{message_type: "RunnerJobRequest", body: body}, credentials, work_dir) do
    job_message = %{
      runner_request_id: body["runner_request_id"] || body["runnerRequestId"],
      run_service_url: body["run_service_url"] || body["runServiceUrl"],
      billing_owner_id: body["billing_owner_id"] || body["billingOwnerId"]
    }

    Logger.info("Executing job: #{job_message.runner_request_id}")

    case JobRunner.run_job(credentials, job_message, work_dir, self()) do
      {:ok, _pid} ->
        # Wait for job to complete
        receive do
          {:job_completed, result} ->
            {:ok, result}

          {:job_failed, reason} ->
            {:ok, %{result: :failed, exit_code: 1, error: reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_job_from_message(%{message_type: type}, _credentials, _work_dir) do
    Logger.warning("Unexpected message type: #{type}")
    {:error, {:unexpected_message_type, type}}
  end

  defp cleanup_session(registration, credentials, session) do
    Logger.info("Cleaning up session...")

    case Session.delete_session(registration.server_url_v2, credentials, session.session_id) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("Failed to delete session: #{inspect(reason)}")
    end
  end

  defp create_working_directory(base_dir, job_id) do
    work_dir = Path.join(base_dir, job_id)

    case File.mkdir_p(work_dir) do
      :ok ->
        Logger.info("Created working directory: #{work_dir}")
        work_dir

      {:error, reason} ->
        Logger.error("Failed to create working directory: #{inspect(reason)}")
        # Fall back to a temp directory
        {:ok, temp_dir} = Briefly.create(directory: true)
        Logger.info("Using temp directory instead: #{temp_dir}")
        temp_dir
    end
  end

  defp cleanup_working_directory(work_dir) do
    Logger.info("Cleaning up working directory: #{work_dir}")

    case File.rm_rf(work_dir) do
      {:ok, _} ->
        Logger.info("Working directory cleaned up")

      {:error, reason, path} ->
        Logger.warning("Failed to clean up #{path}: #{inspect(reason)}")
    end
  end

  defp generate_runner_name(_job_id) do
    hostname =
      case :inet.gethostname() do
        {:ok, name} -> to_string(name)
        _ -> "runner"
      end

    # Use a UUID suffix to ensure uniqueness (GitHub runners must have unique names)
    short_uuid = UUID.uuid4() |> String.split("-") |> hd()
    "#{hostname}-#{short_uuid}"
  end
end
