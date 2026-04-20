defmodule Tuist.Runners.OrchardWorkerProvisioner do
  @moduledoc """
  Provisions a Scaleway bare-metal Mac as an Orchard worker host.

  Runs the same sequence as `mise/tasks/runner/provision-builder.sh` over SSH
  so the resulting machine has:

    * Homebrew, Tart, and the Orchard CLI installed
    * Passwordless sudo for the admin user
    * Auto-login enabled (via /etc/kcpassword + autoLoginUser) so a GUI
      session is active at boot, which Tart needs for Secure Enclave access

  After provisioning the machine is rebooted once so auto-login takes effect.
  The caller is expected to register the Orchard worker daemon with the
  controller in a follow-up step (not yet implemented here).
  """

  alias Tuist.SSHClient

  require Logger

  @ssh_initial_connect_timeout 300_000
  @ssh_command_timeout 600_000
  @reboot_wait_ms 30_000
  @post_reboot_max_attempts 60
  @console_user_max_attempts 30
  @poll_interval_ms 5_000

  @kcpassword_key [0x7D, 0x89, 0x52, 0x23, 0xD2, 0xBC, 0xDD, 0xEA, 0xA3, 0xB9, 0x1F]

  def provision(%{ip: ip, ssh_user: ssh_user, sudo_password: sudo_password}) do
    Logger.info("Provisioning Orchard worker at #{ip}")

    with {:ok, _} <- wait_for_ssh(ip, ssh_user, @ssh_initial_connect_timeout),
         :ok <- enable_passwordless_sudo(ip, ssh_user, sudo_password),
         :ok <- install_packages(ip, ssh_user),
         :ok <- enable_auto_login(ip, ssh_user, sudo_password) do
      maybe_reboot(ip, ssh_user)
    end
  end

  defp enable_passwordless_sudo(ip, ssh_user, sudo_password) do
    command = """
    echo '#{sudo_password}' | sudo -S sh -c 'echo "#{ssh_user} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/#{ssh_user} && chmod 0440 /etc/sudoers.d/#{ssh_user}'
    sudo -n true
    """

    run_command(ip, ssh_user, command)
  end

  defp install_packages(ip, ssh_user) do
    command = ~S"""
    set -euo pipefail

    if ! command -v brew >/dev/null 2>&1; then
      NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    eval "$(/opt/homebrew/bin/brew shellenv)"

    for formula in cirruslabs/cli/tart cirruslabs/cli/orchard; do
      if ! brew list --formula "$formula" >/dev/null 2>&1; then
        brew install "$formula"
      fi
    done
    """

    run_command(ip, ssh_user, command)
  end

  defp enable_auto_login(ip, ssh_user, sudo_password) do
    kcpassword = encode_kcpassword(sudo_password)
    kcpassword_b64 = Base.encode64(kcpassword)

    command = """
    set -euo pipefail
    echo '#{kcpassword_b64}' | base64 -d | sudo tee /etc/kcpassword > /dev/null
    sudo chmod 600 /etc/kcpassword
    sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser #{ssh_user}
    """

    run_command(ip, ssh_user, command)
  end

  defp maybe_reboot(ip, ssh_user) do
    case console_user(ip, ssh_user) do
      {:ok, ^ssh_user} ->
        Logger.info("#{ssh_user} already has an active GUI session on #{ip}; skipping reboot")
        :ok

      _ ->
        Logger.info("Rebooting #{ip} so auto-login takes effect")
        _ = run_command(ip, ssh_user, "nohup sudo shutdown -r now >/dev/null 2>&1 &")
        Process.sleep(@reboot_wait_ms)

        with {:ok, _} <- wait_for_ssh(ip, ssh_user, @post_reboot_max_attempts * @poll_interval_ms) do
          wait_for_console_user(ip, ssh_user)
        end
    end
  end

  defp wait_for_ssh(ip, ssh_user, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    do_wait_for_ssh(ip, ssh_user, deadline)
  end

  defp do_wait_for_ssh(ip, ssh_user, deadline) do
    case connect(ip, ssh_user, 5_000) do
      {:ok, conn} ->
        SSHClient.close(conn)
        {:ok, :ready}

      {:error, reason} ->
        if System.monotonic_time(:millisecond) > deadline do
          {:error, {:ssh_unavailable, reason}}
        else
          Process.sleep(@poll_interval_ms)
          do_wait_for_ssh(ip, ssh_user, deadline)
        end
    end
  end

  defp wait_for_console_user(ip, ssh_user) do
    do_wait_for_console_user(ip, ssh_user, @console_user_max_attempts)
  end

  defp do_wait_for_console_user(_ip, _ssh_user, 0) do
    {:error, :auto_login_failed}
  end

  defp do_wait_for_console_user(ip, ssh_user, attempts_remaining) do
    case console_user(ip, ssh_user) do
      {:ok, ^ssh_user} ->
        :ok

      _ ->
        Process.sleep(@poll_interval_ms)
        do_wait_for_console_user(ip, ssh_user, attempts_remaining - 1)
    end
  end

  defp console_user(ip, ssh_user) do
    case run_command(ip, ssh_user, ~s|stat -f "%Su" /dev/console|) do
      {:ok, output} -> {:ok, String.trim(output)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_command(ip, ssh_user, command) do
    with {:ok, conn} <- connect(ip, ssh_user, 10_000),
         {:ok, output} <- SSHClient.run_command(conn, command, @ssh_command_timeout) do
      SSHClient.close(conn)
      {:ok, output}
    end
  end

  defp connect(ip, ssh_user, connect_timeout) do
    SSHClient.connect(String.to_charlist(ip), 22,
      user: String.to_charlist(ssh_user),
      silently_accept_hosts: true,
      user_interaction: false,
      connect_timeout: connect_timeout
    )
  end

  @doc """
  Encodes a macOS auto-login password into the kcpassword XOR-cipher format
  that `/etc/kcpassword` expects.
  """
  def encode_kcpassword(password) when is_binary(password) do
    bytes = :binary.bin_to_list(password)
    padded_length = div(length(bytes), 12) * 12 + 12
    padded = bytes ++ List.duplicate(0, padded_length - length(bytes))

    padded
    |> Enum.with_index()
    |> Enum.map(fn {byte, i} ->
      Bitwise.bxor(byte, Enum.at(@kcpassword_key, rem(i, length(@kcpassword_key))))
    end)
    |> :binary.list_to_bin()
  end
end
