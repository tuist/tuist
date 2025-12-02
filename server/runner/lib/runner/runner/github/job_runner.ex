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

    # GitHub's acquirejob endpoint expects:
    # - jobMessageId: the runner_request_id from the job message
    # - runnerOS: the operating system
    # - billingOwnerId: from the job message (optional but recommended)
    body =
      Jason.encode!(%{
        jobMessageId: state.job_info.runner_request_id,
        runnerOS: runner_os(),
        billingOwnerId: state.job_info.billing_owner_id
      })

    Logger.debug("Acquiring job with body: #{body}")

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

  defp runner_os do
    case :os.type() do
      {:unix, :darwin} -> "OSX"
      {:unix, :linux} -> "Linux"
      {:win32, _} -> "Windows"
      _ -> "Linux"
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

    Logger.debug("Raw steps from job spec: #{inspect(steps)}")

    Enum.map(steps, fn step ->
      Logger.debug("Parsing step: #{inspect(step)}")

      # GitHub Actions step types:
      # - "action" for uses: actions/checkout@v4 etc
      # - "script" for run: commands
      # The actual script content may be in different fields
      step_type = step["type"] || infer_step_type(step)

      inputs = step["inputs"] || %{}

      %{
        id: step["id"],
        name: step["displayName"] || step["name"] || "Step",
        type: step_type,
        # For script steps, the script content can be in various fields
        script: inputs["script"] || step["script"] || step["run"],
        # For action steps
        action: step["reference"] || step["uses"],
        inputs: inputs,
        env: step["environment"] || step["env"] || %{},
        working_directory: step["workingDirectory"],
        condition: step["condition"]
      }
    end)
  end

  defp parse_steps(_), do: []

  defp infer_step_type(step) do
    inputs = step["inputs"] || %{}

    cond do
      step["reference"] != nil -> "action"
      step["uses"] != nil -> "action"
      step["script"] != nil -> "script"
      step["run"] != nil -> "script"
      inputs["script"] != nil -> "script"
      true -> step["type"] || "unknown"
    end
  end

  defp execute_step(%{type: "script", script: script} = step, work_dir)
       when is_binary(script) do
    execute_script(script, step, work_dir)
  end

  defp execute_step(%{type: "action", action: action} = step, work_dir) do
    # Handle built-in actions
    # The "reference" field can be:
    # - %{"type" => "script"} for run: commands
    # - %{"name" => "actions/checkout", "type" => "repository", ...} for uses: actions
    Logger.info("Executing action: #{inspect(action)}")

    case action do
      # Script type actions (run: commands)
      %{"type" => "script"} ->
        execute_script_from_inputs(step, work_dir)

      # Repository actions (uses: actions/checkout@v4)
      %{"name" => "actions/checkout"} ->
        execute_checkout_action(step, work_dir)

      %{"name" => name, "type" => "repository"} ->
        Logger.warning("Skipping unsupported repository action: #{name}")
        {:ok, "Skipped action: #{name}"}

      %{"name" => name} ->
        Logger.warning("Skipping unsupported action: #{name}")
        {:ok, "Skipped action: #{name}"}

      name when is_binary(name) ->
        if String.starts_with?(name, "actions/checkout") do
          execute_checkout_action(step, work_dir)
        else
          Logger.warning("Skipping unsupported action: #{name}")
          {:ok, "Skipped action: #{name}"}
        end

      _ ->
        Logger.warning("Unknown action format: #{inspect(action)}")
        {:ok, "Skipped unknown action"}
    end
  end

  defp execute_script_from_inputs(step, work_dir) do
    # For script-type actions, the script can be in various formats:
    # 1. Simple: inputs["script"] as a string
    # 2. Complex: inputs["map"] with Key/Value pairs where Key.lit == "script"
    script = extract_script_from_inputs(step.inputs)

    if script do
      Logger.info("Running script from inputs")
      execute_script(script, step, work_dir)
    else
      Logger.warning("Script action has no script in inputs: #{inspect(step.inputs)}")
      {:ok, "No script to execute"}
    end
  end

  defp extract_script_from_inputs(inputs) when is_map(inputs) do
    # Try simple format first
    case inputs["script"] do
      script when is_binary(script) ->
        script

      _ ->
        # Try complex format with map array
        extract_script_from_map(inputs["map"])
    end
  end

  defp extract_script_from_inputs(_), do: nil

  defp extract_script_from_map(map_entries) when is_list(map_entries) do
    # Find the entry where Key.lit == "script"
    script_entry = Enum.find(map_entries, fn entry ->
      get_in(entry, ["Key", "lit"]) == "script"
    end)

    case script_entry do
      %{"Value" => value} ->
        extract_script_value(value)

      _ ->
        nil
    end
  end

  defp extract_script_from_map(_), do: nil

  defp extract_script_value(%{"lit" => script}) when is_binary(script) do
    # Simple literal script
    script
  end

  defp extract_script_value(%{"expr" => expr}) when is_binary(expr) do
    # Expression that needs evaluation - for now, try to extract the literal part
    # Format is like: format('actual script...', github.event.inputs.test_message)
    case Regex.run(~r/format\('(.+?)',\s*[^)]+\)/s, expr) do
      [_, script] ->
        # Unescape the script (handle \n etc)
        script
        |> String.replace("\\n", "\n")
        |> String.replace("\\'", "'")

      _ ->
        # Try to use the expression as-is if it looks like a script
        if String.contains?(expr, "echo") or String.contains?(expr, "run") do
          Logger.warning("Could not parse format expression, using raw: #{String.slice(expr, 0, 100)}")
          expr
        else
          nil
        end
    end
  end

  defp extract_script_value(_), do: nil

  defp execute_script(script, step, work_dir) do
    step_work_dir = step.working_directory || work_dir

    # Ensure directory exists
    File.mkdir_p!(step_work_dir)

    opts = [
      cd: step_work_dir,
      env: build_env_list(step.env),
      stderr_to_stdout: true
    ]

    Logger.info("Running script in #{step_work_dir}")
    Logger.debug("Script content: #{String.slice(script, 0, 500)}...")

    case System.cmd("bash", ["-c", script], opts) do
      {output, 0} ->
        Logger.info("Step completed successfully")
        Logger.debug("Output: #{String.slice(output, 0, 1000)}")
        {:ok, output}

      {output, exit_code} ->
        Logger.error("Script failed with exit code #{exit_code}")
        Logger.error("Output: #{output}")
        {:error, {:script_failed, exit_code, output}}
    end
  end

  defp execute_step(%{type: type} = step, _work_dir) do
    Logger.warning("Unsupported step type: #{type}, step: #{inspect(step)}")
    {:ok, "Skipped unsupported step type: #{type}"}
  end

  defp execute_step(step, _work_dir) do
    Logger.warning("Invalid step: #{inspect(step)}")
    {:ok, "Skipped invalid step"}
  end

  defp execute_checkout_action(step, work_dir) do
    # Clone the repository into the working directory
    # The repository info should be available in the job context
    Logger.info("Checkout action - cloning repository to #{work_dir}")

    # Get repository info from step inputs or use defaults
    inputs = step.inputs || %{}
    repository = extract_input_value(inputs, "repository")
    ref = extract_input_value(inputs, "ref")

    # If no repository specified, we need to get it from the job context
    # For now, use the action reference which has the repo info
    case step.action do
      %{"name" => _name, "repositoryType" => "GitHub"} ->
        # We need the repository URL from the job context
        # This is typically passed via environment or job variables
        do_checkout(work_dir, repository, ref)

      _ ->
        Logger.warning("Checkout action missing repository info")
        {:ok, "Checkout skipped - no repository info"}
    end
  end

  defp do_checkout(work_dir, repository, ref) do
    # For self-hosted runners, we typically have the repository info in env vars
    # or need to construct it from the job context
    repo_url = repository || System.get_env("GITHUB_REPOSITORY")
    git_ref = ref || System.get_env("GITHUB_REF") || "HEAD"

    if repo_url do
      # Construct full URL if needed
      full_url = if String.starts_with?(repo_url, "http") do
        repo_url
      else
        "https://github.com/#{repo_url}.git"
      end

      Logger.info("Cloning #{full_url} at ref #{git_ref}")

      # Clone the repository
      case System.cmd("git", ["clone", "--depth", "1", full_url, work_dir], stderr_to_stdout: true) do
        {_output, 0} ->
          # Checkout specific ref if provided
          if git_ref && git_ref != "HEAD" do
            case System.cmd("git", ["checkout", git_ref], cd: work_dir, stderr_to_stdout: true) do
              {_, 0} -> {:ok, "Checkout completed"}
              {output, code} ->
                Logger.warning("Git checkout ref failed (#{code}): #{output}")
                {:ok, "Checkout completed (default branch)"}
            end
          else
            {:ok, "Checkout completed"}
          end

        {output, code} ->
          Logger.error("Git clone failed (#{code}): #{output}")
          {:error, {:checkout_failed, code, output}}
      end
    else
      Logger.warning("No repository URL available for checkout")
      {:ok, "Checkout skipped - no repository URL"}
    end
  end

  defp extract_input_value(inputs, key) do
    # Handle both simple and complex input formats
    case inputs[key] do
      value when is_binary(value) -> value
      %{"lit" => value} -> value
      _ ->
        # Try map format
        case inputs["map"] do
          entries when is_list(entries) ->
            entry = Enum.find(entries, fn e -> get_in(e, ["Key", "lit"]) == key end)
            case entry do
              %{"Value" => %{"lit" => value}} -> value
              _ -> nil
            end
          _ -> nil
        end
    end
  end

  defp build_env_list(env) when is_map(env) do
    Enum.map(env, fn
      {k, v} when is_binary(v) -> {to_string(k), v}
      {k, %{"value" => v}} -> {to_string(k), to_string(v)}
      {k, v} -> {to_string(k), to_string(v)}
    end)
  end

  defp build_env_list(_), do: []
end
