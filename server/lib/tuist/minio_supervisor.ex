defmodule Tuist.MinioSupervisor do
  @moduledoc false
  use GenServer
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    minio_port = get_minio_port()
    
    port = Port.open({:spawn_executable, System.find_executable("minio")}, [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      {:args, ["server", "tmp/storage", "--address", ":#{minio_port}"]},
      {:env, [
        {"MINIO_ROOT_USER", to_charlist(Tuist.Environment.s3_access_key_id())},
        {"MINIO_ROOT_PASSWORD", to_charlist(Tuist.Environment.s3_secret_access_key())}
      ]}
    ])
    
    Logger.info("Started MinIO on port #{minio_port}")
    
    Task.start(fn ->
      wait_for_minio()
      create_bucket()
    end)
    
    {:ok, %{port: port}}
  end

  def terminate(_reason, %{port: port}) do
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    Port.close(port)
    System.cmd("kill", ["-9", "#{os_pid}"])
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

  def handle_info(_, state), do: {:noreply, state}

  defp get_minio_port do
    %{port: port} = URI.parse(Tuist.Environment.s3_endpoint())
    port || 9095
  end

  defp wait_for_minio(retries \\ 30)
  
  defp wait_for_minio(0), do: Logger.error("MinIO failed to start")
  
  defp wait_for_minio(retries) do
    if minio_ready?() do
      Logger.info("MinIO is ready")
    else
      Process.sleep(1000)
      wait_for_minio(retries - 1)
    end
  end

  defp minio_ready? do
    case ExAws.S3.list_buckets() |> ExAws.request() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp create_bucket do
    bucket_name = Tuist.Environment.s3_bucket_name()
    
    case ExAws.S3.put_bucket(bucket_name, "") |> ExAws.request() do
      {:ok, _} ->
        Logger.info("Created MinIO bucket: #{bucket_name}")
        
      {:error, {:http_error, 409, _}} ->
        Logger.info("MinIO bucket already exists: #{bucket_name}")
        
      {:error, error} ->
        Logger.error("Failed to create MinIO bucket: #{inspect(error)}")
    end
  end
end