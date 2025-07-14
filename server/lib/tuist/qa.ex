defmodule Tuist.QA do
  @moduledoc """
  Agentic QA testing module that uses namespace macOS environments to run automated testing with iOS simulator access.
  """

  alias Tuist.Environment
  alias Tuist.Namespace
  alias Tuist.Namespace.Instance
  alias Tuist.QA.Run
  alias Tuist.Repo

  @doc """
  Runs agentic QA testing by setting up a macOS namespace instance, installing Tuist CLI, and executing tests.
  """
  def run_qa_tests(%{preview_url: preview_url, preview: preview}, opts \\ []) do
    # Get the latest iOS simulator app build for the preview
    preview = Repo.preload(preview, :app_builds)
    app_build = get_latest_ios_simulator_build(preview)
    
    if is_nil(app_build) do
      {:error, "No iOS simulator app build found for preview"}
    else
      # Create QA run record
      {:ok, qa_run} = create_qa_run(%{app_build_id: app_build.id})
      
      if Environment.namespace_enabled?() do
        run_qa_tests_in_namespace(opts)
      else
        Tuist.QAAgent.execute_task(
          %{
            api_key: Environment.anthropic_api_key(),
            model: "claude-3-5-sonnet-20241022",
            simulator_uuid: "5AFD2893-96A6-427E-88BE-4869B41C3F75",
            preview_url: preview_url,
            qa_run_id: qa_run.id
          },
          "You are a QA agent. The engineer has added a feature to show a profile and to go to a preview detail. Test multiple scenarios. On each step, analyze the screen to see if there is any visual inconcistency. If you run into any weird behavior, flag that, too. Be very thorough. Test at least 5 different scenarios. Don't stop until you've tested all the added features"
        )
      end
    end
  end

  @doc """
  Creates a new QA run record.
  """
  def create_qa_run(attrs) do
    %Run{}
    |> Run.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a QA run record.
  """
  def update_qa_run(%Run{} = qa_run, attrs) do
    qa_run
    |> Run.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets a QA run by ID.
  """
  def get_qa_run(id) do
    Repo.get(Run, id)
  end

  defp get_latest_ios_simulator_build(preview) do
    preview.app_builds
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.filter(&(:ios_simulator in (&1.supported_platforms || [])))
    |> List.first()
  end

  defp run_qa_tests_in_namespace(opts) do
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
         :ok <- transfer_qa_agent(connection) do
      {:ok, response} = run_ssh_command(connection, qa_script(), 60_000)
      response |> String.slice(-400..-1) |> dbg()
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
    connection |> :ssh_connection.exec(channel, String.to_charlist(command), timeout) |> dbg()

    receive_message()
  end

  defp receive_message(return_message \\ "") do
    receive do
      {:ssh_cm, _pid, {:data, _cid, 1, data}} ->
        receive_message(dbg(return_message <> data))

      {:ssh_cm, _pid, {:data, _cid, 0, data}} ->
        receive_message(dbg(return_message <> data))

      {:ssh_cm, _pid, {:eof, _cid}} ->
        return_message |> dbg() |> receive_message()

      {:ssh_cm, _pid, {:closed, _cid}} ->
        return_message |> dbg() |> receive_message()

      {:ssh_cm, _pid, {:exit_status, _cid, 0}} ->
        dbg({:ok, return_message})

      {:ssh_cm, _pid, {:exit_status, _cid, code}} ->
        dbg({:error, "return from command failed with code #{code}"})

      unhandled ->
        IO.puts("Unhandled Message: ")
        IO.inspect(unhandled)
    after
      to_timeout(second: 30) ->
        dbg({:error, "no return from command after 30 seconds"})
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
      qa_agent_executable_path
      |> File.stream!(64 * 1024, [])
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
        {:ok, file_info} = sftp_channel |> :ssh_sftp.read_file_info(remote_path) |> dbg()
        # 0o100755 = regular file, executable by all
        updated_info = put_elem(file_info, 7, 0o100755)

        sftp_channel
        |> dbg()
        |> :ssh_sftp.write_file_info(
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
