defmodule Tuist.SSHClient do
  @moduledoc """
  SSH client module for executing commands on remote servers and managing SSH connections.
  """

  require Logger

  @doc """
  Establishes an SSH connection to a remote host.

  ## Parameters
    - host: The hostname or IP address to connect to
    - port: The SSH port (defaults to 22)
    - opts: SSH connection options (user, user_dir, auth_methods, etc.)

  ## Returns
    - {:ok, connection} on success
    - {:error, reason} on failure
  """
  def connect(host, port \\ 22, opts \\ []) do
    :ssh.connect(host, port, opts)
  end

  @doc """
  Closes an SSH connection.

  ## Parameters
    - connection: The SSH connection to close
  """
  def close(connection) do
    :ssh.close(connection)
  end

  def run_command(connection, command, timeout \\ 60_000) do
    Logger.info("Running command: #{command}")
    {:ok, channel} = :ssh_connection.session_channel(connection, timeout)
    :ssh_connection.exec(connection, channel, String.to_charlist(command), timeout)
    receive_message()
  end

  defp receive_message(return_message \\ "") do
    receive do
      {:ssh_cm, _pid, {:data, _cid, 1, data}} ->
        Logger.error("SSH stderr data received: #{inspect(data)}")
        updated_message = return_message <> data
        receive_message(updated_message)

      {:ssh_cm, _pid, {:data, _cid, 0, data}} ->
        updated_message = return_message <> data
        receive_message(updated_message)

      {:ssh_cm, _pid, {:eof, _cid}} ->
        receive_message(return_message)

      {:ssh_cm, _pid, {:closed, _cid}} ->
        receive_message(return_message)

      {:ssh_cm, _pid, {:exit_status, _cid, 0}} ->
        {:ok, return_message}

      {:ssh_cm, _pid, {:exit_status, _cid, code}} ->
        {:error, "return from command failed with code #{code}"}
    after
      to_timeout(minute: 2) ->
        {:error, "no return from command after 60 seconds"}
    end
  end

  @doc """
  Transfers a file from local to remote via SFTP.

  ## Parameters
    - connection: The SSH connection
    - local_path: Path to the local file
    - remote_path: Destination path on the remote server
    - opts: Options including :permissions (defaults to 0o100666)

  ## Returns
    - :ok on success
    - :error on failure
  """
  def transfer_file(connection, local_path, remote_path, opts \\ []) do
    permissions = Keyword.get(opts, :permissions, 0o100666)

    {:ok, sftp_channel} = :ssh_sftp.start_channel(connection)

    {:ok, handle} =
      :ssh_sftp.open(sftp_channel, String.to_charlist(remote_path), [:write, :creat, :trunc])

    result =
      local_path
      |> File.stream!(64 * 1024, [])
      |> Enum.reduce_while(:ok, fn chunk, :ok ->
        case :ssh_sftp.write(sftp_channel, handle, chunk) do
          :ok -> {:cont, :ok}
          {:error, _reason} -> {:halt, :error}
        end
      end)

    case result do
      :ok ->
        {:ok, file_info} = :ssh_sftp.read_file_info(sftp_channel, remote_path)
        updated_info = put_elem(file_info, 7, permissions)

        :ssh_sftp.write_file_info(sftp_channel, String.to_charlist(remote_path), updated_info)
        :ssh_sftp.close(sftp_channel, handle)
        :ssh_sftp.stop_channel(sftp_channel)
        :ok

      :error ->
        :ssh_sftp.close(sftp_channel, handle)
        :ssh_sftp.stop_channel(sftp_channel)
        :error
    end
  end
end
