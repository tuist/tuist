defmodule Runner.Runner.JobExecutor do
  @moduledoc """
  Orchestrates the execution of GitHub Actions jobs using the official runner.

  This module is responsible for:
  1. Starting an ephemeral VM for job isolation
  2. Registering with GitHub to get JIT configuration
  3. Running the official runner inside the VM via SSH
  4. Cleaning up VM and resources after job completion

  Jobs run inside macOS VMs managed by Curie for isolation. The official
  GitHub Actions runner binary is pre-installed in the VM image and handles
  all the complex protocol details.
  """

  require Logger

  alias Runner.Runner.GitHub.OfficialRunner
  alias Runner.Runner.{VM, VMWarmer}

  @runner_path_in_vm "/opt/actions-runner"

  @type job_config :: %{
          job_id: String.t(),
          github_org: String.t(),
          github_repo: String.t() | nil,
          labels: [String.t()],
          encoded_jit_config: String.t(),
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

  Acquires a warm VM from VMWarmer, registers with GitHub, runs the job inside
  the VM via SSH, and releases the VM back to the warmer for cleanup.

  ## Options
    - `:base_work_dir` - Base directory for job working directories (host mode)
    - `:ssh_user` - SSH username for VM (default: "admin")
    - `:ssh_key_path` - Path to SSH private key
    - `:use_vm` - Whether to use VM isolation (default: true)
  """
  @spec execute(job_config(), keyword()) :: {:ok, job_result()} | {:error, term()}
  def execute(job_config, opts \\ []) do
    use_vm = Keyword.get(opts, :use_vm, true)
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting job execution: #{job_config.job_id}")
    Logger.info("VM isolation: #{use_vm}")

    result = if use_vm do
      execute_in_vm(job_config, opts)
    else
      execute_on_host(job_config, opts)
    end

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
  end

  # VM-based execution (using VMWarmer for pre-warmed VMs)

  defp execute_in_vm(job_config, opts) do
    ssh_user = Keyword.get(opts, :ssh_user, ssh_user())
    ssh_key_path = Keyword.get(opts, :ssh_key_path, ssh_key_path())

    Logger.info("Acquiring warm VM from VMWarmer...")

    vm_opts = [
      ssh_user: ssh_user,
      ssh_key_path: ssh_key_path
    ]

    case VMWarmer.acquire() do
      {:ok, container_name} ->
        Logger.info("Acquired warm VM '#{container_name}'")

        try do
          do_execute_in_vm(job_config, container_name, vm_opts)
        after
          # Release the VM back to the warmer for cleanup
          # VMWarmer will stop it and start warming a new one
          VMWarmer.release(container_name)
        end

      {:error, reason} ->
        Logger.error("Failed to acquire VM: #{inspect(reason)}")
        {:error, {:vm_acquire_failed, reason}}
    end
  end

  defp do_execute_in_vm(job_config, container_name, vm_opts) do
    encoded_jit_config = job_config.encoded_jit_config

    unless is_binary(encoded_jit_config) and encoded_jit_config != "" do
      {:error, :missing_jit_config}
    else
      Logger.info("Running job in VM '#{container_name}'")

      command = "cd #{@runner_path_in_vm} && ./run.sh --jitconfig #{encoded_jit_config}"

      output_callback = fn data ->
        String.split(data, "\n", trim: true)
        |> Enum.each(&Logger.info("VM Runner: #{&1}"))
      end

      VM.exec_stream(container_name, command, output_callback, vm_opts)
    end
  end

  # Host-based execution (fallback/legacy)

  defp execute_on_host(job_config, opts) do
    base_work_dir = Keyword.get(opts, :base_work_dir, "/tmp/tuist-runner")
    work_dir = create_working_directory(base_work_dir, job_config.job_id)

    Logger.info("Working directory: #{work_dir}")

    try do
      do_execute_on_host(job_config, work_dir)
    after
      cleanup_working_directory(work_dir)
    end
  end

  defp do_execute_on_host(job_config, work_dir) do
    runner_cache_dir = "/tmp/github-actions-runner"
    encoded_jit_config = job_config.encoded_jit_config

    with true <- is_binary(encoded_jit_config) and encoded_jit_config != "" || {:error, :missing_jit_config},
         {:ok, runner_dir} <- OfficialRunner.ensure_runner_available(runner_cache_dir),
         {:ok, exit_code} <- OfficialRunner.run_with_jitconfig(runner_dir, encoded_jit_config, work_dir) do
      {:ok, exit_code}
    end
  end

  # Private functions

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

  # Configuration helpers

  defp ssh_user do
    System.get_env("VM_SSH_USER", "tuist")
  end

  defp ssh_key_path do
    System.get_env("VM_SSH_KEY_PATH", "~/.ssh/id_ed25519")
  end
end
