defmodule Tuist.SSHClient do
  @moduledoc """
  SSH client module for executing commands on remote servers.
  """

  def run_command(connection, command, timeout \\ 60_000) do
    {:ok, channel} = :ssh_connection.session_channel(connection, timeout)
    :ssh_connection.exec(connection, channel, String.to_charlist(command), timeout)
    receive_message()
  end

  defp receive_message(return_message \\ "") do
    receive do
      {:ssh_cm, _pid, {:data, _cid, 1, data}} ->
        updated_message = return_message <> data
        debug_last_lines(updated_message, "stderr data received")
        receive_message(updated_message)

      {:ssh_cm, _pid, {:data, _cid, 0, data}} ->
        updated_message = return_message <> data
        debug_last_lines(updated_message, "stdout data received")
        receive_message(updated_message)

      {:ssh_cm, _pid, {:eof, _cid}} ->
        debug_last_lines(return_message, "EOF received")
        receive_message(return_message)

      {:ssh_cm, _pid, {:closed, _cid}} ->
        debug_last_lines(return_message, "Channel closed")
        receive_message(return_message)

      {:ssh_cm, _pid, {:exit_status, _cid, 0}} ->
        debug_last_lines(return_message, "Exit status 0")
        {:ok, return_message}

      {:ssh_cm, _pid, {:exit_status, _cid, code}} ->
        debug_last_lines(return_message, "Exit status #{code}")
        {:error, "return from command failed with code #{code}"}
    after
      to_timeout(minute: 1) ->
        debug_last_lines(return_message, "TIMEOUT - last 50 lines")
        {:error, "no return from command after 60 seconds"}
    end
  end

  defp debug_last_lines(text, label) do
    lines = String.split(text, "\n")
    line_count = length(lines)
    last_lines = lines |> Enum.take(-100) |> Enum.join("\n")

    dbg({label, "Total lines: #{line_count}", "Last 100 lines:", last_lines})
  end

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
        # Set executable permissions via SFTP
        {:ok, file_info} = :ssh_sftp.read_file_info(sftp_channel, remote_path)
        updated_info = put_elem(file_info, 7, permissions)

        :ssh_sftp.write_file_info(sftp_channel, String.to_charlist(remote_path), updated_info)
        :ok

      :error ->
        :error
    end

    :ssh_sftp.close(sftp_channel, handle)
    :ssh_sftp.stop_channel(sftp_channel)
  end
end
