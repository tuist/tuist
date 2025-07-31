defmodule Tuist.MinioSupervisor do
  @moduledoc false
  use GenServer

  require Logger

  @health_check_retries 30
  @health_check_interval 1000

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    minio_port = get_minio_port()
    
    kill_existing_minio_processes(minio_port)

    port = start_minio_server(minio_port)

    Logger.info("Started MinIO on port #{minio_port}")

    wait_for_minio_and_create_bucket()

    {:ok, %{port: port}}
  end

  def terminate(_reason, %{port: port}) do
    Logger.info("Terminating MinIO process")

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    Port.close(port)
    Process.sleep(100)
    System.cmd("kill", ["-9", "#{os_pid}"])

    Logger.info("MinIO process terminated")
    :ok
  end

  def handle_info({_port, {:data, data}}, state) do
    Logger.debug("MinIO: #{data}")
    {:noreply, state}
  end

  def handle_info({_port, {:exit_status, status}}, state) do
    Logger.error("MinIO exited with status #{status}")
    {:stop, :normal, state}
  end

  def handle_info(msg, state) do
    Logger.debug("MinIO supervisor received: #{inspect(msg)}")
    {:noreply, state}
  end

  defp wait_for_minio_and_create_bucket do
    Task.start(fn ->
      wait_for_minio()
      create_bucket()
    end)
  end

  defp get_minio_port do
    %{port: port} = URI.parse(Tuist.Environment.s3_endpoint())
    port || 9095
  end

  defp start_minio_server(minio_port) do
    env = [
      {"MINIO_ROOT_USER", Tuist.Environment.s3_access_key_id()},
      {"MINIO_ROOT_PASSWORD", Tuist.Environment.s3_secret_access_key()}
    ]

    Port.open({:spawn_executable, System.find_executable("minio")}, [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      {:args, ["server", "tmp/storage", "--address", ":#{minio_port}"]},
      {:env, Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)}
    ])
  end

  defp wait_for_minio(retries \\ @health_check_retries)

  defp wait_for_minio(0) do
    Logger.error("MinIO failed to start after #{@health_check_retries} seconds")
  end

  defp wait_for_minio(retries) do
    if minio_ready?() do
      Logger.info("MinIO is ready")
      :ok
    else
      Process.sleep(@health_check_interval)
      wait_for_minio(retries - 1)
    end
  end

  defp minio_ready? do
    case ExAws.request(ExAws.S3.list_buckets()) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp create_bucket do
    bucket_name = Tuist.Environment.s3_bucket_name()

    case bucket_name |> ExAws.S3.put_bucket("") |> ExAws.request() do
      {:ok, _} ->
        Logger.info("Created MinIO bucket: #{bucket_name}")

      {:error, {:http_error, 409, _}} ->
        Logger.info("MinIO bucket already exists: #{bucket_name}")

      {:error, error} ->
        Logger.error("Failed to create MinIO bucket: #{inspect(error)}")
    end
  end

  defp kill_existing_minio_processes(minio_port) do
    case System.cmd("lsof", ["-ti:#{minio_port}"]) do
      {pids, 0} ->
        pids
        |> String.trim()
        |> String.split("\n")
        |> Enum.each(&kill_if_minio_process(&1, minio_port))

      _ ->
        :ok
    end
  end

  defp kill_if_minio_process(pid, minio_port) do
    case System.cmd("ps", ["-p", pid, "-o", "comm="]) do
      {command, 0} ->
        if String.contains?(String.downcase(command), "minio") do
          Logger.info("Killing existing MinIO process on port #{minio_port}: PID #{pid}")
          System.cmd("kill", ["-9", pid])
        end

      _ ->
        :ok
    end
  end
end
