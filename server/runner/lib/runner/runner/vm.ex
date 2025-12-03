defmodule Runner.Runner.VM do
  @moduledoc """
  Manages macOS virtual machines using Curie for isolated job execution.

  Curie is a CLI tool for running macOS VMs on Apple Silicon using
  Apple's Virtualization.framework. This module wraps Curie commands
  to provide VM lifecycle management for running GitHub Actions jobs
  in isolation.

  ## Usage

      # Start an ephemeral VM for a job
      {:ok, vm_info} = VM.start_ephemeral("job-123", image: "tuist/runner/xcode-26.1.1:1.0")

      # Wait for VM to be ready
      :ok = VM.wait_for_ready("job-123")

      # Get connection info
      {:ok, ip} = VM.get_ip("job-123")

      # Execute commands via SSH
      {:ok, output, 0} = VM.exec("job-123", "echo hello")

      # Stop the VM (ephemeral VMs auto-cleanup)
      :ok = VM.stop("job-123")
  """

  require Logger

  alias Runner.Runner.SSH

  @default_image "tuist/runner/xcode-26.1.1:1.0"
  @default_ssh_user "admin"
  @default_ssh_key_path "~/.ssh/tuist_runner_vm_key"
  @default_ssh_port 22
  @vm_ready_timeout_ms 120_000
  @vm_ready_poll_interval_ms 2_000

  @type vm_info :: %{
    container_name: String.t(),
    container_id: String.t(),
    image: String.t(),
    ip: String.t() | nil,
    status: :starting | :running | :stopped,
    port: port() | nil,
    os_pid: integer() | nil
  }

  @type vm_opts :: [
    image: String.t(),
    ssh_user: String.t(),
    ssh_key_path: String.t(),
    ssh_port: integer(),
    no_display: boolean()
  ]

  @doc """
  Starts an ephemeral VM using the specified image.

  Ephemeral VMs are automatically deleted when stopped.

  ## Options
    - `:image` - VM image to use (default: #{@default_image})
    - `:ssh_user` - SSH username (default: #{@default_ssh_user})
    - `:ssh_key_path` - Path to SSH private key (default: #{@default_ssh_key_path})
    - `:no_display` - Run without display window (default: true)
  """
  @spec start_ephemeral(String.t(), vm_opts()) :: {:ok, vm_info()} | {:error, term()}
  def start_ephemeral(container_name, opts \\ []) do
    image = Keyword.get(opts, :image, default_image())
    no_display = Keyword.get(opts, :no_display, true)

    Logger.info("Starting ephemeral VM '#{container_name}' from image '#{image}'")

    # Use `curie run` which creates an ephemeral container that auto-deletes on stop
    # Run async and wait for "started" message since curie run blocks while VM runs
    args = ["run", image] ++ if(no_display, do: ["--no-window"], else: [])

    case run_curie_and_wait_for_started(args, container_name) do
      {:ok, container_id, port, os_pid} ->
        Logger.info("VM '#{container_id}' started (ephemeral), OS PID: #{os_pid}")
        vm_info = %{
          container_name: container_name,
          container_id: container_id,
          image: image,
          ip: nil,
          status: :starting,
          port: port,
          os_pid: os_pid
        }
        {:ok, vm_info}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_curie_and_wait_for_started(args, container_name) do
    case System.find_executable("curie") do
      nil ->
        {:error, :curie_not_found}

      curie_path ->
        Logger.debug("Running: curie #{Enum.join(args, " ")}")

        port = Port.open(
          {:spawn_executable, curie_path},
          [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            {:args, args},
            {:line, 1024}
          ]
        )

        # Wait for container ID and "started" message (with timeout)
        wait_for_vm_started(port, container_name, nil, 60_000)
    end
  rescue
    e ->
      {:error, {:curie_error, Exception.message(e)}}
  end

  defp wait_for_vm_started(port, container_name, container_id, timeout_ms) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        Logger.debug("curie run output: #{line}")

        cond do
          # Check for error messages first
          String.starts_with?(line, "Error:") ->
            Logger.error("Curie error: #{line}")
            Port.close(port)
            # Clean up the container that was created but failed to start
            if container_id do
              Logger.info("Cleaning up failed container #{container_id}")
              run_curie(["rm", container_id])
            end
            {:error, {:curie_error, line}}

          # Look for container ID in format "  id: <hex>" or "Container <hex> started"
          container_id == nil && String.contains?(line, "id:") ->
            case Regex.run(~r/id:\s*([a-f0-9]{12})/, line) do
              [_, new_container_id] ->
                Logger.info("Container ID: #{new_container_id}")
                wait_for_vm_started(port, container_name, new_container_id, timeout_ms)
              _ ->
                wait_for_vm_started(port, container_name, container_id, timeout_ms)
            end

          # Look for "Container <id> started" message
          String.contains?(line, "started") ->
            # Try to extract container ID from this line if we don't have it yet
            final_container_id = case Regex.run(~r/Container\s+([a-f0-9]{12})\s+started/, line) do
              [_, id] -> id
              _ -> container_id
            end
            # Get OS PID from port info for cleanup
            os_pid = case Port.info(port, :os_pid) do
              {:os_pid, pid} -> pid
              _ -> nil
            end
            # VM is started, return the port and OS PID (it will keep running in background)
            {:ok, final_container_id, port, os_pid}

          true ->
            wait_for_vm_started(port, container_name, container_id, timeout_ms)
        end

      {^port, {:data, {:noeol, _partial}}} ->
        # Partial line, keep waiting
        wait_for_vm_started(port, container_name, container_id, timeout_ms)

      {^port, {:exit_status, status}} ->
        Logger.error("curie run exited unexpectedly with status #{status}")
        {:error, {:run_exited, status}}
    after
      timeout_ms ->
        Logger.error("Timeout waiting for VM '#{container_name}' to start")
        Port.close(port)
        # Clean up the container that was created but timed out
        if container_id do
          Logger.info("Cleaning up timed out container #{container_id}")
          run_curie(["rm", container_id])
        end
        {:error, :start_timeout}
    end
  end

  @doc """
  Gets the IP address of a running VM.
  """
  @spec get_ip(String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_ip(container_name) do
    case run_curie(["inspect", container_name, "-f", "json"]) do
      {:ok, output, 0} ->
        parse_ip_from_inspect(output)

      {:ok, _output, exit_code} ->
        {:error, {:inspect_failed, exit_code}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Waits for the VM to be ready (SSH accessible).

  Polls the VM status and attempts SSH connection until successful
  or timeout is reached.

  ## Options
    - `:timeout_ms` - Maximum time to wait (default: #{@vm_ready_timeout_ms}ms)
    - `:ssh_user` - SSH username (default: #{@default_ssh_user})
    - `:ssh_key_path` - Path to SSH private key
  """
  @spec wait_for_ready(String.t(), vm_opts()) :: :ok | {:error, :timeout | term()}
  def wait_for_ready(container_name, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @vm_ready_timeout_ms)
    ssh_user = Keyword.get(opts, :ssh_user, default_ssh_user())
    ssh_key_path = Keyword.get(opts, :ssh_key_path, default_ssh_key_path())
    ssh_port = Keyword.get(opts, :ssh_port, @default_ssh_port)

    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Logger.info("Waiting for VM '#{container_name}' to be ready (timeout: #{timeout_ms}ms)")

    do_wait_for_ready(container_name, ssh_user, ssh_key_path, ssh_port, deadline)
  end

  @doc """
  Stops an ephemeral VM.

  For ephemeral VMs created with `curie run`, we use `curie rm` to stop them.
  The container will be automatically cleaned up since it's ephemeral.
  """
  @spec stop(String.t()) :: :ok | {:error, term()}
  def stop(container_id) do
    Logger.info("Stopping ephemeral VM '#{container_id}'")

    case run_curie(["rm", container_id]) do
      {:ok, _output, 0} ->
        Logger.info("VM '#{container_id}' stopped (ephemeral - auto cleaned up)")
        :ok

      {:ok, output, exit_code} ->
        # rm might fail if VM already stopped/removed, which is fine
        Logger.debug("curie rm returned exit #{exit_code}: #{output}")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stops a VM using its full info, including killing the curie process.

  This is the preferred way to stop a VM when you have the vm_info map,
  as it ensures the curie process is also killed, not just the container.
  """
  @spec stop_vm(vm_info()) :: :ok | {:error, term()}
  def stop_vm(vm_info) do
    Logger.info("Stopping VM '#{vm_info.container_id}' with OS PID #{inspect(vm_info.os_pid)}")

    # First, kill the curie process if we have its PID
    if vm_info.os_pid do
      kill_os_process(vm_info.os_pid)
    end

    # Also close the port if it's still open
    if vm_info.port && Port.info(vm_info.port) != nil do
      Port.close(vm_info.port)
    end

    # Then clean up the container
    stop(vm_info.container_id)
  end

  @doc """
  Kills an OS process by PID.
  """
  @spec kill_os_process(integer()) :: :ok
  def kill_os_process(os_pid) when is_integer(os_pid) do
    Logger.info("Killing OS process #{os_pid}")
    System.cmd("kill", ["-9", Integer.to_string(os_pid)], stderr_to_stdout: true)
    :ok
  rescue
    e ->
      Logger.warning("Failed to kill OS process #{os_pid}: #{Exception.message(e)}")
      :ok
  end

  def kill_os_process(nil), do: :ok

  @doc """
  Forcefully stops a VM (alias for stop).
  """
  @spec kill(String.t()) :: :ok | {:error, term()}
  def kill(container_id) do
    stop(container_id)
  end

  @doc """
  Executes a command inside the VM via SSH.

  ## Options
    - `:ssh_user` - SSH username (default: #{@default_ssh_user})
    - `:ssh_key_path` - Path to SSH private key
    - `:timeout_ms` - Command timeout
  """
  @spec exec(String.t(), String.t(), vm_opts()) ::
          {:ok, String.t(), integer()} | {:error, term()}
  def exec(container_name, command, opts \\ []) do
    ssh_user = Keyword.get(opts, :ssh_user, default_ssh_user())
    ssh_key_path = Keyword.get(opts, :ssh_key_path, default_ssh_key_path())
    ssh_port = Keyword.get(opts, :ssh_port, @default_ssh_port)
    timeout_ms = Keyword.get(opts, :timeout_ms, 60_000)

    with {:ok, ip} <- get_ip(container_name) do
      SSH.exec(ip, ssh_user, ssh_key_path, command, port: ssh_port, timeout_ms: timeout_ms)
    end
  end

  @doc """
  Executes a command inside the VM with streaming output.

  ## Options
    - `:ssh_user` - SSH username
    - `:ssh_key_path` - Path to SSH private key
    - `:timeout_ms` - Command timeout (default: 1 hour)
  """
  @spec exec_stream(String.t(), String.t(), (String.t() -> any()), vm_opts()) ::
          {:ok, integer()} | {:error, term()}
  def exec_stream(container_name, command, output_callback, opts \\ []) do
    ssh_user = Keyword.get(opts, :ssh_user, default_ssh_user())
    ssh_key_path = Keyword.get(opts, :ssh_key_path, default_ssh_key_path())
    ssh_port = Keyword.get(opts, :ssh_port, @default_ssh_port)
    timeout_ms = Keyword.get(opts, :timeout_ms, 3_600_000)

    with {:ok, ip} <- get_ip(container_name) do
      SSH.exec_stream(ip, ssh_user, ssh_key_path, command, output_callback,
        port: ssh_port, timeout_ms: timeout_ms)
    end
  end

  @doc """
  Copies a file to the VM via SCP.
  """
  @spec copy_to(String.t(), String.t(), String.t(), vm_opts()) :: :ok | {:error, term()}
  def copy_to(container_name, local_path, remote_path, opts \\ []) do
    ssh_user = Keyword.get(opts, :ssh_user, default_ssh_user())
    ssh_key_path = Keyword.get(opts, :ssh_key_path, default_ssh_key_path())
    ssh_port = Keyword.get(opts, :ssh_port, @default_ssh_port)

    with {:ok, ip} <- get_ip(container_name) do
      SSH.copy_to(ip, ssh_user, ssh_key_path, local_path, remote_path, port: ssh_port)
    end
  end

  @doc """
  Lists all VMs.
  """
  @spec list() :: {:ok, [map()]} | {:error, term()}
  def list do
    case run_curie(["ps", "-f", "json"]) do
      {:ok, output, 0} ->
        parse_vm_list(output)

      {:ok, _output, exit_code} ->
        {:error, {:list_failed, exit_code}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if Curie is installed and available.
  """
  @spec check_curie_available() :: :ok | {:error, :curie_not_found}
  def check_curie_available do
    case System.find_executable("curie") do
      nil -> {:error, :curie_not_found}
      _path -> :ok
    end
  end

  @doc """
  Lists available VM images.
  """
  @spec list_images() :: {:ok, [map()]} | {:error, term()}
  def list_images do
    case run_curie(["images", "-f", "json"]) do
      {:ok, output, 0} ->
        parse_image_list(output)

      {:ok, _output, exit_code} ->
        {:error, {:list_images_failed, exit_code}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Configuration helpers

  defp default_image do
    System.get_env("VM_IMAGE", @default_image)
  end

  defp default_ssh_user do
    System.get_env("VM_SSH_USER", @default_ssh_user)
  end

  defp default_ssh_key_path do
    System.get_env("VM_SSH_KEY_PATH", @default_ssh_key_path)
  end

  # Private functions

  defp run_curie(args) do
    case System.find_executable("curie") do
      nil ->
        {:error, :curie_not_found}

      curie_path ->
        Logger.debug("Running: curie #{Enum.join(args, " ")}")

        case System.cmd(curie_path, args, stderr_to_stdout: true) do
          {output, exit_code} ->
            {:ok, output, exit_code}
        end
    end
  rescue
    e ->
      {:error, {:curie_error, Exception.message(e)}}
  end

  defp do_wait_for_ready(container_name, ssh_user, ssh_key_path, ssh_port, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      Logger.error("VM '#{container_name}' failed to become ready within timeout")
      {:error, :timeout}
    else
      case get_ip(container_name) do
        {:ok, ip} when is_binary(ip) and ip != "" ->
          Logger.debug("VM '#{container_name}' has IP #{ip}, checking SSH...")

          case SSH.check_connection(ip, ssh_user, ssh_key_path, port: ssh_port) do
            :ok ->
              Logger.info("VM '#{container_name}' is ready at #{ip}")
              :ok

            {:error, _reason} ->
              Logger.debug("SSH not ready yet, retrying...")
              Process.sleep(@vm_ready_poll_interval_ms)
              do_wait_for_ready(container_name, ssh_user, ssh_key_path, ssh_port, deadline)
          end

        {:ok, _} ->
          Logger.debug("VM '#{container_name}' has no IP yet, retrying...")
          Process.sleep(@vm_ready_poll_interval_ms)
          do_wait_for_ready(container_name, ssh_user, ssh_key_path, ssh_port, deadline)

        {:error, _reason} ->
          Logger.debug("Cannot get VM info yet, retrying...")
          Process.sleep(@vm_ready_poll_interval_ms)
          do_wait_for_ready(container_name, ssh_user, ssh_key_path, ssh_port, deadline)
      end
    end
  end

  defp parse_ip_from_inspect(json_output) do
    case Jason.decode(json_output) do
      {:ok, data} when is_map(data) ->
        # IP address is in the arp array: [{"ip": "...", "macAddress": "..."}]
        ip = case data["arp"] do
          [%{"ip" => ip} | _] when is_binary(ip) and ip != "" -> ip
          _ -> nil
        end

        if ip do
          {:ok, ip}
        else
          {:error, :no_ip_address}
        end

      {:ok, _} ->
        {:error, :invalid_inspect_format}

      {:error, reason} ->
        {:error, {:json_parse_error, reason}}
    end
  rescue
    _ ->
      {:error, :parse_error}
  end

  defp parse_vm_list(json_output) do
    case Jason.decode(json_output) do
      {:ok, data} when is_list(data) ->
        {:ok, data}

      {:ok, _} ->
        {:error, :invalid_list_format}

      {:error, reason} ->
        {:error, {:json_parse_error, reason}}
    end
  rescue
    _ ->
      {:ok, []}
  end

  defp parse_image_list(json_output) do
    case Jason.decode(json_output) do
      {:ok, data} when is_list(data) ->
        {:ok, data}

      {:ok, _} ->
        {:error, :invalid_list_format}

      {:error, reason} ->
        {:error, {:json_parse_error, reason}}
    end
  rescue
    _ ->
      {:ok, []}
  end
end
