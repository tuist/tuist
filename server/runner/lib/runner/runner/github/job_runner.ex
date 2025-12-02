defmodule Runner.Runner.GitHub.JobRunner do
  @moduledoc """
  Handles job acquisition, execution, and completion for GitHub Actions jobs.

  This module manages the lifecycle of a job:
  1. Acquire job details from the Run Service
  2. Execute job steps
  3. Renew job lock periodically
  4. Report job completion

  The job specification contains all the steps, environment variables,
  and context needed to execute the workflow job.
  """

  use GenServer

  require Logger

  alias Runner.Runner.GitHub.Auth

  @runner_version "2.320.0"
  @lock_renewal_interval_ms 60_000
  @acquire_timeout_ms 30_000
  @complete_timeout_ms 30_000

  defstruct [
    :credentials,
    :job_info,
    :plan_id,
    :job_id,
    :work_dir,
    :status,
    :lock_timer,
    :steps,
    :current_step,
    :notify_pid
  ]

  @type job_message :: %{
          runner_request_id: String.t(),
          run_service_url: String.t(),
          billing_owner_id: String.t() | nil
        }

  @type job_result :: %{
          result: :succeeded | :failed | :cancelled,
          exit_code: integer(),
          outputs: map()
        }

  # Client API

  @doc """
  Acquires and starts executing a job.

  This is called when a job message is received from the message listener.
  It acquires the full job specification from the Run Service and starts
  executing the steps.
  """
  @spec run_job(Auth.credentials(), job_message(), String.t(), pid()) ::
          {:ok, pid()} | {:error, term()}
  def run_job(credentials, job_message, work_dir, notify_pid) do
    GenServer.start_link(__MODULE__, %{
      credentials: credentials,
      job_message: job_message,
      work_dir: work_dir,
      notify_pid: notify_pid
    })
  end

  @doc """
  Cancels a running job.
  """
  @spec cancel(pid()) :: :ok
  def cancel(pid) do
    GenServer.cast(pid, :cancel)
  end

  # Server callbacks

  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      credentials: opts.credentials,
      job_info: opts.job_message,
      work_dir: opts.work_dir,
      notify_pid: opts.notify_pid,
      status: :acquiring
    }

    # Start job acquisition
    send(self(), :acquire_job)

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:acquire_job, state) do
    case acquire_job(state) do
      {:ok, job_spec, plan_id, job_id} ->
        Logger.info("Job acquired: #{job_id}")

        # Start lock renewal timer
        timer = Process.send_after(self(), :renew_lock, @lock_renewal_interval_ms)

        new_state = %{
          state
          | plan_id: plan_id,
            job_id: job_id,
            steps: parse_steps(job_spec),
            current_step: 0,
            status: :running,
            lock_timer: timer
        }

        # Start executing steps
        send(self(), :execute_next_step)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to acquire job: #{inspect(reason)}")
        send(state.notify_pid, {:job_failed, reason})
        {:stop, :normal, state}
    end
  end

  def handle_info(:renew_lock, %{status: :running} = state) do
    case renew_lock(state) do
      :ok ->
        timer = Process.send_after(self(), :renew_lock, @lock_renewal_interval_ms)
        {:noreply, %{state | lock_timer: timer}}

      {:error, reason} ->
        Logger.warning("Lock renewal failed: #{inspect(reason)}")
        # Continue anyway, GitHub will let us know if the lock is lost
        timer = Process.send_after(self(), :renew_lock, @lock_renewal_interval_ms)
        {:noreply, %{state | lock_timer: timer}}
    end
  end

  def handle_info(:renew_lock, state) do
    # Not running, don't renew
    {:noreply, state}
  end

  def handle_info(:execute_next_step, %{current_step: current, steps: steps} = state)
      when current >= length(steps) do
    # All steps completed
    complete_job(state, :succeeded, 0)
    send(state.notify_pid, {:job_completed, %{result: :succeeded, exit_code: 0}})
    {:stop, :normal, state}
  end

  def handle_info(:execute_next_step, state) do
    step = Enum.at(state.steps, state.current_step)
    Logger.info("Executing step #{state.current_step + 1}/#{length(state.steps)}: #{step.name}")

    case execute_step(step, state.work_dir) do
      {:ok, _output} ->
        # Move to next step
        send(self(), :execute_next_step)
        {:noreply, %{state | current_step: state.current_step + 1}}

      {:error, reason} ->
        Logger.error("Step failed: #{inspect(reason)}")
        complete_job(state, :failed, 1)
        send(state.notify_pid, {:job_completed, %{result: :failed, exit_code: 1}})
        {:stop, :normal, state}
    end
  end

  @impl GenServer
  def handle_cast(:cancel, state) do
    Logger.info("Job cancelled")

    if state.lock_timer do
      Process.cancel_timer(state.lock_timer)
    end

    complete_job(state, :cancelled, 1)
    send(state.notify_pid, {:job_completed, %{result: :cancelled, exit_code: 1}})
    {:stop, :normal, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.lock_timer do
      Process.cancel_timer(state.lock_timer)
    end

    :ok
  end

  # Private functions

  defp acquire_job(state) do
    url = "#{state.job_info.run_service_url}/acquirejob"

    body =
      Jason.encode!(%{
        jobId: state.job_info.runner_request_id,
        billingOwnerId: state.job_info.billing_owner_id
      })

    with {:ok, credentials} <- Auth.ensure_valid_token(state.credentials) do
      headers =
        [
          {"Content-Type", "application/json"},
          {"User-Agent", "GitHubActionsRunner/#{@runner_version}"}
        ] ++ Auth.auth_headers(credentials)

      case Req.post(url, headers: headers, body: body, receive_timeout: @acquire_timeout_ms) do
        {:ok, %Req.Response{status: 200, body: body, headers: headers}} ->
          plan_id = get_plan_id(headers, body)
          job_id = body["jobId"] || state.job_info.runner_request_id
          {:ok, body, plan_id, job_id}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:acquire_failed, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp renew_lock(state) do
    url = "#{state.job_info.run_service_url}/renewjob"

    body =
      Jason.encode!(%{
        planId: state.plan_id,
        jobId: state.job_id
      })

    with {:ok, credentials} <- Auth.ensure_valid_token(state.credentials) do
      headers =
        [
          {"Content-Type", "application/json"},
          {"User-Agent", "GitHubActionsRunner/#{@runner_version}"}
        ] ++ Auth.auth_headers(credentials)

      case Req.post(url, headers: headers, body: body, receive_timeout: 10_000) do
        {:ok, %Req.Response{status: status}} when status in [200, 204] ->
          :ok

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:renew_failed, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp complete_job(state, result, _exit_code) do
    url = "#{state.job_info.run_service_url}/completejob"

    result_string =
      case result do
        :succeeded -> "Succeeded"
        :failed -> "Failed"
        :cancelled -> "Cancelled"
      end

    body =
      Jason.encode!(%{
        planId: state.plan_id,
        jobId: state.job_id,
        result: result_string,
        outputs: %{}
      })

    with {:ok, credentials} <- Auth.ensure_valid_token(state.credentials) do
      headers =
        [
          {"Content-Type", "application/json"},
          {"User-Agent", "GitHubActionsRunner/#{@runner_version}"}
        ] ++ Auth.auth_headers(credentials)

      case Req.post(url, headers: headers, body: body, receive_timeout: @complete_timeout_ms) do
        {:ok, %Req.Response{status: status}} when status in [200, 204] ->
          Logger.info("Job completed: #{result_string}")
          :ok

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.warning("Job completion returned status #{status}: #{inspect(body)}")
          :ok

        {:error, reason} ->
          Logger.error("Failed to report job completion: #{inspect(reason)}")
          :ok
      end
    end
  end

  defp get_plan_id(headers, body) do
    # Plan ID may be in headers or body
    header_plan_id =
      headers
      |> Enum.find(fn {k, _} -> String.downcase(k) == "x-plan-id" end)
      |> case do
        {_, v} -> v
        nil -> nil
      end

    header_plan_id || body["planId"] || body["plan_id"]
  end

  defp parse_steps(job_spec) when is_map(job_spec) do
    steps = job_spec["steps"] || []

    Enum.map(steps, fn step ->
      %{
        id: step["id"],
        name: step["displayName"] || step["name"] || "Step",
        type: step["type"] || "script",
        script: step["script"] || step["run"],
        env: step["env"] || %{},
        working_directory: step["workingDirectory"]
      }
    end)
  end

  defp parse_steps(_), do: []

  defp execute_step(%{type: "script", script: script} = step, work_dir)
       when is_binary(script) do
    # Execute the script in the working directory
    opts = [
      cd: step.working_directory || work_dir,
      env: Map.to_list(step.env || %{}),
      stderr_to_stdout: true
    ]

    Logger.debug("Running script: #{String.slice(script, 0, 100)}...")

    case System.cmd("bash", ["-c", script], opts) do
      {output, 0} ->
        {:ok, output}

      {output, exit_code} ->
        Logger.error("Script failed with exit code #{exit_code}: #{output}")
        {:error, {:script_failed, exit_code, output}}
    end
  end

  defp execute_step(%{type: type}, _work_dir) do
    Logger.warning("Unsupported step type: #{type}")
    {:ok, "Skipped unsupported step type: #{type}"}
  end

  defp execute_step(step, _work_dir) do
    Logger.warning("Invalid step: #{inspect(step)}")
    {:ok, "Skipped invalid step"}
  end
end
