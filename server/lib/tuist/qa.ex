defmodule Tuist.QA do
  @moduledoc """
  Agentic QA testing module that uses namespace macOS environments to run automated testing with iOS simulator access.
  """

  alias Tuist.Namespace
  alias Tuist.Namespace.Instance
  alias Tuist.Environment

  @doc """
  Runs agentic QA testing by setting up a macOS namespace instance, installing Tuist CLI, and executing tests.
  """
  def run_qa_tests(opts \\ []) do
    # First, get the tenant ID and actor ID from options
    tenant_id = Keyword.fetch!(opts, :tenant_id)
    actor_id = Keyword.get(opts, :actor_id, "qa-testing")

    with {:ok, tenant_token} <-
           Namespace.issue_tenant_token(tenant_id: tenant_id, actor_id: actor_id),
         {:ok, %Instance{id: instance_id}} <-
           Namespace.create_instance(tenant_token: tenant_token),
         :ok <-
           Namespace.wait_for_instance_to_be_running(instance_id, tenant_token: tenant_token),
         {:ok, connection} <- Namespace.ssh_connection(instance_id, tenant_token: tenant_token),
         :ok <- transfer_qa_agent(connection),
         {:ok, response} = run_ssh_command(connection, qa_script(), 60_000) do
      dbg(response |> String.slice(-400..-1))
      cleanup_environment(instance_id)
      :ok
    else
      {:error, reason} ->
        case opts[:instance_id] do
          nil -> :ok
          instance_id -> cleanup_environment(instance_id)
        end

        {:error, reason}
    end
  end

  @doc """
  Cleans up the namespace environment by deleting the instance.
  """
  def cleanup_environment(instance_id) do
    case Namespace.delete_instance(instance_id) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to cleanup environment: #{reason}"}
    end
  end

  defp qa_script do
    """
    set -e

    brew install cameroncooke/axe/axe --quiet || true
    qa_agent "#{Environment.anthropic_api_key()}" "51A36083-428C-4F47-8990-B76EDD6BF1D3" "You are a QA agent. The engineer has added a feature to show a profile and to go to a preview detail. Test multiple scenarios. On each step, analyze the screen to see if there is any visual inconcistency. If you run into any weird behavior, flag that, too. Be very thorough. Test at least 5 different scenarios. Don't stop until you've tested all the added features"
    """
  end

  defp run_ssh_command(connection, command, timeout) do
    dbg("Running ssh command")
    {:ok, channel} = :ssh_connection.session_channel(connection, timeout)
    :ssh_connection.exec(connection, channel, String.to_charlist(command), timeout) |> dbg

    receive_message()
  end

  defp receive_message(return_message \\ "") do
    receive do
      {:ssh_cm, _pid, {:data, _cid, 1, data}} ->
        receive_message(dbg(return_message <> data))

      {:ssh_cm, _pid, {:data, _cid, 0, data}} ->
        receive_message(dbg(return_message <> data))

      {:ssh_cm, _pid, {:eof, _cid}} ->
        receive_message(return_message |> dbg)

      {:ssh_cm, _pid, {:closed, _cid}} ->
        receive_message(return_message |> dbg)

      {:ssh_cm, _pid, {:exit_status, _cid, 0}} ->
        {:ok, return_message} |> dbg

      {:ssh_cm, _pid, {:exit_status, _cid, code}} ->
        {:error, "return from command failed with code #{code}"} |> dbg

      unhandled ->
        IO.puts("Unhandled Message: ")
        IO.inspect(unhandled)
    after
      :timer.seconds(30) ->
        {:error, "no return from command after 30 seconds"} |> dbg
    end
  end

  defp transfer_qa_agent(connection) do
    qa_agent_executable_path =
      if Environment.dev?() do
        "qa-agent/burrito_out/qa_agent_macos"
      else
        "/app/bin/qa-agent"
      end

    remote_path = "/usr/local/bin/qa_agent"

    {:ok, sftp_channel} = :ssh_sftp.start_channel(connection)

    {:ok, handle} =
      :ssh_sftp.open(sftp_channel, String.to_charlist(remote_path), [:write, :creat, :trunc])

    result =
      File.stream!(qa_agent_executable_path, [], 64 * 1024)
      |> Enum.reduce_while(:ok, fn chunk, :ok ->
        case :ssh_sftp.write(sftp_channel, handle, chunk) do
          :ok -> {:cont, :ok}
          {:error, _reason} -> {:halt, :error}
        end
      end)

    dbg(result)

    dbg("updating permissions")

    case result do
      :ok ->
        # Set executable permissions via SFTP
        dbg(sftp_channel)
        {:ok, file_info} = :ssh_sftp.read_file_info(sftp_channel, remote_path) |> dbg
        # 0o100755 = regular file, executable by all
        updated_info = put_elem(file_info, 7, 0o100755)

        :ssh_sftp.write_file_info(
          sftp_channel |> dbg,
          String.to_charlist(remote_path),
          updated_info
        )

        :ok

      :error ->
        :error
    end

    :ssh_sftp.close(sftp_channel, handle)
    :ssh_sftp.stop_channel(sftp_channel)
  end
end
