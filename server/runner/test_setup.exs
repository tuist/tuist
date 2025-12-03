# Test script for starting the VMWarmer
#
# Usage (run from server directory):
#   cd /Users/marekfort/Developer/tuist/server
#   mix run runner/test_setup.exs
#
# Optional environment variables:
#   VM_IMAGE        - VM image (default: ghcr.io/tuist/macos:26.1-xcode-26.1.1)
#   VM_SSH_USER     - SSH user for VM (default: tuist)
#   VM_SSH_KEY_PATH - SSH key path (default: ~/.ssh/id_ed25519)

require Logger
Logger.configure(level: :debug)

alias Runner.Runner.VMWarmer
alias Runner.Runner.VM

IO.puts("""
===========================================
  Tuist Runner - VM Setup Test
===========================================
""")

# Check prerequisites
IO.puts("Checking prerequisites...")

case VM.check_curie_available() do
  :ok ->
    IO.puts("  ✓ Curie is installed")

  {:error, :curie_not_found} ->
    IO.puts(:stderr, "  ✗ Curie not found")
    IO.puts(:stderr, "  Install with: /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/macvmio/curie/refs/heads/main/.mise/tasks/install)\"")
    System.halt(1)
end

ssh_key_path = System.get_env("VM_SSH_KEY_PATH", "~/.ssh/id_ed25519") |> Path.expand()

if File.exists?(ssh_key_path) do
  IO.puts("  ✓ SSH key exists at #{ssh_key_path}")
else
  IO.puts(:stderr, "  ✗ SSH key not found at #{ssh_key_path}")
  System.halt(1)
end

vm_image = System.get_env("VM_IMAGE", "ghcr.io/tuist/macos:26.1-xcode-26.1.1")
ssh_user = System.get_env("VM_SSH_USER", "tuist")

IO.puts("""

Configuration:
  VM Image:     #{vm_image}
  SSH User:     #{ssh_user}
  SSH Key:      #{ssh_key_path}

Starting VMWarmer...
""")

case VMWarmer.start_link(
       image: vm_image,
       ssh_user: ssh_user,
       ssh_key_path: ssh_key_path
     ) do
  {:ok, pid} ->
    IO.puts("VMWarmer started (pid: #{inspect(pid)})")
    IO.puts("Waiting for VM to become ready...")

    wait_for_ready = fn wait_for_ready ->
      status = VMWarmer.status()
      if status.warm_vm do
        IO.puts("\n✓ VM is ready: #{status.warm_vm}")
        IO.puts("""

        ===========================================
          VM is warm and ready!
          Container: #{status.warm_vm}
        ===========================================

        Press Ctrl+C to stop and clean up.
        """)

        # Keep running
        Process.sleep(:infinity)
      else
        IO.write(".")
        Process.sleep(2_000)
        wait_for_ready.(wait_for_ready)
      end
    end

    wait_for_ready.(wait_for_ready)

  {:error, reason} ->
    IO.puts(:stderr, "Failed to start VMWarmer: #{inspect(reason)}")
    System.halt(1)
end
