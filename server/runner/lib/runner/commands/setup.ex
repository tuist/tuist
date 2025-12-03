defmodule Runner.Commands.Setup do
  @moduledoc """
  Setup subcommand for pre-warming a VM before running jobs.

  This command starts the VMWarmer which boots a macOS VM and keeps it
  ready for immediate job execution. Run this before `runner start` to
  ensure jobs can begin instantly without waiting for VM boot.

  The command runs indefinitely, keeping the VM warm and ready.
  """

  require Logger

  alias Runner.Runner.{VM, VMWarmer}

  def run(args) do
    case parse_args(args) do
      {:ok, params} ->
        setup_vm(params)

      {:error, :help} ->
        print_help()
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        print_help()
        {:error, reason}
    end
  end

  defp parse_args(args) do
    {switches, _, _} =
      OptionParser.parse(args,
        switches: [
          image: :string,
          ssh_user: :string,
          ssh_key_path: :string,
          help: :boolean
        ],
        aliases: [
          i: :image,
          u: :ssh_user,
          k: :ssh_key_path,
          h: :help
        ]
      )

    if switches[:help] do
      {:error, :help}
    else
      {:ok,
       %{
         image: switches[:image] || System.get_env("VM_IMAGE", "ghcr.io/tuist/macos:26.1-xcode-26.1.1"),
         ssh_user: switches[:ssh_user] || System.get_env("VM_SSH_USER", "tuist"),
         ssh_key_path: switches[:ssh_key_path] || System.get_env("VM_SSH_KEY_PATH", "~/.ssh/id_ed25519")
       }}
    end
  end

  defp setup_vm(params) do
    Logger.info("Starting Tuist Runner Setup")
    Logger.info("VM Image: #{params.image}")
    Logger.info("SSH User: #{params.ssh_user}")
    Logger.info("SSH Key: #{params.ssh_key_path}")

    # Check prerequisites
    case check_prerequisites(params) do
      :ok ->
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "Setup failed: #{reason}")
        System.halt(1)
    end

    # Trap exits for graceful shutdown
    Process.flag(:trap_exit, true)

    # Start VMWarmer
    case VMWarmer.start_link(
           image: params.image,
           ssh_user: params.ssh_user,
           ssh_key_path: params.ssh_key_path
         ) do
      {:ok, pid} ->
        Logger.info("VMWarmer started, warming up VM...")
        wait_for_warm_and_monitor(pid)

      {:error, reason} ->
        Logger.error("Failed to start VMWarmer: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp check_prerequisites(params) do
    # Check Curie
    case VM.check_curie_available() do
      :ok ->
        :ok

      {:error, :curie_not_found} ->
        {:error, "Curie not found. Install it with: /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/macvmio/curie/refs/heads/main/.mise/tasks/install)\""}
    end
    |> case do
      :ok ->
        # Check SSH key
        expanded_path = Path.expand(params.ssh_key_path)
        if File.exists?(expanded_path) do
          :ok
        else
          {:error, "SSH key not found at #{expanded_path}. Generate one with: ssh-keygen -t ed25519 -f #{params.ssh_key_path} -N \"\""}
        end

      error ->
        error
    end
    |> case do
      :ok ->
        # Check image exists
        case VM.list_images() do
          {:ok, images} ->
            image_exists = Enum.any?(images, fn img ->
              full_name = "#{img["repository"]}:#{img["tag"]}"
              full_name == params.image || img["repository"] == params.image
            end)

            if image_exists do
              :ok
            else
              {:error, "VM image '#{params.image}' not found. Pull it with: curie pull #{params.image}"}
            end

          {:error, _reason} ->
            # Can't list images, try anyway
            :ok
        end

      error ->
        error
    end
  end

  defp wait_for_warm_and_monitor(pid) do
    # Wait for initial VM to be warm
    wait_for_warm_vm()

    status = VMWarmer.status()
    Logger.info("VM is warm and ready: #{status.warm_vm}")
    IO.puts("")
    IO.puts("===========================================")
    IO.puts("  VM is ready!")
    IO.puts("  Container: #{status.warm_vm}")
    IO.puts("===========================================")
    IO.puts("")
    IO.puts("You can now run 'runner start' in another terminal.")
    IO.puts("Press Ctrl+C to stop and clean up.")
    IO.puts("")

    # Monitor and keep running
    monitor_loop(pid)
  end

  defp wait_for_warm_vm do
    status = VMWarmer.status()

    if status.warm_vm do
      :ok
    else
      IO.write(".")
      Process.sleep(2_000)
      wait_for_warm_vm()
    end
  end

  defp monitor_loop(pid) do
    receive do
      {:EXIT, ^pid, :normal} ->
        Logger.info("VMWarmer stopped normally")
        :ok

      {:EXIT, ^pid, reason} ->
        Logger.error("VMWarmer stopped unexpectedly: #{inspect(reason)}")
        {:error, reason}

      :shutdown ->
        Logger.info("Received shutdown signal, stopping VMWarmer...")
        VMWarmer.stop()
        :ok
    after
      30_000 ->
        # Log status periodically
        status = VMWarmer.status()
        Logger.debug("VMWarmer status: warm_vm=#{status.warm_vm}, warming=#{status.is_warming}, total=#{status.total_vms_created}")
        monitor_loop(pid)
    end
  end

  defp print_help do
    IO.puts("""
    Setup Command - Pre-warm a VM for job execution

    Usage:
      runner setup [options]

    Options:
      --image, -i <image>         VM image to use
                                  (default: ghcr.io/tuist/macos:26.1-xcode-26.1.1)
                                  (env: VM_IMAGE)

      --ssh-user, -u <user>       SSH username for VM
                                  (default: admin)
                                  (env: VM_SSH_USER)

      --ssh-key-path, -k <path>   Path to SSH private key
                                  (default: ~/.ssh/tuist_runner_vm_key)
                                  (env: VM_SSH_KEY_PATH)

      --help, -h                  Show this help message

    Description:
      This command starts the VMWarmer which boots a macOS VM and keeps it
      ready for immediate job execution. Run this before `runner start` to
      ensure jobs can begin instantly without waiting for VM boot.

      The VM is kept warm and ready. When a job uses it, a new VM automatically
      starts warming in the background.

    Prerequisites:
      1. Curie installed (VM manager)
      2. VM image available (pull with: curie pull <image>)
      3. SSH key for VM access

    Example:
      # Use defaults
      runner setup

      # Custom image
      runner setup --image ghcr.io/tuist/macos:26.1-xcode-26.1.1

      # With all options
      runner setup -i ghcr.io/tuist/macos:26.1-xcode-26.1.1 -u admin -k ~/.ssh/vm_key
    """)
  end
end
